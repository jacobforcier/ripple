//
//  RippleLinkService.swift
//  Ripple Share
//
//  Self-contained backend client for the iOS Share Extension. Creates Ripple
//  links attributed to this device's anonymous user.
//
//  The anonymous user id lives in the shared App Group UserDefaults
//  ("group.com.ripple.sharewithripple"), so links created from the Share
//  Extension and from the main app earn the same person. The App Group id and
//  the user-id key here must match the values used by the app's LiveRippleAPI.
//

import Foundation

enum RippleLinkServiceError: LocalizedError {
    case badURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL:          return "That link doesn't look like a product URL."
        case .server(let msg): return msg
        }
    }
}

struct RippleLinkService {
    static let shared = RippleLinkService()

    // These two must match the main app's LiveRippleAPI.
    private let appGroupID = "group.com.ripple.sharewithripple"
    private let userIdKey = "ripple.anonymousUserId"

    private let baseURL = "https://api.sharewithripple.com"

    /// Creates a Ripple link for a shared product URL, attributed to this
    /// device's anonymous user. Returns the shareable Ripple URL.
    func createLink(from sourceURL: URL) async throws -> String {
        guard let scheme = sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              sourceURL.host != nil
        else { throw RippleLinkServiceError.badURL }

        let userId = try await anonymousUserId()

        let data = try await post("/v1/links", body: [
            "source_url": sourceURL.absoluteString,
            "user_id": userId,
        ])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rippleURL = json["ripple_url"] as? String
        else { throw RippleLinkServiceError.server("Unexpected response from the server.") }

        return rippleURL
    }

    // MARK: - Anonymous user

    /// This device's anonymous user id, shared with the main app via the App
    /// Group. Created on first use if it doesn't exist yet.
    private func anonymousUserId() async throws -> String {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        if let existing = defaults.string(forKey: userIdKey) {
            return existing
        }

        let data = try await post("/v1/users", body: nil)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String
        else { throw RippleLinkServiceError.server("Could not create a user.") }

        defaults.set(id, forKey: userIdKey)
        return id
    }

    // MARK: - Networking

    private func post(_ path: String, body: [String: Any]?) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw RippleLinkServiceError.server("Could not build the request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
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
