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
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        // S.9.3.2 (Item 8) — FALLBACK de registro do canal de share.
        // didInitializeImplicitFlutterEngine pode não disparar em todos os
        // ciclos de vida; sem canal registrado, o Flutter recebe
        // MissingPluginException e o compartilhamento "some".
        // Registrar duas vezes é inofensivo (o segundo handler substitui).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let controller = self.window?.rootViewController as? FlutterViewController {
                NSLog("[IOS_SHARE] fallback: registrando canal via rootViewController")
                let channel = FlutterMethodChannel(
                    name: "com.aeterna.app/share",
                    binaryMessenger: controller.binaryMessenger
                )
                channel.setMethodCallHandler { [weak self] call, resultCb in
                    if call.method == "getSharedImage" {
                        let path = self?.consumePendingShare()
                        NSLog("[IOS_SHARE] getSharedImage(fallback) -> %@", path ?? "nil (sem pendência)")
                        resultCb(path)
                    } else {
                        resultCb(FlutterMethodNotImplemented)
                    }
                }
            } else {
                NSLog("[IOS_SHARE] fallback: rootViewController não é FlutterViewController")
            }
        }
        return result
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
        guard let registrar = registry.registrar(forPlugin: "AeternaSharePlugin") else {
            NSLog("[IOS_SHARE] registerShareChannel FALHOU: registrar nil")
            return
        }
        NSLog("[IOS_SHARE] canal com.aeterna.app/share registrado")
        let channel = FlutterMethodChannel(
            name: "com.aeterna.app/share",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] call, result in
            if call.method == "getSharedImage" {
                let path = self?.consumePendingShare()
                NSLog("[IOS_SHARE] getSharedImage -> %@", path ?? "nil (sem pendência)")
                result(path)
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
