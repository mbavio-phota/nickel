import SwiftUI

/// Renders one transcript message: a chat bubble when `displayText` finds recognizable
/// text, otherwise a compact tappable "event chip" showing the raw type with a disclosure
/// to the pretty-printed JSON.
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
                    EventChip(type: message.eventKind, detail: message.eventDetail)
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

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 48)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(text)
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

private struct EventChip: View {
    let type: String
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.caption2)
            Text(type)
                .font(Theme.monospace(12))
            if let detail {
                Text(detail)
                    .font(Theme.monospace(11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
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
