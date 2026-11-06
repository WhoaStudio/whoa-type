import SwiftUI

@main
struct whoa_typeApp: App {
    @State private var coordinator = AppCoordinator()
    var body: some Scene {
        MenuBarExtra("Whoa Type", image: "MenuBarLogo") {
            MenuBarView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Whoa Type Settings…") { coordinator.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: coordinator.updater)
            }
        }
    }
}
