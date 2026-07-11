import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let appGroupId = "group.com.aeterna.app"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Sprint R.4 — registra delegate para notificações push
        UNUserNotificationCenter.current().delegate = self
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerShareChannel(registry: engineBridge.pluginRegistry)
    }

    // MARK: — MethodChannel "com.aeterna.app/share"
    //
    // Mesmo canal usado pelo Android (MainActivity.kt → getSharedImage).
    // O Flutter já chama esse canal em cold start e ao voltar ao foreground
    // (_verificarCompartilhamentoPendente em main.dart).

    private func registerShareChannel(registry: FlutterPluginRegistry) {
        let registrar = registry.registrar(forPlugin: "AeternaSharePlugin")
        let channel = FlutterMethodChannel(
            name: "com.aeterna.app/share",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] call, result in
            if call.method == "getSharedImage" {
                result(self?.consumePendingShare())
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Consome o compartilhamento pendente mais antigo do App Group.
    /// Deleta o manifesto JSON e a imagem após leitura.
    /// Retorna o caminho do arquivo de imagem, ou nil se não houver pendências.
    private func consumePendingShare() -> String? {
        let fm = FileManager.default
        guard let container = fm.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return nil }

        guard let contents = try? fm.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        // Filtra e ordena manifestos por data de criação (mais antigo primeiro)
        let manifests = contents
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("share_") }
            .sorted {
                let da = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
                let db = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
                return da < db
            }

        guard let manifestURL = manifests.first,
              let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let filePath = json["file_path"]
        else { return nil }

        // Deleta manifesto e imagem (best-effort)
        try? fm.removeItem(at: manifestURL)
        let imageName = URL(fileURLWithPath: filePath).lastPathComponent
        try? fm.removeItem(at: container.appendingPathComponent(imageName))

        return filePath
    }
}
