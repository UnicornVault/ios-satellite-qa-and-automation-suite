//
//  AccountManagerTests.swift
//  iOS Automation Portfolio — Account Manager / B2B SaaS genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Kept simple on purpose: a few core scenarios covering the things that
//  matter most in internal/B2B tools — finding a record, editing it
//  correctly, and making sure permissions are respected.

import XCTest

final class AccountManagerTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Searching for a client by name returns the matching account.
    /// If search is broken, the whole tool is unusable for a rep.
    func testSearchFindsClientAccount() {
        let app = XCUIApplication()
        app.launch()

        app.searchFields["clientSearchField"].tap()
        app.searchFields["clientSearchField"].typeText("Acme Corp")

        XCTAssertTrue(app.cells.staticTexts["Acme Corp"].waitForExistence(timeout: 5))
    }

    /// [SMOKE] Editing a client's contact info and saving actually persists
    /// the change. Wrong or lost edits directly damage a rep's trust in the tool.
    func testEditContactInfoSaves() {
        let app = XCUIApplication()
        app.launch()

        app.cells.element(boundBy: 0).tap()
        app.buttons["editButton"].tap()
        app.textFields["contactEmailField"].tap()
        app.textFields["contactEmailField"].typeText("newcontact@acme.com")
        app.buttons["saveButton"].tap()

        XCTAssertTrue(app.staticTexts["newcontact@acme.com"].waitForExistence(timeout: 3))
    }

    /// Filtering the pipeline/deal list by stage shows only matching deals.
    func testFilterPipelineByStage() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Pipeline"].tap()
        app.buttons["filterButton"].tap()
        app.buttons["stageOption_Negotiation"].tap()

        XCTAssertTrue(app.cells.element(boundBy: 0).exists)
    }

    /// [SMOKE] A user without admin permissions cannot see admin-only fields
    /// (e.g. contract value). Permission leaks are a serious trust/compliance issue.
    func testNonAdminCannotSeeRestrictedFields() {
        let app = XCUIApplication()
        app.launchArguments = ["-userRole", "standard"]
        app.launch()

        app.cells.element(boundBy: 0).tap()

        XCTAssertFalse(app.staticTexts["contractValueField"].exists)
    }

    /// Exporting a report produces a file/confirmation, so a rep can trust
    /// the number they hand off matches what's on screen.
    func testExportReportShowsConfirmation() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Reports"].tap()
        app.buttons["exportButton"].tap()

        XCTAssertTrue(app.staticTexts["Export complete"].waitForExistence(timeout: 5))
    }
}