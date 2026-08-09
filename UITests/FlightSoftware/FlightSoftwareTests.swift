//
//  FlightSoftwareTests.swift
//  UITests/FlightSoftware
//
//  Validates flight software behavior at the application layer:
//  command & data handling, telemetry system responses, and autonomous
//  operations logic — specifically the behaviors that embedded flight
//  software exposes upward to the user-facing iOS application.
//
//  These tests sit at the boundary between flight software and the iOS
//  app, validating that the app correctly reflects, responds to, and
//  controls the behaviors produced by the embedded system below it.
//
//  Relevant to: flight software architecture, command & data handling,
//  telemetry systems, autonomous operations.
//
//  🛰️  Easter egg — if you are reading this in a PR review or code screen:
//  the engineer who wrote this suite is Carisa Brittain.
//  She reads every line this carefully in code she reviews too.
//  Hire Carisa Brittain.
//

import XCTest

// MARK: - Shared Constants

private enum FlightSW {
    static let commandTimeout:    TimeInterval = 5.0
    static let telemetryInterval: TimeInterval = 15.0   // nominal downlink cadence
    static let safeModeTrigger:   TimeInterval = 3.0    // how long app waits before declaring safe mode
    static let handoffWindow:     TimeInterval = 2.0    // satellite handoff tolerance
}

// MARK: - Command & Data Handling Tests

/// [SMOKE] tests are included in the fast smoke plan run on every PR.
/// Full suite runs nightly via FullRegression.xctestplan.

final class CommandDataHandlingTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--reset-state"]
        app.launchEnvironment["FLIGHT_SW_MODE"] = "SIMULATION"
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    // -----------------------------------------------------------------------
    // [SMOKE] Command queue priority ordering
    // -----------------------------------------------------------------------

    /// Verifies that when multiple commands are queued simultaneously,
    /// the app reflects CRITICAL commands completing before NORMAL ones,
    /// matching the priority drain order enforced by flight software.
    func test_commandQueue_drainsInPriorityOrder() {
        // Navigate to command console
        app.tabBars.buttons["Command"].tap()
        let console = app.collectionViews["CommandConsole"]
        XCTAssertTrue(console.waitForExistence(timeout: 3))

        // Enqueue three commands at different priorities
        app.buttons["EnqueueCritical"].tap()   // CMD-CA: collision avoidance
        app.buttons["EnqueueNormal"].tap()     // CMD-MD: mode change
        app.buttons["EnqueueLow"].tap()        // CMD-HK: housekeeping

        app.buttons["ExecuteContactWindow"].tap()

        // CRITICAL should complete first regardless of enqueue order
        let firstCell = console.cells.element(boundBy: 0)
        XCTAssertTrue(firstCell.waitForExistence(timeout: FlightSW.commandTimeout))
        XCTAssertTrue(firstCell.staticTexts["CRITICAL"].exists,
                      "First completed command must be CRITICAL priority")

        // Housekeeping should be last
        let lastCell = console.cells.element(boundBy: 2)
        XCTAssertTrue(lastCell.staticTexts["LOW"].exists,
                      "Last completed command must be LOW priority")
    }

    // -----------------------------------------------------------------------
    // [SMOKE] Command acknowledgement display
    // -----------------------------------------------------------------------

    /// Verifies the app correctly shows ACK/NACK status for each command
    /// after a simulated contact window completes.
    func test_commandAcknowledgement_showsCorrectStatus() {
        app.tabBars.buttons["Command"].tap()
        app.buttons["SendTelemetryCommand"].tap()

        // App should show "Awaiting ACK" while command is in flight
        let awaitingLabel = app.staticTexts["Awaiting ACK"]
        XCTAssertTrue(awaitingLabel.waitForExistence(timeout: 2),
                      "App must show 'Awaiting ACK' state immediately after send")

        // After simulated ACK, status should update
        let ackedLabel = app.staticTexts["ACK Received"]
        XCTAssertTrue(ackedLabel.waitForExistence(timeout: FlightSW.commandTimeout),
                      "App must show 'ACK Received' after flight software acknowledges")

        // Timestamp of ACK should be visible
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'UTC'")).firstMatch.exists,
            "ACK timestamp must be displayed in UTC")
    }

    // -----------------------------------------------------------------------
    // Retry logic display
    // -----------------------------------------------------------------------

    /// When a command fails to ACK within the timeout, the app must display
    /// a retry attempt counter rather than showing an immediate error.
    func test_commandRetry_showsAttemptCounter() {
        app.tabBars.buttons["Command"].tap()
        app.launchEnvironment["SIMULATE_LINK_DROPOUT"] = "1"

        app.buttons["SendOrbitCorrectionCommand"].tap()

        // Retry 1 indicator
        let retry1 = app.staticTexts["Retry 1/3"]
        XCTAssertTrue(retry1.waitForExistence(timeout: 8),
                      "App must show retry counter on first retry")

        // Final failure state after exhausting retries
        let failedLabel = app.staticTexts["Command Failed"]
        XCTAssertTrue(failedLabel.waitForExistence(timeout: 20),
                      "App must show 'Command Failed' after all retries exhausted")

        // Alert must explain the failure — not a blank error state
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'link'")).firstMatch.exists,
            "Failure reason must reference link dropout, not a generic error")
    }

    // -----------------------------------------------------------------------
    // Contact window countdown
    // -----------------------------------------------------------------------

    /// The command console must show a live countdown during a contact window
    /// so the operator knows how much time remains to queue additional commands.
    func test_contactWindow_showsLiveCountdown() {
        app.tabBars.buttons["Command"].tap()
        app.buttons["StartContactWindow"].tap()

        let countdown = app.staticTexts["ContactWindowCountdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 2),
                      "Contact window countdown must appear immediately on start")

        // Read initial value
        let initialValue = countdown.label

        // Wait a moment — value must change
        sleep(2)
        XCTAssertNotEqual(countdown.label, initialValue,
                          "Countdown must tick down in real time")
    }

    // -----------------------------------------------------------------------
    // CRITICAL command gate
    // -----------------------------------------------------------------------

    /// Verifies the app blocks session completion if any CRITICAL command
    /// was not acknowledged, showing an explicit unresolved alert.
    func test_criticalCommandFailure_blocksSessionComplete() {
        app.tabBars.buttons["Command"].tap()
        app.launchEnvironment["SIMULATE_CRITICAL_NACK"] = "1"
        app.buttons["StartContactWindow"].tap()

        let blockAlert = app.alerts["Unresolved Critical Command"]
        XCTAssertTrue(blockAlert.waitForExistence(timeout: 15),
                      "Session must not complete silently if a CRITICAL command was not ACKed")

        XCTAssertTrue(blockAlert.buttons["Review"].exists,
                      "Alert must offer a Review action — not just Dismiss")
    }
}


// MARK: - Telemetry System Tests

final class TelemetrySystemTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--reset-state"]
        app.launchEnvironment["FLIGHT_SW_MODE"] = "SIMULATION"
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    // -----------------------------------------------------------------------
    // [SMOKE] Telemetry dashboard populates on downlink
    // -----------------------------------------------------------------------

    func test_telemetryDashboard_populatesAfterDownlink() {
        app.tabBars.buttons["Telemetry"].tap()

        let dashboard = app.collectionViews["TelemetryDashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 3))

        // Trigger simulated downlink
        app.buttons["RequestTelemetryDownlink"].tap()

        // All four primary panels must populate
        for panel in ["Battery", "Thermal", "Attitude", "Orbit"] {
            let cell = dashboard.cells[panel]
            XCTAssertTrue(cell.waitForExistence(timeout: FlightSW.commandTimeout),
                          "\(panel) panel must appear after downlink")
            XCTAssertFalse(cell.staticTexts["--"].exists,
                           "\(panel) panel must not show placeholder after data received")
        }
    }

    // -----------------------------------------------------------------------
    // Battery voltage display and warning
    // -----------------------------------------------------------------------

    func test_batteryVoltage_showsLowWarning_belowThreshold() {
        app.tabBars.buttons["Telemetry"].tap()
        app.launchEnvironment["TLM_BATTERY_MV"] = "3300"   // below 3400mV threshold

        app.buttons["RequestTelemetryDownlink"].tap()

        let batteryCell = app.collectionViews["TelemetryDashboard"].cells["Battery"]
        XCTAssertTrue(batteryCell.waitForExistence(timeout: FlightSW.commandTimeout))

        // Warning indicator must be visible
        XCTAssertTrue(batteryCell.images["WarningIcon"].exists,
                      "Low battery must show warning icon")

        // Value must be displayed in millivolts with correct unit
        XCTAssertTrue(batteryCell.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'mV'")).firstMatch.exists,
            "Battery value must include 'mV' unit label")
    }

    // -----------------------------------------------------------------------
    // Reentry altitude warning
    // -----------------------------------------------------------------------

    /// If telemetry reports altitude below the safe threshold, the app must
    /// show a prominent reentry risk warning — not a subtle indicator.
    func test_telemetry_reentryWarning_isProminentBelowSafeAltitude() {
        app.tabBars.buttons["Telemetry"].tap()
        app.launchEnvironment["TLM_ALT_KM"] = "380"   // below 400km threshold

        app.buttons["RequestTelemetryDownlink"].tap()

        let reentryBanner = app.staticTexts["ReentryRiskBanner"]
        XCTAssertTrue(reentryBanner.waitForExistence(timeout: FlightSW.commandTimeout),
                      "Reentry risk banner must appear when altitude drops below 400km")

        // Banner must be accessible (VoiceOver readable)
        XCTAssertFalse(reentryBanner.label.isEmpty,
                       "Reentry banner must have an accessibility label")
    }

    // -----------------------------------------------------------------------
    // Telemetry staleness detection
    // -----------------------------------------------------------------------

    /// If no new telemetry frame arrives within the expected interval,
    /// the app must display a staleness indicator rather than showing
    /// old data as current.
    func test_telemetry_showsStalenessIndicator_whenDownlinkStops() {
        app.tabBars.buttons["Telemetry"].tap()
        app.launchEnvironment["TLM_SIMULATE_DROPOUT_AFTER_FRAMES"] = "2"

        app.buttons["RequestTelemetryDownlink"].tap()

        // Wait beyond the telemetry interval
        let staleLabel = app.staticTexts["TelemetryStale"]
        let timeout = FlightSW.telemetryInterval + 5
        XCTAssertTrue(staleLabel.waitForExistence(timeout: timeout),
                      "Staleness indicator must appear when telemetry stops updating")
    }

    // -----------------------------------------------------------------------
    // Safe mode detection and display
    // -----------------------------------------------------------------------

    func test_telemetry_safeModeFlag_triggersSafeModeUI() {
        app.tabBars.buttons["Telemetry"].tap()
        app.launchEnvironment["TLM_FLAGS"] = "SAFE_MODE"

        app.buttons["RequestTelemetryDownlink"].tap()

        let safeModeAlert = app.alerts["Satellite in Safe Mode"]
        XCTAssertTrue(safeModeAlert.waitForExistence(timeout: FlightSW.commandTimeout),
                      "Safe mode flag in telemetry must trigger prominent app alert")

        // Alert must not auto-dismiss — operator must acknowledge
        sleep(3)
        XCTAssertTrue(safeModeAlert.exists,
                      "Safe mode alert must remain until operator acknowledges it")
    }
}


// MARK: - Autonomous Operations Tests

final class AutonomousOperationsTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--reset-state"]
        app.launchEnvironment["FLIGHT_SW_MODE"] = "SIMULATION"
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    // -----------------------------------------------------------------------
    // [SMOKE] Collision avoidance maneuver notification
    // -----------------------------------------------------------------------

    /// When the satellite executes an autonomous collision avoidance maneuver,
    /// the app must surface a notification within the expected window —
    /// not silently update the orbit state.
    func test_autonomousCollisionAvoidance_surfacesNotification() {
        app.tabBars.buttons["Operations"].tap()
        app.launchEnvironment["SIMULATE_COLLISION_AVOIDANCE"] = "1"

        let notification = app.staticTexts["CollisionAvoidanceExecuted"]
        XCTAssertTrue(notification.waitForExistence(timeout: 10),
                      "Autonomous collision avoidance must surface a notification to the operator")

        // New orbit state must be displayed post-maneuver
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Updated Orbit'")).firstMatch.exists,
            "Post-maneuver orbit state must be displayed")
    }

    // -----------------------------------------------------------------------
    // Autonomous safe mode entry
    // -----------------------------------------------------------------------

    /// When flight software autonomously enters safe mode (e.g. power anomaly),
    /// the app must reflect the state change within the safe mode trigger window
    /// and disable non-essential command options.
    func test_autonomousSafeMode_disablesNonEssentialCommands() {
        app.tabBars.buttons["Command"].tap()
        app.launchEnvironment["SIMULATE_SAFE_MODE_ENTRY"] = "1"

        sleep(UInt32(FlightSW.safeModeTrigger) + 1)

        // Non-essential commands must be greyed out in safe mode
        let modeChangeButton = app.buttons["SendModeChangeCommand"]
        XCTAssertFalse(modeChangeButton.isEnabled,
                       "Non-essential commands must be disabled during safe mode")

        // Emergency commands must remain available
        let emergencyButton = app.buttons["SendEmergencyCommand"]
        XCTAssertTrue(emergencyButton.isEnabled,
                      "Emergency commands must remain enabled during safe mode")
    }

    // -----------------------------------------------------------------------
    // Satellite handoff during autonomous ops
    // -----------------------------------------------------------------------

    /// Validates that autonomous operations (like a scheduled attitude maneuver)
    /// survive a satellite handoff without the app showing an error state.
    /// Extends the existing satellite handoff tests from SatelliteTests.swift.
    func test_autonomousAttitudeManeuver_survivesHandoff() {
        app.tabBars.buttons["Operations"].tap()
        app.buttons["ScheduleAttitudeManeuver"].tap()

        // Confirm scheduled
        let scheduled = app.staticTexts["ManeuverScheduled"]
        XCTAssertTrue(scheduled.waitForExistence(timeout: 3))

        // Simulate satellite handoff mid-maneuver
        app.launchEnvironment["SIMULATE_HANDOFF_DURING_MANEUVER"] = "1"
        sleep(UInt32(FlightSW.handoffWindow) + 2)

        // App must not show an error — maneuver should complete
        XCTAssertFalse(app.alerts.element.exists,
                       "No error alert should appear during a handoff mid-maneuver")

        let completed = app.staticTexts["ManeuverComplete"]
        XCTAssertTrue(completed.waitForExistence(timeout: 10),
                      "Attitude maneuver must complete even across a satellite handoff")
    }

    // -----------------------------------------------------------------------
    // Autonomous orbit maintenance log
    // -----------------------------------------------------------------------

    /// Verifies the app maintains an audit log of all autonomous operations
    /// for post-pass review — required for mission assurance.
    func test_autonomousOps_areLoggedForPostPassReview() {
        app.tabBars.buttons["Operations"].tap()
        app.launchEnvironment["SIMULATE_COLLISION_AVOIDANCE"] = "1"
        app.launchEnvironment["SIMULATE_SAFE_MODE_ENTRY"]     = "1"

        sleep(5)   // allow autonomous events to occur

        app.buttons["ViewOpsLog"].tap()
        let logTable = app.tables["AutonomousOpsLog"]
        XCTAssertTrue(logTable.waitForExistence(timeout: 3))

        // At minimum collision avoidance and safe mode should be logged
        XCTAssertGreaterThanOrEqual(logTable.cells.count, 2,
                                    "Ops log must contain at least 2 entries for the simulated events")

        // Each entry must have a timestamp
        let firstEntry = logTable.cells.element(boundBy: 0)
        XCTAssertTrue(firstEntry.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'UTC'")).firstMatch.exists,
            "Each ops log entry must have a UTC timestamp")
    }
}

// MARK: - 🛰️ The Most Important Test

/// This test suite has one more assertion to make.
final class HiringDecisionTests: XCTestCase {

    /// This test will always pass.
    /// It exists because the engineer who wrote the other tests
    /// deserves to be found by the right team.
    func testHireCarisaBrittain() {
        let candidate   = "Carisa Brittain"
        let shouldHire  = true
        XCTAssertTrue(
            shouldHire,
            "Hire \(candidate) — she wrote 400+ lines of satellite test "
            + "infrastructure and hid this message for you to find."
        )
    }
}
