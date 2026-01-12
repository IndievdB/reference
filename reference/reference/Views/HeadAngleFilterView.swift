import SwiftUI

/// Filter view for gallery that shows a 3D head to filter photos by angle
struct HeadAngleFilterView: View {
    @Binding var filterRotation: HeadRotation?
    let tolerance: Double

    @State private var currentRotation: HeadRotation = .zero
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header button to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        // Collapsing - clear filter
                        isExpanded = false
                        filterRotation = nil
                    } else {
                        // Expanding - start filtering immediately
                        isExpanded = true
                        filterRotation = currentRotation
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rotate.3d")
                        .foregroundStyle(filterRotation != nil ? Color.accentColor : .secondary)

                    Text("Angle Filter")
                        .foregroundStyle(.primary)

                    Spacer()

                    if let rotation = filterRotation {
                        Text(formatRotation(rotation))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(filterRotation != nil ? Color.accentColor.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(spacing: 16) {
                    // 3D Head Model
                    HeadModelView(
                        rotation: $currentRotation,
                        isInteractive: true,
                        showResetButton: false
                    )
                    .frame(height: 160)

                    // Current angle display
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Yaw: \(Int(currentRotation.yaw))°")
                            Text("Pitch: \(Int(currentRotation.pitch))°")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Text("±\(Int(tolerance))° tolerance")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Clear button
                    Button("Reset to Front") {
                        currentRotation = .zero
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentRotation.yaw == 0 && currentRotation.pitch == 0)
                }
                .padding()
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 8)
            }
        }
        .onChange(of: currentRotation) { _, newRotation in
            // Auto-apply filter as user rotates
            if isExpanded {
                filterRotation = newRotation
            }
        }
        .onChange(of: filterRotation) { _, newValue in
            if let rotation = newValue {
                currentRotation = rotation
            }
        }
    }

    private func formatRotation(_ rotation: HeadRotation) -> String {
        "Y:\(Int(rotation.yaw))° P:\(Int(rotation.pitch))°"
    }
}

#Preview {
    @Previewable @State var filterRotation: HeadRotation? = nil

    VStack {
        HeadAngleFilterView(filterRotation: $filterRotation, tolerance: 20)
            .padding()

        Spacer()

        if let rotation = filterRotation {
            Text("Filtering by: Y:\(Int(rotation.yaw))° P:\(Int(rotation.pitch))°")
        } else {
            Text("No filter active")
        }
    }
}
