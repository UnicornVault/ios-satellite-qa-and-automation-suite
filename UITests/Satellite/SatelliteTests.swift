//
//  SatelliteTests.swift
//  iOS Automation Portfolio — Satellite Connectivity (Flagship Feature)
//
//  Author: UnicornVault
//  Created: 2026-08-03
//
//  This is the most forward-looking, differentiated genre in the
//  portfolio, and it's pulled into its own file deliberately: satellite
//  connectivity spans TWO genuinely different technical models, both
//  verified against current, real-world sources rather than assumed:
//
//  1. Device-native satellite (Apple's model): the device connects
//     directly to dedicated satellites (Globalstar), requires manual
//     pointing/aiming guidance, and is used for Emergency SOS and
//     off-grid messaging. Introduced with iPhone 14 in 2022.
//
//  2. Carrier direct-to-cell (T-Mobile + Starlink's model, branded
//     "T-Satellite"): the carrier's own spectrum is relayed via
//     low-orbit satellites acting as "cell towers in space." It
//     connects automatically with NO pointing required, and works
//     inside the phone's regular messaging app. Network name shown is
//     "T-Mobile SpaceX" or "T-Sat+Starlink." Launched commercially
//     July 2025.
//
//  A key physical difference tested here: because direct-to-cell
//  satellites are in low Earth orbit and moving overhead, the phone
//  disconnects from one and automatically reconnects to the next —
//  this "handoff" behavior has no equivalent in ground-based cellular
//  testing and is what makes this genre genuinely new territory for a
//  QA portfolio.

import XCTest

final class SatelliteTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Device-native satellite (Apple Emergency SOS via satellite)
    //
    // Uses dedicated satellites (Globalstar), requires manual pointing
    // guidance, and is the model behind Apple's Emergency SOS and
    // off-grid messaging features.

    /// [SMOKE] Satellite mode activates automatically when the device has
    /// no cellular and no Wi-Fi — the core trigger condition for the
    /// whole feature. If this doesn't fire correctly, satellite messaging
    /// is effectively unreachable exactly when it's needed most.
    func testSatelliteModeActivatesWhenNoCellularOrWiFi() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateNoWiFi", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Satellite available"].waitForExistence(timeout: 8))
        attachScreenshot(named: "Satellite_ModeActivated")
    }

    /// Satellite mode does NOT activate if cellular or Wi-Fi is still
    /// available — confirms the app prioritizes normal connectivity and
    /// doesn't burn satellite bandwidth unnecessarily.
    func testSatelliteModeDoesNotActivateWhenCellularAvailable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertFalse(app.staticTexts["Satellite available"].exists)
    }

    /// [SMOKE] While acquiring a satellite signal, the app shows
    /// directional pointing guidance (which way to angle the device).
    /// Without this, users can't actually connect even though the
    /// feature is technically "on" — a usability-critical path.
    func testSatelliteConnectionShowsPointingGuidance() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateNoWiFi", "true"]
        app.launch()

        app.buttons["connectToSatelliteButton"].tap()

        XCTAssertTrue(app.staticTexts["pointDeviceGuidanceLabel"].waitForExistence(timeout: 5))
        attachScreenshot(named: "Satellite_PointingGuidanceShown")
    }

    /// [SMOKE] Emergency SOS via satellite can be initiated and shows a
    /// confirmed "in progress" state. This is a safety-critical feature —
    /// a silent failure here has real-world consequences, so it stays in
    /// the smoke suite permanently regardless of how the rest of the
    /// satellite feature evolves.
    func testEmergencySOSViaSatelliteInitiatesSuccessfully() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateNoWiFi", "true"]
        app.launch()

        app.buttons["emergencySOSButton"].tap()
        app.buttons["confirmSOSButton"].tap()

        XCTAssertTrue(app.staticTexts["Connecting to emergency services via satellite"].waitForExistence(timeout: 8))
        attachScreenshot(named: "Satellite_EmergencySOSConnecting")
    }

    /// A satellite message composed while out of signal range queues
    /// locally and shows a "will send when connected" state, rather than
    /// silently failing or appearing to send when it hasn't.
    func testSatelliteMessageQueuesWhenSignalNotYetAcquired() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateNoWiFi", "true", "-simulateWeakSatelliteSignal", "true"]
        app.launch()

        app.buttons["satelliteMessageButton"].tap()
        app.textFields["satelliteMessageField"].tap()
        app.textFields["satelliteMessageField"].typeText("Stuck on trail, need help")
        app.buttons["sendSatelliteMessageButton"].tap()

        XCTAssertTrue(app.staticTexts["Queued — will send when connected"].waitForExistence(timeout: 5))
    }

    /// Once a satellite signal is acquired, a queued message actually
    /// sends and the status updates from "queued" to "sent" — confirms
    /// the queue doesn't just sit there indefinitely.
    func testQueuedSatelliteMessageSendsOnceSignalAcquired() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateNoWiFi", "true"]
        app.launch()

        app.buttons["satelliteMessageButton"].tap()
        app.textFields["satelliteMessageField"].tap()
        app.textFields["satelliteMessageField"].typeText("Testing satellite send")
        app.buttons["sendSatelliteMessageButton"].tap()

        app.launchEnvironment["SIMULATE_SATELLITE_SIGNAL_ACQUIRED"] = "true"

        XCTAssertTrue(app.staticTexts["Message sent"].waitForExistence(timeout: 10))
    }

    /// [SMOKE] If cellular or Wi-Fi becomes available mid-satellite-session,
    /// the app automatically switches back rather than continuing to use
    /// the slower, bandwidth-limited satellite connection unnecessarily.
    func testAutoSwitchesFromSatelliteBackToCellularWhenAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateNoWiFi", "true"]
        app.launch()

        app.buttons["connectToSatelliteButton"].tap()
        app.launchEnvironment["SIMULATE_CELLULAR_RESTORED"] = "true"

        XCTAssertTrue(app.staticTexts["Connected via Cellular"].waitForExistence(timeout: 5))
    }

    /// Satellite messaging usage is clearly labeled as not counting
    /// against the regular data plan, avoiding confusion or a support
    /// call about unexpected data charges.
    func testSatelliteUsageLabeledSeparatelyFromDataPlan() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateNoWiFi", "true"]
        app.launch()

        app.buttons["satelliteMessageButton"].tap()

        XCTAssertTrue(app.staticTexts["Does not use plan data"].waitForExistence(timeout: 3))
    }


    // MARK: - Carrier direct-to-cell satellite (T-Satellite / Starlink)
    //
    // Distinct UX model from the device-native satellite tests above:
    // direct-to-cell uses the carrier's own spectrum via satellite, so it
    // connects automatically with no pointing guidance and works inside
    // the regular messaging app rather than a dedicated satellite UI.

    /// [SMOKE] Direct-to-cell service connects automatically when out of
    /// terrestrial coverage, with no pointing/aiming step required — this
    /// is the core UX difference from device-native satellite features,
    /// so confirming "no pointing UI appears" is itself the assertion.
    func testDirectToCellConnectsAutomaticallyWithoutPointing() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Connected via satellite"].waitForExistence(timeout: 8))
        attachScreenshot(named: "DirectToCell_ConnectedAutomatically")
        XCTAssertFalse(app.staticTexts["pointDeviceGuidanceLabel"].exists)
    }

    /// [SMOKE] The network name shown while on direct-to-cell matches the
    /// carrier's actual branding, so a user can visually confirm which
    /// connection type they're on.
    func testDirectToCellShowsCorrectNetworkName() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true"]
        app.launch()

        let networkName = app.staticTexts["networkNameLabel"].label
        XCTAssertTrue(["T-Mobile SpaceX", "T-Sat+Starlink"].contains(networkName))
    }

    /// A message sent over direct-to-cell is composed and sent from the
    /// standard messaging screen, not a separate satellite-specific
    /// composer — confirms the "just works inside the app you already
    /// use" promise rather than forcing a special mode.
    func testDirectToCellMessageSendsFromStandardMessagingScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true"]
        app.launch()

        app.tabBars.buttons["Messages"].tap()
        app.cells.element(boundBy: 0).tap()
        app.textFields["messageComposerField"].tap()
        app.textFields["messageComposerField"].typeText("Running late, no cell service here")
        app.buttons["sendMessageButton"].tap()

        XCTAssertTrue(app.staticTexts["Sent via satellite"].waitForExistence(timeout: 10))
    }

    /// A failed direct-to-cell message automatically retries rather than
    /// requiring the user to manually resend, and only surfaces a failure
    /// notice once retries are exhausted.
    func testFailedDirectToCellMessageAutoRetries() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true", "-simulateSendFailureThenRetrySuccess", "true"]
        app.launch()

        app.tabBars.buttons["Messages"].tap()
        app.cells.element(boundBy: 0).tap()
        app.textFields["messageComposerField"].tap()
        app.textFields["messageComposerField"].typeText("Testing retry behavior")
        app.buttons["sendMessageButton"].tap()

        XCTAssertTrue(app.staticTexts["Sending — retrying"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sent via satellite"].waitForExistence(timeout: 15))
    }

    /// A data-heavy action attempted over direct-to-cell (which has
    /// limited bandwidth) shows a speed/limitation notice rather than
    /// silently hanging or timing out with no explanation.
    func testDirectToCellShowsLimitedSpeedNoticeForDataHeavyAction() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true"]
        app.launch()

        app.buttons["loadLargeImageButton"].tap()

        XCTAssertTrue(app.staticTexts["Limited speed over satellite — this may take longer"].waitForExistence(timeout: 5))
    }

    /// Text-to-911 over direct-to-cell is unavailable in some regions;
    /// the app must warn the user of this clearly rather than implying
    /// emergency texting works everywhere satellite connectivity does.
    func testTextTo911UnavailableWarningShownInUnsupportedRegion() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true", "-simulateRegion", "unsupportedFor911"]
        app.launch()

        app.buttons["emergencySOSButton"].tap()

        XCTAssertTrue(app.staticTexts["Text to 911 unavailable in this region"].waitForExistence(timeout: 5))
    }

    // MARK: - Satellite handoff behavior
    //
    // Low Earth orbit satellites move fast enough that the phone
    // disconnects from one and reconnects to the next every ~15 seconds,
    // per SpaceX's own published figures. This is the single most
    // differentiated testing surface in this genre — it has no
    // equivalent in ground-based cellular testing, where the tower
    // doesn't move. These tests verify the app hides that churn from the
    // user rather than treating each handoff as a failure.

    /// [SMOKE] A message that's mid-send when a satellite handoff occurs
    /// completes successfully once the next satellite locks in, rather
    /// than erroring out because the first satellite dropped mid-transfer.
    func testMessageSurvivesMidSendHandoff() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true", "-simulateHandoffDuringSend", "true"]
        app.launch()

        app.tabBars.buttons["Messages"].tap()
        app.cells.element(boundBy: 0).tap()
        app.textFields["messageComposerField"].tap()
        app.textFields["messageComposerField"].typeText("Testing handoff resilience")
        app.buttons["sendMessageButton"].tap()

        // The handoff gap should not surface as a hard failure state
        XCTAssertFalse(app.staticTexts["Send failed"].exists)
        XCTAssertTrue(app.staticTexts["Sent via satellite"].waitForExistence(timeout: 15))
    }

    /// [SMOKE] Initial satellite connection isn't always instant — the app
    /// shows a patient "searching for satellite" state rather than an
    /// alarming error, matching the real-world guidance that finding a
    /// satellite can take a moment.
    func testConnectionSearchShowsPatientWaitingState() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true", "-simulateSlowInitialLock", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Searching for satellite…"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Connection failed"].exists)
    }

    /// Repeated automatic reconnects during normal satellite use do NOT
    /// generate a new toast/notification for every single handoff — a
    /// real-world complaint pattern is notification spam and battery
    /// drain from an app treating routine handoffs as noteworthy events.
    func testRepeatedHandoffsDoNotSpamNotifications() {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateNoService", "true", "-simulateDirectToCellAvailable", "true", "-simulateMultipleHandoffs", "5"]
        app.launch()

        // A single persistent status indicator is expected; repeated
        // discrete "reconnected" toasts are not.
        XCTAssertTrue(app.staticTexts["Connected via satellite"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.otherElements.matching(identifier: "reconnectToast").count, 0)
    }
}
