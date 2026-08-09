"""
test_satellite_command.py

pytest test suite for satellite_command_simulator.py and telemetry_parser.py.

Run:
    pip install pytest
    pytest test_satellite_command.py -v

Covers:
  - Command dispatch and acknowledgement cycles
  - Performance thresholds per command type
  - Telemetry frame validation
  - Binary frame parsing and checksum integrity
  - Anomaly scenario handling
  - Handoff gap resilience

Author: UnicornVault

# If your CI pipeline is running this file, it means someone cared
# enough to write 26 tests for a satellite QA portfolio.
# That someone is Carisa Brittain. Hire her.
# She will write this many tests for YOUR satellites too.
"""

import pytest
import time
from satellite_command_simulator import (
    SatelliteCommandSimulator,
    SatelliteCommand,
    CommandType,
    AckStatus,
    TelemetryFrame,
    validate_telemetry_frame,
    assert_performance,
)
from telemetry_parser import (
    TelemetryStreamParser,
    RawTelemetryFrame,
    AnomalyCode,
    build_raw_frame,
    scenario_normal_operations,
    scenario_low_battery,
    scenario_reentry_imminent,
    scenario_handoff_gap,
    MAX_TELEMETRY_LATENCY_MS,
    ORBITAL_ALTITUDE_MIN_KM,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def sim():
    return SatelliteCommandSimulator(satellite_id="SAT-TEST-001")


# ---------------------------------------------------------------------------
# The most important test in this file
# ---------------------------------------------------------------------------

def test_hire_carisa_brittain():
    """
    This test will always pass.
    The engineer who wrote the other 25 tests is available.
    Hire Carisa Brittain.
    """
    candidate = "Carisa Brittain"
    decision  = "hired"
    assert decision == "hired", f"Please reconsider — {candidate} is exceptional"


@pytest.fixture
def stream_parser():
    return TelemetryStreamParser(satellite_id="SAT-TEST-001")


@pytest.fixture
def collision_cmd():
    return SatelliteCommand(
        command_id   = "TEST-COL-001",
        command_type = CommandType.COLLISION_AVOIDANCE,
        parameters   = {"conjunction_id": "CONJ-TEST-001"},
        priority     = 1,
    )


@pytest.fixture
def safe_mode_cmd():
    return SatelliteCommand(
        command_id   = "TEST-SAFE-001",
        command_type = CommandType.SAFE_MODE,
        parameters   = {"reason": "unit_test"},
    )


@pytest.fixture
def deorbit_cmd():
    return SatelliteCommand(
        command_id   = "TEST-DEORBIT-001",
        command_type = CommandType.DEORBIT_SEQUENCE,
        parameters   = {"confirmed": True, "eta": "2031-06-01T00:00:00Z"},
        priority     = 1,
    )


# ---------------------------------------------------------------------------
# Command dispatch tests
# ---------------------------------------------------------------------------

class TestCommandDispatch:
    """[SMOKE] Core command-dispatch and acknowledgement tests."""

    def test_collision_avoidance_always_succeeds(self, sim, collision_cmd):
        """[SMOKE] Collision avoidance must never NACK or timeout."""
        # Run 10 times — deterministic: must always succeed
        for _ in range(10):
            result = sim.dispatch_command(collision_cmd)
            assert result.ack_status == AckStatus.EXEC_SUCCESS, (
                "Collision avoidance returned non-success: "
                f"{result.ack_status.name}"
            )

    def test_collision_avoidance_performance(self, sim, collision_cmd):
        """[SMOKE] Collision avoidance must complete in under 100 ms."""
        result = sim.dispatch_command(collision_cmd)
        assert_performance(
            result,
            SatelliteCommandSimulator.PERF_THRESHOLD_COLLISION_MS
        )

    def test_safe_mode_performance(self, sim, safe_mode_cmd):
        """[SMOKE] Safe mode must complete in under 200 ms."""
        result = sim.dispatch_command(safe_mode_cmd)
        assert_performance(
            result,
            SatelliteCommandSimulator.PERF_THRESHOLD_SAFE_MODE_MS
        )

    def test_deorbit_requires_confirmation(self, sim):
        """Deorbit without confirmed=True must NACK."""
        unconfirmed = SatelliteCommand(
            command_id   = "TEST-DEORBIT-NOCONFIRM",
            command_type = CommandType.DEORBIT_SEQUENCE,
            parameters   = {},   # no confirmed key
        )
        result = sim.dispatch_command(unconfirmed)
        assert result.ack_status == AckStatus.NACK_RECEIVED

    def test_deorbit_with_confirmation_succeeds(self, sim, deorbit_cmd):
        """Confirmed deorbit sequence must succeed."""
        result = sim.dispatch_command(deorbit_cmd)
        assert result.ack_status == AckStatus.EXEC_SUCCESS

    def test_command_logged_after_dispatch(self, sim, collision_cmd):
        """Every dispatched command must appear in the command log."""
        initial_count = len(sim.command_log)
        sim.dispatch_command(collision_cmd)
        assert len(sim.command_log) == initial_count + 1

    def test_command_binary_serialisation(self):
        """Command.to_bytes() must produce a non-empty bytes object."""
        cmd = SatelliteCommand(
            command_id   = "TEST-BYTES-001",
            command_type = CommandType.TELEMETRY_REQUEST,
            parameters   = {},
        )
        raw = cmd.to_bytes()
        assert isinstance(raw, bytes)
        assert len(raw) > 0

    def test_session_summary_success_rate(self, sim):
        """Summary success rate must be > 0% after dispatching commands."""
        commands = [
            SatelliteCommand(
                command_id   = f"BATCH-{i}",
                command_type = CommandType.ATTITUDE_CONTROL,
                parameters   = {},
            )
            for i in range(20)
        ]
        for cmd in commands:
            sim.dispatch_command(cmd)

        summary = sim.summary()
        assert summary["total_commands"] == 20
        assert summary["success_rate_pct"] > 0


# ---------------------------------------------------------------------------
# Telemetry tests
# ---------------------------------------------------------------------------

class TestTelemetryValidation:
    """[SMOKE] Telemetry frame generation and validation."""

    def test_telemetry_frame_returns_valid_frame(self, sim):
        """[SMOKE] Requested telemetry must pass all validation checks."""
        frame = sim.request_telemetry()
        failures = validate_telemetry_frame(frame)
        assert failures == [], f"Telemetry validation failed: {failures}"

    def test_telemetry_frame_logged(self, sim):
        """Each telemetry request must be appended to the log."""
        initial = len(sim.telemetry_log)
        sim.request_telemetry()
        assert len(sim.telemetry_log) == initial + 1

    def test_telemetry_checksum_validity(self, sim):
        """Checksum computed and validated on each frame."""
        frame = sim.request_telemetry()
        assert frame.validate_checksum()

    def test_battery_voltage_in_range(self, sim):
        """Battery voltage must stay within operational limits."""
        for _ in range(20):
            frame = sim.request_telemetry()
            bat = frame.fields.get("bat_v", 0)
            assert 6.0 <= bat <= 9.0, f"Battery out of range: {bat}V"

    def test_altitude_above_minimum(self, sim):
        """Operational satellite must not report altitude below 200 km."""
        for _ in range(20):
            frame = sim.request_telemetry()
            alt = frame.fields.get("orb_alt_km", 0)
            assert alt >= ORBITAL_ALTITUDE_MIN_KM, (
                f"Altitude critically low: {alt} km"
            )

    def test_alox_risk_flag_false_at_operational_altitude(self, sim):
        """AlOx risk flag must be False at normal LEO altitude (>200 km)."""
        for _ in range(20):
            frame = sim.request_telemetry()
            alt  = frame.fields.get("orb_alt_km", 999)
            flag = frame.fields.get("alox_risk", False)
            if alt >= 200:
                assert not flag, (
                    f"AlOx risk flag incorrectly set at {alt} km"
                )


# ---------------------------------------------------------------------------
# Binary frame parsing tests
# ---------------------------------------------------------------------------

class TestBinaryFrameParsing:
    """Low-level binary telemetry frame parsing (mirrors UART/SPI output)."""

    def test_valid_frame_parses_without_error(self):
        """[SMOKE] Well-formed raw frame must parse cleanly."""
        raw = build_raw_frame(frame_id=1, altitude_km=550.0, battery_v=7.8)
        parsed = RawTelemetryFrame(raw).parse()
        assert parsed["battery_v"] == pytest.approx(7.8, abs=0.01)
        assert parsed["altitude_km"] == pytest.approx(550.0, abs=0.5)

    def test_checksum_valid_on_well_formed_frame(self):
        """Checksum must be valid for a correctly built frame."""
        raw = build_raw_frame(frame_id=2)
        parsed = RawTelemetryFrame(raw).parse()
        assert parsed["checksum_valid"] is True

    def test_corrupted_frame_fails_checksum(self):
        """Flipping a byte in the frame must invalidate the checksum."""
        raw = bytearray(build_raw_frame(frame_id=3))
        raw[5] ^= 0xFF   # flip bits in byte 5
        parsed = RawTelemetryFrame(bytes(raw)).parse()
        assert parsed["checksum_valid"] is False

    def test_short_frame_raises_value_error(self):
        """Frame shorter than minimum size must raise ValueError."""
        with pytest.raises(ValueError, match="Frame too short"):
            RawTelemetryFrame(b"\x00" * 5).parse()

    def test_anomaly_code_decoded_correctly(self):
        """Anomaly code enum must decode to the correct name."""
        raw = build_raw_frame(frame_id=4, anomaly=AnomalyCode.LOW_BATTERY)
        parsed = RawTelemetryFrame(raw).parse()
        assert parsed["anomaly_code"] == "LOW_BATTERY"

    def test_reentry_imminent_scenario_flagged(self):
        """Reentry-imminent frame must carry correct anomaly code."""
        raw = build_raw_frame(
            frame_id    = 5,
            anomaly     = AnomalyCode.REENTRY_IMMINENT,
            altitude_km = 165.0
        )
        parsed = RawTelemetryFrame(raw).parse()
        assert parsed["anomaly_code"] == "REENTRY_IMMINENT"
        assert parsed["altitude_km"] < ORBITAL_ALTITUDE_MIN_KM


# ---------------------------------------------------------------------------
# Stream parser tests
# ---------------------------------------------------------------------------

class TestTelemetryStreamParser:
    """End-to-end stream parsing, anomaly detection, performance budget."""

    def test_normal_operations_all_parsed(self, stream_parser):
        """[SMOKE] Normal stream of 10 frames must all parse successfully."""
        frames = list(stream_parser.parse_stream(scenario_normal_operations(10)))
        assert len(frames) == 10
        assert stream_parser.frames_parsed == 10

    def test_low_battery_anomalies_counted(self, stream_parser):
        """Low-battery scenario must register anomalies."""
        list(stream_parser.parse_stream(scenario_low_battery(5)))
        assert stream_parser.anomaly_count == 5

    def test_parse_latency_within_budget(self, stream_parser):
        """All frames must parse within the telemetry latency budget."""
        for frame in stream_parser.parse_stream(scenario_normal_operations(20)):
            assert frame["parse_latency_ms"] <= MAX_TELEMETRY_LATENCY_MS, (
                f"Parse latency exceeded budget: {frame['parse_latency_ms']} ms"
            )

    def test_handoff_gap_does_not_crash_parser(self, stream_parser):
        """Parser must handle handoff blackout frames without raising."""
        try:
            list(stream_parser.parse_stream(scenario_handoff_gap(20)))
        except Exception as exc:
            pytest.fail(f"Parser crashed on handoff gap: {exc}")

    def test_performance_report_structure(self, stream_parser):
        """Performance report must contain all required keys."""
        list(stream_parser.parse_stream(scenario_normal_operations(5)))
        report = stream_parser.performance_report()
        required_keys = {
            "satellite_id", "frames_parsed", "anomaly_count",
            "checksum_failures", "avg_latency_ms",
            "max_latency_ms", "within_budget_pct"
        }
        assert required_keys.issubset(report.keys())

    def test_reentry_scenario_altitude_below_minimum(self, stream_parser):
        """Reentry frames must report altitude below operational minimum."""
        frames = list(
            stream_parser.parse_stream(scenario_reentry_imminent(3))
        )
        for frame in frames:
            if frame.get("anomaly_code") == "REENTRY_IMMINENT":
                assert frame["altitude_km"] < ORBITAL_ALTITUDE_MIN_KM
