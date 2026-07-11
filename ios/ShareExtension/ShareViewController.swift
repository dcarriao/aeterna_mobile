import UIKit
import UniformTypeIdentifiers

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
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

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
                guard imageTypes.contains(where: { attachment.hasItemConformingToTypeIdentifier($0) })
                else { continue }

                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, _ in
                    defer { group.leave() }
                    guard let self, !savedOne else { return }

                    let shareId = UUID().uuidString
                    var filePath: String?

                    if let url = data as? URL {
                        filePath = self.copyToAppGroup(url, shareId: shareId)
                    } else if let image = data as? UIImage {
                        filePath = self.saveImageToAppGroup(image, shareId: shareId)
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
        guard let container = containerURL() else { return }
        let manifest: [String: String] = [
            "share_id": shareId,
            "file_path": filePath,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest) else { return }
        let dest = container.appendingPathComponent("share_\(shareId).json")
        try? data.write(to: dest)
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
