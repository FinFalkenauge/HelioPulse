import SwiftUI
import SceneKit

struct VWBus3DView: View {
    private let scene: SCNScene? = VWBus3DView.makeScene()

    var body: some View {
        Group {
            if let scene {
                SceneView(
                    scene: scene,
                    pointOfView: nil,
                    options: [.autoenablesDefaultLighting, .allowsCameraControl]
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    VStack(spacing: 6) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text("3D Modell nicht lesbar")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .frame(height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func makeScene() -> SCNScene? {
        guard let url = Bundle.main.url(forResource: "Volkswagen Type 2 Kombi T1 1967", withExtension: "fbx", subdirectory: "Models") else {
            return nil
        }

        guard let source = SCNSceneSource(url: url, options: nil),
              let scene = source.scene(options: nil) else {
            return nil
        }

        let root = scene.rootNode
        root.scale = SCNVector3(0.015, 0.015, 0.015)
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 14))
        root.runAction(spin)
        return scene
    }
}
