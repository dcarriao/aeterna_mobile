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
    private var salvou = false
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
                let videoTypes = [
                    UTType.movie.identifier,
                    UTType.mpeg4Movie.identifier,
                    UTType.quickTimeMovie.identifier,
                    UTType.video.identifier,
                ]
                iosShareLog("uti=\(attachment.registeredTypeIdentifiers.joined(separator: ","))")
                let isImage = imageTypes.contains(where: { attachment.hasItemConformingToTypeIdentifier($0) })
                let isVideo = videoTypes.contains(where: { attachment.hasItemConformingToTypeIdentifier($0) })
                guard isImage || isVideo else {
                    iosShareLog("attachment ignorado (não conforma a imagem/vídeo)")
                    continue
                }

                let typeId = isVideo ? UTType.movie.identifier : UTType.image.identifier
                group.enter()
                attachment.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    if let error { iosShareLog("loadItem erro=\(error.localizedDescription)") }
                    guard let self, !self.salvou else { return }

                    let shareId = UUID().uuidString
                    var filePath: String?

                    if let url = data as? URL {
                        filePath = self.copyToAppGroup(url, shareId: shareId, isVideo: isVideo)
                        iosShareLog("origem=URL copied_path=\(filePath ?? "FALHOU")")
                    } else if let image = data as? UIImage {
                        filePath = self.saveImageToAppGroup(image, shareId: shareId)
                        iosShareLog("origem=UIImage copied_path=\(filePath ?? "FALHOU")")
                    } else if let raw = data as? Data {
                        filePath = self.saveDataToAppGroup(raw, shareId: shareId, isVideo: isVideo)
                        iosShareLog("origem=Data copied_path=\(filePath ?? "FALHOU")")
                    } else {
                        iosShareLog("origem=tipo inesperado \(String(describing: data))")
                    }

                    if let path = filePath {
                        self.writeManifest(shareId: shareId, filePath: path)
                        self.salvou = true
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
    private func copyToAppGroup(_ url: URL, shareId: String, isVideo: Bool = false) -> String? {
        guard let container = containerURL() else { return nil }
        let ext = isVideo
            ? (url.pathExtension.isEmpty ? "mp4" : url.pathExtension.lowercased())
            : "jpg"
        let dest = container.appendingPathComponent("share_\(shareId).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest.path
        } catch {
            // File provider / Photos às vezes exige security-scoped access.
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                return dest.path
            } catch {
                iosShareLog("copyItem falhou: \(error.localizedDescription)")
                return nil
            }
        }
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

    private func saveDataToAppGroup(_ data: Data, shareId: String, isVideo: Bool) -> String? {
        guard let container = containerURL() else { return nil }
        let dest = container.appendingPathComponent(
            "share_\(shareId).\(isVideo ? "mp4" : "jpg")")
        try? FileManager.default.removeItem(at: dest)
        do {
            try data.write(to: dest)
            return dest.path
        } catch {
            iosShareLog("saveData falhou: \(error.localizedDescription)")
            return nil
        }
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
        iosShareLog("completion=completeRequest chamado salvou=\(salvou)")
        // S.9.3.2 (Item 8) — feedback visual: antes, a extensão fechava em
        // silêncio e parecia quebrada. Mostra confirmação por 1,4s quando o
        // conteúdo foi salvo no App Group.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.salvou {
                self.mostrarConfirmacao()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    self.finalizar()
                }
            } else {
                self.finalizar()
            }
        }
    }

    private func finalizar() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: { expired in
            iosShareLog("completion=finalizado expired=\(expired)")
        })
    }

    private func mostrarConfirmacao() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.29, green: 0.18, blue: 0.42, alpha: 0.96)
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = "✓ Enviado para o aEterna\nAbra o app para criar a memória"
        label.textColor = .white
        label.numberOfLines = 2
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
        ])
    }
}
