import SwiftUI

/// A circular 2D trackpad for controlling light direction
struct LightDirectionPad: View {
    @Binding var direction: CGPoint  // -1 to 1 for X and Y

    private let indicatorSize: CGFloat = 24
    private let padding: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = size / 2
            let maxRadius = center - indicatorSize / 2 - padding

            ZStack {
                // Background circle
                Circle()
                    .fill(Color.secondary.opacity(0.15))

                // Crosshairs
                Path { path in
                    path.move(to: CGPoint(x: center, y: padding))
                    path.addLine(to: CGPoint(x: center, y: size - padding))
                    path.move(to: CGPoint(x: padding, y: center))
                    path.addLine(to: CGPoint(x: size - padding, y: center))
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                // Center dot
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .position(x: center, y: center)

                // Direction indicator
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: indicatorSize, height: indicatorSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(indicatorPosition(center: center, maxRadius: maxRadius))

                // Light ray visualization
                if direction.x != 0 || direction.y != 0 {
                    lightRayPath(center: center, maxRadius: maxRadius)
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateDirection(
                            location: value.location,
                            center: center,
                            maxRadius: maxRadius
                        )
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func indicatorPosition(center: CGFloat, maxRadius: CGFloat) -> CGPoint {
        CGPoint(
            x: center + direction.x * maxRadius,
            y: center - direction.y * maxRadius  // Flip Y for natural up = positive
        )
    }

    private func lightRayPath(center: CGFloat, maxRadius: CGFloat) -> Path {
        Path { path in
            let indicatorPos = indicatorPosition(center: center, maxRadius: maxRadius)

            // Draw rays from indicator towards center (light shining inward)
            let rayCount = 3
            let rayLength: CGFloat = 15

            for i in 0..<rayCount {
                let offset = CGFloat(i - 1) * 8  // Spread rays slightly

                // Direction from indicator to center
                let dx = center - indicatorPos.x
                let dy = center - indicatorPos.y
                let length = sqrt(dx * dx + dy * dy)

                if length > 0 {
                    let normalX = dx / length
                    let normalY = dy / length

                    // Perpendicular offset
                    let perpX = -normalY * offset
                    let perpY = normalX * offset

                    let startX = indicatorPos.x + perpX
                    let startY = indicatorPos.y + perpY

                    path.move(to: CGPoint(x: startX, y: startY))
                    path.addLine(to: CGPoint(
                        x: startX + normalX * rayLength,
                        y: startY + normalY * rayLength
                    ))
                }
            }
        }
    }

    private func updateDirection(location: CGPoint, center: CGFloat, maxRadius: CGFloat) {
        let dx = location.x - center
        let dy = -(location.y - center)  // Flip Y

        // Clamp to unit circle
        let distance = sqrt(dx * dx + dy * dy)
        let clampedDistance = min(distance, maxRadius)

        if distance > 0 {
            direction = CGPoint(
                x: (dx / distance) * (clampedDistance / maxRadius),
                y: (dy / distance) * (clampedDistance / maxRadius)
            )
        } else {
            direction = .zero
        }
    }
}

#Preview {
    @Previewable @State var direction = CGPoint(x: 0.5, y: 0.3)

    VStack(spacing: 20) {
        LightDirectionPad(direction: $direction)
            .frame(width: 200, height: 200)

        Text("X: \(String(format: "%.2f", direction.x)), Y: \(String(format: "%.2f", direction.y))")
            .font(.caption)
            .foregroundStyle(.secondary)

        Button("Reset") {
            direction = .zero
        }
    }
    .padding()
}
