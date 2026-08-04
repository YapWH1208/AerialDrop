import SwiftUI

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let gridSize = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            mesh(time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
        .opacity(colorScheme == .dark ? 0.55 : 0.4)
        .allowsHitTesting(false)
    }

    private func mesh(time: TimeInterval) -> some View {
        let t = Float(time)
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(Self.gridSize * Self.gridSize)
        for row in 0..<Self.gridSize {
            for col in 0..<Self.gridSize {
                let px = Float(col) / Float(Self.gridSize - 1)
                let py = Float(row) / Float(Self.gridSize - 1)
                let driftX = sin(t * 0.35 + Float(col) * 1.3 + Float(row) * 0.7) * 0.05
                let driftY = sin(t * 0.28 + Float(row) * 1.5 + Float(col) * 0.9) * 0.06
                points.append(SIMD2(px + driftX, py + driftY))
            }
        }
        return MeshGradient(
            width: Self.gridSize,
            height: Self.gridSize,
            points: points,
            colors: Self.colors,
            smoothsColors: true
        )
    }

    private static let colors: [Color] = [
        Color(red: 0.20, green: 0.22, blue: 0.46), Color(red: 0.22, green: 0.26, blue: 0.52), Color(red: 0.20, green: 0.24, blue: 0.50), Color(red: 0.19, green: 0.21, blue: 0.44),
        Color(red: 0.24, green: 0.28, blue: 0.56), Color(red: 0.10, green: 0.52, blue: 0.55), Color(red: 0.42, green: 0.32, blue: 0.62), Color(red: 0.22, green: 0.26, blue: 0.52),
        Color(red: 0.20, green: 0.26, blue: 0.54), Color(red: 0.40, green: 0.30, blue: 0.60), Color(red: 0.08, green: 0.46, blue: 0.54), Color(red: 0.18, green: 0.24, blue: 0.48),
        Color(red: 0.18, green: 0.20, blue: 0.42), Color(red: 0.20, green: 0.22, blue: 0.46), Color(red: 0.18, green: 0.20, blue: 0.42), Color(red: 0.16, green: 0.18, blue: 0.38)
    ]
}