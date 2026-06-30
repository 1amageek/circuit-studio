//
//  XcircuiteUITestsLaunchTests.swift
//  XcircuiteUITests
//
//  Created by 1amageek on 2026/02/15.
//

import XCTest

final class XcircuiteUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.segmentedControls["workspace-picker"].waitForExistence(timeout: 5),
            "The launch test should capture the initialized workspace chrome."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
