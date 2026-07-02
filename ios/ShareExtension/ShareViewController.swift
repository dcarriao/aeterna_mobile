import UIKit
import Social
import MobileCoreServices
import Photos

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        
        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                    attachment.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { [weak self] (data, error) in
                        guard let self = self else { return }
                        var imageUrl: URL?
                        
                        if let url = data as? URL {
                            imageUrl = url
                        } else if let image = data as? UIImage {
                            if let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.aeterna.app") {
                                let fileURL = sharedURL.appendingPathComponent("shared_image.jpg")
                                if let jpegData = image.jpegData(compressionQuality: 0.8) {
                                    try? jpegData.write(to: fileURL)
                                    imageUrl = fileURL
                                }
                            }
                        }
                        
                        if let url = imageUrl {
                            self.launchMainApp(with: url)
                        }
                    }
                }
            }
        }
        
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
    
    private func launchMainApp(with imageURL: URL) {
        let urlScheme = "aeterna://share?image=\(imageURL.path)"
        if let appURL = URL(string: urlScheme) {
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
}
