import SwiftUI
import AppKit

/// Opens the entry editor as a real floating NSWindow rather than a SwiftUI sheet,
/// so it survives the menu-bar popover auto-dismissing on focus changes (e.g. when
/// a DatePicker is clicked).
@MainActor
final class EditorCoordinator {
    static let shared = EditorCoordinator()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func open(day: String, mode: EntryEditorSheet.Mode, onSave: @escaping () -> Void) {
        closeWindow()

        let view = EntryEditorSheet(
            day: day,
            mode: mode,
            onSave: { [weak self] in
                onSave()
                self?.closeWindow()
            },
            onCancel: { [weak self] in
                self?.closeWindow()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = {
            switch mode {
            case .edit: return "Edit entry"
            case .create: return "Add entry"
            }
        }()
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.window = nil }
        }
        window = w
    }

    private func closeWindow() {
        window?.close()
        window = nil
    }
}
