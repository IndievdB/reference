import SwiftUI
import SceneKit

/// A reusable 3D head model view with rotation controls
struct HeadModelView: View {
    @Binding var rotation: HeadRotation
    let isInteractive: Bool
    let showResetButton: Bool

    init(
        rotation: Binding<HeadRotation>,
        isInteractive: Bool = true,
        showResetButton: Bool = true
    ) {
        self._rotation = rotation
        self.isInteractive = isInteractive
        self.showResetButton = showResetButton
    }

    var body: some View {
        VStack(spacing: 8) {
            SceneKitContainer(rotation: $rotation, isInteractive: isInteractive)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            if showResetButton {
                Button("Reset") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        rotation = .zero
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
    }
}

// MARK: - SceneKit Container

struct SceneKitContainer: View {
    @Binding var rotation: HeadRotation
    let isInteractive: Bool

    @State private var scene: SCNScene?
    @State private var headNode: SCNNode?

    var body: some View {
        SceneKitViewRepresentable(
            scene: scene,
            headNode: headNode,
            rotation: $rotation,
            isInteractive: isInteractive
        )
        .onAppear {
            loadScene()
        }
        .onChange(of: rotation) { _, newRotation in
            updateNodeRotation(newRotation)
        }
    }

    private func loadScene() {
        let newScene = SCNScene()
        scene = newScene

        // Try to load from bundle first, then from Downloads
        let bundleURL = Bundle.main.url(forResource: "asaro", withExtension: "obj")
        let downloadsURL = URL(fileURLWithPath: "/Users/jarrett/Downloads/asaro.obj")

        guard let headURL = bundleURL ?? (FileManager.default.fileExists(atPath: downloadsURL.path) ? downloadsURL : nil),
              let loadedScene = try? SCNScene(url: headURL, options: [.checkConsistency: true]) else {
            print("Could not load asaro.obj")
            return
        }

        // Get the first child node (the head model)
        guard let sourceNode = loadedScene.rootNode.childNodes.first else { return }
        let node = sourceNode.clone()

        // Center the model using bounding box
        let (minBound, maxBound) = node.boundingBox
        let centerX = (minBound.x + maxBound.x) / 2
        let centerY = (minBound.y + maxBound.y) / 2
        let centerZ = (minBound.z + maxBound.z) / 2
        node.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)

        // Scale to fit nicely in view
        let maxDim = max(maxBound.x - minBound.x, maxBound.y - minBound.y, maxBound.z - minBound.z)
        let scale = 2.0 / maxDim
        node.scale = SCNVector3(scale, scale, scale)

        // Set material for better visibility
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor.gray
        material.lightingModel = .physicallyBased
        node.geometry?.materials = [material]

        headNode = node
        newScene.rootNode.addChildNode(node)

        // Setup lighting
        setupLighting(in: newScene)

        // Setup camera
        setupCamera(in: newScene)

        // Apply initial rotation
        updateNodeRotation(rotation)
    }

    private func setupLighting(in scene: SCNScene) {
        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 300
        ambientLight.light?.color = PlatformColor.white
        scene.rootNode.addChildNode(ambientLight)

        // Key light (front-right)
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 800
        keyLight.position = SCNVector3(3, 3, 5)
        keyLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLight)

        // Fill light (front-left)
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 400
        fillLight.position = SCNVector3(-3, 2, 4)
        fillLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(fillLight)
    }

    private func setupCamera(in scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 50
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func updateNodeRotation(_ rotation: HeadRotation) {
        let radians = rotation.asRadians
        headNode?.eulerAngles = SCNVector3(radians.pitch, radians.yaw, radians.roll)
    }
}

// MARK: - Platform Color

#if os(macOS)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif

// MARK: - Platform-Specific SceneKit View

#if os(macOS)
struct SceneKitViewRepresentable: NSViewRepresentable {
    let scene: SCNScene?
    let headNode: SCNNode?
    @Binding var rotation: HeadRotation
    let isInteractive: Bool

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X

        if isInteractive {
            let panGesture = NSPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            view.addGestureRecognizer(panGesture)
        }

        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = scene
        let radians = rotation.asRadians
        headNode?.eulerAngles = SCNVector3(radians.pitch, radians.yaw, radians.roll)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: SceneKitViewRepresentable
        var lastLocation: CGPoint = .zero

        init(_ parent: SceneKitViewRepresentable) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)

            if gesture.state == .began {
                lastLocation = location
            } else if gesture.state == .changed {
                let delta = CGPoint(
                    x: location.x - lastLocation.x,
                    y: location.y - lastLocation.y
                )

                let sensitivity: Double = 0.5

                // Horizontal drag = yaw, vertical drag = pitch
                var newRotation = parent.rotation
                newRotation.yaw += delta.x * sensitivity
                newRotation.pitch -= delta.y * sensitivity

                // Clamp pitch, wrap yaw
                newRotation.pitch = max(-90, min(90, newRotation.pitch))
                if newRotation.yaw > 180 { newRotation.yaw -= 360 }
                if newRotation.yaw < -180 { newRotation.yaw += 360 }

                parent.rotation = newRotation
                lastLocation = location
            }
        }
    }
}

#else
struct SceneKitViewRepresentable: UIViewRepresentable {
    let scene: SCNScene?
    let headNode: SCNNode?
    @Binding var rotation: HeadRotation
    let isInteractive: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X

        if isInteractive {
            let panGesture = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            view.addGestureRecognizer(panGesture)
        }

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        let radians = rotation.asRadians
        headNode?.eulerAngles = SCNVector3(radians.pitch, radians.yaw, radians.roll)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: SceneKitViewRepresentable
        var lastLocation: CGPoint = .zero

        init(_ parent: SceneKitViewRepresentable) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)

            if gesture.state == .began {
                lastLocation = location
            } else if gesture.state == .changed {
                let delta = CGPoint(
                    x: location.x - lastLocation.x,
                    y: location.y - lastLocation.y
                )

                let sensitivity: Double = 0.5

                var newRotation = parent.rotation
                newRotation.yaw += delta.x * sensitivity
                newRotation.pitch -= delta.y * sensitivity

                newRotation.pitch = max(-90, min(90, newRotation.pitch))
                if newRotation.yaw > 180 { newRotation.yaw -= 360 }
                if newRotation.yaw < -180 { newRotation.yaw += 360 }

                parent.rotation = newRotation
                lastLocation = location
            }
        }
    }
}
#endif

#Preview {
    @Previewable @State var rotation = HeadRotation.zero
    HeadModelView(rotation: $rotation)
        .frame(width: 200, height: 220)
        .padding()
}
