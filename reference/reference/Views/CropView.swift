import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CropView: View {
    let imageData: Data
    let initialCropRect: CGRect
    let initialRotation: Double
    let onConfirm: (CGRect, Double) -> Void  // Returns cropRect and rotation
    let onCancel: () -> Void

    // Crop state - stored as normalized values where cropSize is relative to shorter image dimension
    @State private var cropRect: CGRect
    @State private var rotation: Double  // Rotation in degrees

    // Image metrics
    @State private var imagePixelSize: CGSize = .zero  // Actual pixel dimensions
    @State private var imageDisplaySize: CGSize = .zero // Display size on screen
    @State private var imageOffset: CGPoint = .zero

    // Drag state
    @State private var dragStartCropRect: CGRect?
    @State private var dragStartRotation: Double?
    @State private var dragStartAngle: Double?

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
        initialRotation: Double = 0.0,
        onConfirm: @escaping (CGRect, Double) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.imageData = imageData
        self.initialCropRect = initialCropRect
        self.initialRotation = initialRotation
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._cropRect = State(initialValue: initialCropRect)
        self._rotation = State(initialValue: initialRotation)
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
                    Button("Done") { onConfirm(cropRect, rotation) }
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
        let center = CGPoint(x: screenCropRect.midX, y: screenCropRect.midY)
        let width = screenCropRect.width
        let height = screenCropRect.height

        return ZStack {
            // Dimmed overlay outside crop (with rotated cutout)
            DimmedCropOverlay(cropFrame: screenCropRect, containerSize: containerSize, rotation: rotation)

            // Rotated crop box group - all elements positioned relative to center (0,0)
            ZStack {
                // Center drag area (bottom layer, so handles are on top)
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: width, height: height)
                    .gesture(boxDragGesture(coordinateSpace: .named("container")))

                // Crop border
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)

                // Grid lines
                gridLines(width: width, height: height)

                // Corner handles - positioned relative to center
                cornerHandleView(xOffset: -width/2, yOffset: -height/2, corner: .topLeft)
                cornerHandleView(xOffset: width/2, yOffset: -height/2, corner: .topRight)
                cornerHandleView(xOffset: -width/2, yOffset: height/2, corner: .bottomLeft)
                cornerHandleView(xOffset: width/2, yOffset: height/2, corner: .bottomRight)

                // Rotation handle at top center
                rotationHandleView(cropHeight: height)
            }
            .rotationEffect(.degrees(rotation))
            .position(center)
        }
    }

    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let thirdW = size.width / 3
            let thirdH = size.height / 3

            var path = Path()
            // Vertical lines
            path.move(to: CGPoint(x: thirdW, y: 0))
            path.addLine(to: CGPoint(x: thirdW, y: size.height))
            path.move(to: CGPoint(x: thirdW * 2, y: 0))
            path.addLine(to: CGPoint(x: thirdW * 2, y: size.height))

            // Horizontal lines
            path.move(to: CGPoint(x: 0, y: thirdH))
            path.addLine(to: CGPoint(x: size.width, y: thirdH))
            path.move(to: CGPoint(x: 0, y: thirdH * 2))
            path.addLine(to: CGPoint(x: size.width, y: thirdH * 2))

            context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func cornerHandleView(xOffset: CGFloat, yOffset: CGFloat, corner: Corner) -> some View {
        let handleSize: CGFloat = 24

        return Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 2)
            .offset(x: xOffset, y: yOffset)
            .gesture(cornerDragGesture(corner: corner, coordinateSpace: .named("container")))
    }

    private func rotationHandleView(cropHeight: CGFloat) -> some View {
        let handleOffset = cropHeight / 2 + 30

        return VStack(spacing: 4) {
            // Line connecting to crop box
            Rectangle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 2, height: 20)

            // Rotation handle circle
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .shadow(radius: 2)
        }
        .offset(y: -handleOffset)
        .gesture(rotationDragGesture(coordinateSpace: .named("container")))
    }

    private func rotationDragGesture(coordinateSpace: CoordinateSpace) -> some Gesture {
        DragGesture(coordinateSpace: coordinateSpace)
            .onChanged { value in
                // Get crop center in container coordinates
                let screenCropRect = normalizedToScreen(cropRect)
                let center = CGPoint(x: screenCropRect.midX, y: screenCropRect.midY)

                if dragStartRotation == nil {
                    dragStartRotation = rotation
                    // Calculate initial angle from center to start location
                    let dx = Double(value.startLocation.x - center.x)
                    let dy = Double(value.startLocation.y - center.y)
                    dragStartAngle = atan2(dy, dx) * 180.0 / Double.pi
                }

                guard let startRotation = dragStartRotation,
                      let startAngle = dragStartAngle else { return }

                // Calculate current angle from center to current location
                let dx = Double(value.location.x - center.x)
                let dy = Double(value.location.y - center.y)
                let currentAngle = atan2(dy, dx) * 180.0 / Double.pi

                // Calculate rotation delta
                let delta = currentAngle - startAngle
                rotation = startRotation + delta
            }
            .onEnded { _ in
                dragStartRotation = nil
                dragStartAngle = nil
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

    private func cornerDragGesture(corner: Corner, coordinateSpace: CoordinateSpace) -> some Gesture {
        DragGesture(coordinateSpace: coordinateSpace)
            .onChanged { value in
                if dragStartCropRect == nil {
                    dragStartCropRect = cropRect
                }

                guard let startRect = dragStartCropRect else { return }

                // Calculate anchor position on screen (accounting for rotation)
                let screenCropRect = normalizedToScreen(startRect)
                let center = CGPoint(x: screenCropRect.midX, y: screenCropRect.midY)
                let halfSize = screenCropRect.width / 2  // Square crop
                let rotationRad = rotation * Double.pi / 180.0
                let cosR = CGFloat(cos(rotationRad))
                let sinR = CGFloat(sin(rotationRad))

                // Local offset of anchor corner (opposite to dragged corner)
                let anchorLocalX: CGFloat
                let anchorLocalY: CGFloat
                switch corner {
                case .topLeft:
                    anchorLocalX = halfSize
                    anchorLocalY = halfSize
                case .topRight:
                    anchorLocalX = -halfSize
                    anchorLocalY = halfSize
                case .bottomLeft:
                    anchorLocalX = halfSize
                    anchorLocalY = -halfSize
                case .bottomRight:
                    anchorLocalX = -halfSize
                    anchorLocalY = -halfSize
                }

                // Rotate local offset to get screen position of anchor
                let anchorScreenX = center.x + anchorLocalX * cosR - anchorLocalY * sinR
                let anchorScreenY = center.y + anchorLocalX * sinR + anchorLocalY * cosR

                // Calculate distance from start location to anchor
                let startDist = hypot(value.startLocation.x - anchorScreenX, value.startLocation.y - anchorScreenY)
                // Calculate distance from current location to anchor
                let currentDist = hypot(value.location.x - anchorScreenX, value.location.y - anchorScreenY)

                // Size change is proportional to distance change from anchor
                let distChange = currentDist - startDist
                let shorterDisplayDim = min(imageDisplaySize.width, imageDisplaySize.height)
                let sizeDelta = distChange / shorterDisplayDim

                // Calculate new size
                let newSize = max(0.1, min(1.0, startRect.width + sizeDelta))

                // Calculate new screen half-size
                let shorterPixelDim = min(imagePixelSize.width, imagePixelSize.height)
                let scale = min(imageDisplaySize.width / imagePixelSize.width, imageDisplaySize.height / imagePixelSize.height)
                let newScreenHalfSize = (newSize * shorterPixelDim * scale) / 2

                // Calculate new anchor offset with new size (same corner, but scaled)
                let newAnchorLocalX: CGFloat
                let newAnchorLocalY: CGFloat
                switch corner {
                case .topLeft:
                    newAnchorLocalX = newScreenHalfSize
                    newAnchorLocalY = newScreenHalfSize
                case .topRight:
                    newAnchorLocalX = -newScreenHalfSize
                    newAnchorLocalY = newScreenHalfSize
                case .bottomLeft:
                    newAnchorLocalX = newScreenHalfSize
                    newAnchorLocalY = -newScreenHalfSize
                case .bottomRight:
                    newAnchorLocalX = -newScreenHalfSize
                    newAnchorLocalY = -newScreenHalfSize
                }

                // Rotate new anchor offset
                let newAnchorOffsetX = newAnchorLocalX * cosR - newAnchorLocalY * sinR
                let newAnchorOffsetY = newAnchorLocalX * sinR + newAnchorLocalY * cosR

                // Calculate where center should be to keep anchor at same screen position
                let newCenterScreenX = anchorScreenX - newAnchorOffsetX
                let newCenterScreenY = anchorScreenY - newAnchorOffsetY

                // Convert screen center to normalized origin
                let newDims = normalizedCropDimensions(for: newSize)

                // Screen center to pixel center
                let centerPixelX = (newCenterScreenX - imageOffset.x) / scale
                let centerPixelY = (newCenterScreenY - imageOffset.y) / scale

                // Pixel center to normalized origin
                let newX = (centerPixelX - (newDims.width * imagePixelSize.width) / 2) / imagePixelSize.width
                let newY = (centerPixelY - (newDims.height * imagePixelSize.height) / 2) / imagePixelSize.height

                cropRect = constrainCropRect(CGRect(x: newX, y: newY, width: newSize, height: newSize))
            }
            .onEnded { _ in
                dragStartCropRect = nil
            }
    }

    private func boxDragGesture(coordinateSpace: CoordinateSpace) -> some Gesture {
        DragGesture(coordinateSpace: coordinateSpace)
            .onChanged { value in
                if dragStartCropRect == nil {
                    dragStartCropRect = cropRect
                }

                guard let startRect = dragStartCropRect else { return }

                // Translation is now in container space (not rotated)
                // Convert directly to normalized coordinates
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
    var rotation: Double = 0.0

    var body: some View {
        Canvas { context, size in
            // Fill entire area with semi-transparent black
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(0.6))
            )

            // Cut out the crop area with rotation
            context.blendMode = .destinationOut

            // Create rotated rect path
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: cropFrame.midX, y: cropFrame.midY)
            transform = transform.rotated(by: rotation * .pi / 180)
            transform = transform.translatedBy(x: -cropFrame.midX, y: -cropFrame.midY)

            let rotatedPath = Path(cropFrame).applying(transform)
            context.fill(rotatedPath, with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}

