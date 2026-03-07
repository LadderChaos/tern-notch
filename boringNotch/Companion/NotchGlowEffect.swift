//
//  NotchGlowEffect.swift
//  boringNotch
//
//  Apple Intelligence-style glow effect around the notch border.
//  Uses randomized gradient stops with easing for organic animation.
//

import SwiftUI

/// Apple Intelligence-style glow around the notch border
struct NotchFlowingLight: View {
    let shape: NotchShape
    let color: Color
    @State private var stops: [Gradient.Stop] = []

    private var accentColor: Color {
        switch color {
        case .orange: return .yellow
        case .green: return .mint
        case .blue: return .cyan
        default: return color.opacity(0.6)
        }
    }

    private func generateStops() -> [Gradient.Stop] {
        [
            color.opacity(0.9),
            accentColor.opacity(0.6),
            color.opacity(0.7),
            .clear,
            color.opacity(0.5),
            accentColor.opacity(0.4),
        ]
        .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
        .sorted { $0.location < $1.location }
    }

    var body: some View {
        let gradient = AngularGradient(
            gradient: Gradient(stops: stops.isEmpty ? generateStops() : stops),
            center: .center
        )

        ZStack {
            // Outer soft glow
            shape
                .stroke(gradient, lineWidth: 8)
                .blur(radius: 8)
                .animation(.easeInOut(duration: 0.8), value: stops)

            // Mid glow
            shape
                .stroke(gradient, lineWidth: 4)
                .blur(radius: 3)
                .animation(.easeInOut(duration: 0.6), value: stops)

            // Sharp inner stroke
            shape
                .stroke(gradient, lineWidth: 1.5)
                .blur(radius: 0.5)
                .animation(.easeInOut(duration: 0.5), value: stops)
        }
        .allowsHitTesting(false)
        .task {
            stops = generateStops()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.4))
                stops = generateStops()
            }
        }
    }
}

/// Apple Intelligence-style glow for session cards (RoundedRectangle)
struct CardGlowEffect: View {
    let cornerRadius: CGFloat
    let color: Color
    @State private var stops: [Gradient.Stop] = []

    private var accentColor: Color {
        switch color {
        case .orange: return .yellow
        case .green: return .mint
        case .blue: return .cyan
        default: return color.opacity(0.6)
        }
    }

    private func generateStops() -> [Gradient.Stop] {
        [
            color.opacity(0.9),
            accentColor.opacity(0.6),
            color.opacity(0.7),
            .clear,
            color.opacity(0.5),
            accentColor.opacity(0.4),
        ]
        .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
        .sorted { $0.location < $1.location }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let gradient = AngularGradient(
            gradient: Gradient(stops: stops.isEmpty ? generateStops() : stops),
            center: .center
        )

        ZStack {
            shape
                .strokeBorder(gradient, lineWidth: 6)
                .blur(radius: 4)
                .animation(.easeInOut(duration: 0.8), value: stops)

            shape
                .strokeBorder(gradient, lineWidth: 2)
                .blur(radius: 1.5)
                .animation(.easeInOut(duration: 0.6), value: stops)

            shape
                .strokeBorder(gradient, lineWidth: 1)
                .animation(.easeInOut(duration: 0.5), value: stops)
        }
        .allowsHitTesting(false)
        .task {
            stops = generateStops()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.4))
                stops = generateStops()
            }
        }
    }
}
