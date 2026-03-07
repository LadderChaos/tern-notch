//
//  CompanionLiveActivity.swift
//  boringNotch
//
//  Closed notch indicators for Claude Code sessions.
//  Session dots: green=active, orange=permission, gray=idle.
//

import SwiftUI

/// Compact view in the closed notch showing session dots
struct CompanionCompactView: View {
    @ObservedObject var manager = CompanionManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        Rectangle()
            .fill(.black)
            .frame(width: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
            .overlay(alignment: .bottom) {
                if !manager.sessions.isEmpty {
                    CompanionSessionDots()
                        .padding(.bottom, 2)
                }
            }
    }
}

/// Session dots row
struct CompanionSessionDots: View {
    @ObservedObject var manager = CompanionManager.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(manager.sessions) { info in
                SessionDotView(info: info)
                    .onTapGesture { manager.focusIDE(for: info.session) }
            }
        }
    }
}

struct SessionDotView: View {
    let info: CompanionManager.SessionInfo
    @State private var isBlinking = false

    private var dotColor: Color {
        if info.state.needsPermission { return .orange }
        if info.state.isActive { return .green }
        return .gray
    }

    private var shouldBlink: Bool {
        info.state.needsPermission || info.state.isActive
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(dotColor)
            .frame(width: 14, height: 3)
            .opacity(shouldBlink ? (isBlinking ? 1.0 : 0.3) : 0.5)
            .animation(.easeInOut(duration: 0.6), value: isBlinking)
            .onAppear { if shouldBlink { startBlinking() } }
            .onChange(of: shouldBlink) { _, val in
                if val { startBlinking() } else { isBlinking = false }
            }
            .help(info.session.displayName + (info.state.needsPermission ? " — needs permission" : info.state.isActive ? " — working" : " — idle"))
    }

    private func startBlinking() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { isBlinking = true }
    }
}
