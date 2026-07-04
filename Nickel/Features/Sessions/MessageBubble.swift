import SwiftUI

/// Renders one transcript message: a chat bubble when it's main-thread prose, otherwise
/// a compact left-aligned event row (icon + title + monospaced snippet, in the style of
/// the Conductor desktop timeline) with a disclosure to the pretty-printed JSON.
struct MessageRow: View {
    let message: TranscriptMessage
    @State private var isRawJSONPresented = false

    var body: some View {
        Group {
            if message.rendersAsBubble, let text = message.content.displayText, !text.isEmpty {
                ChatBubble(text: text, isUser: message.isFromUser, timestamp: message.receivedDate)
            } else {
                Button {
                    isRawJSONPresented = true
                } label: {
                    EventRow(summary: EventSummary.make(for: message))
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button {
                isRawJSONPresented = true
            } label: {
                Label("View raw JSON", systemImage: "curlybraces")
            }
        }
        .sheet(isPresented: $isRawJSONPresented) {
            RawEventView(message: message)
        }
    }
}

private struct ChatBubble: View {
    let text: String
    let isUser: Bool
    let timestamp: Date?

    /// Agent replies are markdown; render inline styling (bold, italics, code spans)
    /// while preserving line structure. Falls back to the plain text on parse failure.
    private var markdownText: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 48)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(markdownText)
                    .font(.body)
                    .foregroundStyle(isUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.thinMaterial),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                if let timestamp {
                    Text(timestamp, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            if !isUser {
                Spacer(minLength: 48)
            }
        }
    }
}

/// A Conductor-desktop-style timeline row: leading icon, human title, and an optional
/// one-line monospaced snippet (command, path, output). Red treatment for errors.
private struct EventRow: View {
    let summary: EventSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: summary.icon)
                .font(.caption)
                .foregroundStyle(summary.isError ? AnyShapeStyle(Theme.StatusColor.error) : AnyShapeStyle(.secondary))
                .frame(width: 16)

            Text(summary.title)
                .font(.footnote)
                .foregroundStyle(summary.isError ? AnyShapeStyle(Theme.StatusColor.error) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .layoutPriority(1)

            if let snippet = summary.snippet {
                Text(snippet)
                    .font(Theme.monospace(11))
                    .foregroundStyle(summary.isError ? AnyShapeStyle(Theme.StatusColor.error.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        summary.isError ? AnyShapeStyle(Theme.StatusColor.error.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RawEventView: View {
    @Environment(\.dismiss) private var dismiss
    let message: TranscriptMessage

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(prettyPrinted)
                    .font(Theme.monospace(12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(message.type)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var prettyPrinted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(message.content),
              let string = String(data: data, encoding: .utf8) else {
            return "Unable to render raw JSON."
        }
        return string
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            MessageRow(message: TranscriptMessage(
                id: "1", sessionId: "s", sessionIndex: 0, type: "user",
                content: .object(["text": .string("Can you trace the déjà vu glitch in the lobby sim?")]),
                receivedAt: ISO8601DateFormatter().string(from: Date())
            ))
            MessageRow(message: TranscriptMessage(
                id: "2", sessionId: "s", sessionIndex: 1, type: "agent_message",
                content: .object(["text": .string("Looking into it now.")]),
                receivedAt: ISO8601DateFormatter().string(from: Date())
            ))
            MessageRow(message: TranscriptMessage(
                id: "3", sessionId: "s", sessionIndex: 2, type: "tool_call",
                content: .object(["tool": .string("read_file"), "args": .object(["path": .string("simulacra/render/lobby_loop.c")])]),
                receivedAt: ISO8601DateFormatter().string(from: Date())
            ))
        }
        .padding()
    }
}
