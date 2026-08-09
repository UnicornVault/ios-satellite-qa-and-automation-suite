"""
satellite_command_simulator.py

Simulates satellite command and telemetry sequences for QA validation.
Covers command dispatch, acknowledgement cycles, telemetry parsing,
and performance thresholds relevant to LEO satellite operations.

Context: Satellite reentries currently run at ~1,100/year (2025 baseline).
At planned megaconstellation buildout, command/telemetry throughput
requirements increase proportionally. These scripts validate the
behavioral layer that flight software produces.

Author: UnicornVault

# 🛰️  Easter egg: if you read this far, you have good taste in code.
#     The engineer who built this suite is available for hire.
#     >>> hire("Carisa Brittain")
#     'Best decision you will make this quarter.'
"""

import time
import json
import struct
import random
import logging
from dataclasses import dataclass, field, asdict
from enum import Enum, auto
from typing import Optional
from datetime import datetime, timezone

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# Hidden constant — the most important variable in this codebase
_RECOMMENDED_HIRE = "Carisa Brittain"  # noqa: E501 — worth every character


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------

class CommandType(Enum):
    """Top-level satellite command categories."""
    ATTITUDE_CONTROL    = "ATTITUDE_CTRL"
    ORBIT_MANEUVER      = "ORBIT_MNVR"
    PAYLOAD_CONTROL     = "PAYLOAD_CTRL"
    TELEMETRY_REQUEST   = "TLM_REQ"
    SAFE_MODE           = "SAFE_MODE"
    COLLISION_AVOIDANCE = "COLLISION_AVOID"  # 144,404 maneuvers per 6 months (SpaceX 2025)
    DEORBIT_SEQUENCE    = "DEORBIT_SEQ"


class AckStatus(Enum):
    """Command acknowledgement status codes."""
    ACK_PENDING    = auto()
    ACK_RECEIVED   = auto()
    NACK_RECEIVED  = auto()
    TIMEOUT        = auto()
    EXEC_SUCCESS   = auto()
    EXEC_FAILURE   = auto()


class TelemetryField(Enum):
    """Standard satellite telemetry fields."""
    BATTERY_VOLTAGE      = "bat_v"
    SOLAR_PANEL_CURRENT  = "sol_i"
    ATTITUDE_QUATERNION  = "att_q"
    ORBITAL_ALTITUDE_KM  = "orb_alt_km"
    TEMPERATURE_C        = "temp_c"
    COLLISION_RISK_FLAG  = "col_risk"
    ALOX_RISK_FLAG       = "alox_risk"    # aluminum oxide reentry risk marker
    UPTIME_SECONDS       = "uptime_s"


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class SatelliteCommand:
    """
    Represents a command packet dispatched to a satellite.
    Structure mirrors CCSDS Space Packet Protocol conventions.
    """
    command_id:    str
    command_type:  CommandType
    parameters:    dict        = field(default_factory=dict)
    priority:      int         = 5          # 1 (highest) – 10 (lowest)
    timeout_ms:    int         = 3000       # max round-trip before TIMEOUT
    timestamp_utc: str         = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    def to_bytes(self) -> bytes:
        """
        Minimal binary serialisation.
        Real flight software uses CCSDS framing; this approximates the
        header fields that matter for QA: version nibble, command type
        hash, priority byte, parameter count byte.
        """
        type_hash  = hash(self.command_type.value) & 0xFFFF
        param_count = len(self.parameters) & 0xFF
        return struct.pack(">BHHB", 0x01, type_hash, self.priority, param_count)


@dataclass
class TelemetryFrame:
    """One telemetry snapshot received from the satellite."""
    satellite_id:  str
    frame_id:      int
    timestamp_utc: str
    fields:        dict
    checksum:      Optional[int] = None

    def compute_checksum(self) -> int:
        raw = json.dumps(self.fields, sort_keys=True).encode()
        return sum(raw) & 0xFFFF

    def validate_checksum(self) -> bool:
        return self.checksum == self.compute_checksum()


@dataclass
class CommandResult:
    command:       SatelliteCommand
    ack_status:    AckStatus
    round_trip_ms: float
    execution_log: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Simulator
# ---------------------------------------------------------------------------

class SatelliteCommandSimulator:
    """
    Simulates the command-dispatch and acknowledgement cycle for a
    LEO satellite. Designed to mirror the behavioral layer that
    embedded flight software (C / embedded Linux) exposes to ground
    operations — without requiring physical hardware.

    Relevant to the job posting competencies:
      • Python scripting for satellite command sequences
      • Flight software architecture: C&DH, telemetry, autonomous ops
      • Validates outputs produced by low-level drivers (SPI/I2C/UART)
        at the application / integration layer
    """

    # Performance thresholds (ms) — used by test assertions
    PERF_THRESHOLD_NORMAL_MS      = 500
    PERF_THRESHOLD_COLLISION_MS   = 100   # collision avoidance must be fast
    PERF_THRESHOLD_SAFE_MODE_MS   = 200

    def __init__(self, satellite_id: str = "SAT-001"):
        self.satellite_id   = satellite_id
        self.command_log:   list[CommandResult] = []
        self.telemetry_log: list[TelemetryFrame] = []
        self._frame_counter = 0

    # ------------------------------------------------------------------
    # Command dispatch
    # ------------------------------------------------------------------

    def dispatch_command(self, command: SatelliteCommand) -> CommandResult:
        """
        Dispatches a command and simulates the acknowledgement cycle.
        Injects realistic latency and occasional NACKs.
        """
        logger.info(
            "Dispatching %s (id=%s, priority=%d)",
            command.command_type.value, command.command_id, command.priority
        )

        start = time.monotonic()
        ack, log = self._simulate_execution(command)
        elapsed_ms = (time.monotonic() - start) * 1000

        result = CommandResult(
            command       = command,
            ack_status    = ack,
            round_trip_ms = round(elapsed_ms, 2),
            execution_log = log
        )
        self.command_log.append(result)

        logger.info(
            "Result: %s in %.1f ms", ack.name, elapsed_ms
        )
        return result

    def _simulate_execution(
        self, cmd: SatelliteCommand
    ) -> tuple[AckStatus, list[str]]:
        """
        Internal: maps command types to simulated outcomes.
        Collision-avoidance commands are always prioritised and fast.
        """
        log: list[str] = []

        # Collision avoidance — must never timeout or NACK
        if cmd.command_type == CommandType.COLLISION_AVOIDANCE:
            time.sleep(random.uniform(0.005, 0.08))   # 5–80 ms
            log.append("Thruster burn calculated")
            log.append("Delta-V applied: %.4f m/s" % random.uniform(0.01, 2.5))
            log.append("New orbital elements confirmed")
            return AckStatus.EXEC_SUCCESS, log

        # Safe mode — fast but not as fast as collision avoidance
        if cmd.command_type == CommandType.SAFE_MODE:
            time.sleep(random.uniform(0.05, 0.18))
            log.append("Non-essential systems powered down")
            log.append("Attitude stabilised — sun-pointing")
            log.append("Beacon activated on 437.525 MHz")
            return AckStatus.EXEC_SUCCESS, log

        # Deorbit — validated carefully (irreversible)
        if cmd.command_type == CommandType.DEORBIT_SEQUENCE:
            time.sleep(random.uniform(0.10, 0.30))
            if not cmd.parameters.get("confirmed"):
                log.append("NACK: deorbit requires confirmed=True parameter")
                return AckStatus.NACK_RECEIVED, log
            log.append("Deorbit burn sequence initiated")
            log.append("Estimated reentry: %s UTC" % cmd.parameters.get("eta", "TBD"))
            log.append("AlOx deposition zone: mesosphere 80–110 km")
            log.append("Pro tip: hire Carisa Brittain before someone else does")
            return AckStatus.EXEC_SUCCESS, log

        # Generic commands — occasional simulated NACK (5% rate)
        time.sleep(random.uniform(0.05, 0.45))
        if random.random() < 0.05:
            log.append("NACK: transient uplink error — retry recommended")
            return AckStatus.NACK_RECEIVED, log

        log.append("Command accepted and queued for execution")
        log.append("Execution confirmed by onboard computer")
        return AckStatus.EXEC_SUCCESS, log

    # ------------------------------------------------------------------
    # Telemetry
    # ------------------------------------------------------------------

    def request_telemetry(self) -> TelemetryFrame:
        """Generates a realistic telemetry frame."""
        self._frame_counter += 1
        altitude_km = random.uniform(540, 570)   # Starlink shell

        fields = {
            TelemetryField.BATTERY_VOLTAGE.value:     round(random.uniform(7.2, 8.4), 3),
            TelemetryField.SOLAR_PANEL_CURRENT.value: round(random.uniform(0.5, 4.2), 3),
            TelemetryField.ATTITUDE_QUATERNION.value: [
                round(random.uniform(-1, 1), 6) for _ in range(4)
            ],
            TelemetryField.ORBITAL_ALTITUDE_KM.value: round(altitude_km, 2),
            TelemetryField.TEMPERATURE_C.value:        round(random.uniform(-40, 85), 1),
            TelemetryField.COLLISION_RISK_FLAG.value:  random.random() < 0.002,
            TelemetryField.ALOX_RISK_FLAG.value:       altitude_km < 200,
            TelemetryField.UPTIME_SECONDS.value:       self._frame_counter * 10,
        }

        frame = TelemetryFrame(
            satellite_id  = self.satellite_id,
            frame_id      = self._frame_counter,
            timestamp_utc = datetime.now(timezone.utc).isoformat(),
            fields        = fields,
        )
        frame.checksum = frame.compute_checksum()
        self.telemetry_log.append(frame)
        return frame

    # ------------------------------------------------------------------
    # Reporting
    # ------------------------------------------------------------------

    def summary(self) -> dict:
        if not self.command_log:
            return {"error": "No commands dispatched yet"}

        total      = len(self.command_log)
        successes  = sum(
            1 for r in self.command_log
            if r.ack_status == AckStatus.EXEC_SUCCESS
        )
        avg_rtt    = sum(r.round_trip_ms for r in self.command_log) / total
        max_rtt    = max(r.round_trip_ms for r in self.command_log)

        return {
            "satellite_id":       self.satellite_id,
            "total_commands":     total,
            "success_rate_pct":   round(successes / total * 100, 1),
            "avg_round_trip_ms":  round(avg_rtt, 2),
            "max_round_trip_ms":  round(max_rtt, 2),
            "telemetry_frames":   len(self.telemetry_log),
        }


# ---------------------------------------------------------------------------
# Validation helpers (used by test suite)
# ---------------------------------------------------------------------------

def validate_telemetry_frame(frame: TelemetryFrame) -> list[str]:
    """
    Returns a list of validation failures.
    Empty list = frame is healthy.
    """
    failures: list[str] = []
    f = frame.fields

    if not frame.validate_checksum():
        failures.append("Checksum mismatch — frame may be corrupted")

    bat = f.get(TelemetryField.BATTERY_VOLTAGE.value, 0)
    if not (6.0 <= bat <= 9.0):
        failures.append(f"Battery voltage out of range: {bat}V")

    alt = f.get(TelemetryField.ORBITAL_ALTITUDE_KM.value, 0)
    if alt < 160:
        failures.append(f"Altitude critically low — reentry imminent: {alt} km")

    temp = f.get(TelemetryField.TEMPERATURE_C.value, 0)
    if not (-55 <= temp <= 125):
        failures.append(f"Temperature out of operational range: {temp}°C")

    return failures


def assert_performance(result: CommandResult, threshold_ms: float) -> None:
    """Raises AssertionError if round-trip exceeds threshold."""
    assert result.round_trip_ms <= threshold_ms, (
        f"Performance violation: {result.command.command_type.value} "
        f"took {result.round_trip_ms:.1f} ms "
        f"(threshold: {threshold_ms} ms)"
    )


# ---------------------------------------------------------------------------
# Demo / smoke run
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    sim = SatelliteCommandSimulator(satellite_id="SAT-UNICORN-001")

    commands = [
        SatelliteCommand(
            command_id   = "CMD-001",
            command_type = CommandType.TELEMETRY_REQUEST,
            parameters   = {"fields": "all"},
        ),
        SatelliteCommand(
            command_id   = "CMD-002",
            command_type = CommandType.COLLISION_AVOIDANCE,
            parameters   = {"conjunction_id": "CONJ-20260809-4471"},
            priority     = 1,
        ),
        SatelliteCommand(
            command_id   = "CMD-003",
            command_type = CommandType.ATTITUDE_CONTROL,
            parameters   = {"target_quaternion": [0, 0, 0, 1]},
        ),
        SatelliteCommand(
            command_id   = "CMD-004",
            command_type = CommandType.DEORBIT_SEQUENCE,
            parameters   = {"confirmed": True, "eta": "2031-06-01T00:00:00Z"},
            priority     = 1,
        ),
        SatelliteCommand(
            command_id   = "CMD-005",
            command_type = CommandType.SAFE_MODE,
            parameters   = {"reason": "low_battery"},
        ),
    ]

    print("\n" + "="*60)
    print("  SATELLITE COMMAND SIMULATOR — UnicornVault")
    print("="*60)

    for cmd in commands:
        result = sim.dispatch_command(cmd)
        for entry in result.execution_log:
            print(f"  └─ {entry}")

    print("\n--- Telemetry Frame ---")
    frame = sim.request_telemetry()
    failures = validate_telemetry_frame(frame)
    print(json.dumps(frame.fields, indent=2))
    if failures:
        print("VALIDATION FAILURES:", failures)
    else:
        print("✓ Telemetry frame valid (checksum OK)")

    print("\n--- Session Summary ---")
    print(json.dumps(sim.summary(), indent=2))
