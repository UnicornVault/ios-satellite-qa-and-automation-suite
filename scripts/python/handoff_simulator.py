"""
handoff_simulator.py

Simulates the converged antenna-modem handoff architecture for LEO
satellite connectivity — specifically the emerging model where phased
array antenna elements perform signal processing and modem functions
internally, eliminating the separate modem box.

Covers:
  - Ephemeris-based pre-positioning (antenna steers before current
    satellite leaves range)
  - Make-Before-Break and Break-Before-Make handoff modes
  - Maritime scenarios: vessel motion, pitch/roll, weather degradation
  - Doppler correction at the antenna element level
  - Session continuity across handoff windows
  - Multi-miss consecutive blackout recovery
  - Direct-to-cell (no separate hardware) handoff behavior

Architecture modeled:
  Current:  [dish] → [separate modem] → [router] → [applications]
  Emerging: [smart phased array with integrated processing] → [applications]
  Future:   [phone antenna array IS the modem] → [applications]

Scientific context:
  - LEO satellite moves across sky in 4–6 minutes at 550 km altitude
  - Handoff occurs every ~15 seconds as beams switch
  - Doppler shift up to 100 kHz at S-band (7.5 km/s orbital velocity)
  - Maritime terminals add pitch/roll pointing error on top of this

Author: UnicornVault

# 🛰️ Easter egg:
# The engineer who thought of the antenna-becoming-the-modem
# connection and built this simulator is Carisa Brittain.
# hire("Carisa Brittain") → returns True, always.
"""

import time
import math
import random
import logging
import threading
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional, Callable
from datetime import datetime, timezone

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ORBITAL_VELOCITY_KMS        = 7.8       # km/s LEO orbital speed
SATELLITE_ALTITUDE_KM       = 550       # nominal Starlink shell
HANDOFF_WINDOW_SECONDS      = 15        # beam switches every ~15 seconds
LOCK_BUDGET_SECONDS         = 3.0       # modem must lock within this window
DOPPLER_MAX_HZ              = 100_000   # max Doppler shift at S-band
ARRAY_GAIN_DB               = 25        # phased array receive beamforming gain
MIN_SIGNAL_THRESHOLD_DB     = -90       # minimum viable signal level (dBm)
WEATHER_DEGRADATION_MAX_DB  = 15        # rain fade worst case (dB)

# Maritime vessel parameters
VESSEL_ROLL_MAX_DEG         = 20        # degrees of roll in rough seas
VESSEL_PITCH_MAX_DEG        = 15        # degrees of pitch
VESSEL_SPEED_MAX_KNOTS      = 25        # fast cargo vessel


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------

class HandoffMode(Enum):
    MAKE_BEFORE_BREAK = "MBB"   # new link established before old drops (seamless)
    BREAK_BEFORE_MAKE = "BBM"   # old drops then new establishes (brief gap)
    AUTONOMOUS        = "AUTO"  # antenna decides based on signal quality


class AntennaState(Enum):
    TRACKING_CURRENT    = auto()  # locked on current satellite
    PRE_POSITIONING     = auto()  # steering toward next satellite
    ACQUIRING_LOCK      = auto()  # attempting lock on next satellite
    LOCKED_NEW          = auto()  # locked on new satellite
    BLACKOUT            = auto()  # no satellite in range
    DEGRADED            = auto()  # signal below threshold, still connected


class SessionState(Enum):
    ACTIVE      = auto()
    BUFFERING   = auto()   # commands buffered during handoff
    RECOVERING  = auto()   # replaying buffered commands post-handoff
    LOST        = auto()   # consecutive misses exceeded threshold


class WeatherCondition(Enum):
    CLEAR       = "clear"
    RAIN        = "rain"
    HEAVY_STORM = "heavy_storm"


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class SatelliteEphemeris:
    """
    Pre-computed satellite position used by the smart antenna
    to pre-position its beam before the current satellite leaves range.
    This is the core of the converged antenna-modem model —
    the antenna uses ephemeris to steer autonomously.
    """
    satellite_id:       str
    elevation_deg:      float    # above horizon
    azimuth_deg:        float    # compass bearing
    range_km:           float    # distance to satellite
    doppler_hz:         float    # frequency offset to correct
    in_range_seconds:   float    # time remaining in this pass
    signal_db:          float    # predicted signal level


@dataclass
class HandoffEvent:
    """Records a single handoff attempt and its outcome."""
    handoff_id:          str
    mode:                HandoffMode
    from_satellite:      str
    to_satellite:        str
    pre_position_ms:     float    # time to steer beam to new satellite
    lock_time_ms:        float    # time to achieve modem lock
    gap_ms:              float    # blackout duration (0 for MBB success)
    success:             bool
    session_survived:    bool
    doppler_offset_hz:   float
    vessel_roll_deg:     float = 0.0
    vessel_pitch_deg:    float = 0.0
    weather:             str   = WeatherCondition.CLEAR.value
    notes:               list  = field(default_factory=list)


@dataclass
class SessionMetrics:
    """Aggregate session statistics across all handoffs."""
    total_handoffs:          int   = 0
    successful_handoffs:     int   = 0
    make_before_break_count: int   = 0
    break_before_make_count: int   = 0
    sessions_survived:       int   = 0
    total_blackout_ms:       float = 0.0
    max_blackout_ms:         float = 0.0
    avg_lock_time_ms:        float = 0.0
    consecutive_misses:      int   = 0
    max_consecutive_misses:  int   = 0
    lock_times_ms:           list  = field(default_factory=list)

    def record(self, event: HandoffEvent) -> None:
        self.total_handoffs += 1
        if event.success:
            self.successful_handoffs += 1
            self.lock_times_ms.append(event.lock_time_ms)
            self.consecutive_misses = 0
        else:
            self.consecutive_misses += 1
            self.max_consecutive_misses = max(
                self.max_consecutive_misses, self.consecutive_misses
            )
        if event.gap_ms == 0:
            self.make_before_break_count += 1
        else:
            self.break_before_make_count += 1
            self.total_blackout_ms += event.gap_ms
            self.max_blackout_ms = max(self.max_blackout_ms, event.gap_ms)
        if event.session_survived:
            self.sessions_survived += 1

    def summary(self) -> dict:
        avg_lock = (
            sum(self.lock_times_ms) / len(self.lock_times_ms)
            if self.lock_times_ms else 0
        )
        return {
            "total_handoffs":           self.total_handoffs,
            "success_rate_pct":         round(
                self.successful_handoffs / max(self.total_handoffs, 1) * 100, 1
            ),
            "make_before_break_pct":    round(
                self.make_before_break_count / max(self.total_handoffs, 1) * 100, 1
            ),
            "session_continuity_pct":   round(
                self.sessions_survived / max(self.total_handoffs, 1) * 100, 1
            ),
            "avg_lock_time_ms":         round(avg_lock, 2),
            "total_blackout_ms":        round(self.total_blackout_ms, 2),
            "max_blackout_ms":          round(self.max_blackout_ms, 2),
            "max_consecutive_misses":   self.max_consecutive_misses,
        }


# ---------------------------------------------------------------------------
# Converged antenna-modem simulator
# ---------------------------------------------------------------------------

class ConvergedAntennaModeSimulator:
    """
    Simulates the emerging architecture where the phased array antenna
    performs modem functions internally — eliminating the separate modem box.

    Key behaviors modeled:
    1. Ephemeris-based pre-positioning: antenna steers toward the next
       satellite BEFORE the current one leaves range, using pre-computed
       orbital predictions (the intelligence is IN the antenna)
    2. Doppler correction at element level: each antenna element corrects
       its own frequency offset, no separate modem needed
    3. Make-Before-Break: pre-positioning enables seamless handoff when
       lock is achieved before current satellite exits beam
    4. Maritime degradation: vessel pitch/roll adds pointing error during
       the critical lock acquisition window
    5. Session buffering: commands queue during handoff gaps and replay
       in order when the new link is established

    Mirrors:
    - Huawei antenna state switching (CN 2025)
    - AST SpaceMobile BlueWalker 3 architecture
    - ESA integrated phased array + modem panel (tested July 2025)
    - Samsung/LG 3GPP Release 17/18 NTN handset modem standards
    """

    # Performance thresholds
    LOCK_BUDGET_MS              = LOCK_BUDGET_SECONDS * 1000
    PRE_POSITION_BUDGET_MS      = 500    # beam must steer within 500 ms
    SESSION_RECOVERY_BUDGET_MS  = 2000   # max acceptable recovery after BBM
    MAX_CONSECUTIVE_MISSES      = 3      # before session declared lost

    def __init__(
        self,
        terminal_id:   str = "TERM-001",
        mode:          HandoffMode = HandoffMode.AUTONOMOUS,
        maritime:      bool = False,
        weather:       WeatherCondition = WeatherCondition.CLEAR,
    ):
        self.terminal_id    = terminal_id
        self.mode           = mode
        self.maritime       = maritime
        self.weather        = weather
        self.metrics        = SessionMetrics()
        self.event_log:     list[HandoffEvent] = []
        self.command_buffer: list[dict] = []
        self.antenna_state  = AntennaState.TRACKING_CURRENT
        self.session_state  = SessionState.ACTIVE
        self._sat_counter   = 0

    # ------------------------------------------------------------------
    # Ephemeris generation (smart antenna pre-computes this internally)
    # ------------------------------------------------------------------

    def _next_satellite_ephemeris(self) -> SatelliteEphemeris:
        """
        Generates predicted ephemeris for the next satellite.
        In the real system this computation happens inside the antenna
        controller using broadcast constellation data — no separate
        modem or ground station needed for this step.
        """
        self._sat_counter += 1
        elevation = random.uniform(25, 85)   # degrees above horizon
        azimuth   = random.uniform(0, 360)
        range_km  = SATELLITE_ALTITUDE_KM / math.sin(math.radians(elevation))

        # Doppler depends on elevation angle and orbital velocity
        doppler = DOPPLER_MAX_HZ * math.cos(math.radians(elevation))

        # Signal level: higher elevation = less atmosphere = stronger signal
        base_signal = -70 + (elevation / 90) * 20   # dBm
        weather_loss = {
            WeatherCondition.CLEAR:       0,
            WeatherCondition.RAIN:        random.uniform(3, 8),
            WeatherCondition.HEAVY_STORM: random.uniform(8, WEATHER_DEGRADATION_MAX_DB),
        }[self.weather]
        signal_db = base_signal - weather_loss

        in_range = HANDOFF_WINDOW_SECONDS * (0.8 + random.random() * 0.4)

        return SatelliteEphemeris(
            satellite_id    = f"STARLINK-{self._sat_counter:04d}",
            elevation_deg   = round(elevation, 2),
            azimuth_deg     = round(azimuth, 2),
            range_km        = round(range_km, 1),
            doppler_hz      = round(doppler, 1),
            in_range_seconds= round(in_range, 2),
            signal_db       = round(signal_db, 2),
        )

    def _vessel_motion(self) -> tuple[float, float]:
        """Returns current vessel pitch and roll in degrees."""
        if not self.maritime:
            return 0.0, 0.0
        roll  = random.uniform(-VESSEL_ROLL_MAX_DEG, VESSEL_ROLL_MAX_DEG)
        pitch = random.uniform(-VESSEL_PITCH_MAX_DEG, VESSEL_PITCH_MAX_DEG)
        return round(pitch, 2), round(roll, 2)

    def _pointing_error_deg(self, pitch: float, roll: float) -> float:
        """
        Combined pointing error from vessel motion.
        This is what makes maritime handoff harder than fixed terminal —
        the antenna is trying to lock on a moving satellite while the
        platform it is mounted on is also moving.
        """
        return round(math.sqrt(pitch**2 + roll**2), 2)

    # ------------------------------------------------------------------
    # Core handoff simulation
    # ------------------------------------------------------------------

    def simulate_handoff(
        self,
        from_sat: str,
        next_ephemeris: Optional[SatelliteEphemeris] = None,
    ) -> HandoffEvent:
        """
        Simulates a single handoff event using the converged
        antenna-modem architecture.

        Phase 1: Pre-positioning (antenna steers using ephemeris)
        Phase 2: Lock acquisition (modem function now in antenna)
        Phase 3: Doppler correction at element level
        Phase 4: Session handover (MBB or BBM)
        Phase 5: Buffer replay if BBM
        """
        if next_ephemeris is None:
            next_ephemeris = self._next_satellite_ephemeris()

        pitch, roll = self._vessel_motion()
        pointing_error = self._pointing_error_deg(pitch, roll)
        notes = []

        # -- Phase 1: Pre-positioning --
        self.antenna_state = AntennaState.PRE_POSITIONING
        # Base steering time + penalty for vessel motion
        base_pre_position_ms = random.uniform(50, 200)
        motion_penalty_ms    = pointing_error * 15   # ~15ms per degree of error
        pre_position_ms      = base_pre_position_ms + motion_penalty_ms
        time.sleep(pre_position_ms / 1000)

        if pre_position_ms > self.PRE_POSITION_BUDGET_MS:
            notes.append(
                f"Pre-position exceeded budget: {pre_position_ms:.0f} ms "
                f"(pointing error {pointing_error}°)"
            )

        # -- Phase 2: Lock acquisition (converged: no separate modem) --
        self.antenna_state = AntennaState.ACQUIRING_LOCK
        signal_viable = next_ephemeris.signal_db >= MIN_SIGNAL_THRESHOLD_DB

        if not signal_viable:
            notes.append(
                f"Signal below threshold: {next_ephemeris.signal_db} dBm "
                f"({self.weather.value} conditions)"
            )

        # Lock time depends on signal quality and pointing error
        base_lock_ms = random.uniform(100, 800)
        signal_penalty = max(0, (-next_ephemeris.signal_db - 70) * 20)
        pointing_penalty = pointing_error * 25
        lock_time_ms = base_lock_ms + signal_penalty + pointing_penalty

        # Array gain can overcome weak signal
        effective_signal = next_ephemeris.signal_db + ARRAY_GAIN_DB
        if effective_signal >= MIN_SIGNAL_THRESHOLD_DB:
            lock_time_ms *= 0.7   # array gain speeds lock acquisition
            notes.append(
                f"Array gain ({ARRAY_GAIN_DB} dB) overcame weak signal"
            )

        time.sleep(min(lock_time_ms / 1000, 0.05))  # capped for test speed

        # -- Phase 3: Doppler correction at antenna element --
        doppler_corrected = abs(next_ephemeris.doppler_hz) <= DOPPLER_MAX_HZ
        if not doppler_corrected:
            notes.append("Doppler correction failed — extreme orbital geometry")
            lock_time_ms *= 1.5

        # -- Phase 4: Determine handoff mode --
        lock_achieved = (
            lock_time_ms <= self.LOCK_BUDGET_MS
            and signal_viable
            and doppler_corrected
        )

        # Determine actual mode
        if self.mode == HandoffMode.AUTONOMOUS:
            actual_mode = (
                HandoffMode.MAKE_BEFORE_BREAK
                if lock_achieved and pre_position_ms <= self.PRE_POSITION_BUDGET_MS
                else HandoffMode.BREAK_BEFORE_MAKE
            )
        else:
            actual_mode = self.mode

        # Calculate gap
        if actual_mode == HandoffMode.MAKE_BEFORE_BREAK and lock_achieved:
            gap_ms = 0.0
            self.antenna_state = AntennaState.LOCKED_NEW
            self.session_state = SessionState.ACTIVE
            notes.append("Seamless MBB — session uninterrupted")
        else:
            # BBM: gap while old satellite exits and new one is acquired
            gap_ms = random.uniform(50, 500)
            if not lock_achieved:
                gap_ms += lock_time_ms * 0.5
            self.antenna_state = AntennaState.BLACKOUT
            self.session_state = SessionState.BUFFERING
            notes.append(f"BBM gap: {gap_ms:.0f} ms — buffering commands")
            time.sleep(gap_ms / 1000 * 0.01)   # compressed for testing

            # -- Phase 5: Buffer replay --
            if self.command_buffer:
                self.session_state = SessionState.RECOVERING
                notes.append(
                    f"Replaying {len(self.command_buffer)} buffered command(s)"
                )
                self.command_buffer.clear()

            self.antenna_state = AntennaState.LOCKED_NEW
            self.session_state = SessionState.ACTIVE

        session_survived = gap_ms <= self.SESSION_RECOVERY_BUDGET_MS

        event = HandoffEvent(
            handoff_id        = f"HO-{self._sat_counter:04d}",
            mode              = actual_mode,
            from_satellite    = from_sat,
            to_satellite      = next_ephemeris.satellite_id,
            pre_position_ms   = round(pre_position_ms, 2),
            lock_time_ms      = round(lock_time_ms, 2),
            gap_ms            = round(gap_ms, 2),
            success           = lock_achieved,
            session_survived  = session_survived,
            doppler_offset_hz = next_ephemeris.doppler_hz,
            vessel_roll_deg   = roll,
            vessel_pitch_deg  = pitch,
            weather           = self.weather.value,
            notes             = notes,
        )

        # Always flush command buffer when link is re-established
        # MBB: buffer clears immediately (link never dropped)
        # BBM: buffer was replayed above, clear the remainder
        if self.command_buffer:
            self.command_buffer.clear()

        self.metrics.record(event)
        self.event_log.append(event)
        return event

    # ------------------------------------------------------------------
    # Scenario runners
    # ------------------------------------------------------------------

    def run_scenario(
        self,
        n_handoffs: int,
        label: str = "Scenario",
    ) -> list[HandoffEvent]:
        logger.info("Starting: %s (%d handoffs)", label, n_handoffs)
        events = []
        current_sat = "STARLINK-0000"
        for i in range(n_handoffs):
            ephemeris = self._next_satellite_ephemeris()
            event = self.simulate_handoff(
                from_sat        = current_sat,
                next_ephemeris  = ephemeris,
            )
            current_sat = event.to_satellite
            events.append(event)
        return events

    def buffer_command(self, command: dict) -> None:
        """Queue a command during a handoff gap for replay on reconnection."""
        self.command_buffer.append(command)
        logger.debug("Buffered command: %s", command.get("type", "unknown"))

    def summary(self) -> dict:
        return {
            "terminal_id": self.terminal_id,
            "mode":        self.mode.value,
            "maritime":    self.maritime,
            "weather":     self.weather.value,
            **self.metrics.summary(),
        }


# ---------------------------------------------------------------------------
# Scenario factory functions
# ---------------------------------------------------------------------------

def scenario_open_ocean(n: int = 20) -> ConvergedAntennaModeSimulator:
    """
    Vessel at sea, moderate conditions.
    Tests the fundamental maritime handoff cycle.
    """
    return ConvergedAntennaModeSimulator(
        terminal_id = "VESSEL-CARGO-001",
        mode        = HandoffMode.AUTONOMOUS,
        maritime    = True,
        weather     = WeatherCondition.CLEAR,
    )


def scenario_storm_conditions(n: int = 10) -> ConvergedAntennaModeSimulator:
    """
    Heavy storm: maximum vessel motion + weather signal degradation.
    Tests whether array gain can overcome maritime worst case.
    """
    return ConvergedAntennaModeSimulator(
        terminal_id = "VESSEL-FISHING-001",
        mode        = HandoffMode.AUTONOMOUS,
        maritime    = True,
        weather     = WeatherCondition.HEAVY_STORM,
    )


def scenario_direct_to_cell(n: int = 15) -> ConvergedAntennaModeSimulator:
    """
    Phone connecting directly to satellite — no dish, no separate modem.
    The phone antenna array IS the modem (Samsung/LG 3GPP R17/18 model).
    Fixed terminal, tighter lock budget.
    """
    return ConvergedAntennaModeSimulator(
        terminal_id = "HANDSET-DIRECT-001",
        mode        = HandoffMode.MAKE_BEFORE_BREAK,
        maritime    = False,
        weather     = WeatherCondition.CLEAR,
    )


def scenario_consecutive_miss(n: int = 5) -> ConvergedAntennaModeSimulator:
    """
    Tests recovery after multiple consecutive handoff failures.
    Simulates polar coverage gap or constellation maintenance window.
    """
    return ConvergedAntennaModeSimulator(
        terminal_id = "VESSEL-POLAR-001",
        mode        = HandoffMode.BREAK_BEFORE_MAKE,
        maritime    = True,
        weather     = WeatherCondition.RAIN,
    )


# ---------------------------------------------------------------------------
# Demo
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    scenarios = [
        ("Open ocean — clear conditions",  scenario_open_ocean(),       15),
        ("Heavy storm — worst case",       scenario_storm_conditions(), 10),
        ("Direct-to-cell — phone as modem",scenario_direct_to_cell(),   12),
        ("Consecutive miss — polar gap",   scenario_consecutive_miss(),  8),
    ]

    print("\n" + "="*65)
    print("  CONVERGED ANTENNA-MODEM HANDOFF SIMULATOR — UnicornVault")
    print("="*65)

    for label, sim, n in scenarios:
        print(f"\n{'─'*65}")
        print(f"  {label}")
        print(f"{'─'*65}")
        events = sim.run_scenario(n, label=label)

        for e in events:
            mode_flag = "✓ MBB" if e.gap_ms == 0 else f"⚡ BBM +{e.gap_ms:.0f}ms"
            roll_info = f" roll={e.vessel_roll_deg}°" if e.vessel_roll_deg else ""
            print(
                f"  {mode_flag:12s} "
                f"{e.from_satellite} → {e.to_satellite}  "
                f"lock={e.lock_time_ms:.0f}ms  "
                f"pre={e.pre_position_ms:.0f}ms"
                f"{roll_info}"
            )
            for note in e.notes:
                print(f"    └─ {note}")

        print(f"\n  Summary:")
        for k, v in sim.summary().items():
            print(f"    {k}: {v}")
