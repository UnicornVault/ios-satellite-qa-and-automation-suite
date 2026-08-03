//
//  ProcurementTests.swift
//  iOS Automation Portfolio — Procurement / Resource Allocation genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Scenarios for allocating hours to a project and having that roll up
//  into company-level financial goals — open orders, P&L. This is the
//  highest-stakes genre in the suite: a rollup that silently drifts from
//  the sum of its parts is a real finance/reporting incident, not just a
//  UI bug, so several of these tests are strict equality checks rather
//  than "exists" checks.

import XCTest

final class ProcurementTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Allocating hours to a project saves and shows up on the
    /// project's allocation summary. Core input action for this whole flow.
    func testAllocateHoursToProjectSaves() {
        let app = XCUIApplication()
        app.launch()

        app.cells.staticTexts["Project Alpha"].tap()
        app.textFields["hoursField"].tap()
        app.textFields["hoursField"].typeText("8")
        app.buttons["saveAllocationButton"].tap()

        XCTAssertTrue(app.staticTexts["8 hrs allocated"].waitForExistence(timeout: 3))
    }

    /// Allocating more hours than available in the selected period (e.g.
    /// more than 40 hrs in a work week) is blocked client-side, preventing
    /// impossible resourcing data from ever reaching the rollup.
    func testOverAllocationIsBlocked() {
        let app = XCUIApplication()
        app.launch()

        app.cells.staticTexts["Project Alpha"].tap()
        app.textFields["hoursField"].tap()
        app.textFields["hoursField"].typeText("60")
        app.buttons["saveAllocationButton"].tap()

        XCTAssertTrue(app.staticTexts["Exceeds available hours"].waitForExistence(timeout: 3))
    }

    /// [SMOKE] Project-level allocations roll up correctly into the
    /// company-wide total. Strict equality, not just "a number appears" —
    /// a silent rollup drift here is a real finance-reporting bug.
    func testProjectAllocationsRollUpToCompanyTotal() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Company Goals"].tap()

        let projectATotal = extractDollarAmount(app.staticTexts["projectAlpha_OpenOrders"].label)
        let projectBTotal = extractDollarAmount(app.staticTexts["projectBeta_OpenOrders"].label)
        let companyTotal = extractDollarAmount(app.staticTexts["companyTotal_OpenOrders"].label)

        XCTAssertEqual(companyTotal, projectATotal + projectBTotal, accuracy: 0.01)
    }

    /// [SMOKE] The company dashboard's headline open-order figure matches
    /// the example scale mentioned in requirements (~$30M) and is
    /// formatted correctly. Sanity-checks both the number and its display.
    func testCompanyOpenOrdersDisplaysExpectedScale() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Company Goals"].tap()

        let total = extractDollarAmount(app.staticTexts["companyTotal_OpenOrders"].label)

        XCTAssertTrue(app.staticTexts["companyTotal_OpenOrders"].label.hasPrefix("$"))
        XCTAssertGreaterThan(total, 0)
        // Example scale from requirements — adjust threshold to match real data
        XCTAssertGreaterThan(total, 25_000_000)
        XCTAssertLessThan(total, 35_000_000)
    }

    /// P&L view reflects allocated project costs — changing an allocation
    /// should move the corresponding P&L line, not leave it stale.
    func testPnLReflectsUpdatedAllocationCosts() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Company Goals"].tap()
        let pnlBefore = extractDollarAmount(app.staticTexts["pnl_TotalCost"].label)

        app.tabBars.buttons["Projects"].tap()
        app.cells.staticTexts["Project Alpha"].tap()
        app.textFields["hoursField"].tap()
        app.textFields["hoursField"].typeText("4")
        app.buttons["saveAllocationButton"].tap()

        app.tabBars.buttons["Company Goals"].tap()
        let pnlAfter = extractDollarAmount(app.staticTexts["pnl_TotalCost"].label)

        XCTAssertNotEqual(pnlBefore, pnlAfter)
    }

    // MARK: - Helper

    /// Strips currency formatting ("$", ",") from a label like "$30,412,000"
    /// and returns a comparable Double. Kept local to this file since it's
    /// only meaningful for financial-display assertions.
    private func extractDollarAmount(_ label: String) -> Double {
        let cleaned = label.filter { "0123456789.".contains($0) }
        return Double(cleaned) ?? -1
    }
}
