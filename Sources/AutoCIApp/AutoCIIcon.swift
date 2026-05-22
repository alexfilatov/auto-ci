// Sources/AutoCIApp/AutoCIIcon.swift
import SwiftUI

/// The Auto-CI brand mark: a CI "loop" arrow (continuous integration cycling)
/// wrapped around a central auto-fix spark/bolt. The glyph is identical in every
/// state — only `color` changes, so the menubar reads at a glance:
///   idle = gray · watching = blue · fixing = orange · fixed = green · attention = red.
struct AutoCIIcon: View {
    var color: Color
    var pointSize: CGFloat = 18

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let radius = min(w, h) / 2 - 2.0

            // --- CI loop: a ring with a gap, drawn as an arrow returning on itself ---
            var ring = Path()
            ring.addArc(center: center, radius: radius,
                        startAngle: .degrees(-35), endAngle: .degrees(250),
                        clockwise: false)
            ctx.stroke(ring, with: .color(color),
                       style: StrokeStyle(lineWidth: radius * 0.32, lineCap: .round))

            // --- Arrowhead at the open end of the loop (~ -35°) ---
            let headAngle = Angle.degrees(-35).radians
            let tip = CGPoint(x: center.x + cos(headAngle) * radius,
                              y: center.y + sin(headAngle) * radius)
            // Tangent (counter-clockwise) direction at the tip.
            let tangent = CGVector(dx: -sin(headAngle), dy: cos(headAngle))
            let normal = CGVector(dx: cos(headAngle), dy: sin(headAngle))
            let a = radius * 0.42
            var head = Path()
            head.move(to: CGPoint(x: tip.x + tangent.dx * a, y: tip.y + tangent.dy * a))
            head.addLine(to: CGPoint(x: tip.x + normal.dx * a, y: tip.y + normal.dy * a))
            head.addLine(to: CGPoint(x: tip.x - normal.dx * a, y: tip.y - normal.dy * a))
            head.closeSubpath()
            ctx.fill(head, with: .color(color))

            // --- Central auto-fix spark/bolt ---
            let s = radius * 0.95           // bolt bounding scale
            func p(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
                CGPoint(x: center.x + dx * s, y: center.y + dy * s)
            }
            var bolt = Path()
            bolt.move(to: p(0.18, -0.55))
            bolt.addLine(to: p(-0.30, 0.10))
            bolt.addLine(to: p(-0.02, 0.10))
            bolt.addLine(to: p(-0.18, 0.55))
            bolt.addLine(to: p(0.30, -0.10))
            bolt.addLine(to: p(0.02, -0.10))
            bolt.closeSubpath()
            ctx.fill(bolt, with: .color(color))
        }
        .frame(width: pointSize, height: pointSize)
    }
}
