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
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            shape
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .clear, .clear, .clear,
                            .orange.opacity(0.8),
                            .yellow.opacity(0.6),
                            .orange.opacity(0.8),
                            .clear, .clear, .clear
                        ]),
                        center: .top,
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
                            .orange.opacity(0.5),
                            .clear, .clear, .clear, .clear
                        ]),
                        center: .top,
                        startAngle: .degrees(phase),
                        endAngle: .degrees(phase + 360)
                    ),
                    lineWidth: 1
                )
        }
        // Mask out the top edge — it's behind the notch anyway
        .mask(
            VStack(spacing: 0) {
                Color.clear.frame(height: 4)
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                    .frame(height: 6)
                Color.white
            }
        )
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
        .allowsHitTesting(false)
    }
}

/// Subtle static glow when sessions are active (not needing attention)
struct NotchActivityGlow: View {
    let shape: NotchShape
    @State private var glowOpacity: CGFloat = 0.15

    var body: some View {
        shape
            .stroke(Color.green.opacity(glowOpacity), lineWidth: 1)
            .blur(radius: 1)
            .mask(
                VStack(spacing: 0) {
                    Color.clear.frame(height: 4)
                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: 6)
                    Color.white
                }
            )
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.35
                }
            }
    }
}
