import SwiftUI

// MARK: - Hourglass Icon (Phosphor hourglass-simple)

struct HourglassIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 256
        let sy = rect.height / 256

        var p = Path()

        // Outer shape with rounded corners
        p.move(to: CGPoint(x: 211.18 * sx, y: 196.56 * sy))
        p.addLine(to: CGPoint(x: 139.57 * sx, y: 128 * sy))
        p.addLine(to: CGPoint(x: 211.18 * sx, y: 59.44 * sy))

        p.addQuadCurve(
            to: CGPoint(x: 200 * sx, y: 32 * sy),
            control: CGPoint(x: 216 * sx, y: 40 * sy)
        )
        p.addLine(to: CGPoint(x: 56 * sx, y: 32 * sy))

        p.addQuadCurve(
            to: CGPoint(x: 44.82 * sx, y: 59.44 * sy),
            control: CGPoint(x: 40 * sx, y: 40 * sy)
        )
        p.addLine(to: CGPoint(x: 116.43 * sx, y: 128 * sy))
        p.addLine(to: CGPoint(x: 44.82 * sx, y: 196.56 * sy))

        p.addQuadCurve(
            to: CGPoint(x: 56 * sx, y: 224 * sy),
            control: CGPoint(x: 40 * sx, y: 216 * sy)
        )
        p.addLine(to: CGPoint(x: 200 * sx, y: 224 * sy))

        p.addQuadCurve(
            to: CGPoint(x: 211.18 * sx, y: 196.56 * sy),
            control: CGPoint(x: 216 * sx, y: 216 * sy)
        )
        p.closeSubpath()

        // Top inner triangle cutout
        p.move(to: CGPoint(x: 128 * sx, y: 116.92 * sy))
        p.addLine(to: CGPoint(x: 200 * sx, y: 48 * sy))
        p.addLine(to: CGPoint(x: 56 * sx, y: 48 * sy))
        p.closeSubpath()

        // Bottom inner triangle cutout
        p.move(to: CGPoint(x: 128 * sx, y: 139.08 * sy))
        p.addLine(to: CGPoint(x: 200 * sx, y: 208 * sy))
        p.addLine(to: CGPoint(x: 56 * sx, y: 208 * sy))
        p.closeSubpath()

        return p
    }
}
