//
//  NotchGlowEffect.swift
//  boringNotch
//
//  Flowing light (流光) effect around the notch border.
//  Top edge masked out (hidden by notch).
//

import SwiftUI

/// Flowing light that traces the notch border — skips the top (hidden by notch)
struct NotchFlowingLight: View {
    let shape: NotchShape
    let color: Color
    @State private var phase: CGFloat = 0

    private var highlightColor: Color {
        // Complementary lighter shade for the gradient peak
        switch color {
        case .orange: return .yellow
        case .green: return .mint
        case .blue: return .cyan
        default: return color.opacity(0.6)
        }
    }

    var body: some View {
        ZStack {
            shape
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .clear, .clear, .clear,
                            color.opacity(0.8),
                            highlightColor.opacity(0.6),
                            color.opacity(0.8),
                            .clear, .clear, .clear
                        ]),
                        center: .center,
                        startAngle: .degrees(phase),
                        endAngle: .degrees(phase + 360)
                    ),
                    lineWidth: 2
                )
                .blur(radius: 1)

            // Inner brighter stroke
            shape
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .clear, .clear, .clear, .clear,
                            color.opacity(0.5),
                            .clear, .clear, .clear, .clear
                        ]),
                        center: .center,
                        startAngle: .degrees(phase),
                        endAngle: .degrees(phase + 360)
                    ),
                    lineWidth: 1
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
        .allowsHitTesting(false)
    }
}

/// Subtle grey glow indicating app is running (sessions exist)
struct NotchActivityGlow: View {
    let shape: NotchShape
    @State private var glowOpacity: CGFloat = 0.2

    var body: some View {
        ZStack {
            shape
                .stroke(Color.white.opacity(glowOpacity * 0.4), lineWidth: 4)
                .blur(radius: 4)

            shape
                .stroke(Color.white.opacity(glowOpacity), lineWidth: 1.5)
                .blur(radius: 1)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowOpacity = 0.45
            }
        }
    }
}
