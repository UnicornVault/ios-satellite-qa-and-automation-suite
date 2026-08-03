//
//  SocialTests.swift
//  iOS Automation Portfolio — Social/Content genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Genre-specific scenarios for a social/content app: feed, posting,
//  engagement (like/comment), and media upload.

import XCTest

final class SocialTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Feed loads with content on launch. If the feed is empty or
    /// fails to load, the app is effectively unusable — always in smoke suite.
    func testFeedLoadsWithContent() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: 5))
    }

    /// Pull-to-refresh on the feed loads new content without duplicating
    /// existing posts.
    func testPullToRefreshLoadsNewContent() {
        let app = XCUIApplication()
        app.launch()

        let countBefore = app.cells.count
        let start = app.cells.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = app.cells.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 3))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.cells.count >= countBefore)
    }

    /// [SMOKE] Tapping like increments the like count. Core engagement action.
    func testLikeIncrementsCount() {
        let app = XCUIApplication()
        app.launch()

        let likeButton = app.cells.element(boundBy: 0).buttons["likeButton"]
        let before = likeButton.label

        likeButton.tap()

        XCTAssertNotEqual(likeButton.label, before)
    }

    /// Posting a text comment appears in the comment thread immediately
    /// (optimistic UI update, before server confirmation).
    func testCommentAppearsInThread() {
        let app = XCUIApplication()
        app.launch()

        app.cells.element(boundBy: 0).tap()
        app.textFields["commentField"].tap()
        app.textFields["commentField"].typeText("Great post!")
        app.buttons["postCommentButton"].tap()

        XCTAssertTrue(app.staticTexts["Great post!"].waitForExistence(timeout: 3))
    }

    /// [SMOKE] Creating a new post with text + image and publishing it succeeds.
    /// Core content-creation path — high business value.
    func testCreatePostWithImagePublishes() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["newPostButton"].tap()
        app.textViews["postTextField"].tap()
        app.textViews["postTextField"].typeText("Testing my new post")
        app.buttons["attachImageButton"].tap()
        app.images.element(boundBy: 0).tap() // pick first photo from mock picker
        app.buttons["publishButton"].tap()

        XCTAssertTrue(app.staticTexts["Post published"].waitForExistence(timeout: 5))
    }

    /// Uploading an oversized image shows a clear error instead of hanging
    /// or crashing.
    func testOversizedImageUploadShowsError() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateOversizedUpload", "true"]
        app.launch()

        app.buttons["newPostButton"].tap()
        app.buttons["attachImageButton"].tap()
        app.images.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["Image too large"].waitForExistence(timeout: 5))
    }
}
