import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    // MARK: - UI

    private let card: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 7/255, green: 7/255, blue: 15/255, alpha: 1)
        v.layer.cornerRadius = 24
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let logoLabel: UILabel = {
        let l = UILabel()
        l.text = "ripple"
        l.font = .systemFont(ofSize: 22, weight: .bold)
        l.textColor = UIColor(red: 91/255, green: 138/255, blue: 245/255, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.text = "Generating your link…"
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textColor = UIColor(white: 0.55, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractURL { [weak self] url in
            DispatchQueue.main.async {
                guard let self else { return }
                if let url {
                    let rippleLink = self.generateRippleLink(from: url)
                    UIPasteboard.general.string = rippleLink
                    self.showSuccess()
                } else {
                    self.showError()
                }
            }
        }
    }

    // MARK: - Link generation

    // DEMO MODE — swap this function when the Skimlinks backend is live:
    //
    //   func generateRippleLink(from url: URL) async throws -> String {
    //       var req = URLRequest(url: URL(string: "https://api.sharewithripple.com/v1/links")!)
    //       req.httpMethod = "POST"
    //       req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    //       req.httpBody = try JSONEncoder().encode(["url": url.absoluteString])
    //       let (data, _) = try await URLSession.shared.data(for: req)
    //       return try JSONDecoder().decode([String: String].self, from: data)["short_url"] ?? ""
    //   }
    //
    func generateRippleLink(from url: URL) -> String {
        let id = String(Int.random(in: 0x10000...0xFFFFF), radix: 36)
        return "https://sharewithripple.com/s/\(id)"
    }

    // MARK: - URL extraction

    func extractURL(completion: @escaping (URL?) -> Void) {
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

    // MARK: - States

    func showSuccess() {
        statusLabel.text = "✓ Ripple link copied"
        statusLabel.textColor = UIColor(red: 56/255, green: 189/255, blue: 248/255, alpha: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    func showError() {
        statusLabel.text = "Couldn't find a link to share"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.cancelRequest(
                withError: NSError(domain: "com.ripple.share", code: 0)
            )
        }
    }

    // MARK: - Layout

    func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        view.addSubview(card)
        card.addSubview(logoLabel)
        card.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 260),

            logoLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            logoLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
        ])
    }
}
