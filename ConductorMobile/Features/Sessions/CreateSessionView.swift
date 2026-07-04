import SwiftUI

/// Sheet form for starting a new session in a workspace: agent picker + optional
/// name/model.
struct CreateSessionView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let workspaceId: String
    var onCreated: (Session) -> Void

    @State private var name = ""
    @State private var agent: AgentKind = .claude
    @State private var model = ""
    @State private var isCreating = false
    @State private var creationError: ConductorError?

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Name (optional)", text: $name)
                    Picker("Agent", selection: $agent) {
                        ForEach(AgentKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    TextField("Model (optional)", text: $model)
                        .font(Theme.monospace(14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let creationError {
                    Section {
                        Label(creationError.userMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.StatusColor.error)
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task { await create() }
                        }
                    }
                }
            }
        }
    }

    private func create() async {
        guard let client = session.client else {
            return
        }
        isCreating = true
        creationError = nil
        defer { isCreating = false }

        let request = CreateSessionRequest(
            workspaceId: workspaceId,
            sessionId: nil,
            name: name.isEmpty ? nil : name,
            agent: agent,
            model: model.isEmpty ? nil : model
        )

        do {
            let created = try await client.createSession(request)
            onCreated(created)
            dismiss()
        } catch let error as ConductorError {
            creationError = error
        } catch {
            creationError = .transport(message: error.localizedDescription)
        }
    }
}

#Preview {
    CreateSessionView(workspaceId: "ws_neb_1", onCreated: { _ in })
        .environment({
            let session = AppSession()
            session.enterDemo()
            return session
        }())
}
