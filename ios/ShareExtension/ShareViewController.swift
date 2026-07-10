import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

// Sprint S.9.1 — Share Extension iOS
// Corrige o fluxo de compartilhamento:
//   - Usa extensionContext?.open() para abrir o host app (UIResponder chain não funciona em iOS 13+)
//   - Salva mídia em App Group container com UUID para evitar colisões
//   - Escreve manifest.json com metadados (share_id, file_path, media_type, timestamp)
//   - Suporta foto e vídeo
//   - URL: aeterna://share?manifest=<encoded_path>
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            NSLog("[IOS_SHARE] ERRO — extensionContext sem inputItems")
            completeRequest()
            return
        }

        let group = DispatchGroup()
        var fileURL: URL?
        var mediaType: String = "image"

        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {

                // — Foto
                let imageTypes = [
                    UTType.image.identifier,
                    UTType.jpeg.identifier,
                    UTType.png.identifier,
                    UTType.heic.identifier,
                    UTType.heif.identifier,
                ]
                let conformsToImage = imageTypes.contains { type in
                    attachment.hasItemConformingToTypeIdentifier(type)
                }

                // — Vídeo
                let videoTypes = [
                    UTType.movie.identifier,
                    UTType.video.identifier,
                    "public.movie",
                    "com.apple.quicktime-movie",
                ]
                let conformsToVideo = videoTypes.contains { type in
                    attachment.hasItemConformingToTypeIdentifier(type)
                }

                if conformsToVideo {
                    group.enter()
                    let typeId = UTType.movie.identifier
                    attachment.loadItem(forTypeIdentifier: typeId, options: nil) { data, error in
                        defer { group.leave() }
                        guard fileURL == nil else { return }
                        if let url = data as? URL {
                            fileURL = self.salvarMidiaNoContainer(url, extensao: "mp4")
                            mediaType = "video"
                            NSLog("[IOS_SHARE] Vídeo carregado: %@", url.lastPathComponent)
                        }
                    }
                } else if conformsToImage {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { data, error in
                        defer { group.leave() }
                        guard fileURL == nil else { return }
                        if let url = data as? URL {
                            fileURL = self.salvarMidiaNoContainer(url, extensao: "jpg")
                            mediaType = "image"
                            NSLog("[IOS_SHARE] Foto carregada: %@", url.lastPathComponent)
                        } else if let image = data as? UIImage {
                            fileURL = self.salvarUIImageNoContainer(image)
                            mediaType = "image"
                            NSLog("[IOS_SHARE] UIImage convertida e salva")
                        }
                    }
                }
            }
        }

        var completou = false

        // Timeout de segurança: 10 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !completou else { return }
            completou = true
            NSLog("[IOS_SHARE] Timeout atingido — prosseguindo")
            if let url = fileURL {
                self.escreverManifest(fileURL: url, mediaType: mediaType)
                self.launchMainApp()
            }
            self.completeRequest()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, !com