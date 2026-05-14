//
//  RippleStore.swift
//  Ripple (iOS)
//
//  Shared observable state for the app. Holds the API client and the
//  loaded data; views read from it and ask it to perform actions.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class RippleStore: ObservableObject {

    @Published var links: [RippleLink] = []
    @Published var earnings: EarningsSummary = .zero
    @Published var rates: [RetailerRate] = []

    @Published var isLoading = false
    @Published var loadError: String?
    @Published var hasLoadedOnce = false

    private let api: RippleAPIClient

    init(api: RippleAPIClient) {
        self.api = api
    }

    /// Loads links, earnings, and rate data together. Safe to call repeatedly
    /// (pull-to-refresh, tab re-appear).
    func loadAll() async {
        isLoading = true
        loadError = nil
        do {
            async let links = api.fetchLinks()
            async let earnings = api.fetchEarnings()
            async let rates = api.fetchRetailerRates()
            self.links = try await links
            self.earnings = try await earnings
            self.rates = try await rates
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
        hasLoadedOnce = true
    }

    /// Creates a Ripple link and refreshes the history + earnings so the new
    /// link appears immediately.
    func createLink(sourceURL: String) async throws -> CreatedLink {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = try await api.createLink(sourceURL: trimmed)
        self.links = try await api.fetchLinks()
        self.earnings = try await api.fetchEarnings()
        return created
    }
}
