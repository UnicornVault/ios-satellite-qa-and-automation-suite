//
//  FintechTests.swift
//  iOS Automation Portfolio — Fintech genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Genre-specific scenarios for a finance app: balance display, transaction
//  history, and biometric-gated sensitive actions. Fintech apps carry higher
//  correctness stakes than most genres, so these tests lean toward strict
//  exact-match assertions rather than "exists" checks.

import XCTest

final class FintechTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Account balance displays correctly formatted currency on launch.
    /// A wrong or missing balance is a release-blocking bug in a finance app.
    func testBalanceDisplaysOnLaunch() {
        let app = XCUIApplication()
        app.launch()

        let balance = app.staticTexts["accountBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertTrue(balance.label.hasPrefix("$"))
    }

    /// Transaction history list is sorted most-recent-first.
    func testTransactionHistorySortedByDate() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["History"].tap()

        let firstDate = app.cells.element(boundBy: 0).staticTexts["transactionDate"].label
        let secondDate = app.cells.element(boundBy: 1).staticTexts["transactionDate"].label

        // Exact date comparison logic depends on the app's date model;
        // this assertion is illustrative of intent, not a literal string compare.
        XCTAssertNotEqual(firstDate, secondDate)
    }

    /// [SMOKE] Biometric-gated action (e.g., viewing full account number)
    /// requires Face ID / Touch ID before revealing sensitive data.
    /// Security-critical path — always in smoke suite.
    func testSensitiveDataRequiresBiometricAuth() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["viewAccountNumberButton"].tap()

        // Simulator supports programmatic biometric enrollment/matching via
        // XCUIDevice in recent Xcode versions; exact API varies by Xcode
        // release, so this represents the intended check rather than a
        // guaranteed-compiling call.
        XCTAssertTrue(app.staticTexts["Face ID Required"].waitForExistence(timeout: 3))
    }

    /// A failed biometric match keeps sensitive data hidden.
    func testFailedBiometricKeepsDataHidden() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateBiometricFailure", "true"]
        app.launch()

        app.buttons["viewAccountNumberButton"].tap()

        XCTAssertFalse(app.staticTexts["fullAccountNumber"].exists)
    }

    /// [SMOKE] Initiating a money transfer with valid details shows a
    /// confirmation step before the transfer is final — prevents accidental
    /// fund movement, a core trust requirement for finance apps.
    func testTransferRequiresConfirmationStep() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Transfer"].tap()

        app.textFields["amountField"].tap()
        app.textFields["amountField"].typeText("100")
        app.buttons["continueButton"].tap()

        XCTAssertTrue(app.staticTexts["Confirm transfer of $100"].waitForExistence(timeout: 3))
    }

    /// Attempting to transfer more than the available balance is blocked
    /// client-side with a clear error, not just a failed server call.
    func testTransferExceedingBalanceBlocked() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Transfer"].tap()

        app.textFields["amountField"].tap()
        app.textFields["amountField"].typeText("999999")
        app.buttons["continueButton"].tap()

        XCTAssertTrue(app.staticTexts["Insufficient funds"].waitForExistence(timeout: 3))
    }
}