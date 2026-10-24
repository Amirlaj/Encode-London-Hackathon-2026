import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var checking = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "One connection. A fresh perspective.")
                        Text("Connect your coach.").font(.system(size: 29, weight: .semibold)).tracking(-1).foregroundStyle(Palette.ink)
                        Text("Connect Replay to your review server to get feedback from Gemini 4 Argon.")
                            .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(3)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("Server address").font(.system(size: 12, weight: .semibold))
                                TextField("https://your-server.example.com", text: $address)
                                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .font(.system(size: 15)).accessibilityIdentifier("server-address")
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 9) {
                                Text("Connection token").font(.system(size: 12, weight: .semibold))
                                SecureField("Your server’s APP_TOKEN", text: $token)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .font(.system(size: 15)).accessibilityIdentifier("connection-token")
                            }
                        }.foregroundStyle(Palette.ink)
                    }
                    Button {
                        Task {
                            checking = true; error = nil; result = nil
                            defer { checking = false }
                            do {
                                let client = try APIClient(address: address, token: token)
                                try TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                                store.serverAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                                let config = try await client.configuration()
                                result = config.configured ? "Connected. \(config.model) is ready to review." : "Connected. Add GEMINI_API_KEY to the server’s .env file to enable reviews."
                            } catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if checking { ProgressView().tint(.white) }
                            Text(checking ? "Checking connection…" : "Save & test connection")
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(checking || store.activeID != nil)
                    if store.activeID != nil { Text("Pause your upload or wait for the current review before changing the connection.").font(.caption).foregroundStyle(Palette.muted) }
                    if let result {
                        Label(result, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.ink)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let error { ErrorNotice(message: error) }
                    VStack(alignment: .leading, spacing: 16) {
                        note("Your API key stays on the server", text: "The connection token is saved in your iPhone’s Keychain. Your Google API key is never stored in the app.", icon: "key.horizontal")
                        note("Your video, your feedback", text: "Recordings and reports stay on this iPhone until you delete the session. Uploading sends the video to your server and Google for review.", icon: "video")
                        note("After a successful review", text: "The server removes its video copy and requests deletion of the Gemini file and interaction. Unfinished uploads and server records expire after 24 hours. Failed cleanup is retried.", icon: "clock.arrow.circlepath")
                    }
                    Text("Replay 1.0 · Built for deliberate practice")
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted)
                }.padding(24)
            }.background(Palette.background).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .onAppear { address = store.serverAddress; token = TokenStore.read() }
        }.tint(Palette.ink)
    }

    private func note(_ title: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 23).foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(text).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
            }
        }
    }
}
