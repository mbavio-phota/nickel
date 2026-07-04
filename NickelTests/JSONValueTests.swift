import XCTest
@testable import Nickel

final class JSONValueTests: XCTestCase {
    func testRoundTripAllPrimitives() throws {
        let values: [JSONValue] = [
            .string("hello"),
            .number(42.5),
            .bool(true),
            .bool(false),
            .null,
            .array([.string("a"), .number(1), .bool(true), .null]),
            .object(["key": .string("value"), "nested": .object(["inner": .number(3)])]),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func testDecodeTopLevelString() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data("\"just text\"".utf8))
        XCTAssertEqual(decoded, .string("just text"))
    }

    func testDecodeTopLevelArray() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data("[1, 2, 3]".utf8))
        XCTAssertEqual(decoded, .array([.number(1), .number(2), .number(3)]))
    }

    func testSubscriptAccessors() {
        let object = JSONValue.object(["name": .string("Alice"), "tags": .array([.string("a"), .string("b")])])
        XCTAssertEqual(object["name"]?.stringValue, "Alice")
        XCTAssertEqual(object["tags"]?[0]?.stringValue, "a")
        XCTAssertEqual(object["tags"]?[1]?.stringValue, "b")
        XCTAssertNil(object["tags"]?[5]) // out of bounds, never crashes
        XCTAssertNil(object["missing"])
    }

    func testSubscriptOnNonObjectOrArrayReturnsNil() {
        let string = JSONValue.string("hi")
        XCTAssertNil(string["key"])
        XCTAssertNil(string[0])

        let number = JSONValue.number(1)
        XCTAssertNil(number["key"])
        XCTAssertNil(number[0])
    }

    // MARK: - displayText

    func testDisplayTextForPlainString() {
        XCTAssertEqual(JSONValue.string("plain").displayText, "plain")
    }

    func testDisplayTextDigsTextField() {
        let value = JSONValue.object(["text": .string("dug out")])
        XCTAssertEqual(value.displayText, "dug out")
    }

    func testDisplayTextDigsMessageField() {
        let value = JSONValue.object(["message": .string("a message")])
        XCTAssertEqual(value.displayText, "a message")
    }

    func testDisplayTextDigsContentFieldWhenString() {
        let value = JSONValue.object(["content": .string("content text")])
        XCTAssertEqual(value.displayText, "content text")
    }

    func testDisplayTextPrefersTextOverMessageOverContent() {
        let value = JSONValue.object([
            "text": .string("first"),
            "message": .string("second"),
            "content": .string("third"),
        ])
        XCTAssertEqual(value.displayText, "first")
    }

    func testDisplayTextNilForUnknownShape() {
        let value = JSONValue.object(["tool": .string("edit_file"), "args": .object(["path": .string("x")])])
        XCTAssertNil(value.displayText)
    }

    func testDisplayTextNilWhenNoCarrierKeyLeadsToText() {
        // "content" present but nothing text-like beneath any known carrier key.
        let value = JSONValue.object(["content": .object(["nested": .string("x")])])
        XCTAssertNil(value.displayText)
    }

    func testDisplayTextNilForNumberOrNull() {
        XCTAssertNil(JSONValue.number(1).displayText)
        XCTAssertNil(JSONValue.null.displayText)
        XCTAssertNil(JSONValue.bool(true).displayText)
        XCTAssertNil(JSONValue.array([.number(1), .null]).displayText)
    }

    func testDisplayTextRecursesNestedMessageContentParts() {
        // Anthropic/OpenAI-style nesting: message.content is an array of typed blocks.
        let value = JSONValue.object([
            "message": .object([
                "role": .string("assistant"),
                "content": .array([
                    .object(["type": .string("text"), "text": .string("First block.")]),
                    .object(["type": .string("tool_use"), "name": .string("read_file")]),
                    .object(["type": .string("text"), "text": .string("Second block.")]),
                ]),
            ]),
        ])
        XCTAssertEqual(value.displayText, "First block.\nSecond block.")
    }

    func testDisplayTextConcatenatesArrayOfStrings() {
        XCTAssertEqual(JSONValue.array([.string("a"), .string("b")]).displayText, "a\nb")
    }

    func testDisplayTextIgnoresEmptyResult() {
        XCTAssertNil(JSONValue.object(["text": .string("")]).displayText)
    }

    func testRoleValueDirectAndNestedInMessage() {
        XCTAssertEqual(JSONValue.object(["role": .string("user")]).roleValue, "user")
        XCTAssertEqual(
            JSONValue.object(["message": .object(["role": .string("user")])]).roleValue,
            "user"
        )
        XCTAssertNil(JSONValue.object(["text": .string("x")]).roleValue)
    }

    func testTranscriptMessageIsFromUser() {
        func message(type: String, content: JSONValue) -> TranscriptMessage {
            TranscriptMessage(
                id: "m", sessionId: "s", sessionIndex: 0, type: type, content: content,
                receivedAt: "2026-07-04T10:00:00Z"
            )
        }
        XCTAssertTrue(message(type: "user", content: .null).isFromUser)
        XCTAssertTrue(message(type: "user_message", content: .null).isFromUser)
        XCTAssertTrue(
            message(type: "message", content: .object(["role": .string("user")])).isFromUser
        )
        XCTAssertFalse(message(type: "agent", content: .null).isFromUser)
        XCTAssertFalse(
            message(type: "message", content: .object(["role": .string("assistant")])).isFromUser
        )
    }

    // MARK: - Real Conductor payload shapes (captured from the live API 2026-07-04)

    /// Condensed replica of a live Conductor "agent" message wrapping a Claude Code SDK
    /// assistant event: text lives at rawPayload.message.content[].text.
    private func conductorAssistantEvent(text: String) -> JSONValue {
        .object([
            "eventId": .string("evt:4:0"),
            "turnId": .string("62F5B0FF"),
            "type": .string("agent"),
            "userMessageId": .string("62F5B0FF"),
            "rawPayload": .object([
                "type": .string("assistant"),
                "session_id": .string("fcff15f0"),
                "message": .object([
                    "id": .string("msg_012NQ"),
                    "role": .string("assistant"),
                    "type": .string("message"),
                    "model": .string("claude-sonnet-4-6"),
                    "content": .array([
                        .object(["type": .string("text"), "text": .string(text)]),
                    ]),
                ]),
            ]),
        ])
    }

    func testDisplayTextExtractsConductorAssistantEvent() {
        let value = conductorAssistantEvent(text: "Hello! How can I help you today?")
        XCTAssertEqual(value.displayText, "Hello! How can I help you today?")
    }

    func testConductorSystemInitEventStaysChipWithDescriptiveKind() {
        let content = JSONValue.object([
            "eventId": .string("evt:3:0"),
            "type": .string("agent"),
            "rawPayload": .object([
                "type": .string("system"),
                "subtype": .string("init"),
                "model": .string("claude-sonnet-4-6"),
                "tools": .array([.string("Task"), .string("Bash")]),
            ]),
        ])
        XCTAssertNil(content.displayText, "init events carry no prose and must stay chips")

        let message = TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "agent", content: content,
            receivedAt: "2026-07-04T10:00:00Z"
        )
        XCTAssertEqual(message.eventKind, "system · init")
        XCTAssertFalse(message.isFromUser)
    }

    func testConductorAssistantEventKindAndAuthorship() {
        let message = TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "agent",
            content: conductorAssistantEvent(text: "Hi."),
            receivedAt: "2026-07-04T10:00:00Z"
        )
        XCTAssertEqual(message.eventKind, "assistant")
        XCTAssertFalse(message.isFromUser)
    }

    func testTypedBlockArrayOnlyContributesTextBlocks() {
        let value = JSONValue.array([
            .object(["type": .string("text"), "text": .string("Real prose.")]),
            .object([
                "type": .string("tool_use"),
                "name": .string("read_file"),
                "input": .object(["text": .string("should not leak")]),
            ]),
            .object([
                "type": .string("tool_result"),
                "content": .string("giant tool output, should not leak"),
            ]),
        ])
        XCTAssertEqual(value.displayText, "Real prose.")
    }

    func testPostgresStyleTimestampsParse() {
        XCTAssertNotNil(Formatters.date(from: "2026-07-04 14:27:40.002976+00"), "microsecond variant")
        XCTAssertNotNil(Formatters.date(from: "2026-07-04 14:28:19.429+00"), "millisecond variant")
        XCTAssertNotNil(Formatters.date(from: "2026-07-04 14:28:19+00"), "no-fraction variant")
        XCTAssertNotNil(Formatters.date(from: "2026-07-04T14:28:19.429Z"), "ISO-8601 still accepted")
        XCTAssertNil(Formatters.date(from: "not a date"))
    }

    func testToolResultEventKindAndResultDetail() {
        let toolResult = TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "agent",
            content: .object([
                "rawPayload": .object([
                    "type": .string("user"),
                    "message": .object([
                        "role": .string("user"),
                        "content": .array([
                            .object(["type": .string("tool_result"), "tool_use_id": .string("toolu_1")]),
                        ]),
                    ]),
                ]),
            ]),
            receivedAt: "2026-07-04 14:28:19.429+00"
        )
        XCTAssertEqual(toolResult.eventKind, "tool result")

        let result = TranscriptMessage(
            id: "m2", sessionId: "s", sessionIndex: 1, type: "agent",
            content: .object([
                "rawPayload": .object([
                    "type": .string("result"),
                    "subtype": .string("success"),
                    "total_cost_usd": .number(0.085044),
                    "duration_ms": .number(1112),
                ]),
            ]),
            receivedAt: "2026-07-04 14:28:19.429+00"
        )
        XCTAssertEqual(result.eventKind, "result · success")
        XCTAssertEqual(result.eventDetail, "$0.085 · 1.1s")
    }

    /// Sub-agent (Task) traffic captured live 2026-07-04: the task prompt arrives as a
    /// user-role text event with parent_tool_use_id set. It must chip, never bubble.
    func testSubagentTaskPromptIsChipNotBubble() {
        let message = TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "agent",
            content: .object([
                "rawPayload": .object([
                    "type": .string("user"),
                    "parent_tool_use_id": .string("toolu_task_1"),
                    "message": .object([
                        "role": .string("user"),
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("Give me a complete map of the repository."),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            receivedAt: "2026-07-04 14:28:19.429+00"
        )
        XCTAssertTrue(message.isSubagentEvent)
        XCTAssertFalse(message.rendersAsBubble, "sub-agent prompts must not render as chat prose")
        XCTAssertFalse(message.isFromUser)
        XCTAssertEqual(message.eventKind, "task · user")
    }

    func testMainThreadAssistantTextStillBubbles() {
        let message = TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "agent",
            content: .object([
                "rawPayload": .object([
                    "type": .string("assistant"),
                    "parent_tool_use_id": .null,
                    "message": .object([
                        "role": .string("assistant"),
                        "content": .array([
                            .object(["type": .string("text"), "text": .string("Here you go.")]),
                        ]),
                    ]),
                ]),
            ]),
            receivedAt: "2026-07-04 14:28:19.429+00"
        )
        XCTAssertFalse(message.isSubagentEvent, "a JSON-null parent_tool_use_id is not parented")
        XCTAssertTrue(message.rendersAsBubble)
    }

    func testSystemTaskEventDetailUsesDescriptionOrSummary() {
        func systemEvent(_ fields: [String: JSONValue]) -> TranscriptMessage {
            var raw = fields
            raw["type"] = .string("system")
            return TranscriptMessage(
                id: "m", sessionId: "s", sessionIndex: 0, type: "agent",
                content: .object(["rawPayload": .object(raw)]),
                receivedAt: "2026-07-04 14:28:19.429+00"
            )
        }
        let progress = systemEvent([
            "subtype": .string("task_progress"),
            "description": .string("Map repository structure"),
        ])
        XCTAssertEqual(progress.eventKind, "system · task_progress")
        XCTAssertEqual(progress.eventDetail, "Map repository structure")

        let notification = systemEvent([
            "subtype": .string("task_notification"),
            "summary": .string("Task finished"),
        ])
        XCTAssertEqual(notification.eventDetail, "Task finished")
    }

    func testToolResultUserRoleEventIsNotFromUser() {
        // Claude Code delivers tool results as user-role SDK events; they must not
        // render as the human's own message.
        let message = TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "agent",
            content: .object([
                "rawPayload": .object([
                    "type": .string("user"),
                    "message": .object([
                        "role": .string("user"),
                        "content": .array([
                            .object([
                                "type": .string("tool_result"),
                                "tool_use_id": .string("toolu_1"),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            receivedAt: "2026-07-04T10:00:00Z"
        )
        XCTAssertFalse(message.isFromUser)
    }
}
