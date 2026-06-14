//
//  ComposerView.swift
//  Ripple Messages
//
//  The expanded composer: paste a product link to create a fresh Ripple link,
//  or tap a recent recommendation to re-send it into this conversation. The
//  actual conversation.insert happens in MessagesViewController via onSend.
//

import SwiftUI

struct ComposerView: View {
    /// Hands a created/selected link back to the MSMessagesAppViewController,
    /// which owns the active conversation and does the insert.
    let onSend: (RippleLink) -> Void

    @State private var urlText = ""
    @State private var recents: [RippleLink] = []
    @State private var loadingRecents = true
    @State private var creating = false
    @State private var errorText: String?

    private let accent = Color(red: 0.36, green: 0.54, blue: 0.96)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                pasteCard

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                recentsSection
            }
            .padding(18)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
        .task { await loadRecents() }
        .onAppear(perform: prefillFromClipboard)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ripple").font(.system(size: 22, weight: .heavy)).foregroundColor(accent)
            Text("share a recommendation").font(.subheadline).foregroundColor(.secondary)
        }
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("paste a product link", text: $urlText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(action: createAndSend) {
                HStack {
                    if creating { ProgressView().tint(.white) }
                    Text(creating ? "creating…" : "create & send")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canCreate ? accent : Color.gray.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canCreate || creating)
        }
    }

    @ViewBuilder
    private var recentsSection: some View {
        if loadingRecents {
            ProgressView().tint(accent).frame(maxWidth: .infinity).padding(.top, 8)
        } else if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("recent recommendations")
                    .font(.caption).foregroundColor(.secondary)
                ForEach(recents) { link in
                    Button { onSend(link) } label: { recentRow(link) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func recentRow(_ link: RippleLink) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.25))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "bag").foregroundColor(accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(link.ogTitle ?? link.sourceURL)
                    .font(.subheadline).foregroundColor(.white).lineLimit(1)
                Text(link.retailer ?? "product")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right").foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private var canCreate: Bool {
        URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines))?.host != nil
    }

    private func prefillFromClipboard() {
        guard urlText.isEmpty, UIPasteboard.general.hasURLs,
              let url = UIPasteboard.general.url else { return }
        urlText = url.absoluteString
    }

    private func createAndSend() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }
        creating = true
        errorText = nil
        Task {
            do {
                let link = try await RippleLinkService.shared.createLink(from: url)
                await MainActor.run { creating = false; onSend(link) }
            } catch {
                await MainActor.run {
                    creating = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func loadRecents() async {
        let links = (try? await RippleLinkService.shared.listLinks()) ?? []
        await MainActor.run { recents = links; loadingRecents = false }
    }
}
