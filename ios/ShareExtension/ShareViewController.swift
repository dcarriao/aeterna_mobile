import UIKit
import Social
import MobileCoreServices

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let group = DispatchGroup()
        var firstImageUrl: URL?

        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                guard attachment.hasItemConformingToTypeIdentifier(kUTTypeImage as String) else { continue }
                group.enter()
                attachment.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { data, error in
                    defer { group.leave() }
                    guard firstImageUrl == nil else { return }
                    if let url = data as? URL {
                        firstImageUrl = self.saveToSharedContainer(url)
                    } else if let image = data as? UIImage {
                        firstImageUrl = self.saveImageToSharedContainer(image)
                    }
                }
            }
        }

        var completou = false
        // Safety timeout: force completion after 10s even if loadItem hangs
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !completou else { return }
            completou = true
            if let url = firstImageUrl {
                self.launchMainApp(with: url)
            }
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, !completou else { return }
            completou = true
            if let url = firstImageUrl {
                self.launchMainApp(with: url)
            }
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    private func saveToSharedContainer(_ url: URL) -> URL? {
        guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.aeterna.app") else {
            return url // fallback: pass original URL
        }
        let dest = sharedURL.appendingPathComponent("shared_image.jpg")
        try? FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    private func saveImageToSharedContainer(_ image: UIImage) -> URL? {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return nil }
        if let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.aeterna.app") {
            let fileURL = sharedURL.appendingPathComponent("shared_image.jpg")
            try? jpegData.write(to: fileURL)
            return fileURL
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("shared_image.jpg")
        try? jpegData.write(to: tempURL)
        return tempURL
    }

    private func launchMainApp(with imageURL: URL) {
        guard let encodedPath = imageURL.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "aeterna://share?image=\(encodedPath)") else { return }
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(appURL, options: [:], completionHandler: nil)
                break
            }
            responder = responder?.next
        }
    }
}
