//
//  XcircuiteTests.swift
//  XcircuiteTests
//
//  Created by 1amageek on 2026/02/15.
//

import Testing
@testable import XcircuiteAppHost

struct XcircuiteTests {

    @Test("App host delegates to the shared CircuitStudio app entry point")
    func appHostDelegatesToCircuitStudioApp() {
        #expect(Xcircuite.hostedAppTypeName == "CircuitStudioApp")
    }
}
