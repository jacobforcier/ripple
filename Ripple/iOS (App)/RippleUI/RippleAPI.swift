//
//  RippleAPI.swift
//  Ripple (iOS)
//
//  The app talks to this protocol, never to a concrete client. Today the
//  only implementation is MockRippleAPI (in-memory sample data). When the
//  backend is deployed, add a LiveRippleAPI that hits:
//
//      POST /v1/links               -> createLink
//      GET  /v1/links?user_id=      -> fetchLinks
//      GET  /v1/users/:id/earnings  -> fetchEarnings
//
//  and swap the one line in RootView that constructs the client.
//

import Foundation

// MARK: - Protocol

protocol RippleAPIClient {
    func fetchLinks() async throws -> [RippleLink]
    func fetchEarnings() async throws -> EarningsSummary
    func createLink(sourceURL: String) async throws -> CreatedLink
    func fetchRetailerRates() async throws -> [RetailerRate]
    func fetchTrending() async throws -> [TrendingMerchant]
}

enum RippleAPIError: LocalizedError {
    case invalidURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "That doesn't look like a valid product link."
        case .server(let msg):   return msg
        }
    }
}

/// Shared JSON decoder configured for the backend's timestamp format.
/// Used by the future LiveRippleAPI; kept here so the config lives in one place.
enum RippleJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unrecognized date format: \(raw)")
            )
        }
        return decoder
    }()
}

// MARK: - Mock implementation

/// In-memory client with realistic sample data. Generated links behave like
/// the real backend would — a new id, a sharewithripple.com/s/ URL — and are
/// appended to the history so the Links tab updates immediately.
actor MockRippleAPI: RippleAPIClient {

    private var links: [RippleLink]

    init() {
        let now = Date()
        func daysAgo(_ d: Int) -> Date { now.addingTimeInterval(-Double(d) * 86_400) }

        links = [
            RippleLink(
                id: "k7m2xqp",
                sourceURL: "https://www.amazon.com/dp/B00U26V4VQ",
                retailer: "Amazon",
                createdAt: daysAgo(2),
                clickCount: 9,
                earnedCents: 412,
                pendingCents: 280,
                confirmedCents: 132,
                paidCents: 0
            ),
            RippleLink(
                id: "r3w8azt",
                sourceURL: "https://www.target.com/p/standing-desk/-/A-83920147",
                retailer: "Target",
                createdAt: daysAgo(6),
                clickCount: 4,
                earnedCents: 190,
                pendingCents: 0,
                confirmedCents: 190,
                paidCents: 0
            ),
            RippleLink(
                id: "q9n4hjk",
                sourceURL: "https://www.rei.com/product/199384/tent",
                retailer: "REI",
                createdAt: daysAgo(13),
                clickCount: 2,
                earnedCents: 145,
                pendingCents: 0,
                confirmedCents: 0,
                paidCents: 145
            ),
            RippleLink(
                id: "b5t1zmx",
                sourceURL: "https://www.etsy.com/listing/1029384/handmade-mug",
                retailer: "Etsy",
                createdAt: daysAgo(21),
                clickCount: 0,
                earnedCents: 0,
                pendingCents: 0,
                confirmedCents: 0,
                paidCents: 0
            ),
        ]
    }

    func fetchLinks() async throws -> [RippleLink] {
        try await Task.sleep(nanoseconds: 350_000_000)
        return links.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchEarnings() async throws -> EarningsSummary {
        try await Task.sleep(nanoseconds: 350_000_000)
        return EarningsSummary(
            lifetimeCents:  links.reduce(0) { $0 + $1.earnedCents },
            pendingCents:   links.reduce(0) { $0 + $1.pendingCents },
            confirmedCents: links.reduce(0) { $0 + $1.confirmedCents },
            paidCents:      links.reduce(0) { $0 + $1.paidCents }
        )
    }

    func createLink(sourceURL: String) async throws -> CreatedLink {
        guard let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { throw RippleAPIError.invalidURL }

        try await Task.sleep(nanoseconds: 500_000_000)

        let id = Self.newShortId()
        let retailer = Self.detectRetailer(sourceURL)

        links.append(
            RippleLink(
                id: id,
                sourceURL: sourceURL,
                retailer: retailer,
                createdAt: Date(),
                clickCount: 0,
                earnedCents: 0,
                pendingCents: 0,
                confirmedCents: 0,
                paidCents: 0
            )
        )

        return CreatedLink(
            id: id,
            rippleURL: "https://sharewithripple.com/s/\(id)",
            sourceURL: sourceURL,
            retailer: retailer
        )
    }

    func fetchRetailerRates() async throws -> [RetailerRate] {
        RetailerRateData.all
    }

    func fetchTrending() async throws -> [TrendingMerchant] {
        try await Task.sleep(nanoseconds: 350_000_000)
        return [
            TrendingMerchant(rank: 1,  retailer: "Amazon",     shareCount: 1_284, movement: .steady),
            TrendingMerchant(rank: 2,  retailer: "Target",     shareCount: 612,   movement: .up(1)),
            TrendingMerchant(rank: 3,  retailer: "Etsy",       shareCount: 548,   movement: .up(2)),
            TrendingMerchant(rank: 4,  retailer: "Walmart",    shareCount: 503,   movement: .down(2)),
            TrendingMerchant(rank: 5,  retailer: "REI",        shareCount: 377,   movement: .new),
            TrendingMerchant(rank: 6,  retailer: "Best Buy",   shareCount: 341,   movement: .down(1)),
            TrendingMerchant(rank: 7,  retailer: "Wayfair",    shareCount: 298,   movement: .up(3)),
            TrendingMerchant(rank: 8,  retailer: "Chewy",      shareCount: 264,   movement: .steady),
            TrendingMerchant(rank: 9,  retailer: "Nordstrom",  shareCount: 211,   movement: .down(2)),
            TrendingMerchant(rank: 10, retailer: "Home Depot", shareCount: 189,   movement: .new),
        ]
    }

    // MARK: Helpers (mirror the backend's logic)

    private static func newShortId() -> String {
        let alphabet = Array("23456789abcdefghijkmnpqrstuvwxyz")
        return String((0..<7).map { _ in alphabet.randomElement()! })
    }

    private static func detectRetailer(_ urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host?
            .replacingOccurrences(of: "www.", with: "")
            .lowercased()
        else { return nil }

        let map: [String: String] = [
            "amazon.com": "Amazon", "target.com": "Target", "walmart.com": "Walmart",
            "bestbuy.com": "Best Buy", "etsy.com": "Etsy", "ebay.com": "eBay",
            "wayfair.com": "Wayfair", "rei.com": "REI", "homedepot.com": "Home Depot",
            "nordstrom.com": "Nordstrom", "chewy.com": "Chewy", "lowes.com": "Lowe's",
        ]
        for (domain, name) in map where host == domain || host.hasSuffix(".\(domain)") {
            return name
        }
        let label = host.split(separator: ".").first.map(String.init) ?? host
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}

// MARK: - Static rate reference data

enum RetailerRateData {
    /// Approximate, typical commission rates. Real rates vary by category and
    /// change over time — this is reference-only.
    static let all: [RetailerRate] = [
        RetailerRate(retailer: "Amazon",      category: "Toys & Games",     rateText: "~3%"),
        RetailerRate(retailer: "Amazon",      category: "Electronics",      rateText: "~1–2.5%"),
        RetailerRate(retailer: "Amazon",      category: "Home & Kitchen",   rateText: "~3–4.5%"),
        RetailerRate(retailer: "Amazon",      category: "Apparel",          rateText: "~4%"),
        RetailerRate(retailer: "Target",      category: "Most categories",  rateText: "~1–8%"),
        RetailerRate(retailer: "Walmart",     category: "Most categories",  rateText: "~1–4%"),
        RetailerRate(retailer: "Best Buy",    category: "Electronics",      rateText: "~1–2%"),
        RetailerRate(retailer: "Etsy",        category: "Handmade & craft", rateText: "~4%"),
        RetailerRate(retailer: "eBay",        category: "Most categories",  rateText: "~1–4%"),
        RetailerRate(retailer: "Wayfair",     category: "Home & furniture", rateText: "~5–7%"),
        RetailerRate(retailer: "REI",         category: "Outdoor gear",     rateText: "~5%"),
        RetailerRate(retailer: "Home Depot",  category: "Home improvement", rateText: "~2–8%"),
        RetailerRate(retailer: "Lowe's",      category: "Home improvement", rateText: "~2–8%"),
        RetailerRate(retailer: "Nordstrom",   category: "Apparel & beauty", rateText: "~2–11%"),
        RetailerRate(retailer: "Chewy",       category: "Pet supplies",     rateText: "~4%"),
        RetailerRate(retailer: "Macy's",      category: "Apparel & home",   rateText: "~3–7%"),
        RetailerRate(retailer: "B&H Photo",   category: "Photo & video",    rateText: "~2–4%"),
        RetailerRate(retailer: "Newegg",      category: "Electronics & PC", rateText: "~1–2.5%"),
    ]
}
