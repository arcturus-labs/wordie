import SwiftUI

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

        }

        Settings {
            SettingsView()
                .frame(width: 450, height: 150)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            self.stripMenus()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func stripMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let keepTitles: Set<String> = [
            mainMenu.items.first?.title ?? "",
            "Edit"
        ]
        mainMenu.items.removeAll { item in
            !keepTitles.contains(item.title)
        }
    }
}
