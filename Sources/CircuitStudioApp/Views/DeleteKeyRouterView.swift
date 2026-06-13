import AppKit
import SwiftUI

/// Window-level fallback route for the Delete key. SwiftUI delivers key
/// events only to the focused view, so when focus sits on a navigator list,
/// the console, or an inspector control, Delete reaches no handler and the
/// system beeps even though the user's intent is the visible canvas
/// selection. This view installs a local key-down monitor that routes plain
/// Delete to the active editor's delete verb. The monitor stands down while
/// `action` is nil (an editor subtree holds focus), while the first responder
/// edits text, and for events belonging to other windows (sheets, popovers).
struct DeleteKeyRouterView: NSViewRepresentable {
    let action: RoutedDeleteAction?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(hostView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var action: RoutedDeleteAction?
        private weak var hostView: NSView?
        private var monitor: Any?

        func install(hostView: NSView) {
            self.hostView = hostView
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Local monitors fire on the main thread; NSEvent is not
                // Sendable, so only the swallow decision crosses the closure.
                let swallow = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.shouldSwallow(event)
                }
                return swallow ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            action = nil
        }

        /// Swallows the event only when the delete verb actually deleted
        /// something; otherwise the event propagates unchanged so text
        /// editing, the focused canvas, and system feedback keep their
        /// native behavior.
        private func shouldSwallow(_ event: NSEvent) -> Bool {
            guard
                let action,
                let window = hostView?.window,
                event.window === window
            else { return false }

            let editsText = (window.firstResponder as? NSText)?.isEditable == true
            guard
                DeleteKeyGate.shouldRoute(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    firstResponderEditsText: editsText
                )
            else { return false }

            return action()
        }
    }
}
