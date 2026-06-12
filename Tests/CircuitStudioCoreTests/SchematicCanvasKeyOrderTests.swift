import Foundation
import Testing

/// `.focusable()` must come before `.onKeyPress` in the schematic canvas
/// modifier chain. Key events dispatch from the focused view outward, so
/// a handler applied inside `.focusable()` never receives any key —
/// Delete, shortcuts, everything silently dies — and no in-process test
/// can notice (SwiftUI only dispatches keys under a running, active
/// `NSApplication` event loop). Verified empirically with a standalone
/// probe app driven by real HID key events; the arrangement is pinned at
/// the source level.
@Suite("Schematic Canvas Key Order")
struct SchematicCanvasKeyOrderTests {

    @Test func canvasAppliesOnKeyPressOutsideFocusable() throws {
        let canvasSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CircuitStudioCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/SchematicEditor/Views/SchematicCanvas.swift")
        let source = try String(contentsOf: canvasSource, encoding: .utf8)

        let focusable = try #require(
            source.range(of: ".focusable()"),
            "SchematicCanvas must declare the canvas focusable"
        )
        let keyPress = try #require(
            source.range(of: ".onKeyPress"),
            "SchematicCanvas must handle key presses"
        )
        #expect(
            focusable.lowerBound < keyPress.lowerBound,
            ".onKeyPress must be applied after .focusable(): key events dispatch from the focused view outward, so a handler inside .focusable() never receives any key"
        )
    }
}
