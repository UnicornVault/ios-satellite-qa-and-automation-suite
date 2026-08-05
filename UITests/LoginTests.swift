//
//  LoginTests.swift
//  iOS Automation Portfolio
//
//  Author: UnicornVault
//  Created: 2026-08-03
//

import XCTest

final class LoginTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Validates the happy path: correct username + password logs the user in
    /// and lands them on the item list screen.
    /// Fails if the "ItemList" navigation bar never appears within 5 seconds.
    func testSuccessfulLogin() {
        let app = XCUIApplication()
        app.launch()

        app.loginAsValidUser()

        XCTAssertTrue(app.navigationBars["ItemList"].waitForExistence(timeout: 5))
        attachScreenshot(named: "SuccessfulLogin_ItemListShown")
    }

    /// Validates client-side form validation: tapping Login with both fields
    /// empty should surface an inline error instead of attempting a network call.
    func testEmptyFieldsShowError() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.staticTexts["Please enter credentials"].exists)
        attachScreenshot(named: "EmptyFields_ErrorShown")
    }

    /// Validates server-side auth failure handling: correct username but wrong
    /// password should show "Invalid credentials" rather than crashing or
    /// silently failing. Uses a timeout since this depends on a (mocked) network call.
    func testWrongPasswordShowsError() {
        let app = XCUIApplication()
        app.launch()

        app.textFields["usernameField"].tap()
        app.textFields["usernameField"].typeText("testuser")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("wrongpass")
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.staticTexts["Invalid credentials"].waitForExistence(timeout: 3))
        attachScreenshot(named: "WrongPassword_ErrorShown")
    }
}
