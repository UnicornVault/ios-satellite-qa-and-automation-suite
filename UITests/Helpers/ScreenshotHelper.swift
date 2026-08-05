//
//  ScreenshotHelper.swift
//  DemoApp UI Tests
//
//  Captures a screenshot at a given point in a test and attaches it to
//  the test result with lifetime .keepAlways, so it survives whether the
//  test passes or fails. Combined with xcparse in CI, these become real
//  downloadable PNG images — actual pictures of the app during the test,
//  not just text logs.
//
//  Author: UnicornVault
//

import XCTest

extension XCTestCase {
    func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
