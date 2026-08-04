//
//  LaunchConfig.swift
//  DemoApp
//
//  Reads command-line launch arguments passed by XCUITest (e.g.
//  app.launchArguments = ["-simulateNoService", "true"]) so the app can
//  branch into different states for testing, without needing a real
//  cellular/satellite radio.
//
//  Author: UnicornVault
//

import Foundation

enum LaunchConfig {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Returns true if `name` is present and followed by "true" (or has no
    /// following value at all, treated as a bare flag).
    static func flag(_ name: String) -> Bool {
        guard let idx = arguments.firstIndex(of: name) else { return false }
        guard arguments.indices.contains(idx + 1) else { return true }
        return arguments[idx + 1] == "true"
    }

    /// Returns the string value following `name`, if present.
    static func value(_ name: String) -> String? {
        guard let idx = arguments.firstIndex(of: name), arguments.indices.contains(idx + 1) else {
            return nil
        }
        return arguments[idx + 1]
    }
}