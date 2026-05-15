import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        // A dim backdrop so the confirmation card reads against any host UI.
        view.backgroundColor = UIColor(white: 0, alpha: 0.5)
        setupSpinner()

        extractURL { [weak self] url in
            guard let self else { return }
            guard let url else {
                DispatchQueue.main.async { self.complete() }
                return
            }
            Task { await self.generateAndShow(from: url) }
        }
    }

    // MARK: - Stages

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

    private func generateAndShow(from url: URL) async {
        do {
            let rippleLink = try await RippleLinkService.shared.createLink(from: url)
            await MainActor.run {
                UIPasteboard.general.string = rippleLink
                self.spinner.stopAnimating()
                self.spinner.removeFromSuperview()
                self.showConfirmation(link: rippleLink)
            }
        } catch {
            await MainActor.run {
                self.spinner.stopAnimating()
                self.spinner.removeFromSuperview()
                self.showError(error)
            }
        }
    }

    // MARK: - Confirmation UI
    //
    // We don't re-present a UIActivityViewController here. Passing the link to
    // Messages from within a Share Extension's UIActivityViewController results
    // in Messages rendering the link as a bplist-encoded blob — the extension
    // boundary mangles the activityItem serialization regardless of whether
    // it's a URL or a String. So instead: copy to clipboard, show a clear
    // confirmation card, and let the user paste wherever they want to send it.

    private func showConfirmation(link: String) {
        let card = UIView()
        card.backgroundColor = UIColor(red: 7/255, green: 7/255, blue: 15/255, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(white: 1, alpha: 0.10).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let wordmark = UILabel()
        wordmark.text = "ripple"
        wordmark.font = .systemFont(ofSize: 22, weight: .bold)
        wordmark.textColor = UIColor(red: 91/255, green: 138/255, blue: 245/255, alpha: 1)
        wordmark.textAlignment = .center

        let status = UILabel()
        status.text = "✓ Ripple link copied"
        status.font = .systemFont(ofSize: 17, weight: .semibold)
        status.textColor = .white
        status.textAlignment = .center

        let subtext = UILabel()
        subtext.text = "Paste it wherever you want to share."
        subtext.font = .systemFont(ofSize: 14)
        subtext.textColor = UIColor(white: 0.72, alpha: 1)
        subtext.textAlignment = .center

        let linkLabel = UILabel()
        linkLabel.text = link
        linkLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        linkLabel.textColor = UIColor(red: 56/255, green: 189/255, blue: 248/255, alpha: 1)
        linkLabel.textAlignment = .center
        linkLabel.lineBreakMode = .byTruncatingMiddle
        linkLabel.numberOfLines = 1
        linkLabel.backgroundColor = UIColor(white: 1, alpha: 0.04)
        linkLabel.layer.cornerRadius = 8
        linkLabel.layer.masksToBounds = true

        let doneButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Done"
        config.baseBackgroundColor = UIColor(red: 91/255, green: 138/255, blue: 245/255, alpha: 1)
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        doneButton.configuration = config
        doneButton.addAction(UIAction { [weak self] _ in self?.complete() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [wordmark, status, subtext, linkLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.setCustomSpacing(8, after: wordmark)
        stack.setCustomSpacing(6, after: status)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            linkLabel.heightAnchor.constraint(equalToConstant: 38),
        ])

        // Tap outside the card also dismisses, for a quick exit.
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        view.addGestureRecognizer(tap)
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        // Only dismiss if the tap was outside the card area.
        let location = gesture.location(in: view)
        let cardFrame = view.subviews.first(where: { $0.layer.cornerRadius == 18 })?.frame ?? .zero
        if !cardFrame.contains(location) {
            complete()
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
