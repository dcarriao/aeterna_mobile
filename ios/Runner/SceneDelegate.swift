import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    // S.9.4c (Item 11 — galeria): com UIScene, AppDelegate.window é nil e
    // o canal de share nunca era registrado → o Flutter recebia
    // MissingPluginException e o conteúdo compartilhado "sumia".
    // Aqui a janela existe de verdade.
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
                NSLog("[IOS_SHARE] SceneDelegate: FlutterViewController indisponível")
                return
            }
            app.registerShareChannel(messenger: controller.binaryMessenger)
        }
    }
}
