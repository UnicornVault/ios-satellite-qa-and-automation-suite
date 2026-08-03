//
//  ProductivityTests.swift
//  iOS Automation Portfolio — Productivity/Utility genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Genre-specific scenarios for a productivity/utility app (notes, tasks,
//  offline-first tools): local persistence, offline editing, and sync
//  once connectivity returns.

import XCTest

final class ProductivityTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Creating a new item (note/task) and reopening the app shows
    /// it persisted locally. Core data-integrity check — if this fails,
    /// users lose their work.
    func testCreatedItemPersistsAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["newItemButton"].tap()
        app.textViews["itemTextField"].tap()
        app.textViews["itemTextField"].typeText("Buy groceries")
        app.buttons["saveButton"].tap()

        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    }

    /// Editing an item while offline saves the change locally without
    /// requiring network connectivity.
    func testEditWhileOfflineSavesLocally() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateOffline", "true"]
        app.launch()

        app.cells.element(boundBy: 0).tap()
        app.textViews["itemTextField"].tap()
        app.textViews["itemTextField"].typeText(" - updated")
        app.buttons["saveButton"].tap()

        XCTAssertTrue(app.staticTexts["Saved locally"].waitForExistence(timeout: 3))
    }

    /// [SMOKE] Changes made offline sync automatically once connectivity
    /// returns. This is the core promise of an "offline-first" app — if
    /// sync silently fails, users lose trust in the product entirely.
    func testOfflineChangesSyncWhenReconnected() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateOffline", "true"]
        app.launch()

        app.buttons["newItemButton"].tap()
        app.textViews["itemTextField"].tap()
        app.textViews["itemTextField"].typeText("Created offline")
        app.buttons["saveButton"].tap()

        // Simulate reconnection via a debug menu / launch environment toggle
        app.launchEnvironment["SIMULATE_RECONNECT"] = "true"
        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Synced"].waitForExistence(timeout: 8))
    }

    /// Deleting an item removes it from the list immediately and it does
    /// not reappear after a relaunch (no "ghost" data from a stale cache).
    func testDeletedItemDoesNotReappearAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()

        let itemToDelete = app.cells.element(boundBy: 0)
        itemToDelete.swipeLeft()
        app.buttons["deleteButton"].tap()

        app.terminate()
        app.launch()

        XCTAssertFalse(app.staticTexts["Buy groceries"].exists)
    }

    /// A sync conflict (item edited on two devices) surfaces a clear
    /// resolution prompt rather than silently picking a winner.
    func testSyncConflictShowsResolutionPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateSyncConflict", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Conflict detected"].waitForExistence(timeout: 5))
    }
}
