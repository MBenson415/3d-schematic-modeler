import SwiftUI
import SceneKit

/// NSViewRepresentable wrapper for SCNView with orbit camera and hit testing
struct SceneKitView: NSViewRepresentable {
    let scene: SCNScene
    var onComponentSelected: ((String?) -> Void)?

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        scnView.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
        scnView.antialiasingMode = .multisampling4X

        // Default camera
        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.zNear = 0.01
        camera.zFar = 100

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.8, 1.2)
        cameraNode.look(at: SCNVector3(0, 0, -0.05))
        cameraNode.name = "mainCamera"
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // Click gesture for hit testing
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(click)

        context.coordinator.scnView = scnView

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.onComponentSelected = onComponentSelected
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComponentSelected: onComponentSelected)
    }

    @MainActor
    class Coordinator: NSObject {
        var onComponentSelected: ((String?) -> Void)?
        weak var scnView: SCNView?

        init(onComponentSelected: ((String?) -> Void)?) {
            self.onComponentSelected = onComponentSelected
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView else { return }
            let point = gesture.location(in: scnView)

            let hits = scnView.hitTest(point, options: [
                .searchMode: NSNumber(value: SCNHitTestSearchMode.closest.rawValue),
            ])

            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, current.parent?.name == "components" {
                        onComponentSelected?(name)
                        return
                    }
                    node = current.parent
                }
            }

            onComponentSelected?(nil)
        }
    }
}
