import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

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
        var resultURL: URL?

        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {

                // ── Imagem ────────────────────────────────────────────────
                let imageTypes = [
                    UTType.image.identifier,
                    UTType.jpeg.identifier,
                    UTType.png.identifier,
                    UTType.heic.identifier,
                    UTType.heif.identifier,
                ]
                let conformsToImage = imageTypes.contains {
                    attachment.hasItemConformingToTypeIdentifier($0)
                }

                if conformsToImage {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { data, _ in
                        defer { group.leave() }
                        guard resultURL == nil else { return }
                        NSLog("[IOS_SHARE] inicio — tipo: image")
                        if let url = data as? URL {
                            resultURL = self.saveMediaToSharedContainer(url, mediaType: "image")
                        } else if let image = data as? UIImage {
                            resultURL = self.saveUIImageToSharedContainer(image)
                        }
                    }
                    continue
                }

                // ── Vídeo ─────────────────────────────────────────────────
                let videoTypes = [
                    UTType.movie.identifier,
                    UTType.video.identifier,
                    "public.movie",
                    "public.video",
                    "com.apple.quicktime-movie",
                ]
                let conformsToVideo = videoTypes.contains {
                    attachment.hasItemConformingToTypeIdentifier($0)
                }

                if conformsToVideo {
                    group.enter()
                    let typeId = attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                        ? UTType.movie.identifier
                        : "public.movie"
                    attachment.loadItem(forTypeIdentifier: typeId, options: nil) { data, _ in
                        defer { group.leave() }
                        guard resultURL == nil else { return }
                        NSLog("[IOS_SHARE] inicio — tipo: video")
                        if let url = data as? URL {
                            resultURL = self.saveMediaToSharedContainer(url, mediaType: "video")
                        }
                    }
                    continue
                }
            }
        }

        var completou = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !completou else { return }
            completou = true
            if let url = resultURL {
                self.launchMainApp(with: url)
            }
            self.completeRequest()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, !completou else { return }
            completou = true
            if let url = resultURL {
                self.launchMainApp(with: url)
            }
            self.completeRequest()
        }
    }

    // Salva qualquer arquivo de mídia (imagem ou vídeo) no App Group container.
    // Retorna a URL de destino no container.
    private func saveMediaToSharedContainer(_ sourceURL: URL, mediaType: String) -> URL? {
        guard let containerURL = FileManage