import SwiftUI

@main
struct whoa_typeApp: App {
    @State private var coordinator = AppCoordinator()
    var body: some Scene {
        MenuBarExtra("Whoa Type", image: "MenuBarLogo") {
            MenuBarView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}
