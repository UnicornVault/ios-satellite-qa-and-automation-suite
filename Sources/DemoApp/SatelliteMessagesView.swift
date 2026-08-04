//
//  SatelliteMessagesView.swift
//  DemoApp
//
//  Backs the direct-to-cell tests that send from the standard messaging
//  screen rather than a dedicated satellite composer — matching how
//  T-Satellite actually works.
//
//  Author: UnicornVault
//

import SwiftUI

struct SatelliteMessagesView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: MessageComposeView()) {
                    VStack(alignment: .leading) {
                        Text("Trail Buddy")
                            .font(.headline)
                        Text("Tap to open conversation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Messages")
        }
    }
}

struct MessageComposeView: View {
    @State private var messageText = ""
    @State private var status: String?

    private let sendFailureThenRetry = LaunchConfig.flag("-simulateSendFailureThenRetrySuccess")

    var body: some View {
        VStack(spacing: 12) {
            if let status {
                Text(status)
                    .font(.footnote)
            }

            TextField("Message", text: $messageText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("messageComposerField")

            Button("Send") {
                send()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("sendMessageButton")

            Spacer()
        }
        .padding()
    }

    private func send() {
        if sendFailureThenRetry {
            status = "Sending — retrying"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                status = "Sent via satellite"
            }
        } else {
            // Covers both the plain send case and the mid-send-handoff
            // case: a real handoff gap is milliseconds, so from the UI's
            // perspective it never surfaces as a distinct visible state —
            // the send just completes slightly later than usual.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                status = "Sent via satellite"
            }
        }
    }
}