import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let appGroupId = "group.com.aeterna.app"

    // MARK: — Push diagnóstico nativo (visível via MethodChannel, sem travar startup)

    static var pushDiagnosticoNativo: [String] = []
    private static func diagPush(_ msg: String) {
        let linha = "\(ISO8601DateFormatter().string(from: Date())) \(msg)"
        pushDiagnosticoNativo.append(linha)
        if pushDiagnosticoNativo.count > 20 { pushDiagnosticoNativo.removeFirst() }
        NSLog("[PUSH_IOS_NATIVE] %@", msg)
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        // S.2.2.3 — registro explícito: swizzling do Firebase pode não funcionar
        // com FlutterAppDelegate + FlutterImplicitEngineDelegate.
        // Chamado APÓS super para o engine Flutter já estar configurado.
        Self.diagPush("registerForRemoteNotifications chamado")
        application.registerForRemoteNotifications()

        return result
    }

    // MARK: — APNs callbacks (com super para manter swizzling do Firebase)

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        let parcial = String(tokenStr.prefix(8))
        Self.diagPush("didRegister APNs ok token=\(parcial)...")
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.diagPush("didFail APNs: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    // MARK: — Implicit engine

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AeternaSharePlugin") else {
            NSLog("[IOS_SHARE] registerShareChannel FALHOU: registrar nil")
            return
        }
        registerShareChannel(messenger: registrar.messenger())
    }

    // MARK: — MethodChannel "com.aeterna.app/share"

    func registerShareChannel(messenger: FlutterBinaryMessenger) {
        NSLog("[IOS_SHARE] canal com.aeterna.app/share registrado")
        let channel = FlutterMethodChannel(name: "com.aeterna.app/share", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            if call.method == "getSharedImage" {
                let path = self?.consumePendingShare()
                NSLog("[IOS_SHARE] getSharedImage -> %@", path ?? "nil (sem pendência)")
                result(path)
            } else if call.method == "getPushDiagnostico" {
                result(Self.pushDiagnosticoNativo)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: — Share

    func consumePendingShare() -> String? {
        let fm = FileManager.default
        guard let container = fm.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            NSLog("[IOS_SHARE] APP: container do App Group NULO — o profile do app não inclui group.com.aeterna.app")
            return nil
        }
        NSLog("[IOS_SHARE] APP: lendo pendências em %@", container.path)

        guard let contents = try? fm.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

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

        try? fm.removeItem(at: manifestURL)
        let imageName = URL(fileURLWithPath: filePath).lastPathComponent
        try? fm.removeItem(at: container.appendingPathComponent(imageName))

        return filePath
    }
}
