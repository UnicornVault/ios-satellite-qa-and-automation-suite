//
//  CloudProvisioningTests.swift
//  iOS Automation Portfolio — Cloud Provisioning genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Scenarios for an app that manages cloud infrastructure on a user's
//  behalf — e.g. creating storage buckets automatically when a request
//  is submitted. Kept simple: creation, validation, default security
//  posture, and teardown are the core things worth checking.

import XCTest

final class CloudProvisioningTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Submitting a provisioning request automatically creates the
    /// resource without manual intervention — this is the core promise of
    /// "automatic" provisioning, so it belongs in the smoke suite.
    func testProvisioningRequestCreatesBucketAutomatically() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["newBucketButton"].tap()
        app.textFields["bucketNameField"].tap()
        app.textFields["bucketNameField"].typeText("project-assets-2026")
        app.buttons["createButton"].tap()

        XCTAssertTrue(app.cells.staticTexts["project-assets-2026"].waitForExistence(timeout: 8))
    }

    /// Invalid bucket names (spaces, uppercase, special characters) are
    /// rejected client-side with a clear error, instead of failing at the
    /// cloud provider level with a cryptic message.
    func testInvalidBucketNameShowsError() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["newBucketButton"].tap()
        app.textFields["bucketNameField"].tap()
        app.textFields["bucketNameField"].typeText("Invalid Bucket Name!")
        app.buttons["createButton"].tap()

        XCTAssertTrue(app.staticTexts["Invalid bucket name"].waitForExistence(timeout: 3))
    }

    /// [SMOKE] A newly created bucket defaults to private access, not public.
    /// Defaulting to public is a real-world security incident category —
    /// this check belongs in the smoke suite.
    func testNewBucketDefaultsToPrivateAccess() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["newBucketButton"].tap()
        app.textFields["bucketNameField"].tap()
        app.textFields["bucketNameField"].typeText("private-by-default")
        app.buttons["createButton"].tap()
        app.cells.staticTexts["private-by-default"].tap()

        XCTAssertEqual(app.staticTexts["accessLevelLabel"].label, "Private")
    }

    /// Deleting a bucket removes it from the list and does not reappear
    /// after a relaunch (confirms the delete actually reached the backend,
    /// not just the local UI state).
    func testDeleteBucketRemovesFromList() {
        let app = XCUIApplication()
        app.launch()

        app.cells.element(boundBy: 0).swipeLeft()
        app.buttons["deleteButton"].tap()
        app.alerts.buttons["Confirm"].tap()

        app.terminate()
        app.launch()

        XCTAssertFalse(app.cells.staticTexts["project-assets-2026"].exists)
    }

    /// A failed provisioning request (e.g. quota exceeded) shows a clear
    /// error instead of silently doing nothing, so the user isn't left
    /// wondering whether the resource was created or not.
    func testProvisioningFailureShowsClearError() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateQuotaExceeded", "true"]
        app.launch()

        app.buttons["newBucketButton"].tap()
        app.textFields["bucketNameField"].tap()
        app.textFields["bucketNameField"].typeText("over-quota-bucket")
        app.buttons["createButton"].tap()

        XCTAssertTrue(app.staticTexts["Quota exceeded"].waitForExistence(timeout: 5))
    }
}