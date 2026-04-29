import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private var hasPresentedShareSheet = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        extractURL { [weak self] url in
            DispatchQueue.main.async {
                guard let self, !self.hasPresentedShareSheet else { return }
                guard let url else {
                    self.complete()
                    return
                }
                let rippleLink = self.generateRippleLink(from: url)
                UIPasteboard.general.string = rippleLink   // safety net
                self.presentShareSheet(with: rippleLink)
            }
        }
    }

    // MARK: - Re-share with the Ripple link

    private func presentShareSheet(with link: String) {
        guard !hasPresentedShareSheet else { return }
        hasPresentedShareSheet = true

        guard let rippleURL = URL(string: link) else {
            complete()
            return
        }

        let activity = UIActivityViewController(
            activityItems: [rippleURL],
            applicationActivities: nil
        )

        // Hide things that don't make sense for a link share
        activity.excludedActivityTypes = [
            .addToReadingList, .assignToContact, .openInIBooks, .saveToCameraRoll,
            .markupAsPDF, .print,
        ]

        // iPad popover anchor — center of the screen since we have no source view
        if let pop = activity.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }

        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.complete()
        }

        present(activity, animated: true)
    }

    // MARK: - Link generation
    //
    // DEMO MODE — swap this when the Skimlinks backend is live.
    private func generateRippleLink(from url: URL) -> String {
        let id = String(Int.random(in: 0x10000...0xFFFFF), radix: 36)
        return "https://sharewithripple.com/s/\(id)"
    }

    // MARK: - URL extraction

    private func extractURL(completion: @escaping (URL?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completion(nil)
            return
        }

        let urlType = UTType.url.identifier
        for attachment in attachments where attachment.hasItemConformingToTypeIdentifier(urlType) {
            attachment.loadItem(forTypeIdentifier: urlType) { data, _ in
                if let url = data as? URL {
                    completion(url)
                } else if let str = data as? String, let url = URL(string: str) {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
            return
        }
        completion(nil)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
