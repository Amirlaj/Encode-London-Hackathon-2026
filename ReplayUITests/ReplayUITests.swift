import XCTest

final class ReplayUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        return app
    }

    func testGeneralHomeAndSavedVideos() {
        let app = launch()
        XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["import-photos"].exists)
        XCTAssertTrue(app.textViews["task-description"].exists || app.textFields["task-description"].exists)
        XCTAssertFalse(app.buttons["activity-Tennis"].exists)
        XCTAssertFalse(app.staticTexts["Tennis"].exists)
        app.buttons["Add a checklist (optional)"].tap()
        XCTAssertTrue(app.textViews["task-criteria"].waitForExistence(timeout: 5) || app.textFields["task-criteria"].exists)
        app.buttons["Add a checklist (optional)"].tap()
        app.buttons["tab-Your videos"].tap()
        XCTAssertTrue(app.staticTexts["Your videos"].exists)
        XCTAssertTrue(app.staticTexts["No videos yet."].exists)
        app.buttons["Add a video"].tap()
        XCTAssertTrue(app.buttons["record-button"].exists)
    }

    func testExampleReportIsClearlyLabeled() {
        let app = launch()
        app.swipeUp()
        app.buttons["example-button"].tap()
        XCTAssertTrue(app.staticTexts["EXAMPLE REVIEW"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Check the alignment before moving on."].exists)
        XCTAssertFalse(app.staticTexts["Tennis"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["What needs fixing"].exists)
        XCTAssertTrue(app.staticTexts["Why it matters"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["How to fix it"].firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tab-Review"].exists)
    }

    func testSettingsAndSimulatorCameraFallback() {
        let app = launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.textFields["server-address"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["connection-token"].exists)
        app.buttons["Done"].tap()
        app.buttons["record-button"].tap()
        XCTAssertTrue(app.staticTexts["The simulator has no camera. Run Replay on your iPhone to record, or import a video here."].waitForExistence(timeout: 5))
        app.buttons["Back to review"].tap()
        XCTAssertTrue(app.buttons["record-button"].exists)
    }
}
