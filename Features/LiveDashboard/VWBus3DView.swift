import SwiftUI
import SceneKit
import UIKit

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
        let scene: SCNScene
        if let url = Bundle.main.url(forResource: "Volkswagen Type 2 Kombi T1 1967", withExtension: "fbx", subdirectory: "Models"),
           let source = SCNSceneSource(url: url, options: nil),
           let loaded = source.scene(options: nil) {
            scene = makeLoadedModelScene(from: loaded)
        } else {
            scene = makeFallbackScene()
        }

        scene.background.contents = UIColor.clear
        return scene
    }

    private static func makeLoadedModelScene(from loadedScene: SCNScene) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let content = loadedScene.rootNode.clone()
        normalize(node: content, targetSize: 2.1)
        content.position = SCNVector3(0, -0.28, 0)
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 18))
        content.runAction(spin)
        scene.rootNode.addChildNode(content)

        addCommonLightingAndCamera(to: scene)
        return scene
    }

    private static func makeFallbackScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

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
        busRoot.scale = SCNVector3(0.95, 0.95, 0.95)
        busRoot.position = SCNVector3(0, -0.16, 0)
        scene.rootNode.addChildNode(busRoot)

        addCommonLightingAndCamera(to: scene)

        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 16))
        busRoot.runAction(spin)

        return scene
    }

    private static func addCommonLightingAndCamera(to scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 34
        cameraNode.position = SCNVector3(0, 0.9, 3.1)
        scene.rootNode.addChildNode(cameraNode)

        let keyLightNode = SCNNode()
        keyLightNode.light = SCNLight()
        keyLightNode.light?.type = .omni
        keyLightNode.light?.intensity = 1450
        keyLightNode.position = SCNVector3(2.2, 3.8, 3.5)
        scene.rootNode.addChildNode(keyLightNode)

        let fillLightNode = SCNNode()
        fillLightNode.light = SCNLight()
        fillLightNode.light?.type = .omni
        fillLightNode.light?.intensity = 760
        fillLightNode.position = SCNVector3(-2.4, 2.0, 2.8)
        scene.rootNode.addChildNode(fillLightNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 300
        ambientNode.light?.color = UIColor(red: 0.64, green: 0.73, blue: 0.86, alpha: 1)
        scene.rootNode.addChildNode(ambientNode)
    }

    private static func normalize(node: SCNNode, targetSize: Float) {
        let (minBounds, maxBounds) = node.boundingBox
        let size = SCNVector3(maxBounds.x - minBounds.x, maxBounds.y - minBounds.y, maxBounds.z - minBounds.z)
        let maxDimension = max(size.x, max(size.y, size.z))
        guard maxDimension > 0.0001 else { return }

        let scale = targetSize / maxDimension
        node.scale = SCNVector3(scale, scale, scale)

        let center = SCNVector3(
            (minBounds.x + maxBounds.x) * 0.5,
            (minBounds.y + maxBounds.y) * 0.5,
            (minBounds.z + maxBounds.z) * 0.5
        )
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
    }
}
