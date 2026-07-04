import SwiftUI

/// Sheet form for creating a new workspace on a project. On success, dismisses and hands
/// the freshly-created workspace back to the caller so it can refresh its list and push
/// into the new workspace's detail screen.
struct CreateWorkspaceView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let project: Project
    var onCreated: (Workspace) -> Void

    @State private var name = ""
    @State private var branch = ""
    @State private var agent: AgentKind = .claude
    @State private var model = ""
    @State private var isCreating = false
    @State private var creationError: ConductorError?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    TextField("Name (optional)", text: $name)
                    TextField("Branch (optional)", text: $branch)
                        .font(Theme.monospace(14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Agent") {
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
            .navigationTitle("New Workspace")
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

        let request = CreateWorkspaceRequest.forProject(
            project.id,
            branch: branch.isEmpty ? nil : branch,
            name: name.isEmpty ? nil : name,
            agent: agent,
            model: model.isEmpty ? nil : model
        )

        do {
            let response = try await client.createWorkspace(request)
            let workspace = try await client.getWorkspace(id: response.workspaceId)
            onCreated(workspace)
            dismiss()
        } catch let error as ConductorError {
            creationError = error
        } catch {
            creationError = .transport(message: error.localizedDescription)
        }
    }
}

#Preview {
    CreateWorkspaceView(
        project: Project(id: "proj_neb", name: "nebuchadnezzar", gitRemote: "git@github.com:zion-fleet/nebuchadnezzar.git"),
        onCreated: { _ in }
    )
    .environment({
        let session = AppSession()
        session.enterDemo()
        return session
    }())
}
