import SwiftUI
import CoreImage

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// View for experimenting with photo relighting
struct RelightingView: View {
    let imageData: Data
    let onDismiss: () -> Void

    @State private var lightDirection: CGPoint = .zero
    @State private var intensity: Double = 1.0
    @State private var lightColor: Color = .white
    @State private var shadowLift: Double = 0.0

    @State private var depthMap: CIImage?
    @State private var depthMapImage: CGImage?
    @State private var relitImage: CGImage?
    @State private var isProcessing = false
    @State private var showDepthMap = false

    private let ciContext = CIContext()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                #if os(macOS)
                HStack(spacing: 0) {
                    imagePreview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    controlsPanel
                        .frame(width: 280)
                }
                #else
                VStack(spacing: 0) {
                    imagePreview
                        .frame(maxHeight: geometry.size.height * 0.6)

                    ScrollView {
                        controlsPanel
                            .padding()
                    }
                }
                #endif
            }
            .navigationTitle("Relight")
            #if os(macOS)
            .frame(minWidth: 700, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showDepthMap.toggle()
                    } label: {
                        Label(showDepthMap ? "Show Result" : "Show Depth", systemImage: showDepthMap ? "photo" : "square.stack.3d.up")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Reset") { resetToDefaults() }
                }
            }
        }
        .onAppear {
            loadDepthMap()
        }
        .onChange(of: lightDirection) { _, _ in updateRelighting() }
        .onChange(of: intensity) { _, _ in updateRelighting() }
        .onChange(of: lightColor) { _, _ in updateRelighting() }
        .onChange(of: shadowLift) { _, _ in updateRelighting() }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        ZStack {
            Color.black

            if showDepthMap, let cgImage = depthMapImage {
                // Show depth map for debugging
                VStack {
                    #if os(macOS)
                    Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    #else
                    Image(uiImage: UIImage(cgImage: cgImage))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    #endif

                    Text("Depth Map (white = closer)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 8)
                }
            } else if let cgImage = relitImage {
                #if os(macOS)
                Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: UIImage(cgImage: cgImage))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #endif
            } else if isProcessing {
                ProgressView()
                    .tint(.white)
            } else {
                // Show original while loading
                originalImageView
            }
        }
    }

    @ViewBuilder
    private var originalImageView: some View {
        #if os(macOS)
        if let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        #else
        if let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        #endif
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 24) {
            // Light Direction
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Light Direction")
                        .font(.headline)
                    Spacer()
                    Text("(\(String(format: "%.1f", lightDirection.x)), \(String(format: "%.1f", lightDirection.y)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LightDirectionPad(direction: $lightDirection)
                    .frame(height: 150)
            }

            Divider()

            // Intensity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Intensity")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.1f", intensity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $intensity, in: 0...3)
            }

            // Shadow Lift
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shadow Lift")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.0f%%", shadowLift * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $shadowLift, in: 0...1)
            }

            // Light Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Light Color")
                    .font(.headline)

                HStack(spacing: 12) {
                    colorButton(.white, label: "Neutral")
                    colorButton(Color(red: 1.0, green: 0.95, blue: 0.8), label: "Warm")
                    colorButton(Color(red: 0.85, green: 0.92, blue: 1.0), label: "Cool")
                    ColorPicker("", selection: $lightColor)
                        .labelsHidden()
                        .frame(width: 30)
                }
            }

            Spacer()
        }
        .padding()
        #if os(macOS)
        .background(Color(white: 0.15))
        #endif
    }

    private func colorButton(_ color: Color, label: String) -> some View {
        Button {
            lightColor = color
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .stroke(lightColor == color ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Processing

    private func loadDepthMap() {
        isProcessing = true
        Task {
            let depth = await DepthEstimationService.estimateDepth(from: imageData)
            await MainActor.run {
                self.depthMap = depth

                // Create CGImage of depth map for debug display
                if let depth = depth,
                   let cgImage = ciContext.createCGImage(depth, from: depth.extent) {
                    self.depthMapImage = cgImage
                }

                updateRelighting()
            }
        }
    }

    private func updateRelighting() {
        guard let depthMap = depthMap else { return }

        let params = RelightingParams(
            lightDirection: lightDirection,
            intensity: intensity,
            lightColor: colorToCIColor(lightColor),
            shadowLift: shadowLift
        )

        Task {
            let relit = RelightingService.applyRelighting(
                to: imageData,
                depthMap: depthMap,
                params: params
            )

            if let relit = relit,
               let cgImage = ciContext.createCGImage(relit, from: relit.extent) {
                await MainActor.run {
                    self.relitImage = cgImage
                    self.isProcessing = false
                }
            }
        }
    }

    private func resetToDefaults() {
        lightDirection = .zero
        intensity = 1.0
        lightColor = .white
        shadowLift = 0.0
    }

    private func colorToCIColor(_ color: Color) -> CIColor {
        #if os(macOS)
        let nsColor = NSColor(color)
        return CIColor(color: nsColor) ?? CIColor.white
        #else
        let uiColor = UIColor(color)
        return CIColor(color: uiColor)
        #endif
    }
}

#Preview {
    RelightingView(imageData: Data(), onDismiss: {})
}
