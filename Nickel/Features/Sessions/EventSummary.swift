import Foundation

/// Presentation mapping for non-prose transcript events, mirroring the Conductor desktop
/// app's timeline rows: an icon, a human title, and an optional monospaced snippet
/// (command, file path, output line). Built from the SDK payload shapes documented in
/// tools/transport-probe/FINDINGS.md.
struct EventSummary: Equatable {
    let icon: String
    let title: String
    let snippet: String?
    let isError: Bool

    static func make(for message: TranscriptMessage) -> EventSummary {
        guard let raw = message.content["rawPayload"] else {
            // Non-SDK payloads (demo world, unknown) fall back to the generic chip.
            return EventSummary(icon: "curlybraces", title: message.eventKind, snippet: nil, isError: false)
        }

        let taskPrefix = message.isSubagentEvent ? "task · " : ""

        switch raw["type"]?.stringValue {
        case "system":
            return systemSummary(raw: raw, fallbackTitle: message.eventKind)
        case "result":
            return resultSummary(raw: raw)
        case "assistant", "user":
            if let block = firstInterestingBlock(raw: raw) {
                return blockSummary(block: block, taskPrefix: taskPrefix)
            }
            return EventSummary(icon: "curlybraces", title: message.eventKind, snippet: nil, isError: false)
        default:
            return EventSummary(icon: "curlybraces", title: message.eventKind, snippet: nil, isError: false)
        }
    }

    private static func systemSummary(raw: JSONValue, fallbackTitle: String) -> EventSummary {
        switch raw["subtype"]?.stringValue {
        case "init":
            return EventSummary(
                icon: "power",
                title: "Session started",
                snippet: raw["model"]?.stringValue,
                isError: false
            )
        case "api_retry":
            let attempt = raw["attempt"]?.numberValue.map { String(Int($0)) } ?? "?"
            let maxRetries = raw["max_retries"]?.numberValue.map { String(Int($0)) } ?? "?"
            var reason = ""
            if let status = raw["error_status"]?.numberValue {
                reason += " · \(Int(status))"
            }
            if let error = raw["error"]?.stringValue {
                reason += reason.isEmpty ? " · \(error)" : " \(error)"
            }
            return EventSummary(
                icon: "arrow.clockwise",
                title: "Retrying (attempt \(attempt)/\(maxRetries))\(reason)",
                snippet: nil,
                isError: false
            )
        case "thinking_tokens":
            let tokens = raw["estimated_tokens"]?.numberValue.map { "~\(Int($0)) tokens" }
            return EventSummary(icon: "brain", title: "Thinking", snippet: tokens, isError: false)
        case let subtype where subtype?.hasPrefix("task") == true:
            let detail = raw["description"]?.stringValue ?? raw["summary"]?.stringValue
            let label = subtype?.replacingOccurrences(of: "task_", with: "task ") ?? "task"
            return EventSummary(icon: "person.2", title: label, snippet: detail, isError: false)
        default:
            return EventSummary(icon: "gearshape", title: fallbackTitle, snippet: nil, isError: false)
        }
    }

    private static func resultSummary(raw: JSONValue) -> EventSummary {
        let failed = raw["is_error"]?.boolValue == true
        var parts: [String] = []
        if let cost = raw["total_cost_usd"]?.numberValue {
            parts.append(String(format: "$%.3f", cost))
        }
        if let milliseconds = raw["duration_ms"]?.numberValue {
            parts.append(String(format: "%.1fs", milliseconds / 1000))
        }
        return EventSummary(
            icon: failed ? "xmark.circle" : "checkmark.circle",
            title: failed ? "Turn failed" : "Turn finished",
            snippet: parts.isEmpty ? nil : parts.joined(separator: " · "),
            isError: failed
        )
    }

    /// The first non-text content block (tool_use / tool_result / thinking), if any.
    private static func firstInterestingBlock(raw: JSONValue) -> JSONValue? {
        guard let blocks = raw["message"]?["content"]?.arrayValue else {
            return nil
        }
        return blocks.first { block in
            guard let type = block["type"]?.stringValue else {
                return false
            }
            return type != "text"
        }
    }

    private static func blockSummary(block: JSONValue, taskPrefix: String) -> EventSummary {
        switch block["type"]?.stringValue {
        case "tool_use":
            let name = block["name"]?.stringValue ?? "tool"
            let input = block["input"]
            let title = input?["description"]?.stringValue ?? name
            let snippet = input?["command"]?.stringValue
                ?? input?["file_path"]?.stringValue
                ?? input?["path"]?.stringValue
                ?? input?["pattern"]?.stringValue
                ?? input?["prompt"]?.stringValue
            return EventSummary(
                icon: toolIcon(name: name),
                title: taskPrefix + title,
                snippet: snippet.map(firstLine),
                isError: false
            )
        case "tool_result":
            let failed = block["is_error"]?.boolValue == true
            let output = block["content"]?.stringValue
                ?? block["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.first
            return EventSummary(
                icon: failed ? "xmark.circle" : "arrow.turn.down.right",
                title: taskPrefix + (failed ? "Error" : "Output"),
                snippet: output.map(firstLine),
                isError: failed
            )
        case "thinking":
            return EventSummary(icon: "brain", title: taskPrefix + "Thinking", snippet: nil, isError: false)
        default:
            let type = block["type"]?.stringValue ?? "event"
            return EventSummary(
                icon: "curlybraces",
                title: taskPrefix + type.replacingOccurrences(of: "_", with: " "),
                snippet: nil,
                isError: false
            )
        }
    }

    private static func toolIcon(name: String) -> String {
        switch name {
        case "Bash":
            return "terminal"
        case "Read":
            return "doc.text"
        case "Edit", "Write", "NotebookEdit":
            return "pencil"
        case "Grep", "Glob", "WebSearch":
            return "magnifyingglass"
        case "Task":
            return "person.2"
        case "WebFetch":
            return "globe"
        default:
            return "wrench.and.screwdriver"
        }
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? text
    }
}
