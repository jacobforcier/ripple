//
//  ShareView.swift
//  Ripple (iOS)
//
//  Share tab: paste any product URL, get a Ripple link back. Useful when
//  the browser extension or share sheet isn't where you are.
//

import SwiftUI

struct ShareView: View {
    @EnvironmentObject private var store: RippleStore

    @State private var input = ""
    @State private var result: CreatedLink?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    intro
                    inputCard
                    if let result {
                        resultCard(for: result)
                    }
                }
                .padding(16)
            }
            .rippleBackground()
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .principal) { RippleWordmark() }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showShareSheet) {
            if let result {
                ActivityView(items: [URL(string: result.rippleURL) ?? result.rippleURL])
            }
        }
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn any product link into a Ripple link")
                .font(.headline)
                .foregroundColor(RippleTheme.text)
            Text("Paste a product URL from a supported retailer. You'll get a shareable Ripple link that earns you a small commission when someone buys through it.")
                .font(.subheadline)
                .foregroundColor(RippleTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("https://www.amazon.com/dp/…", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .font(.subheadline)
                .foregroundColor(RippleTheme.text)
                .padding(12)
                .background(RippleTheme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(RippleTheme.border, lineWidth: 1)
                )
                .cornerRadius(10)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button(action: generate) {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isWorking ? "Generating…" : "Generate Ripple link")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RippleTheme.gradient)
                .cornerRadius(10)
                .opacity(canGenerate ? 1 : 0.5)
            }
            .disabled(!canGenerate)
            .buttonStyle(.plain)
        }
        .rippleCard()
    }

    private func resultCard(for result: CreatedLink) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(RippleTheme.positive)
                Text("Your Ripple link is ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(RippleTheme.text)
            }

            if let retailer = result.retailer {
                Text(retailer.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(RippleTheme.muted)
            }

            Text(result.rippleURL)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(RippleTheme.accent2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RippleTheme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(RippleTheme.border, lineWidth: 1)
                )
                .cornerRadius(10)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = result.rippleURL
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(copied ? RippleTheme.positive : RippleTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RippleTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(RippleTheme.border, lineWidth: 1)
                        )
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RippleTheme.gradient)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
    }

    // MARK: Logic

    private var canGenerate: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    private func generate() {
        errorMessage = nil
        isWorking = true
        let source = input
        Task {
            do {
                let created = try await store.createLink(sourceURL: source)
                await MainActor.run {
                    result = created
                    isWorking = false
                    copied = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isWorking = false
                }
            }
        }
    }
}

// MARK: - Share sheet wrapper

/// Bridges UIActivityViewController for the iOS 15 deployment target
/// (ShareLink is iOS 16+).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
