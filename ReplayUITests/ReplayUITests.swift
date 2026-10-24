import XCTest

final class ReplayUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        return app
    }

    func testHomeActivitiesAndSessions() {
        let app = launch()
        XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: 10))
        app.buttons["activity-Workout"].tap()
        XCTAssertTrue(app.buttons["activity-Workout"].isSelected)
        app.buttons["tab-Sessions"].tap()
        XCTAssertTrue(app.staticTexts["Your sessions"].exists)
        XCTAssertTrue(app.staticTexts["Your first session starts here."].exists)
        app.buttons["Start a session"].tap()
        XCTAssertTrue(app.buttons["record-button"].exists)
    }

    func testExampleReportIsClearlyLabeled() {
        let app = launch()
        app.swipeUp()
        app.buttons["example-button"].tap()
        XCTAssertTrue(app.staticTexts["EXAMPLE REVIEW"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A strong start. A steadier finish."].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Keep doing"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tab-Practice"].exists)
    }

    func testSettingsAndSimulatorCameraFallback() {
        let app = launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.textFields["server-address"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["connection-token"].exists)
        app.buttons["Done"].tap()
        app.buttons["record-button"].tap()
        XCTAssertTrue(app.staticTexts["The simulator has no camera. Run Replay on your iPhone to record, or import a video here."].waitForExistence(timeout: 5))
        app.buttons["Back to practice"].tap()
        XCTAssertTrue(app.buttons["record-button"].exists)
    }
}
