import AppKit

/// Decides whether a key-down event is a plain Delete press that should be
/// routed to the visible canvas editor. Editable text always wins: while the
/// first responder edits text, Delete means character deletion and must never
/// become a canvas verb. Shift and the function flag stay permitted because
/// forward-delete events carry `.function` and Shift+Delete is still the
/// delete verb on the canvas.
enum DeleteKeyGate {
    static let deleteKeyCode: UInt16 = 51
    static let forwardDeleteKeyCode: UInt16 = 117

    static func shouldRoute(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        firstResponderEditsText: Bool
    ) -> Bool {
        guard keyCode == deleteKeyCode || keyCode == forwardDeleteKeyCode else {
            return false
        }
        guard modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }
        return !firstResponderEditsText
    }
}
