import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private var hasPresentedShareSheet = false
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        // Slight dim so the spinner reads against the host app's content
        // while the Ripple link is being generated.
        view.backgroundColor = UIColor(white: 0, alpha: 0.15)
        setupSpinner()

        extractURL { [weak self] url in
            guard let self else { return }
            guard let url else {
                DispatchQueue.main.async { self.complete() }
                return
            }
            Task { await self.generateAndShare(from: url) }
        }
    }

    private func setupSpinner() {
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Generate the Ripple link, then re-share it

    private func generateAndShare(from url: URL) async {
        do {
            let rippleLink = try await RippleLinkService.shared.createLink(from: url)
            await MainActor.run {
                guard !self.hasPresentedShareSheet else { return }
                self.spinner.stopAnimating()
                UIPasteboard.general.string = rippleLink   // safety net
                self.presentShareSheet(with: rippleLink)
            }
        } catch {
            await MainActor.run {
                self.spinner.stopAnimating()
                self.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn't create a Ripple link",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.complete()
        })
        present(alert, animated: true)
    }

    private func presentShareSheet(with link: String) {
        guard !hasPresentedShareSheet else { return }
        hasPresentedShareSheet = true

        // Wrap the link in an item source rather than passing a raw URL. When
        // a Share Extension presents UIActivityViewController and hands a
        // `URL` to Messages, the URL arrives at Messages as a bplist-encoded
        // blob (visible in the chat as `bplist00%C2…`) — Messages doesn't
        // unwrap the NSItemProvider correctly across the extension boundary.
        // Returning the link as a String (which Messages auto-detects as a
        // URL and renders with a preview) sidesteps the issue.
        let source = RippleLinkActivityItemSource(linkString: link)

        let activity = UIActivityViewController(
            activityItems: [source],
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
