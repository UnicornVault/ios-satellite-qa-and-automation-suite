//
//  LoginHelper.swift
//  iOS Automation Portfolio
//
//  Author: UnicornVault
//  Created: 2026-08-03
//

import XCTest

/// Shared helper so every test file doesn't repeat the same login steps.
/// Keeping this separate mirrors the Page Object pattern used in most
/// production automation frameworks.
extension XCUIApplication {

    func loginAsValidUser(username: String = "testuser", password: String = "password123") {
        self.textFields["usernameField"].tap()
        self.textFields["usernameField"].typeText(username)

        self.secureTextFields["passwordField"].tap()
        self.secureTextFields["passwordField"].typeText(password)

        self.buttons["loginButton"].tap()
    }
}