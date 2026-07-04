import Foundation

// MARK: - Projects

struct Project: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let gitRemote: String
}

// MARK: - Workspaces

enum WorkspaceStatusValue: String, Codable, Equatable, CaseIterable {
    case initializing
    case ready
    case sleeping
    case archived
    case deleted
    case updating
}

enum WorkspaceLifecycleStep: String, Codable, Equatable, CaseIterable {
    case buildingSnapshot = "building_snapshot"
    case preparing
    case settingUp = "setting_up"
    case updating
}

struct Workspace: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    /// ISO-8601 timestamp string, as returned by the server. Use `createdDate` to parse it.
    let createdAt: String
    let deepLink: String
    let creatorId: String?

    var createdDate: Date? {
        Formatters.date(from: createdAt)
    }
}

struct WorkspaceStatus: Codable, Equatable {
    let workspaceId: String
    let status: WorkspaceStatusValue
    let lifecycleStep: WorkspaceLifecycleStep?
    /// ISO-8601 timestamp string, as returned by the server.
    let updatedAt: String
    let errorMessage: String?

    var updatedDate: Date? {
        Formatters.date(from: updatedAt)
    }
}

struct WorkspaceCreateResponse: Codable, Equatable {
    let workspaceId: String
    let sessionId: String
    let deepLink: String
}

struct WorkspaceArchiveResponse: Codable, Equatable {
    let workspaceId: String
    let status: String
}

// MARK: - Sessions

enum SessionStatusValue: String, Codable, Equatable, CaseIterable {
    case idle
    case working
    case error
}

struct Session: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let deepLink: String
    let name: String?
    let model: String?

    /// The session's name, falling back to a placeholder when unset or blank.
    var displayName: String {
        guard let name, !name.isEmpty else {
            return "Untitled session"
        }
        return name
    }
}

struct SessionStatus: Codable, Equatable {
    let workspaceId: String
    let sessionId: String
    let status: SessionStatusValue
    /// ISO-8601 timestamp string, as returned by the server.
    let updatedAt: String
    let errorMessage: String?

    var updatedDate: Date? {
        Formatters.date(from: updatedAt)
    }
}

struct SessionCancelResponse: Codable, Equatable {
    let workspaceId: String
    let sessionId: String
    let status: SessionStatusValue
    let canceledQueuedMessages: Double
}

// MARK: - Messages

struct TranscriptMessage: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let sessionId: String
    let sessionIndex: Double
    let type: String
    let content: JSONValue
    /// ISO-8601 timestamp string, as returned by the server.
    let receivedAt: String

    var receivedDate: Date? {
        Formatters.date(from: receivedAt)
    }

    static func == (lhs: TranscriptMessage, rhs: TranscriptMessage) -> Bool {
        lhs.id == rhs.id && lhs.sessionId == rhs.sessionId && lhs.sessionIndex == rhs.sessionIndex
            && lhs.type == rhs.type && lhs.content == rhs.content && lhs.receivedAt == rhs.receivedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum MessageState: String, Codable, Equatable {
    case queued
    case sent
}

struct MessageCreateResponse: Codable, Equatable {
    let messageId: String
    let state: MessageState
}

// MARK: - Pagination

/// Generic wrapper for the `{ data, offset, hasMore }` shape every list endpoint returns.
struct Page<Element: Codable & Equatable>: Codable, Equatable {
    let data: [Element]
    let offset: Double
    let hasMore: Bool
}

// MARK: - Requests

enum AgentKind: String, Codable, Equatable, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor
    case acp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .acp: return "ACP"
        }
    }
}

/// Body for `POST /v0/workspaces`. Exactly one of `projectId` / `repositoryUrl` must be
/// set — enforced by construction via the two static factories rather than at decode time.
struct CreateWorkspaceRequest: Encodable, Equatable {
    let projectId: String?
    let repositoryUrl: String?
    let branch: String?
    let name: String?
    let agent: AgentKind?
    let model: String?

    static func forProject(
        _ projectId: String,
        branch: String? = nil,
        name: String? = nil,
        agent: AgentKind? = nil,
        model: String? = nil
    ) -> CreateWorkspaceRequest {
        CreateWorkspaceRequest(
            projectId: projectId,
            repositoryUrl: nil,
            branch: branch,
            name: name,
            agent: agent,
            model: model
        )
    }

    static func forRepository(
        _ repositoryUrl: String,
        branch: String? = nil,
        name: String? = nil,
        agent: AgentKind? = nil,
        model: String? = nil
    ) -> CreateWorkspaceRequest {
        CreateWorkspaceRequest(
            projectId: nil,
            repositoryUrl: repositoryUrl,
            branch: branch,
            name: name,
            agent: agent,
            model: model
        )
    }
}

/// Body for `POST /v0/sessions`.
struct CreateSessionRequest: Encodable, Equatable {
    let workspaceId: String
    let sessionId: String?
    let name: String?
    let agent: AgentKind
    let model: String?
}

struct RenameRequest: Encodable, Equatable {
    let name: String
}

struct SendMessageRequest: Encodable, Equatable {
    let messageId: String?
    let message: String
}
