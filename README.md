# iOS Automation Portfolio — XCUITest + GitHub Actions

![iOS Tests](https://github.com/yourusername/yourrepo/actions/workflows/ios-tests.yml/badge.svg)

A sample XCUITest suite demonstrating automated UI testing for iOS, built to run entirely
through GitHub Actions using free macOS runners — no local Mac required to maintain or extend.

## Flagship: satellite connectivity testing

The **`Satellite/`** suite is the centerpiece of this repo. It covers both real,
currently-shipping satellite technologies — verified against current sources, not assumed:

- **Device-native satellite** (Apple's model) — dedicated Globalstar satellites, manual
  pointing guidance, used for Emergency SOS and off-grid messaging since iPhone 14.
- **Carrier direct-to-cell** (T-Mobile + Starlink's "T-Satellite") — the carrier's own
  spectrum relayed via low-orbit satellites acting as cell towers in space. No pointing
  required; connects automatically inside the phone's regular messaging app.

It also tests something with no equivalent anywhere else in this repo: **satellite
handoff behavior**. Low-orbit satellites move fast enough that the phone disconnects
from one and reconnects to the next roughly every 15 seconds — these tests confirm a
message survives a handoff mid-send, the app shows a patient "searching" state instead
of an alarming error while the initial lock happens, and routine reconnects don't spam
the user with a notification every time. Ground-based cellular testing has no version of
this scenario, since a cell tower doesn't physically move.

**All 17 satellite tests run against a real SwiftUI implementation** — see
`Sources/DemoApp/SatelliteHomeView.swift` and `SatelliteMessagesView.swift` — not just
written as hypothetical assertions. They execute via the "Demo App — Proof of Concept"
GitHub Actions workflow on a free macOS runner. One honest caveat: two of the original
test scenarios set `launchEnvironment` *after* the app has already launched, which can't
actually reach a running process — those specific mid-session transitions are approximated
with a short timer instead, documented directly in the view's code comments.

## What this demonstrates

- Writing and structuring XCUITest suites in Swift
- CI/CD integration: tests run automatically on every push and pull request via GitHub Actions
- Test design across multiple categories, not just happy-path clicking
- Reusable helper functions and a maintainable page-object-style structure
- Verifying real-world technical claims against current sources before writing tests
  around them, rather than assuming a feature works the way it's commonly described

## Project structure

```
.
├── .github/workflows/ios-tests.yml   # CI pipeline: smoke on every PR, full regression nightly
├── TestPlans/
│   ├── Smoke.xctestplan              # Critical-path subset for fast feedback
│   └── FullRegression.xctestplan     # Entire suite, all genres
├── UITests/
│   ├── Satellite/                    # ⭐ FLAGSHIP — see above
│   │   └── SatelliteTests.swift      # Device-native + carrier direct-to-cell, handoff resilience
│   ├── LoginTests.swift              # Core auth flow: success, validation, error states
│   ├── NavigationTests.swift         # List/detail navigation, scrolling
│   ├── AdvancedTests.swift           # Permissions, lifecycle, network, deep links, accessibility, rotation
│   ├── Ecommerce/
│   │   └── EcommerceTests.swift      # Cart, promo codes, checkout, payment
│   ├── Social/
│   │   └── SocialTests.swift         # Feed, likes/comments, post creation, media upload
│   ├── Fintech/
│   │   └── FintechTests.swift        # Balance, transaction history, biometric-gated actions
│   ├── Productivity/
│   │   └── ProductivityTests.swift   # Offline-first editing, local persistence, sync conflicts
│   ├── AccountManager/
│   │   └── AccountManagerTests.swift # Client search, contact edits, permissions, reporting
│   ├── CloudProvisioning/
│   │   └── CloudProvisioningTests.swift # Automated bucket creation, naming validation, default privacy, teardown
│   ├── OpenOrderReport/
│   │   └── OpenOrderReportTests.swift # Interactive report: sorting, filtering, drill-down, summary accuracy
│   ├── Procurement/
│   │   └── ProcurementTests.swift    # Hourly project allocation, rollup to company P&L/open orders
│   ├── Telecom/
│   │   └── TelecomTests.swift        # Data usage, SIM activation, number porting, outages, billing
│   ├── AIAgent/
│   │   └── AIAgentTests.swift        # Guardrails, human-in-the-loop confirmation, prompt injection resistance, graceful degradation
│   ├── Purchasing/
│   │   └── PurchasingTests.swift     # Requisitions, approval thresholds, vendor comparison, POs, receiving, invoice matching
│   └── Helpers/
│       └── LoginHelper.swift         # Shared login helper used across test files
├── LICENSE
└── README.md
```

## Test categories covered

| Category | File | Examples |
|---|---|---|
| ⭐ **Satellite Connectivity (flagship)** | `Satellite/SatelliteTests.swift` | Device-native (Apple) vs. carrier direct-to-cell (T-Satellite/Starlink) models, Emergency SOS, pointing guidance, auto-connect with no pointing, network name verification, **handoff resilience** (mid-send survival, patient connection search, no notification spam) |
| Core auth flow | `LoginTests.swift` | Successful login, empty-field validation, wrong-password error |
| Navigation | `NavigationTests.swift` | List scrolling, detail view navigation, logout flow |
| Permissions | `AdvancedTests.swift` | System permission dialogs (location, camera, notifications) |
| App lifecycle | `AdvancedTests.swift` | Background/foreground state retention |
| Network conditions | `AdvancedTests.swift` | Loading states, offline handling |
| Deep linking | `AdvancedTests.swift` | Launch-argument-based deep link routing |
| Accessibility | `AdvancedTests.swift` | Accessibility label verification for VoiceOver support |
| Device rotation | `AdvancedTests.swift` | Layout assertions after orientation change |
| **E-commerce** | `Ecommerce/EcommerceTests.swift` | Cart badge updates, promo codes, checkout, declined payment handling |
| **Social/Content** | `Social/SocialTests.swift` | Feed loading, likes, comments, post creation, oversized media upload |
| **Fintech** | `Fintech/FintechTests.swift` | Balance display, transaction sorting, biometric-gated data, transfer limits |
| **Productivity/Utility** | `Productivity/ProductivityTests.swift` | Local persistence, offline editing, sync conflicts |
| **Account Manager/B2B SaaS** | `AccountManager/AccountManagerTests.swift` | Client search, contact edits, pipeline filtering, role-based permissions, report export |
| **Cloud Provisioning** | `CloudProvisioning/CloudProvisioningTests.swift` | Automated bucket creation, naming validation, default-private access, deletion, quota errors |
| **Interactive Open Order Report** | `OpenOrderReport/OpenOrderReportTests.swift` | Report loading, column sorting, status filtering, row drill-down, summary count accuracy |
| **Procurement/Resource Allocation** | `Procurement/ProcurementTests.swift` | Hourly project allocation, over-allocation limits, rollup accuracy to company open orders (~$30M) and P&L |
| **Telecom** | `Telecom/TelecomTests.swift` | Data usage, SIM/eSIM activation, porting, network/signal status, roaming, plan changes, Wi-Fi calling, hotspot, multi-line plans, billing, automation (auto network switching, data-limit syncing, auto-pay) — see the flagship row above for satellite |
| **AI/Agentic Features** | `AIAgent/AIAgentTests.swift` | Human-in-the-loop confirmation for high-stakes actions, proportionate guardrails, prompt-injection resistance, out-of-scope refusal, confidence/clarification prompts, AI-content labeling, graceful degradation, audit logging |
| **Purchasing/Buyer Tasks** | `Purchasing/PurchasingTests.swift` | Requisition creation, approval thresholds for high-value spend, vendor price comparison, requisition-to-PO conversion, receiving, invoice 3-way-match mismatch flagging |

## Smoke vs. full regression

As the suite grows, running every test on every PR gets slow. This repo splits tests into two tiers:

- **Smoke suite** (`TestPlans/Smoke.xctestplan`) — a small set of critical-path tests, tagged `[SMOKE]` in their doc comments, covering the flows that would block a release if broken (login, checkout, biometric security, offline sync). Runs on every push and pull request for fast feedback.
- **Full regression suite** (`TestPlans/FullRegression.xctestplan`) — every test across all genres. Runs nightly via a scheduled GitHub Actions job, so it doesn't slow down day-to-day development.

**How the suite grows over time:** every bug found after release gets a new regression test added here, so it can never silently reappear. Tests that turn out to be flaky (intermittent failures unrelated to real bugs) get flagged and fixed or quarantined rather than left to erode trust in the suite.

## Running locally (requires macOS + Xcode)

```bash
xcodebuild test \
  -project YourApp.xcodeproj \
  -scheme YourApp \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Running via CI (no Mac needed)

Every push and pull request to `main` triggers `.github/workflows/ios-tests.yml`, which runs
the full suite on a GitHub-hosted `macos-latest` runner. Results appear in the **Actions** tab,
and failed runs upload an `.xcresult` artifact with detailed logs.

## Tech stack

- **Language:** Swift
- **Framework:** XCUITest (XCTest UI testing)
- **CI/CD:** GitHub Actions (macOS runner)
- **Simulator target:** iPhone 15, iOS Simulator

## Why this approach

This repo was built to demonstrate XCUITest proficiency without requiring local Mac hardware —
all test authoring happens in any standard editor, and GitHub Actions' free macOS runners (on
public repos) handle execution and validation. This mirrors a common real-world setup where
test code is written and reviewed cross-platform but executed in a controlled CI environment.

## Related skills

This suite is part of a broader automation background covering:
- **Espresso** (Android UI automation)
- **Karate Framework** (API automation)
- General QA methodology, SDLC/STLC, and automated test framework design

## Author

**UnicornVault**

## License

MIT — see [LICENSE](./LICENSE) for details.

## Disclaimer

This is an independent portfolio project for demonstration purposes. Company and product
names referenced (Apple, T-Mobile, Starlink, etc.) are used descriptively to illustrate
real-world testing scenarios and are trademarks of their respective owners. This project is
not affiliated with, endorsed by, or sponsored by any of the companies mentioned.


**UnicornVault**

## License

MIT — see [LICENSE](./LICENSE) for details.
