import AppKit

/// Quit guard: blocks termination while the session holds unsaved changes,
/// offering the standard save / discard / cancel choice. The dirty check
/// and save behavior are injected by the app so the delegate stays free of
/// document knowledge.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Returns true when any document state is unsaved.
    public var hasUnsavedChanges: (() -> Bool)?
    /// Performs the same save as the File menu's Save command.
    public var performSave: (() async -> Bool)?

    public func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard hasUnsavedChanges?() == true else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Save your changes before quitting?"
        alert.addButton(withTitle: "Save and Quit")
        alert.addButton(withTitle: "Cancel")
        let discardButton = alert.addButton(withTitle: "Quit Without Saving")
        discardButton.hasDestructiveAction = true

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                let saved = await performSave?() ?? false
                sender.reply(toApplicationShouldTerminate: saved)
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
