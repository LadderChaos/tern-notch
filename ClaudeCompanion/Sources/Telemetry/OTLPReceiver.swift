import Foundation
import Network

/// Lightweight HTTP server that receives OTLP telemetry from Claude Code and Codex.
/// Listens on localhost:4318 for OTLP/HTTP log and metric exports.
///
/// Setup for Claude Code:
///   export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
///
/// Setup for Codex:
///   export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
///
/// Endpoints:
///   POST /v1/logs    — Receives log entries (tool calls, phase changes)
///   POST /v1/metrics — Receives token counts, latency measurements
///   POST /v1/traces  — Receives trace spans (tool execution details)
final class OTLPReceiver {
    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.claude.companion.otlp", qos: .userInitiated)

    var onToolCall: ((String, Date, AgentSource) -> Void)?
    var onMetrics: ((Int, Int, String, AgentSource) -> Void)?
    var onPhaseChange: ((Phase) -> Void)?
    var onActivity: ((AgentSource) -> Void)?

    init(port: UInt16 = 4318) {
        self.port = port
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[OTLP] Listening on port \(self.port)")
                case .failed(let error):
                    print("[OTLP] Listener failed: \(error)")
                    self.listener?.cancel()
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: queue)
        } catch {
            print("[OTLP] Failed to create listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.processHTTPRequest(data, connection: connection)
            }
            if isComplete || error != nil {
                connection.cancel()
            } else {
                self?.receiveData(on: connection)
            }
        }
    }

    private func processHTTPRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400)
            return
        }

        // Parse HTTP request line
        let lines = request.split(separator: "\r\n", maxSplits: 1)
        guard let firstLine = lines.first else {
            sendResponse(connection: connection, status: 400)
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400)
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        guard method == "POST" else {
            sendResponse(connection: connection, status: 405)
            return
        }

        // Extract JSON body (after double CRLF)
        let bodyData: Data?
        if let range = data.range(of: Data("\r\n\r\n".utf8)) {
            bodyData = data.subdata(in: range.upperBound..<data.endIndex)
        } else {
            bodyData = nil
        }

        switch path {
        case "/v1/logs":
            processLogs(bodyData)
            sendResponse(connection: connection, status: 200)
        case "/v1/metrics":
            processMetrics(bodyData)
            sendResponse(connection: connection, status: 200)
        case "/v1/traces":
            processTraces(bodyData)
            sendResponse(connection: connection, status: 200)
        default:
            sendResponse(connection: connection, status: 404)
        }
    }

    // MARK: - Log Processing

    private func processLogs(_ data: Data?) {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Extract tool calls from OTLP log records
        if let resourceLogs = json["resourceLogs"] as? [[String: Any]] {
            for resourceLog in resourceLogs {
                let source = detectSource(from: resourceLog)

                DispatchQueue.main.async { [weak self] in
                    self?.onActivity?(source)
                }

                if let scopeLogs = resourceLog["scopeLogs"] as? [[String: Any]] {
                    for scopeLog in scopeLogs {
                        if let logRecords = scopeLog["logRecords"] as? [[String: Any]] {
                            for record in logRecords {
                                processLogRecord(record, source: source)
                            }
                        }
                    }
                }
            }
        }
    }

    private func processLogRecord(_ record: [String: Any], source: AgentSource) {
        // Extract tool name from attributes
        var toolName: String?
        if let attributes = record["attributes"] as? [[String: Any]] {
            for attr in attributes {
                if let key = attr["key"] as? String, key == "tool.name",
                   let value = attr["value"] as? [String: Any],
                   let stringValue = value["stringValue"] as? String {
                    toolName = stringValue
                }
            }
        }

        // Also check body for tool information
        if toolName == nil, let body = record["body"] as? [String: Any],
           let stringValue = body["stringValue"] as? String {
            toolName = inferToolName(from: stringValue)
        }

        if let tool = toolName {
            let mappedName = mapToolName(tool)
            DispatchQueue.main.async { [weak self] in
                self?.onToolCall?(mappedName, Date(), source)
            }
        }
    }

    // MARK: - Metrics Processing

    private func processMetrics(_ data: Data?) {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var tokens = 0
        var latency = 0
        var model = ""
        var source = AgentSource.unknown

        if let resourceMetrics = json["resourceMetrics"] as? [[String: Any]] {
            for resourceMetric in resourceMetrics {
                source = detectSource(from: resourceMetric)

                if let scopeMetrics = resourceMetric["scopeMetrics"] as? [[String: Any]] {
                    for scopeMetric in scopeMetrics {
                        if let metrics = scopeMetric["metrics"] as? [[String: Any]] {
                            for metric in metrics {
                                let name = metric["name"] as? String ?? ""
                                if name.contains("token") {
                                    if let sum = metric["sum"] as? [String: Any],
                                       let dataPoints = sum["dataPoints"] as? [[String: Any]],
                                       let point = dataPoints.first,
                                       let value = point["asInt"] as? Int {
                                        tokens = value
                                    }
                                }
                                if name.contains("latency") || name.contains("duration") {
                                    if let histogram = metric["histogram"] as? [String: Any],
                                       let dataPoints = histogram["dataPoints"] as? [[String: Any]],
                                       let point = dataPoints.first,
                                       let sum = point["sum"] as? Double,
                                       let count = point["count"] as? Int, count > 0 {
                                        latency = Int(sum / Double(count) * 1000)
                                    }
                                }
                            }
                        }
                    }
                }

                // Extract model from resource attributes
                if let resource = resourceMetric["resource"] as? [String: Any],
                   let attrs = resource["attributes"] as? [[String: Any]] {
                    for attr in attrs {
                        if let key = attr["key"] as? String, key == "ai.model",
                           let value = attr["value"] as? [String: Any],
                           let stringValue = value["stringValue"] as? String {
                            model = stringValue
                        }
                    }
                }
            }
        }

        // Default model name based on detected source
        if model.isEmpty {
            model = source == .codex ? "Codex" : "Opus 4.6"
        }

        if tokens > 0 || latency > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onMetrics?(tokens, latency, model, source)
            }
        }
    }

    // MARK: - Trace Processing (Codex sends traces)

    private func processTraces(_ data: Data?) {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let resourceSpans = json["resourceSpans"] as? [[String: Any]] {
            for resourceSpan in resourceSpans {
                let source = detectSource(from: resourceSpan)

                DispatchQueue.main.async { [weak self] in
                    self?.onActivity?(source)
                }

                if let scopeSpans = resourceSpan["scopeSpans"] as? [[String: Any]] {
                    for scopeSpan in scopeSpans {
                        if let spans = scopeSpan["spans"] as? [[String: Any]] {
                            for span in spans {
                                processSpan(span, source: source)
                            }
                        }
                    }
                }
            }
        }
    }

    private func processSpan(_ span: [String: Any], source: AgentSource) {
        // Extract tool name from span name or attributes
        var toolName: String?

        if let name = span["name"] as? String {
            toolName = inferToolName(from: name)
        }

        if toolName == nil, let attributes = span["attributes"] as? [[String: Any]] {
            for attr in attributes {
                if let key = attr["key"] as? String,
                   (key == "tool.name" || key == "code.function"),
                   let value = attr["value"] as? [String: Any],
                   let stringValue = value["stringValue"] as? String {
                    toolName = stringValue
                    break
                }
            }
        }

        if let tool = toolName {
            let mappedName = mapToolName(tool)
            DispatchQueue.main.async { [weak self] in
                self?.onToolCall?(mappedName, Date(), source)
            }
        }
    }

    // MARK: - Source Detection

    /// Detect whether telemetry came from Claude Code or Codex based on resource attributes
    private func detectSource(from resourcePayload: [String: Any]) -> AgentSource {
        var serviceName: String?
        var modelName: String?

        if let resource = resourcePayload["resource"] as? [String: Any],
           let attrs = resource["attributes"] as? [[String: Any]] {
            for attr in attrs {
                guard let key = attr["key"] as? String,
                      let value = attr["value"] as? [String: Any],
                      let stringValue = value["stringValue"] as? String else { continue }

                switch key {
                case "service.name":
                    serviceName = stringValue
                case "ai.model", "model.name":
                    modelName = stringValue
                default:
                    break
                }
            }
        }

        return AgentSource.detect(from: serviceName, modelName: modelName)
    }

    // MARK: - Helpers

    private func mapToolName(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("search") || lowered.contains("web") { return "web_search" }
        if lowered.contains("bash") || lowered.contains("exec") || lowered.contains("shell") { return "code_exec" }
        if lowered.contains("read") || lowered.contains("file_read") { return "file_read" }
        if lowered.contains("write") || lowered.contains("file_write") { return "file_write" }
        if lowered.contains("edit") { return "edit" }
        if lowered.contains("grep") { return "grep" }
        if lowered.contains("glob") { return "glob" }
        if lowered.contains("agent") { return "agent" }
        return name
    }

    private func inferToolName(from body: String) -> String? {
        let lowered = body.lowercased()
        if lowered.contains("tool_use") || lowered.contains("tool_call") {
            if lowered.contains("read") { return "file_read" }
            if lowered.contains("write") { return "file_write" }
            if lowered.contains("bash") { return "code_exec" }
            if lowered.contains("search") { return "web_search" }
        }
        return nil
    }

    private func sendResponse(connection: NWConnection, status: Int) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Error"
        }

        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
