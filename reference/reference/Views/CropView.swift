import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CropView: View {
    let imageData: Data
    let initialCropRect: CGRect
    let onConfirm: (CGRect) -> Void
    let onCancel: () -> Void

    // Crop state - stored as normalized values where cropSize is relative to shorter image dimension
    @State private var cropRect: CGRect

    // Image metrics
    @State private var imagePixelSize: CGSize = .zero  // Actual pixel dimensions
    @State private var imageDisplaySize: CGSize = .zero // Display size on screen
    @State private var imageOffset: CGPoint = .zero

    // Drag state
    @State private var dragStartCropRect: CGRect?

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    // Aspect ratio of actual image (width / height)
    private var imageAspectRatio: CGFloat {
        guard imagePixelSize.height > 0 else { return 1 }
        return imagePixelSize.width / imagePixelSize.height
    }

    init(
        imageData: Data,
        initialCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        onConfirm: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.imageData = imageData
        self.initialCropRect = initialCropRect
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._cropRect = State(initialValue: initialCropRect)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    // Image layer
                    imageView
                        .background(
                            GeometryReader { imageGeometry in
                                Color.clear.onAppear {
                                    updateImageMetrics(imageFrame: imageGeometry.frame(in: .named("container")))
                                }
                                .onChange(of: geometry.size) { _, _ in
                                    // Small delay to let layout settle
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        updateImageMetrics(imageFrame: imageGeometry.frame(in: .named("container")))
                                    }
                                }
                            }
                        )

                    // Crop overlay
                    if imageDisplaySize.width > 0 && imagePixelSize.width > 0 {
                        cropOverlay(containerSize: geometry.size)
                    }
                }
                .coordinateSpace(name: "container")
            }
            .navigationTitle("Crop Image")
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 600)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onConfirm(cropRect) }
                }
            }
        }
        .onAppear {
            loadImageDimensions()
        }
    }

    @ViewBuilder
    private var imageView: some View {
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

    private func loadImageDimensions() {
        #if os(macOS)
        if let nsImage = NSImage(data: imageData) {
            if let rep = nsImage.representations.first {
                imagePixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            } else {
                imagePixelSize = nsImage.size
            }
        }
        #else
        if let uiImage = UIImage(data: imageData),
           let cgImage = uiImage.cgImage {
            imagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        }
        #endif
    }

    private func cropOverlay(containerSize: CGSize) -> some View {
        let screenCropRect = normalizedToScreen(cropRect)

        return ZStack {
            // Dimmed overlay outside crop
            DimmedCropOverlay(cropFrame: screenCropRect, containerSize: containerSize)

            // Crop border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: screenCropRect.width, height: screenCropRect.height)
                .position(x: screenCropRect.midX, y: screenCropRect.midY)

            // Grid lines
            CropGridOverlay(frame: screenCropRect)

            // Corner handles
            ForEach(Corner.allCases, id: \.self) { corner in
                cornerHandle(corner: corner, screenCropRect: screenCropRect)
            }

            // Center drag area
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(0, screenCropRect.width - 60), height: max(0, screenCropRect.height - 60))
                .position(x: screenCropRect.midX, y: screenCropRect.midY)
                .gesture(boxDragGesture())
        }
    }

    private func cornerHandle(corner: Corner, screenCropRect: CGRect) -> some View {
        let position = cornerPosition(corner: corner, in: screenCropRect)
        let handleSize: CGFloat = 24

        return Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 2)
            .position(position)
            .gesture(cornerDragGesture(corner: corner))
    }

    private func cornerPosition(corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    // MARK: - Gestures

    /// Get the normalized width/height of the crop in image coordinates
    private func normalizedCropDimensions(for cropSize: CGFloat) -> (width: CGFloat, height: CGFloat) {
        if imageAspectRatio >= 1 {
            // Landscape: shorter dim is height
            return (width: cropSize / imageAspectRatio, height: cropSize)
        } else {
            // Portrait: shorter dim is width
            return (width: cropSize, height: cropSize * imageAspectRatio)
        }
    }

    private func cornerDragGesture(corner: Corner) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartCropRect == nil {
                    dragStartCropRect = cropRect
                }

                guard let startRect = dragStartCropRect else { return }

                // Calculate the anchored corner position (opposite to the one being dragged)
                let startDims = normalizedCropDimensions(for: startRect.width)
                let anchorX: CGFloat
                let anchorY: CGFloat

                switch corner {
                case .topLeft:
                    // Anchor is bottom-right
                    anchorX = startRect.origin.x + startDims.width
                    anchorY = startRect.origin.y + startDims.height
                case .topRight:
                    // Anchor is bottom-left
                    anchorX = startRect.origin.x
                    anchorY = startRect.origin.y + startDims.height
                case .bottomLeft:
                    // Anchor is top-right
                    anchorX = startRect.origin.x + startDims.width
                    anchorY = startRect.origin.y
                case .bottomRight:
                    // Anchor is top-left
                    anchorX = startRect.origin.x
                    anchorY = startRect.origin.y
                }

                // Determine size change based on drag direction
                var sizeDelta: CGFloat = 0
                let shorterDisplayDim = min(imageDisplaySize.width, imageDisplaySize.height)

                switch corner {
                case .topLeft:
                    sizeDelta = -max(value.translation.width, value.translation.height) / shorterDisplayDim
                case .topRight:
                    sizeDelta = max(value.translation.width, -value.translation.height) / shorterDisplayDim
                case .bottomLeft:
                    sizeDelta = max(-value.translation.width, value.translation.height) / shorterDisplayDim
                case .bottomRight:
                    sizeDelta = max(value.translation.width, value.translation.height) / shorterDisplayDim
                }

                // Calculate new size
                let newSize = max(0.1, min(1.0, startRect.width + sizeDelta))
                let newDims = normalizedCropDimensions(for: newSize)

                // Calculate new origin to keep anchor point fixed
                var newX: CGFloat
                var newY: CGFloat

                switch corner {
                case .topLeft:
                    newX = anchorX - newDims.width
                    newY = anchorY - newDims.height
                case .topRight:
                    newX = anchorX
                    newY = anchorY - newDims.height
                case .bottomLeft:
                    newX = anchorX - newDims.width
                    newY = anchorY
                case .bottomRight:
                    newX = anchorX
                    newY = anchorY
                }

                cropRect = constrainCropRect(CGRect(x: newX, y: newY, width: newSize, height: newSize))
            }
            .onEnded { _ in
                dragStartCropRect = nil
            }
    }

    private func boxDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartCropRect == nil {
                    dragStartCropRect = cropRect
                }

                guard let startRect = dragStartCropRect else { return }

                // Convert screen translation to normalized coordinates
                let deltaX = value.translation.width / imageDisplaySize.width
                let deltaY = value.translation.height / imageDisplaySize.height

                var newRect = startRect
                newRect.origin.x = startRect.origin.x + deltaX
                newRect.origin.y = startRect.origin.y + deltaY

                cropRect = constrainCropRect(newRect)
            }
            .onEnded { _ in
                dragStartCropRect = nil
            }
    }

    // MARK: - Coordinate Conversion

    /// Convert normalized crop rect to screen coordinates
    /// The crop is square in pixels, so we need to account for aspect ratio
    private func normalizedToScreen(_ rect: CGRect) -> CGRect {
        // The crop size is normalized to the shorter dimension
        // For display, we need to show a square on screen

        let shorterPixelDim = min(imagePixelSize.width, imagePixelSize.height)
        let cropPixelSize = rect.width * shorterPixelDim

        // Calculate pixel position
        let cropPixelX = rect.origin.x * imagePixelSize.width
        let cropPixelY = rect.origin.y * imagePixelSize.height

        // Convert to screen coordinates
        let scaleX = imageDisplaySize.width / imagePixelSize.width
        let scaleY = imageDisplaySize.height / imagePixelSize.height

        let screenX = imageOffset.x + cropPixelX * scaleX
        let screenY = imageOffset.y + cropPixelY * scaleY
        let screenSize = cropPixelSize * min(scaleX, scaleY)

        return CGRect(x: screenX, y: screenY, width: screenSize, height: screenSize)
    }

    private func constrainCropRect(_ rect: CGRect) -> CGRect {
        var constrained = rect

        // Minimum size (10% of shorter dimension)
        let minSize: CGFloat = 0.1
        constrained.size.width = max(minSize, constrained.width)
        constrained.size.height = constrained.width // Keep square

        // Max size is 1.0 (full shorter dimension)
        constrained.size.width = min(constrained.width, 1.0)
        constrained.size.height = constrained.width

        // Get normalized dimensions for this crop size
        let dims = normalizedCropDimensions(for: constrained.width)

        // Keep within bounds: origin + dimension <= 1.0
        let maxX = max(0, 1.0 - dims.width)
        let maxY = max(0, 1.0 - dims.height)

        constrained.origin.x = max(0, min(constrained.origin.x, maxX))
        constrained.origin.y = max(0, min(constrained.origin.y, maxY))

        return constrained
    }

    private func updateImageMetrics(imageFrame: CGRect) {
        imageDisplaySize = imageFrame.size
        imageOffset = imageFrame.origin
    }
}

// MARK: - Helper Views

struct DimmedCropOverlay: View {
    let cropFrame: CGRect
    let containerSize: CGSize

    var body: some View {
        Canvas { context, size in
            // Fill entire area with semi-transparent black
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(0.6))
            )

            // Cut out the crop area
            context.blendMode = .destinationOut
            context.fill(
                Path(cropFrame),
                with: .color(.white)
            )
        }
        .allowsHitTesting(false)
    }
}

struct CropGridOverlay: View {
    let frame: CGRect

    var body: some View {
        Path { path in
            let thirdWidth = frame.width / 3
            let thirdHeight = frame.height / 3

            // Vertical lines
            path.move(to: CGPoint(x: frame.minX + thirdWidth, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.minX + thirdWidth, y: frame.maxY))
            path.move(to: CGPoint(x: frame.minX + thirdWidth * 2, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.minX + thirdWidth * 2, y: frame.maxY))

            // Horizontal lines
            path.move(to: CGPoint(x: frame.minX, y: frame.minY + thirdHeight))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + thirdHeight))
            path.move(to: CGPoint(x: frame.minX, y: frame.minY + thirdHeight * 2))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + thirdHeight * 2))
        }
        .stroke(Color.white.opacity(0.4), lineWidth: 1)
        .allowsHitTesting(false)
    }
}
