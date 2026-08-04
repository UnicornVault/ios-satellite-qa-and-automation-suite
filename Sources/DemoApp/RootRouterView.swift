//
//  RootRouterView.swift
//  DemoApp
//
//  Real apps commonly branch their root view for test builds based on
//  launch arguments. Here: if satellite-triggering flags are present,
//  skip straight to the satellite demo (matching how SatelliteTests.swift
//  launches and interacts immediately, with no login step). Otherwise,
//  the normal login flow (LoginTests.swift, NavigationTests.swift) runs.
//
//  Author: UnicornVault
//

import SwiftUI

struct RootRouterView: View {
    var body: some View {
        if LaunchConfig.flag("-simulateDirectToCellAvailable")
            || (LaunchConfig.flag("-simulateNoService") && LaunchConfig.flag("-simulateNoWiFi")) {
            SatelliteHomeView()
        } else {
            LoginView()
        }
    }
}