import SwiftUI
import AppKit

/// Opens the preferences pane as a floating NSWindow so it doesn't get killed
/// by the menu-bar popover dismissing on focus change.
@MainActor
final class PreferencesCoordinator {
    static let shared = PreferencesCoordinator()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func open() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: PreferencesView())
        let w = NSWindow(contentViewController: hosting)
        w.title = "Preferences"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let obs = closeObserver { NotificationCenter.default.removeObserver(obs) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.window = nil }
        }
        window = w
    }
}
