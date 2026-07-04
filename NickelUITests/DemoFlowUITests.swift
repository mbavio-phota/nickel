import XCTest

/// End-to-end walk of the demo-mode flow: onboarding → projects → project detail →
/// workspace detail → session chat → send a message and watch the agent "work" → reply.
/// Captures a named screenshot at every step for visual verification.
final class DemoFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDemoModeEndToEndFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // Onboarding.
        let demoButton = app.buttons["Explore with demo data"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "01-onboarding")
        demoButton.tap()

        // Projects list.
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 10))
        let projectRow = app.staticTexts["nebuchadnezzar"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "02-projects")

        // Project detail: workspaces with status dots.
        projectRow.tap()
        XCTAssertTrue(app.navigationBars["nebuchadnezzar"].waitForExistence(timeout: 10))
        let workspaceRow = app.staticTexts["free-the-mind"]
        XCTAssertTrue(workspaceRow.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "03-project-detail")

        // Workspace detail: status card + sessions.
        workspaceRow.tap()
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 10))
        let sessionRow = app.staticTexts["Follow the white rabbit"]
        XCTAssertTrue(sessionRow.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "04-workspace-detail")

        // Session chat: transcript loads.
        sessionRow.tap()
        let composer = app.textFields["Message"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Idle"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "05-session-chat")

        // Send a message; the demo agent flips to Working, then replies ~6s later.
        composer.tap()
        composer.typeText("Also patch the spoon so it does not bend back")
        app.buttons["Send"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Working"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "06-agent-working")

        XCTAssertTrue(app.staticTexts["Idle"].waitForExistence(timeout: 30))
        // Wait for the demo agent's canned reply bubble itself, not just the Idle flip —
        // the status and the transcript refresh land a poll apart.
        let replyPredicate = NSPredicate(
            format: "label CONTAINS 'I made the change' OR label CONTAINS 'pushed a fix' "
                + "OR label CONTAINS 'what I found' OR label CONTAINS 'cleaned up a residual glitch'"
        )
        XCTAssertTrue(app.staticTexts.matching(replyPredicate).firstMatch.waitForExistence(timeout: 15))
        attachScreenshot(app, name: "07-agent-replied")

        // Settings sheet from the projects root.
        app.navigationBars.buttons.firstMatch.tap() // back to workspace
        app.navigationBars.buttons.firstMatch.tap() // back to project
        app.navigationBars.buttons.firstMatch.tap() // back to projects
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Demo mode"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "08-settings")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
