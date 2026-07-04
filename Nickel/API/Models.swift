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

    /// Whether this message was authored by the human. The API's `type` vocabulary is
    /// unschemad, so match any user-ish type ("user", "user_message", ...) and fall back
    /// to a `role` field embedded in the content payload. Deliberately does NOT look at
    /// `rawPayload.message.role` — Claude Code tool results arrive as user-role SDK
    /// events and must not render as the human's own words.
    var isFromUser: Bool {
        if type.lowercased().contains("user") {
            return true
        }
        return content.roleValue?.lowercased() == "user"
    }

    /// Sub-agent (Task tool) turns are multiplexed into the transcript as ordinary SDK
    /// user/assistant events distinguished only by `parent_tool_use_id` — including the
    /// task prompt as a user-role text event. They are never main-thread prose.
    var isSubagentEvent: Bool {
        content["rawPayload"]?["parent_tool_use_id"]?.stringValue != nil
    }

    /// Whether this message renders as a chat bubble (main-thread prose) rather than an
    /// event chip: the human's own messages, and un-parented assistant text.
    var rendersAsBubble: Bool {
        guard !isSubagentEvent else {
            return false
        }
        if isFromUser {
            return true
        }
        guard let raw = content["rawPayload"] else {
            // Non-SDK payloads (e.g. the demo world) keep the text-presence heuristic.
            return content.displayText != nil
        }
        return raw["type"]?.stringValue == "assistant" && content.displayText != nil
    }

    /// A descriptive label for non-text events. Conductor's top-level `type` is a flat
    /// "agent" for every SDK event, so prefer the wrapped event's leading content-block
    /// type ("tool use", "tool result") or its own type/subtype ("system · init",
    /// "result · success") over that. Sub-agent traffic is prefixed "task".
    var eventKind: String {
        guard let raw = content["rawPayload"] else {
            return type
        }
        let prefix = isSubagentEvent ? "task · " : ""
        if let blockType = raw["message"]?["content"]?[0]?["type"]?.stringValue, blockType != "text" {
            return prefix + blockType.replacingOccurrences(of: "_", with: " ")
        }
        guard let rawType = raw["type"]?.stringValue else {
            return type
        }
        if let subtype = raw["subtype"]?.stringValue {
            return "\(rawType) · \(subtype)"
        }
        return prefix + rawType
    }

    /// Compact context shown next to the chip label: turn cost + duration for `result`
    /// events, the task description/summary for `system` task events.
    var eventDetail: String? {
        guard let raw = content["rawPayload"] else {
            return nil
        }
        switch raw["type"]?.stringValue {
        case "result":
            var parts: [String] = []
            if let cost = raw["total_cost_usd"]?.numberValue {
                parts.append(String(format: "$%.3f", cost))
            }
            if let milliseconds = raw["duration_ms"]?.numberValue {
                parts.append(String(format: "%.1fs", milliseconds / 1000))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case "system":
            return raw["description"]?.stringValue ?? raw["summary"]?.stringValue
        default:
            return nil
        }
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
