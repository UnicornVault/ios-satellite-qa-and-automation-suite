//
//  EcommerceTests.swift
//  iOS Automation Portfolio — E-commerce genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Genre-specific scenarios for a shopping app: browse -> cart -> checkout -> payment.
//  Assumes accessibility identifiers like "addToCartButton", "cartBadge", etc.
//  exist on the product/cart/checkout screens.

import XCTest

final class EcommerceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Adding an item to the cart updates the cart badge count.
    /// Critical path — broken cart badge is a release-blocking bug.
    func testAddToCartUpdatesBadgeCount() {
        let app = XCUIApplication()
        app.launch()

        app.cells.element(boundBy: 0).tap()
        app.buttons["addToCartButton"].tap()

        XCTAssertEqual(app.staticTexts["cartBadge"].label, "1")
    }

    /// Removing an item from the cart updates the total price shown at checkout.
    func testRemoveItemUpdatesCartTotal() {
        let app = XCUIApplication()
        app.launch()

        app.cells.element(boundBy: 0).tap()
        app.buttons["addToCartButton"].tap()
        app.tabBars.buttons["Cart"].tap()

        let totalBefore = app.staticTexts["cartTotal"].label

        app.buttons["removeItemButton"].tap()

        XCTAssertNotEqual(app.staticTexts["cartTotal"].label, totalBefore)
    }

    /// [SMOKE] Applying a valid promo code reduces the order total.
    /// Discount logic errors directly affect revenue — high business risk.
    func testValidPromoCodeAppliesDiscount() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Cart"].tap()

        app.textFields["promoCodeField"].tap()
        app.textFields["promoCodeField"].typeText("SAVE10")
        app.buttons["applyPromoButton"].tap()

        XCTAssertTrue(app.staticTexts["discountApplied"].waitForExistence(timeout: 3))
    }

    /// Invalid promo code shows an error instead of silently failing.
    func testInvalidPromoCodeShowsError() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Cart"].tap()

        app.textFields["promoCodeField"].tap()
        app.textFields["promoCodeField"].typeText("FAKE999")
        app.buttons["applyPromoButton"].tap()

        XCTAssertTrue(app.staticTexts["Invalid promo code"].waitForExistence(timeout: 3))
    }

    /// [SMOKE] Checkout with a saved payment method completes successfully.
    /// The core revenue-generating flow of the app — always in the smoke suite.
    func testCheckoutWithSavedPaymentSucceeds() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Cart"].tap()
        app.buttons["checkoutButton"].tap()
        app.buttons["useSavedPaymentButton"].tap()
        app.buttons["placeOrderButton"].tap()

        XCTAssertTrue(app.staticTexts["Order confirmed"].waitForExistence(timeout: 8))
    }

    /// Declined payment shows a clear error and keeps the cart intact
    /// (user shouldn't lose their cart contents on a failed charge).
    func testDeclinedPaymentKeepsCartIntact() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateDeclinedPayment", "true"]
        app.launch()
        app.tabBars.buttons["Cart"].tap()
        app.buttons["checkoutButton"].tap()
        app.buttons["placeOrderButton"].tap()

        XCTAssertTrue(app.staticTexts["Payment declined"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Cart"].tap()
        XCTAssertTrue(app.cells.count > 0)
    }
}
