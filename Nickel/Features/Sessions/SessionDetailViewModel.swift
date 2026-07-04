import Foundation
import Observation

/// Delivery state of an optimistically-sent message, tracked until the server echo
/// (or a cancel) resolves it.
enum OptimisticMessageState {
    case queued
    case sent
    case canceled
}

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
    /// Delivery state of each optimistic message still awaiting (or denied) a server
    /// echo, keyed by the client-generated `messageId`. Consulted by the view to render
    /// a "Queued" or "Not delivered — canceled" footer on the pending bubble.
    private(set) var optimisticMessageStatesById: [String: OptimisticMessageState] = [:]

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
                var newMessageCount = 0
                for message in page.data {
                    if serverMessagesById[message.id] == nil {
                        newMessageCount += 1
                    }
                    serverMessagesById[message.id] = message
                }
                pagesFetched += 1
                if !page.hasMore {
                    break
                }
                // A non-empty page that contributed no new ids would re-request the same
                // offset forever (offset is derived from `serverMessagesById.count`) —
                // bail out instead of spinning until the page-count valve trips.
                if !page.data.isEmpty && newMessageCount == 0 {
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
    /// messages the server hasn't echoed back yet. The live API assigns its own
    /// transcript-event id to the echo and carries the client-generated `messageId` at
    /// `content.id`, so optimistic copies are matched on either.
    private func reconcile() {
        let confirmedClientIds = Set(
            serverMessagesById.values.compactMap { $0.content["id"]?.stringValue }
        )
        pendingOptimistic.removeAll {
            let isEchoed = serverMessagesById[$0.id] != nil || confirmedClientIds.contains($0.id)
            if isEchoed {
                optimisticMessageStatesById.removeValue(forKey: $0.id)
            }
            return isEchoed
        }
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
            let response = try await client.sendMessage(sessionId: session.id, message: trimmed, messageId: messageId)
            optimisticMessageStatesById[messageId] = response.state == .queued ? .queued : .sent
            await loadStatus()
            await refreshMessages()
        } catch let error as ConductorError {
            sendError = error
            pendingOptimistic.removeAll { $0.id == messageId }
            optimisticMessageStatesById.removeValue(forKey: messageId)
            reconcile()
        } catch {
            sendError = .transport(message: error.localizedDescription)
            pendingOptimistic.removeAll { $0.id == messageId }
            optimisticMessageStatesById.removeValue(forKey: messageId)
            reconcile()
        }
    }

    func cancel() async {
        guard !isCanceling else {
            return
        }
        isCanceling = true
        defer { isCanceling = false }

        do {
            let response = try await client.cancelSession(id: session.id)
            // Apply the response directly rather than issuing a follow-up status GET:
            // if that second request failed, a cancel that actually succeeded would
            // surface as a false failure. Preserve whatever error message is already
            // loaded, since the cancel response doesn't carry one.
            let updatedAt = ISO8601DateFormatter().string(from: Date())
            statusLoadable = .loaded(SessionStatus(
                workspaceId: response.workspaceId,
                sessionId: response.sessionId,
                status: response.status,
                updatedAt: updatedAt,
                errorMessage: statusLoadable.value?.errorMessage
            ))

            if response.canceledQueuedMessages > 0 {
                // Not-yet-delivered queued messages were dropped by the cancel and will
                // never be echoed by the server — mark their bubbles so they don't sit
                // as "pending" forever.
                for message in pendingOptimistic where optimisticMessageStatesById[message.id] == .queued {
                    optimisticMessageStatesById[message.id] = .canceled
                }
            }
        } catch let error as ConductorError {
            sendError = error
        } catch {
            sendError = .transport(message: error.localizedDescription)
        }
    }

    func rename(to newName: String) async -> Bool {
        guard !isRenaming else {
            return false
        }
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
