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
        UNUserNotificationCenter.current().delegate = self
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                result(true)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Consome o compartilhamento pendente mais antigo do App Group.
    func consumePendingShare() -> String? {
        let fm = FileManager.default
        guard let container = fm.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            NSLog("[IOS_SHARE] APP: container do App Group NULO")
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
        else { return nil }

        try? fm.removeItem(at: manifestURL)
        let imageName = URL(fileURLWithPath: filePath).lastPathComponent
        try? fm.removeItem(at: container.appendingPathComponent(imageName))

        return filePath
    }
}
