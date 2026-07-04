import XCTest

@testable import Nickel

/// EventSummary must reproduce the Conductor desktop timeline rows from the SDK payload
/// shapes captured live (see tools/transport-probe/FINDINGS.md).
final class EventSummaryTests: XCTestCase {
    private func message(rawPayload: JSONValue) -> TranscriptMessage {
        TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "agent",
            content: .object(["rawPayload": rawPayload]),
            receivedAt: "2026-07-04 14:28:19.429+00"
        )
    }

    func testApiRetryMatchesConductorWording() {
        let summary = EventSummary.make(for: message(rawPayload: .object([
            "type": .string("system"),
            "subtype": .string("api_retry"),
            "attempt": .number(1),
            "max_retries": .number(10),
            "retry_delay_ms": .number(7000),
            "error_status": .number(429),
            "error": .string("rate_limit"),
        ])))
        XCTAssertEqual(summary.title, "Retrying (attempt 1/10) · 429 rate_limit")
        XCTAssertFalse(summary.isError)
    }

    func testBashToolUseShowsDescriptionAndCommand() {
        let summary = EventSummary.make(for: message(rawPayload: .object([
            "type": .string("assistant"),
            "message": .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("tool_use"),
                        "name": .string("Bash"),
                        "input": .object([
                            "command": .string("git remote -v"),
                            "description": .string("Check remote URLs"),
                        ]),
                    ]),
                ]),
            ]),
        ])))
        XCTAssertEqual(summary.icon, "terminal")
        XCTAssertEqual(summary.title, "Check remote URLs")
        XCTAssertEqual(summary.snippet, "git remote -v")
    }

    func testFailedToolResultIsRedWithFirstLine() {
        let summary = EventSummary.make(for: message(rawPayload: .object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("tool_result"),
                        "is_error": .bool(true),
                        "content": .string("Exit code 128 Author identity unknown\n*** Please tell me who you are."),
                    ]),
                ]),
            ]),
        ])))
        XCTAssertTrue(summary.isError)
        XCTAssertEqual(summary.title, "Error")
        XCTAssertEqual(summary.snippet, "Exit code 128 Author identity unknown")
    }

    func testSuccessfulToolResultShowsOutputFirstLine() {
        let summary = EventSummary.make(for: message(rawPayload: .object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("tool_result"),
                        "content": .string("/workspace/README.md\n/workspace/skills"),
                    ]),
                ]),
            ]),
        ])))
        XCTAssertFalse(summary.isError)
        XCTAssertEqual(summary.title, "Output")
        XCTAssertEqual(summary.snippet, "/workspace/README.md")
    }

    func testInitAndResultRows() {
        let started = EventSummary.make(for: message(rawPayload: .object([
            "type": .string("system"),
            "subtype": .string("init"),
            "model": .string("claude-sonnet-4-6"),
        ])))
        XCTAssertEqual(started.title, "Session started")
        XCTAssertEqual(started.snippet, "claude-sonnet-4-6")

        let failed = EventSummary.make(for: message(rawPayload: .object([
            "type": .string("result"),
            "subtype": .string("success"),
            "is_error": .bool(true),
            "total_cost_usd": .number(0.085),
            "duration_ms": .number(1112),
        ])))
        XCTAssertTrue(failed.isError)
        XCTAssertEqual(failed.title, "Turn failed")
        XCTAssertEqual(failed.snippet, "$0.085 · 1.1s")
    }

    func testSubagentToolUseGetsTaskPrefix() {
        let summary = EventSummary.make(for: message(rawPayload: .object([
            "type": .string("assistant"),
            "parent_tool_use_id": .string("toolu_task"),
            "message": .object([
                "content": .array([
                    .object([
                        "type": .string("tool_use"),
                        "name": .string("Read"),
                        "input": .object(["file_path": .string("README.md")]),
                    ]),
                ]),
            ]),
        ])))
        XCTAssertEqual(summary.title, "task · Read")
        XCTAssertEqual(summary.snippet, "README.md")
    }

    func testNonSDKPayloadFallsBackToEventKind() {
        let demo = TranscriptMessage(
            id: "m", sessionId: "s", sessionIndex: 0, type: "tool_call",
            content: .object(["tool": .string("read_file")]),
            receivedAt: "2026-07-04 14:28:19.429+00"
        )
        let summary = EventSummary.make(for: demo)
        XCTAssertEqual(summary.icon, "curlybraces")
        XCTAssertEqual(summary.title, "tool_call")
    }
}
