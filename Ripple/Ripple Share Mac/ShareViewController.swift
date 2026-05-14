//
//  ShareViewController.swift
//  Ripple Share Mac
//
//  macOS Share Extension — turns a shared product URL into a Ripple link
//  and copies it to the clipboard.
//
//  Unlike iOS, macOS share extensions can't cleanly re-present the system
//  share sheet, so the flow here is: extract URL → generate Ripple link →
//  copy to the pasteboard → show a confirmation the user can dismiss.
//

import Cocoa

class ShareViewController: NSViewController {

    // MARK: - UI

    private let statusLabel = NSTextField(labelWithString: "Generating your Ripple link…")
    private let linkField = NSTextField(labelWithString: "")
    private let doneButton = NSButton()

    private var hasGeneratedLink = false

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 240))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 7/255, green: 7/255, blue: 15/255, alpha: 1).cgColor
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        extractURL { [weak self] url in
            DispatchQueue.main.async {
                guard let self, !self.hasGeneratedLink else { return }
                guard let url else {
                    self.statusLabel.stringValue = "No link found to share."
                    return
                }
                self.hasGeneratedLink = true

                let rippleLink = self.generateRippleLink(from: url)

                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(rippleLink, forType: .string)

                self.statusLabel.stringValue = "Ripple link copied to your clipboard"
                self.linkField.stringValue = rippleLink
                self.linkField.isHidden = false
            }
        }
    }

    // MARK: - Layout

    private func setupUI() {
        let wordmark = NSTextField(labelWithString: "ripple")
        wordmark.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        wordmark.textColor = NSColor(red: 91/255, green: 138/255, blue: 245/255, alpha: 1)
        wordmark.backgroundColor = .clear
        wordmark.isBezeled = false
        wordmark.isEditable = false

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = NSColor(white: 0.93, alpha: 1)
        statusLabel.backgroundColor = .clear
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        // Selectable so the user can also copy the link manually if they want.
        linkField.font = NSFont.userFixedPitchFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
        linkField.textColor = NSColor(red: 56/255, green: 189/255, blue: 248/255, alpha: 1)
        linkField.backgroundColor = NSColor(white: 1, alpha: 0.04)
        linkField.isBezeled = false
        linkField.isEditable = false
        linkField.isSelectable = true
        linkField.alignment = .center
        linkField.isHidden = true
        linkField.wantsLayer = true
        linkField.layer?.cornerRadius = 8
        linkField.lineBreakMode = .byTruncatingMiddle

        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)

        let stack = NSStackView(views: [wordmark, statusLabel, linkField, doneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            statusLabel.widthAnchor.constraint(equalToConstant: 300),
            linkField.widthAnchor.constraint(equalToConstant: 320),
            linkField.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    // MARK: - Actions

    @objc private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - Link generation
    //
    // DEMO MODE — swap this when the affiliate backend is live.
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

        // "public.url" is the well-known UTI for URLs — using the string literal
        // keeps this compatible with the 10.14 deployment target (UTType is 11.0+).
        let urlType = "public.url"
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
}
