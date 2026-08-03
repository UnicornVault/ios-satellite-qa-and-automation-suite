//
//  NavigationTests.swift
//  iOS Automation Portfolio
//
//  Author: UnicornVault
//  Created: 2026-08-03
//

import XCTest

final class NavigationTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Validates that the list screen loads at least one item and that scrolling
    /// reveals additional content. Confirms the list isn't just a static single-item view.
    func testListScrollsAndShowsItems() {
        let app = XCUIApplication()
        app.launch()
        app.loginAsValidUser()

        let firstCell = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))

        app.swipeUp()
        XCTAssertTrue(app.cells.count > 1)
    }

    /// Validates list-to-detail navigation: tapping the first cell should push
    /// to a detail screen, identified by the "ItemDetail" navigation bar.
    func testTapItemOpensDetail() {
        let app = XCUIApplication()
        app.launch()
        app.loginAsValidUser()

        app.cells.element(boundBy: 0).tap()

        XCTAssertTrue(app.navigationBars["ItemDetail"].waitForExistence(timeout: 3))
    }

    /// Validates the logout flow: tapping logout should clear the session and
    /// return the user to the login screen (confirmed by the username field reappearing).
    func testLogoutReturnsToLogin() {
        let app = XCUIApplication()
        app.launch()
        app.loginAsValidUser()

        app.buttons["logoutButton"].tap()

        XCTAssertTrue(app.textFields["usernameField"].waitForExistence(timeout: 3))
    }
}
