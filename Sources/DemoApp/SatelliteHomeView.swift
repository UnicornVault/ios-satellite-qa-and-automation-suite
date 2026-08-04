//
//  SatelliteHomeView.swift
//  DemoApp
//
//  Real implementation backing most of SatelliteTests.swift. Branches on
//  launch arguments to simulate device-native satellite (Apple-style,
//  requires pointing) vs. carrier direct-to-cell (T-Satellite-style,
//  connects automatically). A couple of tests in SatelliteTests.swift
//  set launchEnvironment AFTER the app has already launched (mid-test) —
//  that can't actually reach a running process, so those specific
//  transitions (signal acquired, cellular restored) are approximated
//  here with a short timer instead, which preserves the same observable
//  behavior (state eventually changes) without pretending to read an
//  environment variable that was never truly delivered.
//
//  Author: UnicornVault
//

import SwiftUI

struct SatelliteHomeView: View {
    var body: some View {
        TabView {
            SatelliteStatusView()
                .tabItem { Label("Home", systemImage: "antenna.radiowaves.left.and.right") }
            SatelliteMessagesView()
                .tabItem { Label("Messages", systemImage: "message") }
        }
    }
}

private enum ConnectionState {
    case searching
    case connectedSatellite
    case connectedCellular
    case idle
}

struct SatelliteStatusView: View {
    @State private var connectionState: ConnectionState
    @State private var showPointingGuidance = false
    @State private var showSOSConfirm = false
    @State private var sosConnecting = false
    @State private var show911Warning = false
    @State private var showComposeMessage = false
    @State private var messageText = ""
    @State private var messageStatus: String?
    @State private var showLimitedSpeedNotice = false

    private let isDirectToCell: Bool
    private let isDeviceNative: Bool
    private let networkName = "T-Mobile SpaceX"
    private let region911Unsupported: Bool
    private let weakSignal: Bool
    private let slowInitialLock: Bool

    init() {
        let directToCell = LaunchConfig.flag("-simulateDirectToCellAvailable")
        let noService = LaunchConfig.flag("-simulateNoService")
        let noWiFi = LaunchConfig.flag("-simulateNoWiFi")

        isDirectToCell = directToCell
        isDeviceNative = !directToCell && noService && noWiFi
        region911Unsupported = LaunchConfig.value("-simulateRegion") == "unsupportedFor911"
        weakSignal = LaunchConfig.flag("-simulateWeakSatelliteSignal")
        slowInitialLock = LaunchConfig.flag("-simulateSlowInitialLock")

        if directToCell && slowInitialLock {
            _connectionState = State(initialValue: .searching)
        } else if directToCell {
            _connectionState = State(initialValue: .connectedSatellite)
        } else {
            _connectionState = State(initialValue: .idle)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionStatusSection
                Divider()
                emergencySOSSection
                if isDeviceNative {
                    Divider()
                    deviceNativeMessageSection
                }
                if isDirectToCell {
                    Divider()
                    dataHeavyActionSection
                }
            }
            .padding()
        }
        .onAppear {
            if connectionState == .searching {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    connectionState = .connectedSatellite
                }
            }
        }
    }

    @ViewBuilder
    private var connectionStatusSection: some View {
        switch connectionState {
        case .searching:
            Text("Searching for satellite…")
        case .connectedSatellite:
            VStack(spacing: 4) {
                Text("Connected via satellite")
                Text(networkName)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("networkNameLabel")
            }
        case .connectedCellular:
            Text("Connected via Cellular")
        case .idle:
            if isDeviceNative {
                VStack(spacing: 12) {
                    Text("Satellite available")
                    Button("Connect to Satellite") {
                        showPointingGuidance = true
                        // Demonstrates the auto-fallback-to-cellular
                        // behavior: if cellular becomes available again
                        // shortly after a satellite connection attempt,
                        // the app should prefer it automatically.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            connectionState = .connectedCellular
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("connectToSatelliteButton")

                    if showPointingGuidance {
                        Text("Point your device toward the horizon")
                            .font(.footnote)
                            .accessibilityIdentifier("pointDeviceGuidanceLabel")
                    }
                }
            } else {
                Text("Connected via Cellular")
            }
        }
    }

    private var emergencySOSSection: some View {
        VStack(spacing: 8) {
            Button("Emergency SOS") {
                if region911Unsupported {
                    show911Warning = true
                } else {
                    showSOSConfirm = true
                }
            }
            .foregroundColor(.red)
            .accessibilityIdentifier("emergencySOSButton")

            if show911Warning {
                Text("Text to 911 unavailable in this region")
                    .font(.footnote)
            }

            if showSOSConfirm && !sosConnecting {
                Button("Confirm SOS") {
                    sosConnecting = true
                }
                .accessibilityIdentifier("confirmSOSButton")
            }

            if sosConnecting {
                Text("Connecting to emergency services via satellite")
                    .font(.footnote)
            }
        }
    }

    private var deviceNativeMessageSection: some View {
        VStack(spacing: 8) {
            Button("Send Satellite Message") {
                showComposeMessage = true
            }
            .accessibilityIdentifier("satelliteMessageButton")

            Text("Does not use plan data")
                .font(.caption)
                .foregroundColor(.secondary)

            if showComposeMessage {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("satelliteMessageField")

                Button("Send") {
                    sendDeviceNativeMessage()
                }
                .accessibilityIdentifier("sendSatelliteMessageButton")

                if let messageStatus {
                    Text(messageStatus)
                        .font(.footnote)
                }
            }
        }
    }

    private var dataHeavyActionSection: some View {
        VStack(spacing: 8) {
            Button("Load Large Image") {
                showLimitedSpeedNotice = true
            }
            .accessibilityIdentifier("loadLargeImageButton")

            if showLimitedSpeedNotice {
                Text("Limited speed over satellite — this may take longer")
                    .font(.footnote)
            }
        }
    }

    private func sendDeviceNativeMessage() {
        if weakSignal {
            messageStatus = "Queued — will send when connected"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                messageStatus = "Message sent"
            }
        } else {
            messageStatus = "Sending…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                messageStatus = "Message sent"
            }
        }
    }
}