//
//  XcircuiteUITests.swift
//  XcircuiteUITests
//
//  Created by 1amageek on 2026/02/15.
//

import XCTest

final class XcircuiteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsWorkspacePicker() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.segmentedControls["workspace-picker"].waitForExistence(timeout: 5),
            "The main CircuitStudio workspace picker should be visible after launch."
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
