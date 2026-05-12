import SwiftUI
import SceneKit

struct VWBus3DView: View {
    private let scene: SCNScene = VWBus3DView.makeScene()

    var body: some View {
        SceneView(
            scene: scene,
            pointOfView: nil,
            options: [.autoenablesDefaultLighting, .allowsCameraControl]
        )
        .frame(height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func makeScene() -> SCNScene {
        guard let url = Bundle.main.url(forResource: "Volkswagen Type 2 Kombi T1 1967", withExtension: "fbx", subdirectory: "Models") else {
            return makeFallbackScene()
        }

        guard let source = SCNSceneSource(url: url, options: nil),
              let scene = source.scene(options: nil) else {
            return makeFallbackScene()
        }

        let root = scene.rootNode
        root.scale = SCNVector3(0.015, 0.015, 0.015)
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 14))
        root.runAction(spin)
        return scene
    }

    private static func makeFallbackScene() -> SCNScene {
        let scene = SCNScene()

        let body = SCNBox(width: 2.3, height: 0.9, length: 1.1, chamferRadius: 0.12)
        body.firstMaterial?.diffuse.contents = UIColor(red: 0.16, green: 0.30, blue: 0.56, alpha: 1)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.1, 0)

        let roof = SCNBox(width: 1.6, height: 0.55, length: 1.05, chamferRadius: 0.1)
        roof.firstMaterial?.diffuse.contents = UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(-0.08, 0.72, 0)

        let splitter = SCNBox(width: 0.05, height: 0.95, length: 1.12, chamferRadius: 0.01)
        splitter.firstMaterial?.diffuse.contents = UIColor(red: 0.98, green: 0.73, blue: 0.25, alpha: 1)
        let splitterNode = SCNNode(geometry: splitter)
        splitterNode.position = SCNVector3(0.62, 0.2, 0)

        let wheelGeometry = SCNCylinder(radius: 0.22, height: 0.14)
        wheelGeometry.firstMaterial?.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        let rimGeometry = SCNCylinder(radius: 0.1, height: 0.145)
        rimGeometry.firstMaterial?.diffuse.contents = UIColor(white: 0.75, alpha: 1)

        let wheelPositions: [SCNVector3] = [
            SCNVector3(-0.72, -0.36, 0.58),
            SCNVector3(0.72, -0.36, 0.58),
            SCNVector3(-0.72, -0.36, -0.58),
            SCNVector3(0.72, -0.36, -0.58)
        ]

        for position in wheelPositions {
            let wheel = SCNNode(geometry: wheelGeometry)
            wheel.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            wheel.position = position
            scene.rootNode.addChildNode(wheel)

            let rim = SCNNode(geometry: rimGeometry)
            rim.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            rim.position = position
            scene.rootNode.addChildNode(rim)
        }

        let busRoot = SCNNode()
        busRoot.addChildNode(bodyNode)
        busRoot.addChildNode(roofNode)
        busRoot.addChildNode(splitterNode)
        busRoot.scale = SCNVector3(0.55, 0.55, 0.55)
        scene.rootNode.addChildNode(busRoot)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 1.0, 4.0)
        scene.rootNode.addChildNode(cameraNode)

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 1200
        lightNode.position = SCNVector3(2.5, 4.5, 4.5)
        scene.rootNode.addChildNode(lightNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 420
        ambientNode.light?.color = UIColor(red: 0.62, green: 0.72, blue: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambientNode)

        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 16))
        busRoot.runAction(spin)

        return scene
    }
}
