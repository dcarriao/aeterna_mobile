import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        DispatchQueue.main.async {
            guard let windowScene = scene as? UIWindowScene,
                  let controller = windowScene.windows.first?.rootViewController
                      as? FlutterViewController,
                  let app = UIApplication.shared.delegate as? AppDelegate
            else {
                NSLog("[IOS_SHARE] SceneDelegate: FlutterViewController indisponivel")
                return
            }
            app.registerShareChannel(messenger: controller.binaryMessenger)
        }
    }
}
