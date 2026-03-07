import SwiftUI
import Combine

/// Main view model that manages session state and connects telemetry to UI.
@MainActor
final class CompanionViewModel: ObservableObject {
    @Published var state = SessionState()
    @Published var isConnected = false

    private let receiver = OTLPReceiver()
    private var phaseTimer: Timer?
    private var activityTimer: Timer?
    private var lastActivityTime = Date()

    // MARK: - Lifecycle

    func start() {
        setupReceiver()
        receiver.start()
        startPhaseSimulation()
    }

    func stop() {
        receiver.stop()
        phaseTimer?.invalidate()
        activityTimer?.invalidate()
    }

    // MARK: - Telemetry Binding

    private func setupReceiver() {
        receiver.onToolCall = { [weak self] name, timestamp, source in
            Task { @MainActor in
                self?.recordToolCall(name: name, at: timestamp, source: source)
            }
        }

        receiver.onMetrics = { [weak self] tokens, latency, model, source in
            Task { @MainActor in
                self?.updateMetrics(tokens: tokens, latency: latency, model: model, source: source)
            }
        }

        receiver.onPhaseChange = { [weak self] phase in
            Task { @MainActor in
                self?.transitionToPhase(phase)
            }
        }

        receiver.onActivity = { [weak self] source in
            Task { @MainActor in
                self?.markActive(source: source)
            }
        }
    }

    // MARK: - State Updates

    private func recordToolCall(name: String, at timestamp: Date, source: AgentSource) {
        if let index = state.toolCalls.firstIndex(where: { $0.name == name }) {
            state.toolCalls[index].count += 1
            state.toolCalls[index].lastUsed = timestamp
        } else {
            state.toolCalls.append(ToolCallCategory(
                id: name,
                name: name,
                count: 1,
                lastUsed: timestamp
            ))
        }
        if source != .unknown { state.metrics.source = source }
        advancePhaseProgress()
    }

    private func updateMetrics(tokens: Int, latency: Int, model: String, source: AgentSource) {
        state.metrics.tokenCount = tokens
        state.metrics.latencyMs = latency
        state.metrics.modelName = model
        state.metrics.source = source
        state.metrics.isActive = true
        isConnected = true
    }

    private func transitionToPhase(_ phase: Phase) {
        // Mark previous phases as completed
        for p in Phase.allCases where p.rawValue < phase.rawValue {
            state.phaseCompleted[p] = true
            state.phaseProgress[p] = 1.0
        }
        state.currentPhase = phase
    }

    private func markActive(source: AgentSource) {
        lastActivityTime = Date()
        state.metrics.isActive = true
        if source != .unknown { state.metrics.source = source }
        isConnected = true
    }

    // MARK: - Phase Simulation

    /// When no OTLP data, simulate phase progression based on tool call patterns.
    /// In production this would be driven entirely by telemetry.
    private func startPhaseSimulation() {
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickPhaseProgress()
            }
        }

        // Activity timeout — mark inactive after 30s of no telemetry
        activityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if Date().timeIntervalSince(self.lastActivityTime) > 30 {
                    self.state.metrics.isActive = false
                }
            }
        }
    }

    private func tickPhaseProgress() {
        let phase = state.currentPhase
        let current = state.phaseProgress[phase] ?? 0

        guard current < 1.0 else { return }

        // Advance progress smoothly
        let increment = 0.008
        let newProgress = min(1.0, current + increment)
        state.phaseProgress[phase] = newProgress
    }

    private func advancePhaseProgress() {
        let phase = state.currentPhase
        let current = state.phaseProgress[phase] ?? 0

        // Each tool call bumps progress
        let bump = 0.05
        let newProgress = min(1.0, current + bump)
        state.phaseProgress[phase] = newProgress

        // Auto-advance to next phase when progress reaches 100%
        if newProgress >= 1.0 {
            state.phaseCompleted[phase] = true
            if let nextPhase = Phase(rawValue: phase.rawValue + 1) {
                state.currentPhase = nextPhase
            }
        }
    }

    // MARK: - Demo Mode

    /// Populate with sample data for testing / demo purposes
    func loadDemoData() {
        state.currentPhase = .reasoning
        state.phaseProgress = [
            .researching: 1.0,
            .reasoning: 0.55,
            .writing: 0,
            .reviewing: 0
        ]
        state.phaseCompleted = [
            .researching: true,
            .reasoning: false,
            .writing: false,
            .reviewing: false
        ]
        state.toolCalls = [
            ToolCallCategory(id: "web_search", name: "web_search", count: 3, lastUsed: Date().addingTimeInterval(-2)),
            ToolCallCategory(id: "code_exec", name: "code_exec", count: 1, lastUsed: Date().addingTimeInterval(-8)),
            ToolCallCategory(id: "file_read", name: "file_read", count: 5, lastUsed: Date())
        ]
        state.metrics = SessionMetrics(
            tokenCount: 19800,
            latencyMs: 143,
            modelName: "Opus 4.6",
            isActive: true
        )
        isConnected = true
    }
}
