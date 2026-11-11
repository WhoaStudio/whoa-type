import SwiftUI

@main
struct whoa_typeApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var menuBar

    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Whoa Type Settings…") { menuBar.coordinator.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: menuBar.coordinator.updater)
            }
        }
    }
}
