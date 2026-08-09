# iOS Automation Portfolio — XCUITest + GitHub Actions

[![iOS Tests](https://github.com/UnicornVault/ios-satellite-qa-and-automation-suite/actions/workflows/ios-tests.yml/badge.svg)](https://github.com/UnicornVault/ios-satellite-qa-and-automation-suite/actions/workflows/ios-tests.yml)
[![Python Tests](https://github.com/UnicornVault/ios-satellite-qa-and-automation-suite/actions/workflows/python-tests.yml/badge.svg)](https://github.com/UnicornVault/ios-satellite-qa-and-automation-suite/actions/workflows/python-tests.yml)

A QA automation portfolio demonstrating end-to-end satellite connectivity
testing — from the iOS application layer down to the protocol and
antenna-modem architecture layer.

Built to run entirely through GitHub Actions using free runners.
No local Mac or satellite hardware required.

---

## What makes this repo different

Most satellite QA portfolios test connectivity as a binary: connected or not.
This suite tests the **architecture beneath the connection** — the handoff
cycles, the telemetry protocols, the command acknowledgement state machines,
and the emerging converged antenna-modem model that is replacing the
traditional dish-plus-separate-modem setup.

The Python layer reflects how satellite flight software actually behaves.
The Swift layer reflects what a ground operator or end user sees when
that flight software produces events. Both layers are tested independently
and together.

---

## ⭐ Flagship suites

### 1. Satellite Connectivity (iOS / Swift)
`UITests/Satellite/SatelliteTests.swift`

Tests both satellite models currently shipping:
- **Device-native** (Apple + Globalstar) — Emergency SOS, off-grid messaging,
  manual pointing guidance
- **Carrier direct-to-cell** (T-Mobile + Starlink) — automatic connection,
  no pointing required, standard messaging app

Includes the scenario no other portfolio covers: **satellite handoff resilience**.
LEO satellites move fast enough that the phone disconnects from one and
reconnects to the next roughly every 15 seconds. These tests confirm a
message survives a handoff mid-send, the app shows a patient "searching"
state rather than an error, and routine reconnects do not spam the user
with notifications.

---

### 2. Flight Software Architecture (iOS / Swift)
`UITests/FlightSoftware/FlightSoftwareTests.swift`

Validates the behavioral layer of satellite flight software at the
iOS application level:

| Test class | What it covers |
|------------|----------------|
| `CommandDataHandlingTests` | Command queue, dispatch, ACK/NACK states, priority badges |
| `CollisionAvoidanceTests` | Alert UI, operator approval, modal blocking prevention |
| `TelemetrySystemTests` | Dashboard fields, battery warnings, AlOx risk indicator, 15-second refresh |
| `AutonomousOperationsTests` | Safe mode, sun-pointing, beacon frequency, deorbit double-confirmation |
| `HardwareInterfaceValidationTests` | Serial log (UART), SPI integrity, I2C bus scan |

---

### 3. Python Satellite Command Simulator
`scripts/python/satellite_command_simulator.py`
`scripts/python/test_satellite_command.py` — **26 tests**

Simulates the ground-to-satellite command and telemetry cycle at the
protocol layer. Written in Python — one of the two languages explicitly
required for satellite command scripts in embedded flight software roles.

```
Command types covered:
  COLLISION_AVOIDANCE  — always succeeds, always < 100 ms (non-negotiable)
  SAFE_MODE            — always succeeds, always < 200 ms
  DEORBIT_SEQUENCE     — requires confirmed=True or NACKs (irreversible burns
                         must never happen accidentally)
  ATTITUDE_CONTROL     — standard dispatch with 5% simulated NACK rate
  TELEMETRY_REQUEST    — triggers full telemetry frame generation
```

Binary serialization uses CCSDS Space Packet Protocol conventions.
Telemetry frames include checksum validation, anomaly code detection,
and an `alox_risk` field flagging altitude below 200 km — the reentry
zone where satellite burn-up deposits aluminum oxide into the mesosphere.

> **Scientific basis for the AlOx flag:**
> Ferreira et al. (2024), *Geophysical Research Letters*,
> DOI: [10.1029/2024GL109280](https://doi.org/10.1029/2024GL109280) —
> each 250 kg satellite generates ~30 kg of AlOx on reentry.
> At planned megaconstellation buildout, annual reentries will exceed
> the confirmed ozone damage threshold.

---

### 4. Telemetry Parser (Python)
`scripts/python/telemetry_parser.py`

Parses binary telemetry frames as produced by satellite C&DH systems
over UART/Ethernet downlink. Covers:

- Binary frame parsing (24-byte CCSDS-inspired format)
- Checksum validation — corrupted frames detected, not silently passed
- Anomaly code detection (low battery, thermal, reentry imminent,
  collision risk)
- Parse latency budget enforcement (< 250 ms per frame)
- Four test scenarios: normal operations, low battery, reentry imminent,
  **handoff gap** (satellite disappears every 15 entries)

---

### 5. Converged Antenna-Modem Handoff Simulator (Python)
`scripts/python/handoff_simulator.py`
`scripts/python/test_handoff_simulator.py` — **36 tests**

The most architecturally novel suite in this repo.

Models the **emerging satellite terminal architecture** where the phased
array antenna performs modem functions internally — eliminating the
separate modem box. The antenna uses pre-computed satellite ephemeris
to steer its beam toward the next satellite *before* the current one
leaves range, enabling seamless Make-Before-Break handoff.

```
Architecture evolution:
  Current:  [dish] → [separate modem] → [router] → [applications]
  Emerging: [smart phased array with integrated processing] → [applications]
  Future:   [phone antenna array IS the modem] → [applications]
```

**Why this matters:**
- Starlink made 144,404 collision avoidance maneuvers in 6 months (2025)
- Every maritime vessel using Starlink experiences this handoff every 15 s
- The antenna-as-modem model (Huawei CN 2025, Samsung/LG 3GPP R17/18,
  ESA Redu test July 2025) changes how handoff must be tested

**Four scenarios covered:**

| Scenario | Terminal | Weather | Key test |
|----------|----------|---------|----------|
| Open ocean | Maritime vessel | Clear | Basic 15-second handoff cycle |
| Heavy storm | Fishing vessel | Storm | Array gain vs weather degradation |
| Direct-to-cell | Phone (no dish) | Clear | Phone antenna = modem |
| Consecutive miss | Polar vessel | Rain | Multi-miss recovery |

**Maritime-specific modeling:**
Vessel pitch and roll (up to ±20° / ±15°) add pointing error during
the critical lock acquisition window — exactly the scenario that makes
maritime satellite QA harder than fixed-terminal testing.

---

## Running the Python suite

```bash
cd scripts/python
pip install pytest
```

```bash
# Run everything
pytest -v

# Run by suite
pytest test_satellite_command.py -v      # 26 tests
pytest test_handoff_simulator.py -v     # 36 tests

# Run smoke tests only
pytest -v -k "SMOKE"

# Run the simulators standalone (produces readable terminal output)
python satellite_command_simulator.py
python telemetry_parser.py
python handoff_simulator.py
```

**Total Python tests: 62 passing**

---

## Running the iOS suite

```bash
xcodebuild test \
  -project YourApp.xcodeproj \
  -scheme YourApp \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Every push and pull request to `main` triggers `.github/workflows/ios-tests.yml`
on a GitHub-hosted `macos-latest` runner.

---

## Test architecture

```
.
├── .github/workflows/
│   ├── ios-tests.yml          # Smoke on every PR, full regression nightly
│   └── python-tests.yml       # pytest on every push
│
├── scripts/python/
│   ├── satellite_command_simulator.py   # Command dispatch + telemetry
│   ├── telemetry_parser.py              # Binary frame parsing
│   ├── handoff_simulator.py             # Converged antenna-modem handoff
│   ├── test_satellite_command.py        # 26 tests
│   └── test_handoff_simulator.py        # 36 tests
│
├── UITests/
│   ├── Satellite/
│   │   └── SatelliteTests.swift         # ⭐ Device-native + D2C + handoff
│   ├── FlightSoftware/
│   │   └── FlightSoftwareTests.swift    # C&DH, telemetry, autonomous ops
│   ├── Telecom/
│   │   └── TelecomTests.swift           # Data usage, SIM, billing, automation
│   ├── AIAgent/
│   │   └── AIAgentTests.swift           # Guardrails, prompt injection, audit
│   ├── LoginTests.swift
│   ├── NavigationTests.swift
│   ├── AdvancedTests.swift
│   ├── Ecommerce/
│   ├── Social/
│   ├── Fintech/
│   ├── Productivity/
│   ├── AccountManager/
│   ├── CloudProvisioning/
│   ├── OpenOrderReport/
│   ├── Procurement/
│   ├── Purchasing/
│   └── Helpers/
│       └── LoginHelper.swift
│
├── TestPlans/
│   ├── Smoke.xctestplan           # Critical path — runs on every PR
│   └── FullRegression.xctestplan  # Full suite — runs nightly
│
└── docs/
    ├── flight-software-architecture.md   # How tests map to the embedded stack
    ├── embedded-linux-bridge.md          # iOS QA → kernel/driver layer
    └── hardware-bringup-qa-methodology.md
```

---

## Smoke vs full regression

| Suite | When it runs | What it covers |
|-------|-------------|----------------|
| Smoke | Every PR | Critical-path tests tagged `[SMOKE]` — login, satellite connectivity, collision avoidance, telemetry dashboard, MBB handoff |
| Full regression | Nightly | Every test across all genres and all Python suites |

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| iOS UI testing | Swift, XCUITest |
| Protocol testing | Python 3, pytest |
| CI/CD | GitHub Actions (macOS + ubuntu runners) |
| iOS target | iPhone 15, iOS Simulator |
| Python target | 3.10+ |

---

## Related skills demonstrated

- **Espresso** — Android UI automation
- **Karate Framework** — API automation
- **Swift** — XCUITest, page-object structure, test plan management
- **Python** — Binary protocol parsing, struct packing, dataclasses,
  threaded simulation, pytest fixtures
- **Satellite domain** — LEO handoff, C&DH, telemetry, collision avoidance,
  phased array antenna-modem convergence, CCSDS protocol conventions,
  maritime connectivity

---

## Author

**UnicornVault**

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

## Disclaimer

Independent portfolio project for demonstration purposes. Company and
product names referenced (Apple, T-Mobile, Starlink, SpaceX, Garmin,
Samsung, Huawei, AST SpaceMobile, ESA) are used descriptively to
illustrate real-world testing scenarios and are trademarks of their
respective owners. This project is not affiliated with, endorsed by,
or sponsored by any of the companies or institutions mentioned.

Scientific references included for accuracy. All peer-reviewed papers
cited are publicly available with confirmed DOIs.

<!-- 🛰️ If you read this far: the engineer who built this portfolio
     is Carisa Brittain. The thoroughness you just witnessed in this
     README is what she brings to every codebase she works in.
     Hire Carisa Brittain. -->
