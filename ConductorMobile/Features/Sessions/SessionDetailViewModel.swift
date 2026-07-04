import Foundation
import Observation

/// Drives the session chat screen: message transcript with pagination, status polling,
/// optimistic send, and cancel.
@MainActor
@Observable
final class SessionDetailViewModel {
    private(set) var session: Session
    private(set) var statusLoadable: Loadable<SessionStatus> = .idle
    private(set) var messagesLoadable: Loadable<[TranscriptMessage]> = .idle
    private(set) var isSending = false
    private(set) var isCanceling = false
    private(set) var sendError: ConductorError?
    private(set) var isRenaming = false

    private let client: ConductorClient
    private let pageSize = 50
    /// Safety valve on the paging loop for pathologically long transcripts.
    private let maxPagesPerRefresh = 20
    /// Server-confirmed messages keyed by id, accumulated incrementally across polls.
    private var serverMessagesById: [String: TranscriptMessage] = [:]
    /// Sent-but-not-yet-echoed messages, matched back to server copies by the
    /// client-generated `messageId` passed to `sendMessage`.
    private var pendingOptimistic: [TranscriptMessage] = []

    init(session: Session, client: ConductorClient) {
        self.session = session
        self.client = client
    }

    var messages: [TranscriptMessage] {
        messagesLoadable.value ?? []
    }

    var status: SessionStatusValue? {
        statusLoadable.value?.status
    }

    var isWorking: Bool {
        status == .working
    }

    /// Poll cadence per the design direction: 3s while working, 10s otherwise (while the
    /// screen is visible).
    var pollInterval: Duration {
        isWorking ? .seconds(3) : .seconds(10)
    }

    func loadInitial() async {
        async let statusTask: Void = loadStatus()
        async let messagesTask: Void = loadMessagesInitial()
        _ = await (statusTask, messagesTask)
    }

    func loadStatus() async {
        do {
            let status = try await client.getSessionStatus(id: session.id)
            statusLoadable = .loaded(status)
        } catch let error as ConductorError {
            statusLoadable = .failed(error)
        } catch {
            statusLoadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    func loadMessagesInitial() async {
        if messagesLoadable.value == nil {
            messagesLoadable = .loading
        }
        await refreshMessages()
    }

    /// Fetches messages the client doesn't have yet, starting from the count already
    /// accumulated (the transcript is append-only, so `offset = known count` yields only
    /// new messages) and paging until `hasMore` is false. Merging by id makes a repeated
    /// or shifted page harmless.
    func refreshMessages() async {
        do {
            var pagesFetched = 0
            while pagesFetched < maxPagesPerRefresh {
                let page = try await client.listMessages(
                    sessionId: session.id,
                    limit: pageSize,
                    offset: serverMessagesById.count
                )
                for message in page.data {
                    serverMessagesById[message.id] = message
                }
                pagesFetched += 1
                if !page.hasMore {
                    break
                }
            }
            reconcile()
        } catch let error as ConductorError {
            if messagesLoadable.value == nil {
                messagesLoadable = .failed(error)
            }
        } catch {
            if messagesLoadable.value == nil {
                messagesLoadable = .failed(.transport(message: error.localizedDescription))
            }
        }
    }

    /// Publishes server messages (ordered by transcript index) plus any optimistic
    /// messages the server hasn't echoed back yet. A server copy sharing an optimistic
    /// message's id supersedes it.
    private func reconcile() {
        pendingOptimistic.removeAll { serverMessagesById[$0.id] != nil }
        let ordered = serverMessagesById.values.sorted {
            ($0.sessionIndex, $0.receivedAt) < ($1.sessionIndex, $1.receivedAt)
        }
        messagesLoadable = .loaded(ordered + pendingOptimistic)
    }

    func pollStatusAndMessages() async {
        await loadStatus()
        await refreshMessages()
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        sendError = nil
        isSending = true
        defer { isSending = false }

        // The client-generated id is passed to the API as `messageId`, so the server's
        // echo of this message carries the same id and supersedes the optimistic copy.
        let messageId = UUID().uuidString
        let maxServerIndex = serverMessagesById.values.map(\.sessionIndex).max() ?? -1
        let optimisticMessage = TranscriptMessage(
            id: messageId,
            sessionId: session.id,
            sessionIndex: maxServerIndex + 1 + Double(pendingOptimistic.count),
            type: "user",
            content: .object(["text": .string(trimmed)]),
            receivedAt: ISO8601DateFormatter().string(from: Date())
        )
        pendingOptimistic.append(optimisticMessage)
        reconcile()

        do {
            _ = try await client.sendMessage(sessionId: session.id, message: trimmed, messageId: messageId)
            await loadStatus()
            await refreshMessages()
        } catch let error as ConductorError {
            sendError = error
            pendingOptimistic.removeAll { $0.id == messageId }
            reconcile()
        } catch {
            sendError = .transport(message: error.localizedDescription)
            pendingOptimistic.removeAll { $0.id == messageId }
            reconcile()
        }
    }

    func cancel() async {
        isCanceling = true
        defer { isCanceling = false }

        do {
            _ = try await client.cancelSession(id: session.id)
            await loadStatus()
        } catch let error as ConductorError {
            sendError = error
        } catch {
            sendError = .transport(message: error.localizedDescription)
        }
    }

    func rename(to newName: String) async -> Bool {
        isRenaming = true
        defer { isRenaming = false }

        do {
            session = try await client.renameSession(id: session.id, name: newName)
            return true
        } catch let error as ConductorError {
            sendError = error
            return false
        } catch {
            sendError = .transport(message: error.localizedDescription)
            return false
        }
    }
}
