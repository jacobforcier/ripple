//
//  RippleLinkActivityItemSource.swift
//  Ripple Share
//
//  Supplies a Ripple link to UIActivityViewController as a plain String.
//
//  Why not a URL? When a Share Extension presents another UIActivityViewController
//  and hands a `URL` object to Messages, the URL arrives at Messages as a
//  bplist-encoded blob — the NSItemProvider isn't unwrapped correctly across
//  the extension boundary. A String is safe: Messages auto-detects URLs in
//  text and renders them as proper bubbles with previews; Mail, Notes, Slack,
//  and other targets also handle a URL-in-string cleanly.
//

import UIKit

final class RippleLinkActivityItemSource: NSObject, UIActivityItemSource {

    private let linkString: String

    init(linkString: String) {
        self.linkString = linkString
    }

    func activityViewControllerPlaceholderItem(_ ac: UIActivityViewController) -> Any {
        linkString
    }

    func activityViewController(
        _ ac: UIActivityViewController,
        itemForActivityType type: UIActivity.ActivityType?
    ) -> Any? {
        linkString
    }

    // Used by Mail (and other targets that ask for a subject).
    func activityViewController(
        _ ac: UIActivityViewController,
        subjectForActivityType type: UIActivity.ActivityType?
    ) -> String {
        "Ripple link"
    }
}
