import SwiftUI
import Carbon.HIToolbox

@main
struct WordieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}

            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .help) {}

            CommandGroup(replacing: .appInfo) {
                Button("About Wordie") {
                    NotificationCenter.default.post(name: .showAbout, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
                .frame(width: 450, height: 150)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(self, selector: #selector(showAboutWindow), name: .showAbout, object: nil)

        // Catch ⌘W globally within the app — hide window instead of closing
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "w" {
                self.hideMainWindow()
                return nil // consume the event
            }
            return event
        }

        registerGlobalHotkey()

        // Let SwiftUI create the window, then configure it
        DispatchQueue.main.async {
            self.captureMainWindow()
            self.stripMenus()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - NSWindowDelegate

    /// Intercept the red close button (and any other close path) — hide instead of destroy
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - Window management

    private func captureMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        mainWindow = window
        window.delegate = self
    }

    private func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    private func showMainWindow() {
        let wasHidden = mainWindow == nil || !mainWindow!.isVisible
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        }
        if wasHidden {
            NotificationCenter.default.post(name: .windowSummoned, object: nil)
        }
    }

    // MARK: - Global hotkey (⌃⌥W)

    private func registerGlobalHotkey() {
        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Store self pointer for the C callback
        let appDelegate = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.showMainWindow()
            }
            return noErr
        }, 1, &eventType, appDelegate, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x574F5244), id: 1) // "WORD"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_W),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // MARK: - About

    @objc func showAboutWindow() {
        let shortcuts = """
        Keyboard Shortcuts

        ⌃⌥W  Summon Wordie
        ⌘W    Hide window
        ⌘↩    Process / Accept All
        Esc   Reject All
        ⌘J    Next diff site
        ⌘K    Previous diff site
        ⌘Y    Accept selected site
        ⌘N    Reject selected site
        ⌘,    Settings
        """

        let alert = NSAlert()
        alert.messageText = "Wordie"
        alert.informativeText = """
        Refine text with Claude, review word-level diffs, and accept or reject changes individually or all at once.

        \(shortcuts)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Menu setup

    private func stripMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let keepTitles: Set<String> = [
            mainMenu.items.first?.title ?? "",
            "Edit"
        ]
        mainMenu.items.removeAll { item in
            !keepTitles.contains(item.title)
        }

        // Add "Hide Window" (⌘W) to the app menu, before Quit
        if let appMenu = mainMenu.items.first?.submenu {
            let quitIndex = appMenu.items.count - 1
            let hideItem = NSMenuItem(title: "Hide Window", action: #selector(hideWindowAction), keyEquivalent: "w")
            hideItem.target = self
            appMenu.insertItem(NSMenuItem.separator(), at: max(0, quitIndex))
            appMenu.insertItem(hideItem, at: max(0, quitIndex + 1))
        }
    }

    @objc private func hideWindowAction() {
        hideMainWindow()
    }
}

extension Notification.Name {
    static let showAbout = Notification.Name("showAbout")
    static let windowSummoned = Notification.Name("windowSummoned")
}
