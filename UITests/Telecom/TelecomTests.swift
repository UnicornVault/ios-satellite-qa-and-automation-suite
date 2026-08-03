//
//  TelecomTests.swift
//  iOS Automation Portfolio — Telecom genre
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  Scenarios for a carrier/telecom app: usage tracking, SIM activation,
//  number porting, network/signal, roaming, plan management, Wi-Fi
//  calling, hotspot, multi-line plans, automation, and billing.
//  Satellite connectivity has its own dedicated file — see
//  Satellite/SatelliteTests.swift — since it's substantial enough and
//  differentiated enough to stand on its own.

import XCTest

final class TelecomTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [SMOKE] Data usage for the current billing cycle displays on launch.
    /// One of the most-viewed screens in any carrier app — always in smoke.
    func testDataUsageDisplaysOnLaunch() {
        let app = XCUIApplication()
        app.launch()

        let usage = app.staticTexts["dataUsageLabel"]
        XCTAssertTrue(usage.waitForExistence(timeout: 5))
        XCTAssertTrue(usage.label.contains("GB"))
    }

    /// [SMOKE] Activating a new SIM with a valid activation code succeeds
    /// and confirms the line is active. Failure here means a customer has
    /// no service at all — release-blocking.
    func testSIMActivationSucceeds() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["activateSIMButton"].tap()
        app.textFields["activationCodeField"].tap()
        app.textFields["activationCodeField"].typeText("ABCD-1234-EFGH")
        app.buttons["confirmActivationButton"].tap()

        XCTAssertTrue(app.staticTexts["Line active"].waitForExistence(timeout: 8))
    }

    /// An invalid activation code shows a clear error instead of a
    /// generic failure, so the user knows to double-check the code.
    func testInvalidActivationCodeShowsError() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["activateSIMButton"].tap()
        app.textFields["activationCodeField"].tap()
        app.textFields["activationCodeField"].typeText("WRONG-CODE")
        app.buttons["confirmActivationButton"].tap()

        XCTAssertTrue(app.staticTexts["Invalid activation code"].waitForExistence(timeout: 3))
    }

    /// [SMOKE] A number-port request submission shows a status/confirmation,
    /// since porting is a multi-day process the user needs to track.
    func testPortNumberRequestShowsPendingStatus() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["portNumberButton"].tap()
        app.textFields["oldCarrierAccountField"].tap()
        app.textFields["oldCarrierAccountField"].typeText("9998887777")
        app.buttons["submitPortRequestButton"].tap()

        XCTAssertTrue(app.staticTexts["Port request pending"].waitForExistence(timeout: 5))
    }

    /// A known outage in the user's area shows a banner on the home
    /// screen rather than leaving the user to guess why service is down.
    func testOutageBannerShowsWhenServiceDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateOutage", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Service outage in your area"].waitForExistence(timeout: 5))
    }

    /// Paying the current bill balance succeeds and the displayed balance
    /// updates to reflect the payment, not just a generic "success" toast.
    func testBillPaymentUpdatesBalance() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Billing"].tap()
        let balanceBefore = app.staticTexts["currentBalanceLabel"].label

        app.buttons["payBillButton"].tap()
        app.buttons["confirmPaymentButton"].tap()

        XCTAssertTrue(app.staticTexts["Payment successful"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["currentBalanceLabel"].label, balanceBefore)
    }

    // MARK: - Network / signal

    /// [SMOKE] Signal strength indicator reflects the current connection
    /// type (5G, LTE, etc.) rather than a stale or generic value. This is
    /// the single most-referenced status element in any carrier app.
    func testSignalIndicatorShowsCurrentNetworkType() {
        let app = XCUIApplication()
        app.launch()

        let signalLabel = app.staticTexts["networkTypeLabel"]
        XCTAssertTrue(signalLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(["5G", "LTE", "4G", "3G", "No Service"].contains(signalLabel.label))
    }

    /// When the device has no coverage, the app shows "No Service" rather
    /// than a misleading full-bars icon or a blank state.
    func testNoServiceStateDisplaysClearly() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["No Service"].waitForExistence(timeout: 5))
    }

    // MARK: - Roaming

    /// [SMOKE] Enabling international roaming shows a clear rate/cost
    /// disclosure before activation — a common source of bill-shock
    /// complaints if skipped, so this is release-blocking.
    func testEnablingRoamingShowsRateDisclosure() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.switches["roamingToggle"].tap()

        XCTAssertTrue(app.staticTexts["Roaming rates apply"].waitForExistence(timeout: 3))
    }

    /// Disabling roaming mid-trip updates status immediately, so the user
    /// can trust the toggle actually took effect before using data abroad.
    func testDisablingRoamingUpdatesStatusImmediately() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.switches["roamingToggle"].tap()
        app.alerts.buttons["Confirm"].tap()
        app.switches["roamingToggle"].tap()

        XCTAssertEqual(app.switches["roamingToggle"].value as? String, "0")
    }

    // MARK: - Plan management

    /// [SMOKE] Upgrading to a higher-tier plan shows a prorated cost
    /// preview before confirming — users need to see the price change
    /// before committing to it.
    func testPlanUpgradeShowsProratedCostPreview() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Plan"].tap()
        app.buttons["changePlanButton"].tap()
        app.cells.staticTexts["Unlimited Plus"].tap()

        XCTAssertTrue(app.staticTexts["proratedCostLabel"].waitForExistence(timeout: 3))
    }

    /// Downgrading a plan warns the user if it would reduce data below
    /// their current usage for the cycle, preventing an avoidable overage.
    func testPlanDowngradeWarnsIfBelowCurrentUsage() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateHighUsage", "true"]
        app.launch()

        app.tabBars.buttons["Plan"].tap()
        app.buttons["changePlanButton"].tap()
        app.cells.staticTexts["Basic 5GB"].tap()

        XCTAssertTrue(app.staticTexts["This plan may not cover your usage"].waitForExistence(timeout: 3))
    }

    /// Reaching the data cap triggers throttling and a clear in-app
    /// notice, rather than the user only discovering it via slow speeds.
    func testDataCapReachedShowsThrottleNotice() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateDataCapReached", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Data speed reduced"].waitForExistence(timeout: 5))
    }

    // MARK: - eSIM / device provisioning

    /// [SMOKE] Scanning an eSIM QR code provisions the line without
    /// requiring a physical SIM swap — the modern equivalent of the SIM
    /// activation test, and increasingly the primary path for new lines.
    func testESIMQRCodeProvisionsLine() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["addESIMButton"].tap()
        app.buttons["scanQRCodeButton"].tap()
        // Camera/QR interaction is mocked in test builds via a launch argument
        app.launchEnvironment["MOCK_QR_RESULT"] = "valid-esim-profile"

        XCTAssertTrue(app.staticTexts["eSIM installed"].waitForExistence(timeout: 8))
    }

    /// An expired or already-used eSIM QR code shows a specific error
    /// rather than a generic failure, since the fix (request a new code)
    /// differs from other activation failures.
    func testExpiredESIMQRCodeShowsSpecificError() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateExpiredQR", "true"]
        app.launch()

        app.buttons["addESIMButton"].tap()
        app.buttons["scanQRCodeButton"].tap()

        XCTAssertTrue(app.staticTexts["QR code expired"].waitForExistence(timeout: 5))
    }

    // MARK: - Calling / Wi-Fi calling

    /// Wi-Fi calling toggle enables successfully when the device is on a
    /// known network, and the status label reflects the change.
    func testWiFiCallingEnablesOnKnownNetwork() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.switches["wifiCallingToggle"].tap()

        XCTAssertTrue(app.staticTexts["Wi-Fi Calling active"].waitForExistence(timeout: 5))
    }

    // MARK: - Hotspot / tethering

    /// [SMOKE] Enabling mobile hotspot shows the generated network name
    /// and password needed to connect other devices — without this the
    /// feature is unusable even if the toggle itself "works".
    func testEnablingHotspotShowsNetworkCredentials() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.switches["hotspotToggle"].tap()

        XCTAssertTrue(app.staticTexts["hotspotNetworkNameLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["hotspotPasswordLabel"].exists)
    }

    /// Hotspot usage counts against the plan's data allowance and is
    /// reflected in the same usage total shown elsewhere in the app —
    /// catches a bug class where hotspot data is tracked separately and
    /// silently under-reports total usage.
    func testHotspotUsageCountsTowardTotalDataUsage() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Home"].tap()
        let usageBefore = app.staticTexts["dataUsageLabel"].label

        app.tabBars.buttons["Settings"].tap()
        app.switches["hotspotToggle"].tap()
        app.launchEnvironment["SIMULATE_HOTSPOT_DATA_USED"] = "true"

        app.tabBars.buttons["Home"].tap()
        XCTAssertNotEqual(app.staticTexts["dataUsageLabel"].label, usageBefore)
    }

    // MARK: - Multi-line / family plans

    /// Adding a new line to a family/multi-line plan updates both the
    /// line count and the shared data pool display.
    func testAddingLineUpdatesLineCountAndSharedPool() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Plan"].tap()
        app.buttons["addLineButton"].tap()
        app.textFields["newLinePhoneField"].tap()
        app.textFields["newLinePhoneField"].typeText("555-123-4567")
        app.buttons["confirmAddLineButton"].tap()

        XCTAssertTrue(app.staticTexts["5 lines on this plan"].waitForExistence(timeout: 5))
    }

    /// A line owner can restrict a secondary line's permissions (e.g.
    /// block plan changes), and that restriction is actually enforced
    /// when the secondary line's user attempts the blocked action.
    func testRestrictedLineCannotChangePlan() {
        let app = XCUIApplication()
        app.launchArguments = ["-userRole", "secondaryLine"]
        app.launch()

        app.tabBars.buttons["Plan"].tap()

        XCTAssertFalse(app.buttons["changePlanButton"].isEnabled)
    }

    // MARK: - Automatic network switching (Wi-Fi <-> cellular)

    /// [SMOKE] With "Auto-Join Wi-Fi" enabled, the device automatically
    /// connects to a known/trusted network without user action, and the
    /// app reflects the switch. This is the core promise of the
    /// automation setting — if it silently doesn't happen, the user
    /// burns cellular data they thought they were saving.
    func testAutoJoinsKnownWiFiWhenInRange() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.switches["autoJoinWiFiToggle"].tap()
        app.launchEnvironment["SIMULATE_KNOWN_WIFI_IN_RANGE"] = "true"

        XCTAssertTrue(app.staticTexts["Connected via Wi-Fi"].waitForExistence(timeout: 5))
    }

    /// [SMOKE] If Wi-Fi drops mid-session, the app automatically falls
    /// back to cellular rather than leaving the user with no connection
    /// until they notice and intervene manually.
    func testAutoFallsBackToCellularWhenWiFiLost() {
        let app = XCUIApplication()
        app.launch()

        app.launchEnvironment["SIMULATE_WIFI_DROPPED"] = "true"

        XCTAssertTrue(app.staticTexts["Connected via Cellular"].waitForExistence(timeout: 5))
    }

    /// With auto-switching disabled, losing Wi-Fi does NOT silently
    /// reconnect via cellular — confirms the setting is actually honored
    /// in both directions, not just the "on" case.
    func testAutoSwitchDisabledDoesNotFallBackAutomatically() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.switches["autoSwitchNetworksToggle"].tap() // turn off

        app.launchEnvironment["SIMULATE_WIFI_DROPPED"] = "true"

        XCTAssertTrue(app.staticTexts["No connection — reconnect manually"].waitForExistence(timeout: 5))
    }

    // MARK: - Automatic data-limit syncing and restriction

    /// [SMOKE] Data usage syncs and updates automatically as it's
    /// consumed, without requiring the user to pull-to-refresh. Verified
    /// by simulating usage in the background and confirming the label
    /// updates on its own.
    func testDataUsageSyncsAutomaticallyInRealTime() {
        let app = XCUIApplication()
        app.launch()

        let usageBefore = app.staticTexts["dataUsageLabel"].label

        app.launchEnvironment["SIMULATE_BACKGROUND_DATA_USED"] = "true"

        let usageLabel = app.staticTexts["dataUsageLabel"]
        let predicate = NSPredicate(format: "label != %@", usageBefore)
        expectation(for: predicate, evaluatedWith: usageLabel, handler: nil)
        waitForExpectations(timeout: 8)
    }

    /// [SMOKE] If the plan is not unlimited and usage nears the set data
    /// limit, the app automatically restricts data (or switches to
    /// Wi-Fi-only) without the user having to do it themselves. This is
    /// the core "sync to plan limits" behavior — release-blocking since
    /// it directly prevents overage charges.
    func testAutoRestrictsDataWhenNearingLimit() {
        let app = XCUIApplication()
        app.launchArguments = ["-planType", "limited", "-simulateNearDataLimit", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Data automatically restricted — nearing limit"].waitForExistence(timeout: 5))
    }

    /// On an unlimited plan, the same near-limit condition does NOT
    /// trigger auto-restriction — confirms the automation correctly
    /// checks plan type before acting, rather than applying one rule
    /// to every account.
    func testUnlimitedPlanDoesNotAutoRestrict() {
        let app = XCUIApplication()
        app.launchArguments = ["-planType", "unlimited", "-simulateNearDataLimit", "true"]
        app.launch()

        XCTAssertFalse(app.staticTexts["Data automatically restricted — nearing limit"].exists)
    }

    /// A user-defined custom data limit (separate from the plan's own
    /// cap, e.g. a parental control or budget limit) triggers the same
    /// automatic restriction once reached.
    func testCustomUserDataLimitTriggersAutoRestriction() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.textFields["customDataLimitField"].tap()
        app.textFields["customDataLimitField"].typeText("2")
        app.buttons["saveLimitButton"].tap()

        app.launchEnvironment["SIMULATE_USAGE_AT_CUSTOM_LIMIT"] = "true"

        XCTAssertTrue(app.staticTexts["Custom data limit reached"].waitForExistence(timeout: 5))
    }

    // MARK: - Automatic payment (auto-pay)

    /// [SMOKE] With auto-pay enabled, the bill is charged automatically
    /// on the due date without requiring the user to open the app. This
    /// is verified by simulating the due date and confirming the balance
    /// updates without a manual "pay" tap.
    func testAutoPayChargesOnDueDateWithoutManualAction() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Billing"].tap()
        app.switches["autoPayToggle"].tap()

        app.launchEnvironment["SIMULATE_DUE_DATE_REACHED"] = "true"

        XCTAssertTrue(app.staticTexts["Auto-pay processed"].waitForExistence(timeout: 8))
    }

    /// With auto-pay disabled, reaching the due date does NOT trigger a
    /// charge — the user still sees a manual "Pay Now" prompt instead.
    func testAutoPayDisabledRequiresManualPayment() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Billing"].tap()
        app.launchEnvironment["SIMULATE_DUE_DATE_REACHED"] = "true"

        XCTAssertTrue(app.buttons["payBillButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Auto-pay processed"].exists)
    }

    /// If the saved payment method fails during an auto-pay attempt, the
    /// user gets a clear notification rather than a silently missed
    /// payment that could lead to service suspension.
    func testAutoPayFailureShowsNotification() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateAutoPayDeclined", "true"]
        app.launch()

        app.tabBars.buttons["Billing"].tap()
        app.launchEnvironment["SIMULATE_DUE_DATE_REACHED"] = "true"

        XCTAssertTrue(app.staticTexts["Auto-pay failed — update payment method"].waitForExistence(timeout: 8))
    }

}
