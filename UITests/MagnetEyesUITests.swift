import XCTest

final class MagnetEyesUITests: XCTestCase {
    @MainActor
    func testSimulatorDoesNotSilentlyUseSyntheticData() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Simulator has no magnetometer")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recenter"].isEnabled)
        saveScreenshot("Unavailable sensor")
    }

    @MainActor
    func testDemoRecenterAndCameraModeKeepDemoDisclosure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["recenter"].waitForExistence(timeout: 5))
        saveScreenshot("Labeled demo")
        app.buttons["recenter"].tap()
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["recenter"])
        waitForExpectations(timeout: 5)
        app.buttons["camera-mode"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "DEMO")).firstMatch.exists)
        XCTAssertTrue(app.buttons["exit-camera-mode"].exists)
        saveScreenshot("Camera mode with demo disclosure")
        app.buttons["exit-camera-mode"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["live-mode"].waitForExistence(timeout: 3))
        app.buttons["live-mode"].tap()
        // Verify returning to live never preserves synthetic field/gaze state.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Simulator has no magnetometer")).firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testFieldViewShowsOnlyMeasuredOrExplicitlySimulatedData() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["view-field"].waitForExistence(timeout: 5))
        app.buttons["view-field"].tap()
        XCTAssertTrue(app.otherElements["field-grid"].exists)
        XCTAssertFalse(app.otherElements["field-marker"].exists)
        saveScreenshot("Light field unavailable")

        app.buttons["demo-mode"].tap()
        XCTAssertTrue(app.otherElements["field-marker"].waitForExistence(timeout: 5))
        saveScreenshot("Light field demo")

        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["live-mode"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        saveScreenshot("Light settings")
        app.buttons["live-mode"].tap()
        app.buttons["Done"].tap()
        XCTAssertFalse(app.otherElements["field-marker"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Simulator has no magnetometer")).firstMatch.exists)
    }

    @MainActor
    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
