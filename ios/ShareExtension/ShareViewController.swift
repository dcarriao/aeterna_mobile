import UIKit
import UniformTypeIdentifiers
import os.log

/// S.9.3.1 (Item 8) — logs [IOS_SHARE] visíveis no Console.app / Xcode
/// (subsystem com.aeterna.share) para auditar o handoff completo.
private let shareLog = OSLog(subsystem: "com.aeterna.share", category: "IOS_SHARE")
private func iosShareLog(_ msg: String) {
    os_log("[IOS_SHARE] %{public}@", log: shareLog, type: .default, msg)
    NSLog("[IOS_SHARE] %@", msg)
}

/// Share Extension — aEterna
///
/// Arquitetura: App Group + manifesto por compartilhamento.
/// A extensão NÃO tenta abrir o app principal (API não suportada em
/// Share Extensions no iOS). Em vez disso, ela salva um arquivo de imagem
/// e um manifesto JSON independentes no App Group e chama completeRequest.
/// O app principal consome as pendências ao abrir (cold start) ou ao
/// voltar ao foreground, via MethodChannel "com.aeterna.app/share".
class ShareViewController: UIViewController {

    private var completou = false
    private let appGroupId = "group.com.aeterna.app"

    override func viewDidLoad() {
        super.viewDidLoad()
        // Equivalente ao didSelectPost() de uma SLComposeService — ponto
        // de entrada da extensão após o usuário tocar em "aEterna".
        iosShareLog("did_select_post=true (viewDidLoad)")
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            iosShareLog("attachments=0 (inputItems vazio)")
            completeRequest()
            return
        }

        let totalAttachments = items.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        iosShareLog("attachments=\(totalAttachments)")

        let group = DispatchGroup()
        var savedOne = false

        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                let imageTypes = [
                    UTType.image.identifier,
                    UTType.jpeg.identifier,
                    UTType.png.identifier,
                    UTType.heic.identifier,
                    UTType.heif.identifier,
                ]
                iosShareLog("uti=\(attachment.registeredTypeIdentifiers.joined(separator: ","))")
                guard imageTypes.contains(where: { attachment.hasItemConformingToTypeIdentifier($0) })
                else {
                    iosShareLog("attachment ignorado (não conforma a imagem)")
                    continue
                }

                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    if let error { iosShareLog("loadItem erro=\(error.localizedDescription)") }
                    guard let self, !savedOne else { return }

                    let shareId = UUID().uuidString
                    var filePath: String?

                    if let url = data as? URL {
                        filePath = self.copyToAppGroup(url, shareId: shareId)
                        iosShareLog("origem=URL copied_path=\(filePath ?? "FALHOU")")
                    } else if let image = data as? UIImage {
                        filePath = self.saveImageToAppGroup(image, shareId: shareId)
                        iosShareLog("origem=UIImage copied_path=\(filePath ?? "FALHOU")")
                    } else {
                        iosShareLog("origem=tipo inesperado \(String(describing: data))")
                    }

                    if let path = filePath {
                        self.writeManifest(shareId: shareId, filePath: path)
                        savedOne = true
                    }
                }
            }
        }

        // Timeout de segurança: garante que completeRequest sempre é chamado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.completou else { return }
            self.completou = true
            self.completeRequest()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, !self.completou else { return }
            self.completou = true
            self.completeRequest()
        }
    }

    // MARK: — App Group helpers

    private func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    /// Copia um arquivo de URL já existente para o App Group.
    private func copyToAppGroup(_ url: URL, shareId: String) -> String? {
        guard let container = containerURL() else { return nil }
        let dest = container.appendingPathComponent("share_\(shareId).jpg")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        return dest.path
    }

    /// Comprime e salva um UIImage diretamente no App Group.
    private func saveImageToAppGroup(_ image: UIImage, shareId: String) -> String? {
        guard let jpegData = image.jpegData(compressionQuality: 0.85),
              let container = containerURL() else { return nil }
        let dest = container.appendingPathComponent("share_\(shareId).jpg")
        try? FileManager.default.removeItem(at: dest)
        try? jpegData.write(to: dest)
        return dest.path
    }

    /// Grava um manifesto JSON individual por compartilhamento.
    /// Um arquivo por share_id evita race condition quando dois
    /// compartilhamentos chegam simultaneamente.
    private func writeManifest(shareId: String, filePath: String) {
        guard let container = containerURL() else {
            iosShareLog("manifest=FALHOU (App Group container nil — verificar entitlement group.com.aeterna.app no profile da extensão)")
            return
        }
        let manifest: [String: String] = [
            "share_id": shareId,
            "file_path": filePath,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest) else { return }
        let dest = container.appendingPathComponent("share_\(shareId).json")
        do {
            try data.write(to: dest)
            iosShareLog("manifest=\(String(data: data, encoding: .utf8) ?? "?") gravado em \(dest.lastPathComponent)")
        } catch {
            iosShareLog("manifest=FALHOU erro=\(error.localizedDescription)")
        }
    }

    private func completeRequest() {
        iosShareLog("completion=completeRequest chamado")
        extensionContext?.completeRequest(returningItems: [], completionHandler: { expired in
            iosShareLog("completion=finalizado expired=\(expired)")
        })
    }
}
