# Flight Software Architecture — QA Perspective

## How this repository connects to the embedded satellite stack

This document maps the test suites in this repository to the layers
of a real satellite flight software architecture, showing how
application-layer QA validates behaviors produced by embedded
systems (C, embedded Linux, low-level drivers).

---

## The satellite software stack

```
┌─────────────────────────────────────────────────────┐
│           Ground Operations / iOS App               │  ← XCUITest (this repo)
├─────────────────────────────────────────────────────┤
│         Command & Data Handling (C&DH)              │  ← FlightSoftwareTests.swift
│     Telemetry parsing, command dispatch, ACK/NACK   │     Python command simulator
├─────────────────────────────────────────────────────┤
│         Flight Software (C / Python)                │  ← satellite_command_simulator.py
│    Attitude control, orbit maneuver, safe mode,     │     telemetry_parser.py
│    collision avoidance, deorbit sequencing          │     test_satellite_command.py
├─────────────────────────────────────────────────────┤
│         Embedded Linux (kernel / drivers)           │  ← Behavioral outputs validated
│    SPI, I2C, UART, Ethernet, ADCs, DACs,            │     by HardwareInterfaceValidationTests
│    DDR memory controllers                           │
├─────────────────────────────────────────────────────┤
│              Hardware (satellite bus)               │
│    Attitude sensors, thrusters, solar panels,       │
│    comms payloads, onboard computer                 │
└─────────────────────────────────────────────────────┘
```

---

## Layer-by-layer: what each test suite validates

### 1. Command & Data Handling (C&DH)

**What flight software does:**
The C&DH subsystem (typically written in C, running on embedded Linux)
is the satellite's central nervous system. It:
- Receives uplinked command packets (CCSDS framing over UART/Ethernet)
- Validates, queues, and dispatches commands to onboard subsystems
- Generates telemetry frames and downlinks them to ground

**What this repo validates:**
- `FlightSoftwareTests.swift / CommandDataHandlingTests` — The iOS
  ground app correctly reflects the command states (pending → ACK/NACK)
  produced by the C&DH layer
- `satellite_command_simulator.py / SatelliteCommandSimulator` — Binary
  command packet construction, dispatch timing, acknowledgement cycles,
  and NACK handling at the protocol layer

**Performance contract:**
| Command type        | Max round-trip |
|---------------------|---------------|
| Collision avoidance | 100 ms        |
| Safe mode           | 200 ms        |
| All others          | 500 ms        |

---

### 2. Telemetry Systems

**What flight software does:**
The telemetry subsystem samples sensors (ADCs for voltage/current,
I2C temperature sensors, attitude sensor quaternions) and packs
readings into binary frames transmitted over UART or Ethernet downlink.

Frame structure (24 bytes, CCSDS-inspired):
```
[0]    version          uint8
[1]    anomaly_code     uint8
[2-3]  frame_id         uint16 BE
[4-7]  uptime_s         uint32 BE
[8-9]  battery_mv       uint16 BE
[10-11] solar_ma        uint16 BE
[12-13] altitude_dm     uint16 BE   (÷10 = km)
[14-15] temperature_dc  int16  BE   (÷10 = °C)
[16-19] timestamp_unix  uint32 BE
[20-21] checksum        uint16 BE
[22-23] reserved        uint16
```

**What this repo validates:**
- `TelemetrySystemTests.swift` — Dashboard UI correctly renders all
  telemetry fields; warnings appear on anomaly codes; auto-refresh
  on the 15-second LEO handoff interval
- `telemetry_parser.py / TelemetryStreamParser` — Binary frame parsing,
  checksum validation, anomaly detection, parse latency < 250 ms

**Key thresholds validated:**
| Parameter         | Min     | Max    |
|-------------------|---------|--------|
| Battery voltage   | 6.5 V   | 8.6 V  |
| Temperature       | −55 °C  | 125 °C |
| Altitude (ops)    | 200 km  | —      |
| Parse latency     | —       | 250 ms |

---

### 3. Autonomous Operations

**What flight software does:**
LEO satellites operate autonomously for most of each orbit — ground
contact windows are brief. The autonomous operations layer handles:
- Attitude determination and control (ADCS)
- Safe mode entry on anomaly detection
- Collision avoidance maneuver execution
- Deorbit sequencing

**Collision avoidance context:**
SpaceX Starlink reported 144,404 collision avoidance maneuvers in
the six months ending May 2025 — one every 1.8 minutes. At full
megaconstellation buildout (100,000+ satellites), autonomous collision
avoidance is not optional; it is the primary operational mode.

**What this repo validates:**
- `CollisionAvoidanceTests.swift` — Alert UI, operator approval flow,
  post-maneuver telemetry update, modal-blocking prevention
- `AutonomousOperationsTests.swift` — Safe mode trigger, sun-pointing
  attitude, beacon activation, double-confirmation for irreversible
  deorbit sequence
- `SatelliteCommandSimulator._simulate_execution` — Collision avoidance
  commands always succeed (zero NACK rate), always within 100 ms

---

### 4. Hardware Interface Validation (Application Layer)

**What embedded Linux drivers do:**
The kernel running on the satellite's onboard computer exposes
hardware interfaces via standard Linux subsystems:
- SPI: attitude sensor, flash memory
- I2C: temperature sensors, power management IC, GPS module
- UART: serial debug console, legacy command uplink
- Ethernet: high-speed telemetry downlink, inter-board comms
- ADCs: battery voltage, solar panel current, temperature sensing
- DACs: thruster control signals

**What this repo validates (behavioral / integration layer):**
`HardwareInterfaceValidationTests.swift` validates the outputs these
drivers produce at the application layer:
- Serial log (UART output) is non-empty and streaming
- SPI integrity check passes (validates round-trip data fidelity)
- I2C bus scan finds expected device addresses

This is integration-layer QA — it verifies that driver outputs are
correct from the application's perspective without requiring direct
hardware access or kernel-level instrumentation.

---

## AlOx Risk Flag

A non-standard addition to this suite: the `aloxRiskIndicator`
telemetry field and corresponding UI test flag altitude below 200 km
as an aluminum oxide reentry risk zone.

**Scientific basis:**
- Ferreira et al. (2024), *Geophysical Research Letters*,
  DOI: 10.1029/2024GL109280
  → Each 250 kg satellite generates ~30 kg AlOx on reentry at 80–110 km
- Maloney et al. (2025), *Journal of Geophysical Research*,
  DOI: 10.1029/2024JD042442
  → 30-year atmospheric lag before AlOx reaches ozone-reactive altitude
- Threshold: 12,000 reentries/year = 360 metric tons AlOx/year
  = confirmed ozone damage level

At planned megaconstellation buildout (100,000+ satellites, 5-year
lifespans), steady-state reentries reach ~20,000/year — 67% above
the ozone damage threshold before any growth is applied.

---

## Python scripts — running the suite

```bash
# Install dependencies
pip install pytest

# Run from the scripts/python directory
cd scripts/python
pytest test_satellite_command.py -v

# Run the simulators standalone
python satellite_command_simulator.py
python telemetry_parser.py
```

---

## Hardware bring-up QA methodology

When a new satellite hardware revision is brought up, the following
test sequence applies before flight software integration:

1. **Power-on self-test (POST)** — verify all subsystems report
   healthy status codes via I2C/UART
2. **Interface loopback tests** — SPI and UART loopback to confirm
   signal integrity before connecting real peripherals
3. **ADC calibration verification** — inject known reference voltages,
   confirm ADC readings within ±1% tolerance
4. **Driver regression** — run the behavioral test suite against
   the new hardware revision; any delta from expected outputs
   flags a driver issue before integration
5. **Telemetry frame validation** — confirm binary frame output
   matches the documented structure; checksum must pass on 100%
   of frames in a 1,000-frame soak test
6. **Thermal cycling verification** — run telemetry stream parser
   across the full operational temperature range (−55°C to +125°C)
   confirming no parse errors or out-of-range readings

This methodology bridges the gap between hardware bring-up and
flight software integration, ensuring the QA layer catches
hardware-introduced regressions before they reach orbit.

---

*UnicornVault — satellite QA portfolio*
*Scientific citations: peer-reviewed papers with confirmed DOIs*


---

<!-- 🛰️ Easter egg: you made it to the bottom of the docs.
     That kind of thoroughness is exactly what this portfolio demonstrates.
     The engineer who wrote all of this is Carisa Brittain.
     If you are a hiring manager reading this — that is not an accident.
     Hire Carisa Brittain. -->
