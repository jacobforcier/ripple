//
//  RippleLinkService.swift
//  Ripple Messages
//
//  Self-contained backend client for the iMessage extension. Mirrors the Share
//  Extension's service (same App Group anonymous identity, so links sent from
//  Messages earn the same person), plus two read endpoints the composer needs:
//  listLinks() for the "recent recommendations" picker and preview() for the
//  product card's title/image.
//
//  The App Group id and user-id key MUST match the app's LiveRippleAPI and the
//  Share Extension's RippleLinkService.
//

import Foundation

struct RippleLink: Identifiable, Equatable {
    let id: String
    let rippleURL: String
    let sourceURL: String
    var retailer: String?
    var ogTitle: String?
    var ogImage: String?
}

enum RippleLinkServiceError: LocalizedError {
    case badURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL:          return "That doesn't look like a product link."
        case .server(let msg): return msg
        }
    }
}

struct RippleLinkService {
    static let shared = RippleLinkService()

    // These two must match the main app's LiveRippleAPI + the Share Extension.
    private let appGroupID = "group.com.ripple.sharewithripple"
    private let userIdKey = "ripple.anonymousUserId"
    private let baseURL = "https://api.sharewithripple.com"
    private let webBase = "https://sharewithripple.com"

    private func rippleURL(forId id: String) -> String { "\(webBase)/s/\(id)" }

    // MARK: - Create

    /// Creates a Ripple link for a product URL, attributed to this device's
    /// anonymous user. Best-effort fills og title/image from the preview so the
    /// card is rich.
    func createLink(from sourceURL: URL) async throws -> RippleLink {
        guard let scheme = sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              sourceURL.host != nil
        else { throw RippleLinkServiceError.badURL }

        #if targetEnvironment(simulator)
        // The simulator inherits this Mac's network, where a local TLS filter
        // blocks api.sharewithripple.com (documented — same issue that blanked
        // the Journey tab). Short-circuit to a stub so the composer + card
        // insert can be exercised in the simulator. Real devices hit live.
        return RippleLink(id: "sim\(Int.random(in: 1000...9999))",
                          rippleURL: "https://sharewithripple.com/s/simdemo",
                          sourceURL: sourceURL.absoluteString,
                          retailer: sourceURL.host?.contains("amazon") == true ? "amazon" : nil,
                          ogTitle: "Sample product (simulator)", ogImage: nil)
        #else
        let userId = try await anonymousUserId()
        let data = try await request("POST", "/v1/links", body: [
            "source_url": sourceURL.absoluteString,
            "user_id": userId,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let url = json["ripple_url"] as? String
        else { throw RippleLinkServiceError.server("Unexpected response from the server.") }

        var link = RippleLink(id: id, rippleURL: url,
                              sourceURL: sourceURL.absoluteString,
                              retailer: json["retailer"] as? String)
        // Best-effort enrich; a missing preview just yields a branded card.
        if let p = try? await preview(id: id) {
            link.ogTitle = p.ogTitle
            link.ogImage = p.ogImage
        }
        return link
        #endif
    }

    // MARK: - Read

    /// This user's recent links, newest first — backs the "recent
    /// recommendations" picker. Returns [] if there's no user yet.
    func listLinks(limit: Int = 12) async throws -> [RippleLink] {
        #if targetEnvironment(simulator)
        return [
            RippleLink(id: "sim1", rippleURL: "https://sharewithripple.com/s/sim1",
                       sourceURL: "https://amazon.com/dp/SIM1", retailer: "amazon",
                       ogTitle: "Wireless Headphones", ogImage: nil),
            RippleLink(id: "sim2", rippleURL: "https://sharewithripple.com/s/sim2",
                       sourceURL: "https://amazon.com/dp/SIM2", retailer: "amazon",
                       ogTitle: "4-Person Camping Tent", ogImage: nil),
        ]
        #else
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        guard let userId = defaults.string(forKey: userIdKey) else { return [] }

        let data = try await request("GET", "/v1/links?user_id=\(userId)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["links"] as? [[String: Any]]
        else { return [] }

        return rows.prefix(limit).compactMap { row in
            guard let id = row["id"] as? String,
                  let src = row["source_url"] as? String else { return nil }
            return RippleLink(id: id, rippleURL: rippleURL(forId: id),
                              sourceURL: src,
                              retailer: row["retailer"] as? String,
                              ogTitle: row["og_title"] as? String,
                              ogImage: row["og_image"] as? String)
        }
        #endif
    }

    /// A link's display metadata (no click logged).
    func preview(id: String) async throws -> (ogTitle: String?, ogImage: String?) {
        let data = try await request("GET", "/v1/links/\(id)/preview")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["og_title"] as? String, json?["og_image"] as? String)
    }

    // MARK: - Anonymous user

    private func anonymousUserId() async throws -> String {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        if let existing = defaults.string(forKey: userIdKey) { return existing }

        let data = try await request("POST", "/v1/users")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String
        else { throw RippleLinkServiceError.server("Could not create a user.") }

        defaults.set(id, forKey: userIdKey)
        return id
    }

    // MARK: - Networking

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw RippleLinkServiceError.server("Could not build the request URL.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw RippleLinkServiceError.server("No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["error"] as? String {
                throw RippleLinkServiceError.server(message)
            }
            throw RippleLinkServiceError.server("Server error (\(http.statusCode)).")
        }
        return data
    }
}
