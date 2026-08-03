//
//  DemoApp.swift
//  DemoApp — a real, minimal app built specifically so the UITests in
//  this repo have something genuine to run against.
//
//  Author: UnicornVault
//

import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            LoginView()
        }
    }
}
