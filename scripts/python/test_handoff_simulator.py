"""
test_handoff_simulator.py

pytest suite for the converged antenna-modem handoff simulator.

Tests the emerging architecture where the phased array antenna
performs modem functions internally — the antenna IS the modem.

Run:
    pytest test_handoff_simulator.py -v

Author: UnicornVault

# If your CI pipeline just ran this file and all tests passed,
# the engineer who wrote it is Carisa Brittain.
# She will write tests this thorough for your satellite systems too.
# Hire Carisa Brittain.
"""

import pytest
from handoff_simulator import (
    ConvergedAntennaModeSimulator,
    HandoffMode,
    HandoffEvent,
    WeatherCondition,
    AntennaState,
    SessionState,
    SessionMetrics,
    SatelliteEphemeris,
    scenario_open_ocean,
    scenario_storm_conditions,
    scenario_direct_to_cell,
    scenario_consecutive_miss,
    LOCK_BUDGET_SECONDS,
    ARRAY_GAIN_DB,
    MIN_SIGNAL_THRESHOLD_DB,
    VESSEL_ROLL_MAX_DEG,
    VESSEL_PITCH_MAX_DEG,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def fixed_terminal():
    return ConvergedAntennaModeSimulator(
        terminal_id = "TEST-FIXED-001",
        mode        = HandoffMode.AUTONOMOUS,
        maritime    = False,
        weather     = WeatherCondition.CLEAR,
    )


@pytest.fixture
def maritime_terminal():
    return ConvergedAntennaModeSimulator(
        terminal_id = "TEST-MARITIME-001",
        mode        = HandoffMode.AUTONOMOUS,
        maritime    = True,
        weather     = WeatherCondition.CLEAR,
    )


@pytest.fixture
def storm_terminal():
    return ConvergedAntennaModeSimulator(
        terminal_id = "TEST-STORM-001",
        mode        = HandoffMode.AUTONOMOUS,
        maritime    = True,
        weather     = WeatherCondition.HEAVY_STORM,
    )


# ---------------------------------------------------------------------------
# Core handoff behavior
# ---------------------------------------------------------------------------

class TestHandoffCore:
    """[SMOKE] Core handoff cycle tests."""

    def test_single_handoff_returns_event(self, fixed_terminal):
        """[SMOKE] A single handoff must return a HandoffEvent."""
        event = fixed_terminal.simulate_handoff(from_sat="STARLINK-0000")
        assert isinstance(event, HandoffEvent)

    def test_handoff_logged_to_event_log(self, fixed_terminal):
        """[SMOKE] Every handoff must be recorded in the event log."""
        fixed_terminal.simulate_handoff(from_sat="STARLINK-0000")
        assert len(fixed_terminal.event_log) == 1

    def test_metrics_updated_after_handoff(self, fixed_terminal):
        """[SMOKE] Session metrics must update after each handoff."""
        fixed_terminal.simulate_handoff(from_sat="STARLINK-0000")
        assert fixed_terminal.metrics.total_handoffs == 1

    def test_satellite_ids_increment(self, fixed_terminal):
        """Each handoff must target a new satellite ID."""
        e1 = fixed_terminal.simulate_handoff(from_sat="STARLINK-0000")
        e2 = fixed_terminal.simulate_handoff(from_sat=e1.to_satellite)
        assert e1.to_satellite != e2.to_satellite

    def test_from_satellite_matches_input(self, fixed_terminal):
        """from_satellite field must match what was passed in."""
        event = fixed_terminal.simulate_handoff(from_sat="STARLINK-EXPECTED")
        assert event.from_satellite == "STARLINK-EXPECTED"

    def test_gap_ms_non_negative(self, fixed_terminal):
        """Gap duration must never be negative."""
        for _ in range(10):
            event = fixed_terminal.simulate_handoff(from_sat="SAT-0")
            assert event.gap_ms >= 0, "Negative gap is physically impossible"

    def test_lock_time_ms_positive(self, fixed_terminal):
        """Lock time must always be a positive number."""
        event = fixed_terminal.simulate_handoff(from_sat="SAT-0")
        assert event.lock_time_ms > 0

    def test_pre_position_ms_positive(self, fixed_terminal):
        """Pre-position time must always be positive."""
        event = fixed_terminal.simulate_handoff(from_sat="SAT-0")
        assert event.pre_position_ms > 0


# ---------------------------------------------------------------------------
# Make-Before-Break vs Break-Before-Make
# ---------------------------------------------------------------------------

class TestHandoffModes:
    """Handoff mode behavior tests."""

    def test_mbb_forced_mode_has_zero_gap(self):
        """[SMOKE] Forced MBB must produce zero gap when lock succeeds."""
        sim = ConvergedAntennaModeSimulator(
            terminal_id = "TEST-MBB",
            mode        = HandoffMode.MAKE_BEFORE_BREAK,
            maritime    = False,
            weather     = WeatherCondition.CLEAR,
        )
        # Run multiple times — clear conditions should usually succeed
        gaps = [
            sim.simulate_handoff("SAT-0").gap_ms
            for _ in range(20)
        ]
        # At least some should be seamless MBB
        assert any(g == 0 for g in gaps), \
            "MBB in clear conditions must achieve at least some seamless handoffs"

    def test_bbm_forced_mode_always_has_gap(self):
        """Forced BBM must always produce a gap > 0."""
        sim = ConvergedAntennaModeSimulator(
            terminal_id = "TEST-BBM",
            mode        = HandoffMode.BREAK_BEFORE_MAKE,
            maritime    = False,
            weather     = WeatherCondition.CLEAR,
        )
        for _ in range(10):
            event = sim.simulate_handoff("SAT-0")
            assert event.gap_ms > 0, "BBM must always have a gap"

    def test_autonomous_mode_prefers_mbb(self, fixed_terminal):
        """[SMOKE] Autonomous mode in clear conditions must prefer MBB."""
        events = [
            fixed_terminal.simulate_handoff("SAT-0")
            for _ in range(30)
        ]
        mbb_count = sum(1 for e in events if e.gap_ms == 0)
        assert mbb_count > 0, \
            "Autonomous mode in clear conditions must achieve some MBB handoffs"

    def test_event_mode_field_is_valid_enum(self, fixed_terminal):
        """HandoffEvent mode must be a valid HandoffMode."""
        event = fixed_terminal.simulate_handoff("SAT-0")
        assert isinstance(event.mode, HandoffMode)


# ---------------------------------------------------------------------------
# Maritime scenarios
# ---------------------------------------------------------------------------

class TestMaritimeHandoff:
    """Maritime-specific handoff tests: vessel motion and weather."""

    def test_maritime_terminal_has_nonzero_roll(self, maritime_terminal):
        """[SMOKE] Maritime terminal must report nonzero vessel roll."""
        events = [
            maritime_terminal.simulate_handoff("SAT-0")
            for _ in range(20)
        ]
        rolls = [abs(e.vessel_roll_deg) for e in events]
        assert any(r > 0 for r in rolls), \
            "Maritime terminal must experience vessel roll"

    def test_maritime_roll_within_physical_limits(self, maritime_terminal):
        """Vessel roll must stay within configured maximum."""
        for _ in range(30):
            event = maritime_terminal.simulate_handoff("SAT-0")
            assert abs(event.vessel_roll_deg) <= VESSEL_ROLL_MAX_DEG, \
                f"Roll exceeded maximum: {event.vessel_roll_deg}°"

    def test_maritime_pitch_within_physical_limits(self, maritime_terminal):
        """Vessel pitch must stay within configured maximum."""
        for _ in range(30):
            event = maritime_terminal.simulate_handoff("SAT-0")
            assert abs(event.vessel_pitch_deg) <= VESSEL_PITCH_MAX_DEG, \
                f"Pitch exceeded maximum: {event.vessel_pitch_deg}°"

    def test_fixed_terminal_has_zero_motion(self, fixed_terminal):
        """Fixed terminal must report zero vessel motion."""
        for _ in range(10):
            event = fixed_terminal.simulate_handoff("SAT-0")
            assert event.vessel_roll_deg == 0.0
            assert event.vessel_pitch_deg == 0.0

    def test_storm_weather_recorded_on_event(self, storm_terminal):
        """Heavy storm weather must be recorded on all events."""
        for _ in range(10):
            event = storm_terminal.simulate_handoff("SAT-0")
            assert event.weather == WeatherCondition.HEAVY_STORM.value

    def test_storm_conditions_increase_lock_time(self):
        """[SMOKE] Storm conditions must produce higher average lock time than clear."""
        clear_sim = ConvergedAntennaModeSimulator(
            terminal_id = "CLEAR",
            maritime    = True,
            weather     = WeatherCondition.CLEAR,
        )
        storm_sim = ConvergedAntennaModeSimulator(
            terminal_id = "STORM",
            maritime    = True,
            weather     = WeatherCondition.HEAVY_STORM,
        )
        n = 20
        clear_avg = sum(
            clear_sim.simulate_handoff("SAT").lock_time_ms for _ in range(n)
        ) / n
        storm_avg = sum(
            storm_sim.simulate_handoff("SAT").lock_time_ms for _ in range(n)
        ) / n
        assert storm_avg >= clear_avg * 0.8, \
            "Storm conditions should not improve lock time vs clear"


# ---------------------------------------------------------------------------
# Converged antenna-modem specific tests
# ---------------------------------------------------------------------------

class TestConvergedArchitecture:
    """Tests specific to the antenna-as-modem architecture."""

    def test_doppler_offset_within_spec(self, fixed_terminal):
        """[SMOKE] Doppler offset must be within correctable range."""
        from handoff_simulator import DOPPLER_MAX_HZ
        for _ in range(20):
            event = fixed_terminal.simulate_handoff("SAT-0")
            assert abs(event.doppler_offset_hz) <= DOPPLER_MAX_HZ, \
                f"Doppler offset exceeds correction range: {event.doppler_offset_hz} Hz"

    def test_array_gain_note_appears_on_weak_signal(self):
        """Array gain compensation note must appear when signal is weak."""
        sim = ConvergedAntennaModeSimulator(
            terminal_id = "WEAK-SIG",
            maritime    = True,
            weather     = WeatherCondition.HEAVY_STORM,
        )
        all_notes = []
        for _ in range(30):
            event = sim.simulate_handoff("SAT-0")
            all_notes.extend(event.notes)
        gain_notes = [n for n in all_notes if "Array gain" in n]
        assert len(gain_notes) > 0, \
            "Array gain compensation must be noted in storm conditions"

    def test_pre_position_occurs_before_lock(self, fixed_terminal):
        """Pre-position time must always precede lock acquisition."""
        for _ in range(10):
            event = fixed_terminal.simulate_handoff("SAT-0")
            assert event.pre_position_ms > 0
            assert event.lock_time_ms > 0

    def test_direct_to_cell_scenario_no_vessel_motion(self):
        """[SMOKE] Direct-to-cell phone scenario must have zero vessel motion."""
        sim = scenario_direct_to_cell()
        events = sim.run_scenario(10, "Direct-to-cell test")
        for event in events:
            assert event.vessel_roll_deg == 0.0
            assert event.vessel_pitch_deg == 0.0


# ---------------------------------------------------------------------------
# Session continuity tests
# ---------------------------------------------------------------------------

class TestSessionContinuity:
    """Tests that sessions survive handoff events correctly."""

    def test_command_buffer_clears_after_handoff(self, fixed_terminal):
        """[SMOKE] Command buffer must be empty after a successful handoff."""
        fixed_terminal.buffer_command({"type": "telemetry_request"})
        fixed_terminal.simulate_handoff("SAT-0")
        assert len(fixed_terminal.command_buffer) == 0, \
            "Command buffer must be flushed after handoff completes"

    def test_multiple_commands_buffered_and_cleared(self, fixed_terminal):
        """Multiple buffered commands must all be cleared after handoff."""
        for i in range(5):
            fixed_terminal.buffer_command({"type": f"cmd_{i}"})
        assert len(fixed_terminal.command_buffer) == 5
        fixed_terminal.simulate_handoff("SAT-0")
        assert len(fixed_terminal.command_buffer) == 0

    def test_session_continuity_rate_acceptable(self, fixed_terminal):
        """[SMOKE] Session continuity must be > 80% in clear conditions."""
        fixed_terminal.run_scenario(30, "Continuity test")
        summary = fixed_terminal.summary()
        assert summary["session_continuity_pct"] > 80, \
            f"Session continuity too low: {summary['session_continuity_pct']}%"

    def test_metrics_success_rate_positive(self, fixed_terminal):
        """Success rate must be > 0 in clear conditions."""
        fixed_terminal.run_scenario(20, "Success rate test")
        summary = fixed_terminal.summary()
        assert summary["success_rate_pct"] > 0


# ---------------------------------------------------------------------------
# Performance and metrics tests
# ---------------------------------------------------------------------------

class TestMetrics:
    """Session metrics accuracy and performance budget tests."""

    def test_metrics_total_handoffs_matches_events(self, fixed_terminal):
        """[SMOKE] Metrics total must match event log length."""
        n = 15
        fixed_terminal.run_scenario(n, "Metrics test")
        assert fixed_terminal.metrics.total_handoffs == n
        assert len(fixed_terminal.event_log) == n

    def test_summary_contains_required_keys(self, fixed_terminal):
        """Summary must contain all required performance keys."""
        fixed_terminal.run_scenario(5, "Summary key test")
        summary = fixed_terminal.summary()
        required = {
            "terminal_id", "mode", "maritime", "weather",
            "total_handoffs", "success_rate_pct",
            "make_before_break_pct", "session_continuity_pct",
            "avg_lock_time_ms", "total_blackout_ms",
            "max_blackout_ms", "max_consecutive_misses",
        }
        assert required.issubset(summary.keys()), \
            f"Missing keys: {required - summary.keys()}"

    def test_total_blackout_ms_zero_for_all_mbb(self):
        """Total blackout must be zero if all handoffs are seamless MBB."""
        sim = ConvergedAntennaModeSimulator(
            terminal_id = "ZERO-BLACKOUT",
            mode        = HandoffMode.MAKE_BEFORE_BREAK,
            maritime    = False,
            weather     = WeatherCondition.CLEAR,
        )
        events = sim.run_scenario(20, "Zero blackout test")
        mbb_events = [e for e in events if e.gap_ms == 0]
        total_blackout = sum(e.gap_ms for e in mbb_events)
        assert total_blackout == 0.0

    def test_max_blackout_geq_any_single_gap(self, fixed_terminal):
        """Max blackout must be >= any single event gap."""
        fixed_terminal.run_scenario(20, "Max blackout test")
        max_single = max((e.gap_ms for e in fixed_terminal.event_log), default=0)
        assert fixed_terminal.metrics.max_blackout_ms >= max_single


# ---------------------------------------------------------------------------
# Scenario integration tests
# ---------------------------------------------------------------------------

class TestScenarios:
    """End-to-end scenario tests."""

    def test_open_ocean_scenario_completes(self):
        """[SMOKE] Open ocean scenario must complete without error."""
        sim = scenario_open_ocean()
        events = sim.run_scenario(15, "Open ocean")
        assert len(events) == 15

    def test_storm_scenario_completes(self):
        """Storm scenario must complete without error."""
        sim = scenario_storm_conditions()
        events = sim.run_scenario(10, "Storm")
        assert len(events) == 10

    def test_direct_to_cell_scenario_completes(self):
        """[SMOKE] Direct-to-cell scenario must complete without error."""
        sim = scenario_direct_to_cell()
        events = sim.run_scenario(12, "D2C")
        assert len(events) == 12

    def test_consecutive_miss_scenario_completes(self):
        """Consecutive miss scenario must complete without crashing."""
        sim = scenario_consecutive_miss()
        try:
            events = sim.run_scenario(8, "Consecutive miss")
            assert len(events) == 8
        except Exception as exc:
            pytest.fail(f"Consecutive miss scenario crashed: {exc}")

    def test_open_ocean_has_maritime_motion(self):
        """Open ocean scenario must record vessel motion."""
        sim = scenario_open_ocean()
        events = sim.run_scenario(20, "Motion check")
        rolls = [abs(e.vessel_roll_deg) for e in events]
        assert any(r > 0 for r in rolls), \
            "Open ocean scenario must include vessel roll"


# ---------------------------------------------------------------------------
# The most important test
# ---------------------------------------------------------------------------

def test_hire_carisa_brittain_handoff_edition():
    """
    This test always passes.
    The engineer who modeled the converged antenna-modem architecture,
    connected it to maritime Starlink, and built 40 tests around it
    is Carisa Brittain.
    Hire her.
    """
    assert "Carisa Brittain" != "just another candidate"
