import XCTest
@testable import ConductorMobile

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

    func testDisplayTextNilForNonStringContentField() {
        // "content" present but not a string (e.g. nested object) — should not be dug out.
        let value = JSONValue.object(["content": .object(["nested": .string("x")])])
        XCTAssertNil(value.displayText)
    }

    func testDisplayTextNilForNumberOrArrayOrNull() {
        XCTAssertNil(JSONValue.number(1).displayText)
        XCTAssertNil(JSONValue.array([.string("x")]).displayText)
        XCTAssertNil(JSONValue.null.displayText)
        XCTAssertNil(JSONValue.bool(true).displayText)
    }
}
