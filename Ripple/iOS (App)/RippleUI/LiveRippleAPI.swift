//
//  LiveRippleAPI.swift
//  Ripple (iOS)
//
//  Talks to the real Ripple backend at api.sharewithripple.com.
//
//  Ripple is anonymous-first: on first use this creates an anonymous user
//  (POST /v1/users), persists the id in UserDefaults, and sends it as
//  `user_id` on every request that needs attribution. A real account is
//  collected later, at payout time.
//

import Foundation

actor LiveRippleAPI: RippleAPIClient {

    private let baseURL = "https://api.sharewithripple.com"

    // Anonymous user identity is stored in the shared App Group so the main
    // app and the Share Extension attribute links to the same person. These
    // two values must match RippleLinkService in the Share Extension.
    private static let appGroupID = "group.com.ripple.sharewithripple"
    private static let userIdKey = "ripple.anonymousUserId"

    /// Shared App Group defaults, falling back to standard defaults if the
    /// App Group isn't available (e.g. entitlement not yet provisioned).
    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    private var cachedUserId: String?

    // MARK: - RippleAPIClient

    func fetchLinks() async throws -> [RippleLink] {
        let uid = try await userId()
        let response: LinksResponse = try await send("GET", "/v1/links?user_id=\(uid)")
        return response.links
    }

    func fetchEarnings() async throws -> EarningsSummary {
        let uid = try await userId()
        return try await send("GET", "/v1/users/\(uid)/earnings")
    }

    func createLink(sourceURL: String) async throws -> CreatedLink {
        // Validate client-side first for an immediate, friendly error.
        guard let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { throw RippleAPIError.invalidURL }

        let uid = try await userId()
        return try await send(
            "POST", "/v1/links",
            body: ["source_url": sourceURL, "user_id": uid]
        )
    }

    func fetchRetailerRates() async throws -> [RetailerRate] {
        // Reference data — same static table the mock uses. No backend endpoint.
        RetailerRateData.all
    }

    func fetchTrending() async throws -> [TrendingMerchant] {
        let response: TrendingResponse = try await send("GET", "/v1/trending")
        return response.trending
    }

    // MARK: - Anonymous user

    /// This install's anonymous user id, created and persisted on first use.
    /// Shared with the Share Extension via the App Group.
    private func userId() async throws -> String {
        if let cachedUserId { return cachedUserId }

        let defaults = sharedDefaults
        if let stored = defaults.string(forKey: Self.userIdKey) {
            cachedUserId = stored
            return stored
        }

        let response: CreateUserResponse = try await send("POST", "/v1/users")
        defaults.set(response.id, forKey: Self.userIdKey)
        cachedUserId = response.id
        return response.id
    }

    // MARK: - Networking

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw RippleAPIError.server("Could not build the request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, data: data)
        return try RippleJSON.decoder.decode(T.self, from: data)
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RippleAPIError.server("No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Surface the backend's { "error": "..." } message when present.
            if let payload = try? JSONDecoder().decode([String: String].self, from: data),
               let message = payload["error"] {
                throw RippleAPIError.server(message)
            }
            throw RippleAPIError.server("Server error (\(http.statusCode)).")
        }
    }

    // MARK: - Response envelopes

    private struct LinksResponse: Decodable { let links: [RippleLink] }
    private struct TrendingResponse: Decodable { let trending: [TrendingMerchant] }
    private struct CreateUserResponse: Decodable { let id: String }
}
