//
//  RippleMessageCard.swift
//  Ripple Messages
//
//  Builds the MSMessage that gets inserted into a conversation. The bubble's
//  url is the Ripple redirect link, so tapping it opens the disclosure +
//  product page — and recipients without the app still get a tappable preview.
//

import Messages
import UIKit

enum RippleMessageCard {

    static func makeMessage(for link: RippleLink, image: UIImage? = nil) -> MSMessage {
        let layout = MSMessageTemplateLayout()
        layout.caption = link.ogTitle ?? "A product I recommend"
        layout.subcaption = "Recommended via Ripple"
        layout.image = image ?? brandedImage(title: link.ogTitle)

        let message = MSMessage(session: MSSession())
        message.layout = layout
        message.url = URL(string: link.rippleURL)
        message.summaryText = "Shared a recommendation via Ripple"
        return message
    }

    /// Frames a real product photo on a clean card with a small ripple badge —
    /// aspect-fit so odd photo ratios aren't awkwardly cropped by Messages.
    static func productCard(_ photo: UIImage, title: String?) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // aspect-fit the photo into a padded region
            let pad: CGFloat = 28
            let box = CGRect(x: pad, y: pad, width: size.width - pad * 2, height: size.height - pad * 2)
            let scale = min(box.width / photo.size.width, box.height / photo.size.height)
            let w = photo.size.width * scale, h = photo.size.height * scale
            photo.draw(in: CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))

            // ripple badge, bottom-right
            let badge = CGRect(x: size.width - 168, y: size.height - 70, width: 140, height: 46)
            let accent = UIColor(red: 0.36, green: 0.54, blue: 0.96, alpha: 1)
            UIBezierPath(roundedRect: badge, cornerRadius: 23).addClip()
            accent.setFill(); UIRectFill(badge)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                .foregroundColor: UIColor.white,
            ]
            ("ripple" as NSString).draw(at: CGPoint(x: badge.minX + 22, y: badge.minY + 9), withAttributes: attrs)
        }
    }

    /// A branded fallback card drawn when there's no product image yet.
    static func brandedImage(title: String?) -> UIImage {
        let size = CGSize(width: 600, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext
            // brand gradient backdrop
            let colors = [UIColor(red: 0.10, green: 0.13, blue: 0.30, alpha: 1).cgColor,
                          UIColor(red: 0.07, green: 0.09, blue: 0.18, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: .zero,
                                 end: CGPoint(x: size.width, y: size.height), options: [])
            // wordmark
            let mark = "ripple"
            let markAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .heavy),
                .foregroundColor: UIColor(red: 0.45, green: 0.65, blue: 1, alpha: 1),
            ]
            (mark as NSString).draw(at: CGPoint(x: 40, y: 36), withAttributes: markAttrs)
            // product title / prompt
            let t = (title ?? "A product I recommend")
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let rect = CGRect(x: 40, y: 150, width: size.width - 80, height: 150)
            (t as NSString).draw(with: rect, options: .usesLineFragmentOrigin,
                                 attributes: titleAttrs, context: nil)
        }
    }
}
