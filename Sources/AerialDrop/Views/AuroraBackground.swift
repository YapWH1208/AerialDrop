import SwiftUI

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let gridSize = 4

    var body: some View {
        Group {
            if reduceMotion {
                mesh(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                    mesh(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
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
            colors: AerialTheme.auroraColors,
            smoothsColors: true
        )
    }
}