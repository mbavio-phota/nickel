import SwiftUI

/// Sheet: account info (masked key or demo label), replace key, sign out, and about.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isReplaceKeyPresented = false
    @State private var isSignOutConfirmPresented = false

    private static let appVersion: String = {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if session.isDemo {
                        Label("Demo mode", systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    } else if let maskedKey = session.maskedApiKey {
                        LabeledContent("API key") {
                            Text(maskedKey)
                                .font(Theme.monospace(13))
                        }
                        Button("Replace key") {
                            isReplaceKeyPresented = true
                        }
                        if let warning = session.keyPersistenceWarning {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.StatusColor.error)
                        }
                    }

                    Button("Sign out", role: .destructive) {
                        isSignOutConfirmPresented = true
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Self.appVersion)
                    Link(destination: URL(string: "https://www.conductor.build")!) {
                        Label("conductor.build", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://api.conductor.build/v0/")!) {
                        Label("API docs", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isReplaceKeyPresented) {
                ReplaceKeyView()
            }
            .confirmationDialog(
                "Sign out?",
                isPresented: $isSignOutConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    session.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your saved API key from this device.")
            }
        }
    }
}

/// Sub-sheet for replacing the stored API key, reusing the same validation flow as
/// onboarding.
private struct ReplaceKeyView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New API key") {
                    SecureField("cond_...", text: $apiKey)
                        .font(Theme.monospace(14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let error = session.signInError {
                    Section {
                        Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.StatusColor.error)
                    }
                }
            }
            .navigationTitle("Replace Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(session.isValidatingSignIn)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if session.isValidatingSignIn {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                await session.signInLive(apiKey: trimmedKey)
                                if session.signInError == nil {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(trimmedKey.isEmpty)
                    }
                }
            }
        }
    }
}

#Preview("Live") {
    SettingsView()
        .environment(AppSession(
            liveClientFactory: { _ in MockConductorClient() },
            demoClientFactory: { MockConductorClient() }
        ))
}

#Preview("Demo") {
    let session = AppSession()
    session.enterDemo()
    return SettingsView()
        .environment(session)
}
