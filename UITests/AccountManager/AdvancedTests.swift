//
//  AdvancedTests.swift
//  iOS Automation Portfolio
//
//  Author: UnicornVault
//  Created: 2026-08-03
//

import XCTest

final class AdvancedTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Permissions

    /// Validates the app's behavior when a user denies a system permission
    /// dialog (location, in this case). Taps "Don't Allow" on the OS-level
    /// prompt, then confirms the app shows a helpful message rather than
    /// crashing or silently doing nothing.
    func testLocationPermissionDenied() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["enableLocationButton"].tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Don't Allow"].waitForExistence(timeout: 3) {
            springboard.buttons["Don't Allow"].tap()
        }

        XCTAssertTrue(app.staticTexts["Location access needed"].exists)
    }

    // MARK: - App lifecycle

    /// Validates that in-progress user input survives the app being sent to
    /// the background and brought back to the foreground. Simulates pressing
    /// the home button, then reactivating, and checks the search field still
    /// holds what was typed.
    func testStateRetainedAfterBackground() {
        let app = XCUIApplication()
        app.launch()

        app.textFields["searchField"].tap()
        app.textFields["searchField"].typeText("shoes")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertEqual(app.textFields["searchField"].value as? String, "shoes")
    }

    // MARK: - Network conditions

    /// Validates offline handling. Launches the app with a custom launch
    /// argument that tells a test-only code path to simulate no network
    /// connection, then checks that an "offline" banner appears instead of
    /// a generic crash or infinite spinner.
    func testOfflineStateShowsBanner() {
        let app = XCUIApplication()
        // Launch argument used by the app to simulate offline mode in test builds
        app.launchArguments = ["-simulateOffline", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["You're offline"].waitForExistence(timeout: 5))
    }

    // MARK: - Deep linking

    /// Validates that launching the app via a deep link URL routes directly
    /// to the correct screen with the correct data, skipping the normal
    /// login/list navigation path entirely.
    func testDeepLinkOpensCorrectItem() {
        let app = XCUIApplication()
        app.launchArguments = ["-deeplink", "myapp://item/42"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Item 42"].waitForExistence(timeout: 5))
    }

    // MARK: - Accessibility

    /// Validates that the login button has a human-readable accessibility
    /// label ("Log In"), which is what VoiceOver would read aloud. Catches
    /// cases where a button only has an icon and no label for screen readers.
    func testLoginButtonHasAccessibilityLabel() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.buttons["loginButton"].label, "Log In")
    }

    // MARK: - Device rotation

    /// Validates that key UI elements (the login button, here) remain visible
    /// and tappable after rotating the device to landscape, then rotates back
    /// to portrait to leave the simulator in a clean state for the next test.
    func testLayoutSurvivesRotation() {
        let app = XCUIApplication()
        app.launch()

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["loginButton"].exists)

        XCUIDevice.shared.orientation = .portrait
    }
}
