import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let appGroupId = "group.com.aeterna.app"

    /// Diagnóstico APNs / share — lido sob demanda via getPushDiag (nunca no startup Dart).
    static var pushDiag: [String] = []

    static func diagPush(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts) \(msg)"
        pushDiag.append(line)
        if pushDiag.count > 30 {
            pushDiag.removeFirst()
        }
        NSLog("[PUSH_IOS_NATIVE] %@", msg)
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: — APNs callbacks (sem Firebase imports — swizzling/Dart cuidam do token FCM)

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        AppDelegate.diagPush("didRegister APNs ok bytes=\(deviceToken.count)")
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        AppDelegate.diagPush("didFail APNs: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

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
                NSLog("[IOS_SHARE] getSharedImage -> %@", path ?? "nil (sem pendencia)")
                result(path)
            } else if call.method == "requestPushRegistration" {
                AppDelegate.diagPush("registerForRemoteNotifications() chamado")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                result(true)
            } else if call.method == "probeAppGroup" {
                let container = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: self?.appGroupId ?? ""
                )
                let ok = container != nil
                AppDelegate.diagPush(ok ? "probeAppGroup=ok" : "probeAppGroup=NULL")
                result(ok)
            } else if call.method == "getPushDiag" {
                result(AppDelegate.pushDiag)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Consome o compartilhamento pendente mais antigo do App Group.
    /// Copia para o temp do app ANTES de apagar o App Group — o Flutter
    /// lê o path retornado; apagar antes fazia `File.exists()` falhar.
    func consumePendingShare() -> String? {
        let fm = FileManager.default
        guard let container = fm.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            NSLog("[IOS_SHARE] APP: container do App Group NULO")
            AppDelegate.diagPush("share: container App Group NULO")
            return nil
        }
        NSLog("[IOS_SHARE] APP: lendo pendencias em %@", container.path)

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
        else {
            return nil
        }

        let sourceListed = URL(fileURLWithPath: filePath)
        let fileName = sourceListed.lastPathComponent
        var sourceURL = sourceListed
        if !fm.fileExists(atPath: sourceURL.path) {
            let alt = container.appendingPathComponent(fileName)
            if fm.fileExists(atPath: alt.path) {
                sourceURL = alt
            } else {
                NSLog("[IOS_SHARE] APP: arquivo ausente %@", fileName)
                AppDelegate.diagPush("share: arquivo_ausente \(fileName)")
                try? fm.removeItem(at: manifestURL)
                return nil
            }
        }

        let dest = fm.temporaryDirectory.appendingPathComponent("aeterna_\(fileName)")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            NSLog("[IOS_SHARE] APP: copy falhou %@", error.localizedDescription)
            AppDelegate.diagPush("share: copy_falhou \(error.localizedDescription)")
            return nil
        }

        try? fm.removeItem(at: manifestURL)
        try? fm.removeItem(at: sourceURL)
        AppDelegate.diagPush("share: pendencia_lida \(fileName)")
        NSLog("[IOS_SHARE] APP: pendencia_lida -> %@", dest.path)
        return dest.path
    }
}
