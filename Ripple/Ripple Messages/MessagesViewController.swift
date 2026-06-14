//
//  MessagesViewController.swift
//  Ripple Messages
//
//  Principal class of the iMessage extension. Hosts the SwiftUI composer and
//  owns the active conversation, so it does the conversation.insert when the
//  composer hands back a link. We insert (not send) so the user reviews and
//  taps send themselves — App Store-safe and less spammy.
//

import Messages
import SwiftUI

class MessagesViewController: MSMessagesAppViewController {

    private var hosting: UIHostingController<ComposerView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let composer = ComposerView { [weak self] link in
            self?.insert(link)
        }
        let host = UIHostingController(rootView: composer)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hosting = host
    }

    /// Open straight into the expanded composer (the compact strip is too small
    /// for the paste field + recents).
    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        if presentationStyle == .compact {
            requestPresentationStyle(.expanded)
        }
    }

    private func insert(_ link: RippleLink) {
        Task {
            let image = await cardImage(for: link)
            await MainActor.run {
                guard let conversation = self.activeConversation else { return }
                let message = RippleMessageCard.makeMessage(for: link, image: image)
                conversation.insert(message) { [weak self] _ in
                    DispatchQueue.main.async { self?.requestPresentationStyle(.compact) }
                }
            }
        }
    }

    /// Real product photo framed on a card, or the branded fallback.
    private func cardImage(for link: RippleLink) async -> UIImage {
        if let s = link.ogImage, let url = URL(string: s),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let photo = UIImage(data: data) {
            return RippleMessageCard.productCard(photo, title: link.ogTitle)
        }
        return RippleMessageCard.brandedImage(title: link.ogTitle)
    }
}
