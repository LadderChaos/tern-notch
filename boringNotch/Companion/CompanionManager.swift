//
//  CompanionManager.swift
//  boringNotch
//
//  Claude Code session monitoring via ~/.claude/ file watching.
//  Zero-config: auto-detects all sessions, no manual selection needed.
//

import Foundation
import Combine
import Defaults
import AppKit
import UserNotifications

@MainActor
final class CompanionManager: ObservableObject {
    static let shared = CompanionManager()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Published State

    /// All detected sessions with their live state
    @Published private(set) var sessions: [SessionInfo] = []

    /// True if ANY session needs user permission (drives green dot indicator)
    @Published private(set) var anyNeedsPermission: Bool = false

    /// Daily aggregate stats from stats-cache.json
    @Published private(set) var dailyStats: DailyStats = DailyStats()

    /// Wrapper combining session identity with live state
    struct SessionInfo: Identifiable, Equatable {
        var session: ClaudeSession
        var state: ClaudeCodeState
        var id: String { session.id }

        static func == (lhs: SessionInfo, rhs: SessionInfo) -> Bool {
            lhs.session == rhs.session && lhs.state == rhs.state
        }
    }

    /// True if there are any active sessions (for showing Claude tab indicator)
    var hasAnySessions: Bool { !sessions.isEmpty }

    /// Dominant agent type for glow color (priority: active session, then first session)
    var dominantAgentType: AgentType {
        sessions.first { $0.state.isActive }?.session.agentType
            ?? sessions.first?.session.agentType
            ?? .claude
    }

    /// True if any session is actively working
    var hasAnyActivity: Bool {
        sessions.contains { $0.state.isActive || $0.state.needsPermission }
            || Date().timeIntervalSince(lastActivityTime) < activityGracePeriod
    }

    // MARK: - Private

    private let claudeDir: URL = {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home)).appendingPathComponent(".claude")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }()
    private var projectsDir: URL { claudeDir.appendingPathComponent("projects") }
    private var ideDir: URL { claudeDir.appendingPathComponent("ide") }

    private var sessionScanTimer: Timer?
    private var lastActivityTime = Date()
    private let activityGracePeriod: TimeInterval = 3.0

    // Per-session file watchers
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var fileHandles: [String: FileHandle] = [:]
    private var readPositions: [String: UInt64] = [:]
    private var loadingHistory: Set<String> = []

    // Permission detection
    private var pendingTools: [String: [String: Date]] = [:]  // [sessionId: [toolId: startTime]]
    private var permissionTimer: Timer?
    private let permissionDelay: TimeInterval = 2.5
    private var notifiedSessions: Set<String> = []

    // Idle detection
    private var idleTimer: Timer?
    private let idleDelay: TimeInterval = 8.0

    private func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        // Try multiple locations
        let paths = [
            NSTemporaryDirectory() + "notchhud-debug.log",
            "/tmp/notchhud-debug.log",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notch-debug.log").path
        ]
        for logFile in paths {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile) {
                    if let fh = FileHandle(forWritingAtPath: logFile) { fh.seekToEndOfFile(); fh.write(data); fh.closeFile(); return }
                } else {
                    if FileManager.default.createFile(atPath: logFile, contents: data) { return }
                }
            }
        }
    }

    // MARK: - Init

    private init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        print("[Companion] Claude dir: \(claudeDir.path)")
        print("[Companion] Projects dir exists: \(FileManager.default.fileExists(atPath: projectsDir.path))")
        startScanning()
        loadDailyStats()
    }

    // MARK: - Scanning

    private func startScanning() {
        scan()
        sessionScanTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
                self?.loadDailyStats()
            }
        }
    }

    private func scan() {
        let fm = FileManager.default
        var discovered: [ClaudeSession] = []
        let recentThreshold = Date().addingTimeInterval(-10 * 60)  // 10 minutes

        // 1. Build IDE info map: projectKey -> (pid, ideName)
        var ideInfo: [String: (pid: Int, ideName: String)] = [:]
        if fm.fileExists(atPath: ideDir.path) {
            if let lockFiles = try? fm.contentsOfDirectory(at: ideDir, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension == "lock" }) {
                for lockFile in lockFiles {
                    guard let data = fm.contents(atPath: lockFile.path),
                          let lock = try? JSONDecoder().decode(ClaudeSessionLockFile.self, from: data),
                          let key = lock.projectKey,
                          isProcessRunning(pid: lock.pid) else { continue }
                    ideInfo[key] = (pid: lock.pid, ideName: lock.ideName)
                }
            }
        }

        // 2. Scan ALL project dirs for recently-modified JSONL files
        //    Each JSONL file = one session
        if fm.fileExists(atPath: projectsDir.path) {
            if let projectDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) {
                for projectDir in projectDirs {
                    let key = projectDir.lastPathComponent
                    if key.hasPrefix(".") { continue }

                    let jsonlFiles = findRecentJSONLFiles(in: projectDir, after: recentThreshold)
                    let ide = ideInfo[key]

                    for jsonlFile in jsonlFiles {
                        let sessionId = jsonlFile.deletingPathExtension().lastPathComponent
                        discovered.append(ClaudeSession(
                            id: sessionId,
                            projectKey: key,
                            jsonlPath: jsonlFile.path,
                            pid: ide?.pid ?? 0,
                            ideName: ide?.ideName ?? "CLI",
                            isTerminalSession: ide == nil,
                            agentType: .claude
                        ))
                    }
                }
            }
        }

        // 3. Scan Codex sessions: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
        discovered.append(contentsOf: scanCodexSessions(after: recentThreshold))

        // 4. Scan OpenCode sessions: ~/.local/share/opencode/opencode.db
        let openCodeResults = scanOpenCodeSessions(after: recentThreshold)
        discovered.append(contentsOf: openCodeResults)

        debugLog("scan() found \(discovered.count) sessions (claude: \(discovered.filter { $0.agentType == .claude }.count), codex: \(discovered.filter { $0.agentType == .codex }.count), opencode: \(openCodeResults.count))")

        // Reconcile: start/stop watchers, update session list
        let currentIds = Set(discovered.map { $0.id })
        let existingIds = Set(sessions.map { $0.id })

        // Start watching new sessions
        for session in discovered where !existingIds.contains(session.id) {
            let info = SessionInfo(session: session, state: ClaudeCodeState())
            sessions.append(info)
            startWatching(session)
        }

        // Remove sessions that disappeared
        for id in existingIds where !currentIds.contains(id) {
            stopWatching(id: id)
            sessions.removeAll { $0.id == id }
        }

        // Refresh OpenCode sessions (SQLite-based, no file watcher)
        for session in sessions where session.session.agentType == .opencode {
            loadOpenCodeState(session.session)
        }

        updatePermissionState()
    }

    /// Find all JSONL files modified after the threshold
    private func findRecentJSONLFiles(in dir: URL, after threshold: Date) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files
            .filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-") }
            .filter { url in
                guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return false }
                return date > threshold
            }
    }

    // MARK: - Codex Session Scanning

    private var codexDir: URL {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home)).appendingPathComponent(".codex/sessions")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    private func scanCodexSessions(after threshold: Date) -> [ClaudeSession] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: codexDir.path) else { return [] }
        var results: [ClaudeSession] = []

        // Walk YYYY/MM/DD directories to find recent rollout-*.jsonl
        guard let years = try? fm.contentsOfDirectory(at: codexDir, includingPropertiesForKeys: nil) else { return [] }
        for yearDir in years {
            guard let months = try? fm.contentsOfDirectory(at: yearDir, includingPropertiesForKeys: nil) else { continue }
            for monthDir in months {
                guard let days = try? fm.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: nil) else { continue }
                for dayDir in days {
                    guard let files = try? fm.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                    for file in files where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("rollout-") {
                        guard let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                              date > threshold else { continue }
                        let sessionId = "codex-" + file.deletingPathExtension().lastPathComponent
                        // Try to extract project name from first session_meta line
                        var projectName = "Codex"
                        if let handle = FileHandle(forReadingAtPath: file.path),
                           let firstChunk = String(data: handle.readData(ofLength: 32 * 1024), encoding: .utf8) {
                            handle.closeFile()
                            for jsonLine in firstChunk.components(separatedBy: "\n") {
                                if let d = jsonLine.data(using: .utf8),
                                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                                   obj["type"] as? String == "session_meta",
                                   let p = obj["payload"] as? [String: Any],
                                   let cwd = p["cwd"] as? String {
                                    projectName = (cwd as NSString).lastPathComponent
                                    break
                                }
                            }
                        }
                        results.append(ClaudeSession(
                            id: sessionId,
                            projectKey: projectName,
                            jsonlPath: file.path,
                            pid: 0,
                            ideName: "Codex",
                            isTerminalSession: true,
                            agentType: .codex
                        ))
                    }
                }
            }
        }
        return results
    }

    // MARK: - OpenCode Session Scanning

    private var openCodeDBPath: URL {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home)).appendingPathComponent(".local/share/opencode/opencode.db")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/opencode.db")
    }

    private func scanOpenCodeSessions(after threshold: Date) -> [ClaudeSession] {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: openCodeDBPath.path)
        debugLog("OpenCode DB: \(openCodeDBPath.path), exists: \(exists)")
        guard exists else { return [] }

        // Use sqlite3 CLI to query active sessions
        let thresholdMs = Int(threshold.timeIntervalSince1970 * 1000)
        let query = "SELECT id, title, directory FROM session WHERE time_updated > \(thresholdMs) ORDER BY time_updated DESC LIMIT 5;"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-separator", "\t", openCodeDBPath.path, query]
        let pipe = Pipe()
        proc.standardOutput = pipe
        let errPipe = Pipe()
        proc.standardError = errPipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            debugLog("OpenCode sqlite3 launch error: \(error)")

            return []
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
            debugLog("OpenCode sqlite3 stderr: \(errStr)")
        }

        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return [] }
        debugLog("OpenCode query result (\(output.count) chars): \(output.prefix(200))")

        var results: [ClaudeSession] = []
        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let id = parts[0]
            let directory = parts[2]
            let projectKey = directory.replacingOccurrences(of: "/", with: "-")
            results.append(ClaudeSession(
                id: "opencode-" + id,
                projectKey: projectKey,
                jsonlPath: openCodeDBPath.path,  // Not JSONL but we need a path
                pid: 0,
                ideName: "OpenCode",
                isTerminalSession: true,
                agentType: .opencode
            ))
        }
        return results
    }

    private func isProcessRunning(pid: Int) -> Bool {
        if NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier == Int32(pid) }) { return true }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        return sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 && size > 0
    }

    // MARK: - File Watching

    private func startWatching(_ session: ClaudeSession) {
        print("[Companion] Watching: \(session.agentType.displayName) \(session.displayName) [\(session.id.prefix(8))]")

        // OpenCode uses SQLite polling, not file watching
        if session.agentType == .opencode {
            loadOpenCodeState(session)
            updateState(for: session.id) { $0.isConnected = true }
            return
        }

        let jsonlFile = URL(fileURLWithPath: session.jsonlPath)

        do {
            let handle = try FileHandle(forReadingFrom: jsonlFile)
            handle.seekToEndOfFile()
            fileHandles[session.id] = handle
            readPositions[session.id] = handle.offsetInFile

            // Load recent history for initial state
            loadHistory(from: jsonlFile, sessionId: session.id, agentType: session.agentType)
        } catch {
            print("[Companion] Error opening \(jsonlFile.lastPathComponent): \(error)")
            return
        }

        let fd = open(jsonlFile.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        let sessionId = session.id
        let agentType = session.agentType
        source.setEventHandler { [weak self] in self?.readNew(sessionId: sessionId, agentType: agentType) }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers[session.id] = source

        updateState(for: session.id) { $0.isConnected = true }
    }

    private func stopWatching(id: String) {
        watchers[id]?.cancel()
        watchers.removeValue(forKey: id)
        fileHandles[id]?.closeFile()
        fileHandles.removeValue(forKey: id)
        readPositions.removeValue(forKey: id)
        pendingTools.removeValue(forKey: id)
        notifiedSessions.remove(id)
    }

    // MARK: - Data Reading

    private func loadHistory(from file: URL, sessionId: String, agentType: AgentType = .claude) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        // First: scan the first 32KB for session metadata (Codex session_meta can be ~15KB due to base_instructions)
        let headData = handle.readData(ofLength: 32 * 1024)
        if let headContent = String(data: headData, encoding: .utf8) {
            loadingHistory.insert(sessionId)
            for line in headContent.components(separatedBy: .newlines) where !line.isEmpty {
                parseJSONL(line, sessionId: sessionId, agentType: agentType)
            }
            loadingHistory.remove(sessionId)
        }

        // Then: scan last 50KB for recent state (tokens, tools, etc.)
        let maxBytes: UInt64 = 50 * 1024
        let fileSize = handle.seekToEndOfFile()
        let startPos = fileSize > maxBytes ? fileSize - maxBytes : 0
        handle.seek(toFileOffset: startPos)
        guard let data = try? handle.readToEnd(), let content = String(data: data, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        let toProcess = startPos > 0 ? Array(lines.dropFirst().suffix(50)) : Array(lines.suffix(50))

        loadingHistory.insert(sessionId)
        for line in toProcess where !line.isEmpty { parseJSONL(line, sessionId: sessionId, agentType: agentType) }
        loadingHistory.remove(sessionId)

        // Clear transient state from history
        updateState(for: sessionId) {
            $0.activeTools.removeAll()
            $0.isThinking = false
        }
        pendingTools[sessionId]?.removeAll()
    }

    private func readNew(sessionId: String, agentType: AgentType = .claude) {
        guard let handle = fileHandles[sessionId], let lastPos = readPositions[sessionId] else { return }
        handle.seek(toFileOffset: lastPos)
        let newData = handle.readDataToEndOfFile()
        readPositions[sessionId] = handle.offsetInFile
        guard !newData.isEmpty, let content = String(data: newData, encoding: .utf8) else { return }

        updateState(for: sessionId) { $0.isThinking = true }
        lastActivityTime = Date()

        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            parseJSONL(line, sessionId: sessionId, agentType: agentType)
        }
        updateState(for: sessionId) { $0.lastUpdateTime = Date() }
        resetIdleTimer()
    }

    // MARK: - JSONL Parsing

    private func parseJSONL(_ line: String, sessionId: String, agentType: AgentType = .claude) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        switch agentType {
        case .claude:
            parseClaudeJSONL(json, sessionId: sessionId)
        case .codex:
            parseCodexJSONL(json, sessionId: sessionId)
        case .opencode:
            break  // OpenCode uses SQLite, not JSONL
        }
    }

    private func parseClaudeJSONL(_ json: [String: Any], sessionId: String) {
        if let cwd = json["cwd"] as? String { updateState(for: sessionId) { $0.cwd = cwd } }
        if let branch = json["gitBranch"] as? String { updateState(for: sessionId) { $0.gitBranch = branch } }
        if let sid = json["sessionId"] as? String { updateState(for: sessionId) { $0.sessionId = sid } }
        if let mode = json["permissionMode"] as? String { updateState(for: sessionId) { $0.permissionMode = mode } }
        if let message = json["message"] as? [String: Any] { parseMessage(message, sessionId: sessionId) }
    }

    // MARK: - Codex JSONL Parsing

    private func parseCodexJSONL(_ json: [String: Any], sessionId: String) {
        guard let type = json["type"] as? String,
              let payload = json["payload"] as? [String: Any] else { return }

        switch type {
        case "session_meta":
            if let cwd = payload["cwd"] as? String {
                updateState(for: sessionId) { $0.cwd = cwd }
                // Derive display name from cwd
                if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                    let name = (cwd as NSString).lastPathComponent
                    if sessions[idx].session.displayName != name {
                        sessions[idx].session.projectKey = name
                    }
                }
            }
            if let model = payload["model_provider"] as? String {
                updateState(for: sessionId) { $0.model = model }
            }
            if let git = payload["git"] as? [String: Any],
               let branch = git["branch"] as? String {
                updateState(for: sessionId) { $0.gitBranch = branch }
            }

        case "event_msg":
            guard let event = payload["type"] as? String else { return }
            switch event {
            case "task_started":
                updateState(for: sessionId) { $0.isThinking = true }
                if let mode = payload["collaboration_mode_kind"] as? String {
                    updateState(for: sessionId) { $0.permissionMode = mode }
                }
                if let ctxWindow = payload["model_context_window"] as? Int {
                    updateState(for: sessionId) { $0.tokenUsage.contextWindow = ctxWindow }
                }
            case "task_complete":
                updateState(for: sessionId) { $0.isThinking = false }
            case "token_count":
                if let info = payload["info"] as? [String: Any] {
                    // Use last_token_usage for display (what's actually in context this turn)
                    if let last = info["last_token_usage"] as? [String: Any] {
                        updateState(for: sessionId) {
                            if let input = last["input_tokens"] as? Int { $0.tokenUsage.inputTokens = input }
                            if let cached = last["cached_input_tokens"] as? Int { $0.tokenUsage.cacheReadInputTokens = cached }
                            if let output = last["output_tokens"] as? Int { $0.tokenUsage.outputTokens = output }
                            $0.tokenUsage.contextTokens = (last["input_tokens"] as? Int ?? 0) + (last["output_tokens"] as? Int ?? 0)
                        }
                    }
                }
            default: break
            }

        case "response_item":
            guard let itemType = payload["type"] as? String else { return }
            switch itemType {
            case "function_call":
                if let name = payload["name"] as? String {
                    let toolId = payload["call_id"] as? String ?? UUID().uuidString
                    let arg = parseCodexToolArg(payload["arguments"] as? String)
                    let tool = ToolExecution(id: toolId, toolName: name, argument: arg, startTime: Date())
                    updateState(for: sessionId) {
                        $0.activeTools = [tool]
                        $0.isThinking = true
                    }
                    // Register for permission detection (same as Claude path)
                    if !loadingHistory.contains(sessionId) {
                        pendingTools[sessionId, default: [:]][toolId] = Date()
                        startPermissionTimer()
                    }
                }
            case "function_call_output":
                let toolId = payload["call_id"] as? String
                if let toolId {
                    clearPendingTool(sessionId: sessionId, toolId: toolId)
                }
                updateState(for: sessionId) {
                    if let toolId, let idx = $0.activeTools.firstIndex(where: { $0.id == toolId }) {
                        var tool = $0.activeTools.remove(at: idx)
                        tool.endTime = Date()
                        $0.recentTools.insert(tool, at: 0)
                        if $0.recentTools.count > 10 { $0.recentTools.removeLast() }
                    } else if let tool = $0.activeTools.first {
                        var finished = tool
                        finished.endTime = Date()
                        $0.recentTools.insert(finished, at: 0)
                        if $0.recentTools.count > 10 { $0.recentTools.removeLast() }
                        $0.activeTools.removeAll()
                    }
                }
            case "message":
                if let content = payload["content"] as? [[String: Any]],
                   let first = content.first,
                   let text = first["text"] as? String {
                    updateState(for: sessionId) {
                        $0.lastMessage = String(text.prefix(100))
                        $0.lastMessageTime = Date()
                    }
                }
            default: break
            }

        case "turn_context":
            if let model = payload["model"] as? String {
                updateState(for: sessionId) { $0.model = model }
            }

        default: break
        }
    }

    /// Extract a readable argument from Codex function_call JSON arguments string
    private func parseCodexToolArg(_ raw: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw.flatMap { String($0.prefix(50)) }
        }
        // exec_command: show cmd
        if let cmd = obj["cmd"] as? String { return String(cmd.prefix(60)) }
        // file operations: show path
        if let path = obj["file_path"] as? String ?? obj["path"] as? String {
            return String(path.prefix(60))
        }
        // search: show pattern or query
        if let pattern = obj["pattern"] as? String ?? obj["query"] as? String {
            return String(pattern.prefix(60))
        }
        // Fallback: first string value
        for (_, v) in obj {
            if let s = v as? String, !s.isEmpty { return String(s.prefix(60)) }
        }
        return raw.count > 50 ? String(raw.prefix(50)) : raw
    }

    // MARK: - OpenCode State Loading

    private func loadOpenCodeState(_ session: ClaudeSession) {
        let sessionId = session.id
        let dbId = String(sessionId.dropFirst("opencode-".count))

        // Model and mode from latest assistant message
        let metaQuery = """
        SELECT json_extract(data,'$.modelID'), json_extract(data,'$.mode') \
        FROM message WHERE session_id='\(dbId)' AND json_extract(data,'$.role')='assistant' \
        ORDER BY time_created DESC LIMIT 1;
        """
        if let result = runSQLite(metaQuery), !result.isEmpty {
            let parts = result.components(separatedBy: "|")
            if parts.count >= 2 {
                let model = parts[0]
                let mode = parts[1]
                updateState(for: sessionId) {
                    if !mode.isEmpty {
                        $0.model = mode
                    } else if !model.isEmpty {
                        $0.model = model
                    }
                }
            }
        }

        // Check activity from session time_updated and recent parts
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)

        // Session-level activity: if session was updated within 10s, it's active
        let sessionTimeQuery = "SELECT time_updated FROM session WHERE id='\(dbId)';"
        var sessionActive = false
        if let result = runSQLite(sessionTimeQuery), let ts = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            sessionActive = (nowMs - ts) < 10_000
            updateState(for: sessionId) { $0.lastUpdateTime = Date(timeIntervalSince1970: Double(ts) / 1000) }
        }

        // Get latest tool and latest part for display
        let recentToolQuery = """
        SELECT json_extract(data,'$.tool'), json_extract(data,'$.state.status'), \
        json_extract(data,'$.state.title'), time_updated \
        FROM part WHERE session_id='\(dbId)' AND json_extract(data,'$.type')='tool' \
        ORDER BY time_updated DESC LIMIT 1;
        """
        let latestPartQuery = """
        SELECT json_extract(data,'$.type'), time_updated \
        FROM part WHERE session_id='\(dbId)' ORDER BY time_updated DESC LIMIT 1;
        """

        // Parse latest tool
        var latestToolName = ""
        var latestToolTitle = ""
        var latestToolCompleted = true
        var latestToolTs = 0
        if let result = runSQLite(recentToolQuery), !result.isEmpty {
            let p = result.components(separatedBy: "|")
            if p.count >= 4 {
                latestToolName = p[0]
                latestToolCompleted = p[1] == "completed"
                latestToolTitle = p[2]
                latestToolTs = Int(p[3]) ?? 0
            }
        }

        // Parse latest part type
        var latestPartType = ""
        if let result = runSQLite(latestPartQuery), !result.isEmpty {
            let p = result.components(separatedBy: "|")
            latestPartType = p.first ?? ""
        }

        updateState(for: sessionId) {
            if !latestToolName.isEmpty && !latestToolCompleted && sessionActive {
                // Running tool
                let toolExec = ToolExecution(id: "oc-active", toolName: latestToolName, argument: latestToolTitle.isEmpty ? nil : String(latestToolTitle.prefix(50)), startTime: Date(timeIntervalSince1970: Double(latestToolTs) / 1000))
                $0.activeTools = [toolExec]
                $0.isThinking = true
            } else {
                $0.activeTools = []
                // Show recent completed tool
                if !latestToolName.isEmpty {
                    var toolExec = ToolExecution(id: "oc-recent", toolName: latestToolName, argument: latestToolTitle.isEmpty ? nil : String(latestToolTitle.prefix(50)), startTime: Date(timeIntervalSince1970: Double(latestToolTs) / 1000))
                    toolExec.endTime = Date(timeIntervalSince1970: Double(latestToolTs) / 1000)
                    $0.recentTools = [toolExec]
                }
                // Thinking if session active and last part is step-start or text
                $0.isThinking = sessionActive && (latestPartType == "step-start" || latestPartType == "text" || latestPartType == "reasoning")
            }
        }

        // Tokens: SUM for display, latest for context percentage
        let tokenQuery = """
        SELECT \
        SUM(json_extract(data,'$.tokens.input')), \
        SUM(json_extract(data,'$.tokens.output')), \
        SUM(json_extract(data,'$.tokens.cache.read')) \
        FROM message WHERE session_id='\(dbId)';
        """
        if let result = runSQLite(tokenQuery), !result.isEmpty {
            let parts = result.components(separatedBy: "|")
            if parts.count >= 3 {
                updateState(for: sessionId) {
                    $0.tokenUsage.inputTokens = Int(parts[0]) ?? 0
                    $0.tokenUsage.outputTokens = Int(parts[1]) ?? 0
                    $0.tokenUsage.cacheReadInputTokens = Int(parts[2]) ?? 0
                }
            }
        }

        // Context: use latest message's total (reflects current window)
        let ctxQuery = """
        SELECT json_extract(data,'$.tokens.total') \
        FROM message WHERE session_id='\(dbId)' AND json_extract(data,'$.tokens.total') > 0 \
        ORDER BY time_created DESC LIMIT 1;
        """
        if let result = runSQLite(ctxQuery), let total = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            updateState(for: sessionId) { $0.tokenUsage.contextTokens = total }
        }

        // Todos
        let todoQuery = "SELECT content, status FROM todo WHERE session_id='\(dbId)';"
        if let result = runSQLite(todoQuery, separator: "\t"), !result.isEmpty {
            var todos: [ClaudeTodoItem] = []
            for line in result.components(separatedBy: .newlines) where !line.isEmpty {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2 else { continue }
                let status: ClaudeTodoItem.TodoStatus = switch parts[1] {
                    case "in_progress": .inProgress; case "completed": .completed; default: .pending
                }
                todos.append(ClaudeTodoItem(content: parts[0], status: status))
            }
            updateState(for: sessionId) { $0.todos = todos }
        }

        // Session permission & directory
        let sessionQuery = "SELECT directory, permission FROM session WHERE id='\(dbId)';"
        if let result = runSQLite(sessionQuery), !result.isEmpty {
            let parts = result.components(separatedBy: "|")
            if let cwd = parts.first, !cwd.isEmpty {
                updateState(for: sessionId) { $0.cwd = cwd }
                // Get git branch from the working directory
                if let branch = getGitBranch(at: cwd) {
                    updateState(for: sessionId) { $0.gitBranch = branch }
                }
            }
            // Parse permission JSON to derive a mode label
            if parts.count >= 2 {
                let permJson = parts[1]
                if permJson.contains("\"write\"") && permJson.contains("\"deny\"") {
                    // Write denied = read-only/plan mode
                } else if permJson.contains("\"write\"") && permJson.contains("\"allow\"") {
                    updateState(for: sessionId) { $0.permissionMode = "bypassPermissions" }
                }
            }
        }
    }

    private func getGitBranch(at directory: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", directory, "branch", "--show-current"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }
        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (result?.isEmpty ?? true) ? nil : result
    }

    /// Run a sqlite3 query and return trimmed output
    private func runSQLite(_ query: String, separator: String? = nil) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        var args = [openCodeDBPath.path, query]
        if let sep = separator { args = ["-separator", sep, openCodeDBPath.path, query] }
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseMessage(_ message: [String: Any], sessionId: String) {
        if let model = message["model"] as? String, model != "<synthetic>" { updateState(for: sessionId) { $0.model = model } }
        if let role = message["role"] as? String, role == "user" || role == "assistant" {
            updateState(for: sessionId) { $0.isThinking = true }
        }

        // Token usage
        if let usage = message["usage"] as? [String: Any] {
            updateState(for: sessionId) {
                $0.tokenUsage.inputTokens = usage["input_tokens"] as? Int ?? $0.tokenUsage.inputTokens
                $0.tokenUsage.outputTokens = usage["output_tokens"] as? Int ?? $0.tokenUsage.outputTokens
                $0.tokenUsage.cacheReadInputTokens = usage["cache_read_input_tokens"] as? Int ?? $0.tokenUsage.cacheReadInputTokens
                $0.tokenUsage.cacheCreationInputTokens = usage["cache_creation_input_tokens"] as? Int ?? $0.tokenUsage.cacheCreationInputTokens
                // Context window = this request's input + cache_read + output
                $0.tokenUsage.contextTokens = $0.tokenUsage.inputTokens + $0.tokenUsage.cacheReadInputTokens + $0.tokenUsage.outputTokens
            }
        }

        // Content blocks
        if let content = message["content"] as? [[String: Any]] {
            for item in content {
                guard let type = item["type"] as? String else { continue }
                switch type {
                case "text":
                    if let text = item["text"] as? String {
                        let preview = String((text.components(separatedBy: .newlines).first ?? text).prefix(100))
                        updateState(for: sessionId) {
                            $0.lastMessage = preview
                            $0.lastMessageTime = Date()
                        }
                    }
                case "tool_use":
                    if let toolId = item["id"] as? String, let toolName = item["name"] as? String {
                        if toolName == "TodoWrite", let input = item["input"] as? [String: Any],
                           let todos = input["todos"] as? [[String: Any]] { parseTodos(todos, sessionId: sessionId) }
                        let tool = ToolExecution(id: toolId, toolName: toolName, argument: extractArg(from: item["input"]), startTime: Date())
                        updateState(for: sessionId) {
                            if !$0.activeTools.contains(where: { $0.id == toolId }) {
                                $0.activeTools.append(tool)
                            }
                        }
                        if !loadingHistory.contains(sessionId) {
                            pendingTools[sessionId, default: [:]][toolId] = Date()
                            startPermissionTimer()
                        }
                    }
                default: break
                }
            }
        }

        // Tool results (in user messages)
        if let role = message["role"] as? String, role == "user",
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String, type == "tool_result",
                   let toolUseId = item["tool_use_id"] as? String {
                    clearPendingTool(sessionId: sessionId, toolId: toolUseId)
                    updateState(for: sessionId) {
                        if let idx = $0.activeTools.firstIndex(where: { $0.id == toolUseId }) {
                            var tool = $0.activeTools.remove(at: idx)
                            tool.endTime = Date()
                            $0.recentTools.insert(tool, at: 0)
                            if $0.recentTools.count > 10 { $0.recentTools.removeLast() }
                        }
                        $0.isThinking = true
                    }
                }
            }
        }
    }

    private func extractArg(from input: Any?) -> String? {
        guard let input = input as? [String: Any] else { return nil }
        if let v = input["pattern"] as? String { return v }
        if let v = input["command"] as? String { return String(v.prefix(50)) }
        if let v = input["file_path"] as? String { return URL(fileURLWithPath: v).lastPathComponent }
        if let v = input["query"] as? String { return String(v.prefix(50)) }
        return nil
    }

    private func parseTodos(_ todosArray: [[String: Any]], sessionId: String) {
        var newTodos: [ClaudeTodoItem] = []
        for dict in todosArray {
            guard let content = dict["content"] as? String, let statusStr = dict["status"] as? String else { continue }
            let status: ClaudeTodoItem.TodoStatus = switch statusStr {
                case "in_progress": .inProgress; case "completed": .completed; default: .pending
            }
            newTodos.append(ClaudeTodoItem(content: content, status: status))
        }
        updateState(for: sessionId) { $0.todos = newTodos }
    }

    // MARK: - State Helpers

    private func updateState(for sessionId: String, _ block: (inout ClaudeCodeState) -> Void) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            block(&sessions[idx].state)
        }
    }

    // MARK: - Idle Detection

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for i in self.sessions.indices {
                    if !self.sessions[i].state.needsPermission {
                        self.sessions[i].state.isThinking = false
                    }
                }
            }
        }
    }

    // MARK: - Permission Detection

    private func startPermissionTimer() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: permissionDelay, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPermissions() }
        }
    }

    private func checkPermissions() {
        let now = Date()
        var anyChanged = false

        for (sessionId, toolChecks) in pendingTools {
            for (toolId, startTime) in toolChecks {
                if now.timeIntervalSince(startTime) >= permissionDelay {
                    if let idx = sessions.firstIndex(where: { $0.id == sessionId }),
                       let tool = sessions[idx].state.activeTools.first(where: { $0.id == toolId }) {
                        let wasNeeding = sessions[idx].state.needsPermission
                        sessions[idx].state.needsPermission = true
                        sessions[idx].state.pendingPermissionTool = tool.toolName
                        if !wasNeeding {
                            anyChanged = true
                            sendPermissionNotification(sessionInfo: sessions[idx])
                        }
                    }
                }
            }
        }

        if anyChanged { updatePermissionState() }

        // Stop timer if nothing pending
        if pendingTools.values.allSatisfy({ $0.isEmpty }) {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    private func clearPendingTool(sessionId: String, toolId: String) {
        pendingTools[sessionId]?.removeValue(forKey: toolId)
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }),
           sessions[idx].state.needsPermission,
           (pendingTools[sessionId]?.isEmpty ?? true) {
            sessions[idx].state.needsPermission = false
            sessions[idx].state.pendingPermissionTool = nil
            notifiedSessions.remove(sessionId)
        }
        updatePermissionState()
    }

    private func updatePermissionState() {
        let needs = sessions.contains { $0.state.needsPermission }
        if needs != anyNeedsPermission {
            anyNeedsPermission = needs

            if needs && Defaults[.enableClaudeCode] {
                // Auto-switch to Claude tab when permission needed
                BoringViewCoordinator.shared.currentView = .claudeCode
            }
        }
    }

    // MARK: - Notifications

    private func sendPermissionNotification(sessionInfo: SessionInfo) {
        guard !notifiedSessions.contains(sessionInfo.id) else { return }
        notifiedSessions.insert(sessionInfo.id)

        let content = UNMutableNotificationContent()
        content.title = "Claude needs permission"
        content.body = "\(sessionInfo.session.displayName): \(sessionInfo.state.pendingPermissionTool ?? "tool") waiting for approval"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "perm-\(sessionInfo.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - IDE Focus

    func focusIDE(for session: ClaudeSession) {
        let ideName = session.ideName.lowercased()
        let bundleIds: [String] = {
            if session.isTerminalSession {
                return ["dev.warp.Warp-Stable", "com.googlecode.iterm2", "com.apple.Terminal"]
            } else if ideName.contains("cursor") { return ["com.todesktop.230313mzl4w4u92"] }
            else if ideName.contains("code") || ideName.contains("vscode") { return ["com.microsoft.VSCode"] }
            else if ideName.contains("windsurf") { return ["com.codeium.windsurf"] }
            else if ideName.contains("zed") { return ["dev.zed.Zed"] }
            else { return [] }
        }()

        for bid in bundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
                app.activate(options: [.activateIgnoringOtherApps]); return
            }
        }
        if !session.isTerminalSession,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == Int32(session.pid) }) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: - Daily Stats

    func loadDailyStats() {
        let file = claudeDir.appendingPathComponent("stats-cache.json")
        guard FileManager.default.fileExists(atPath: file.path),
              let data = FileManager.default.contents(atPath: file.path),
              let cache = try? JSONDecoder().decode(StatsCache.self, from: data) else { return }

        let today = Self.dateFormatter.string(from: Date())
        var stats = DailyStats()

        let sorted = cache.dailyActivity?.sorted { $0.date > $1.date }
        if let act = sorted?.first(where: { $0.date == today }) ?? sorted?.first {
            stats.date = act.date
            stats.messageCount = act.messageCount ?? 0
            stats.toolCallCount = act.toolCallCount ?? 0
            stats.sessionCount = act.sessionCount ?? 0
        }

        let sortedTokens = cache.dailyModelTokens?.sorted { $0.date > $1.date }
        if let day = sortedTokens?.first(where: { $0.date == (stats.date.isEmpty ? today : stats.date) }) ?? sortedTokens?.first,
           let byModel = day.tokensByModel {
            stats.tokensUsed = byModel.values.reduce(0, +)
        }

        if stats != dailyStats { dailyStats = stats }
    }
}
