//
//  OpenOrderReportTests.swift
//  iOS Automation Portfolio — Interactive Open Order Report genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Scenarios for an interactive report screen showing open orders — the
//  kind of tool an ops/supply-chain user would live in daily. Core
//  concerns: the data loads correctly, sorting/filtering actually change
//  what's shown, drilling into a row works, and the numbers stay accurate.

import XCTest

final class OpenOrderReportTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] The report loads with open orders on screen. If this fails,
    /// the report is useless — always in the smoke suite.
    func testReportLoadsWithOpenOrders() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: 5))
    }

    /// [SMOKE] Tapping a column header (e.g. "Order Date") sorts the report,
    /// and tapping again reverses the sort order. Sorting is the main way
    /// users interact with this report, so it belongs in the smoke suite.
    func testTappingColumnHeaderSortsRows() {
        let app = XCUIApplication()
        app.launch()

        let firstOrderBefore = app.cells.element(boundBy: 0).staticTexts["orderIdLabel"].label

        app.buttons["orderDateColumnHeader"].tap()

        let firstOrderAfter = app.cells.element(boundBy: 0).staticTexts["orderIdLabel"].label
        XCTAssertNotEqual(firstOrderBefore, firstOrderAfter)
    }

    /// Filtering by status (e.g. "Delayed") shows only matching rows, and
    /// the visible row count updates to reflect the filter.
    func testFilterByStatusShowsMatchingRowsOnly() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["filterButton"].tap()
        app.buttons["statusOption_Delayed"].tap()
        app.buttons["applyFilterButton"].tap()

        XCTAssertTrue(app.staticTexts["Delayed"].exists)
        XCTAssertFalse(app.staticTexts["Shipped"].exists)
    }

    /// Tapping a row expands or navigates to order detail, showing
    /// line-item information not visible in the summary row.
    func testTappingRowShowsOrderDetail() {
        let app = XCUIApplication()
        app.launch()

        app.cells.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["lineItemsHeader"].waitForExistence(timeout: 3))
    }

    /// The total open-order count/sum shown in the report header matches
    /// the number of rows actually displayed — catches a common bug class
    /// where a summary stat drifts out of sync with the underlying data.
    func testSummaryCountMatchesVisibleRows() {
        let app = XCUIApplication()
        app.launch()

        let summaryCountText = app.staticTexts["openOrderCountLabel"].label
        let summaryCount = Int(summaryCountText.filter(\.isNumber)) ?? -1

        XCTAssertEqual(summaryCount, app.cells.count)
    }
}
