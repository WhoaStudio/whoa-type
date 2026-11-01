import SwiftUI
import ImageIO

private enum SettingsPane: String, CaseIterable, Identifiable {
    case playback = "Sound"
    case about = "About"
    case startup = "General"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .playback: "waveform"
        case .about: "info.circle.fill"
        case .startup: "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .playback: .pink
        case .about: .gray
        case .startup: .gray
        }
    }
}

struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var editingHotkey = false
    @State private var selection: SettingsPane? = .startup

    private var pane: SettingsPane { selection ?? .startup }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(.startup)
                sidebarHeading("Settings")
                sidebarRow(.playback)
                sidebarHeading("Whoa Type")
                sidebarRow(.about)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            .frame(width: 224)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    paneIcon(pane, size: 22)
                    Text(pane.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 0)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                    switch pane {
                    case .playback:
                        playbackSettingsGroups
                        soundEffectsSettingsGroup
                        switchSettingsGroups
                    case .about: aboutSettingsGroups
                    case .startup: startupSettingsGroups
                    }
                    }
                    .padding(16)
                }
                .font(.system(size: 13))
                .tint(.mint)
                .scrollContentBackground(.hidden)
                .controlSize(.regular)
                .pickerStyle(.menu)
            }
            .background(Color(nsColor: .settingsBackground))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .settingsBackground))
        .frame(width: 640, height: 620)
        .ignoresSafeArea(.container, edges: .top)

        .onAppear { coordinator.refresh() }
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        Button {
            selection = pane
        } label: {
            HStack(spacing: 8) {
                paneIcon(pane, size: 22)
                Text(pane.rawValue)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
            .background {
                if self.pane == pane {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.primary.opacity(0.09))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(self.pane == pane ? .isSelected : [])
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func paneIcon(_ pane: SettingsPane, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(pane.color.gradient
                .shadow(.inner(color: .white.opacity(0.32), radius: 1, x: 0, y: 1))
                .shadow(.inner(color: .black.opacity(0.20), radius: 2, x: 0, y: -1)))
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .imageScale(.medium)
                    .foregroundStyle(.white)
                    .frame(width: size, height: size, alignment: .center)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var playbackSettingsGroups: some View {
        SettingsGroup {
            SoundSettingsView(settings: coordinator.settings)
        } header: {
            EmptyView()
        } footer: {
            Text("Choose the physical layout of your keyboard. Switch previews play even when key sounds are off.")
        }
        if let error = coordinator.errorMessage {
            SettingsGroup {
                Text(error).foregroundStyle(.secondary)
                Button("Retry audio") { coordinator.refresh() }
            }
        }

    }

    @ViewBuilder private var switchSettingsGroups: some View {
        SettingsGroup("Recordings") {
            if coordinator.packs.isEmpty {
                Text("Switch recordings are unavailable. Retry loading the bundled library.")
                    .foregroundStyle(.secondary)
                Button("Retry loading") { coordinator.refresh() }
            }
            ForEach(coordinator.packs) { pack in
                Button {
                    coordinator.selectAndPreview(pack.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: coordinator.settings.selectedPackID == pack.id
                              ? "checkmark.circle.fill" : "circle")
                            .frame(width: 18)
                        Text(pack.name)
                        Spacer(minLength: 0)
                        if coordinator.previewing == pack.name {
                            Image(systemName: "waveform")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pack.name)
                .accessibilityValue(coordinator.settings.selectedPackID == pack.id ? "Selected" : "Not selected")
                .accessibilityHint("Selects and previews this recording")
                .accessibilityAddTraits(coordinator.settings.selectedPackID == pack.id ? .isSelected : [])

            }
        }
    }

    @ViewBuilder private var inputAccessSettingsGroups: some View {
        SettingsGroup("Input Access") {
            PermissionOnboardingView(permission: coordinator.permission, retry: coordinator.refresh)
        }
        SettingsGroup("Password fields") {
            Text("macOS Secure Input can pause keyboard sounds while you enter a password. Sounds resume when secure input ends.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var aboutSettingsGroups: some View {
        AboutKeyBanner {
            coordinator.preview(coordinator.settings.selectedPackID)
        }
        .disabled(coordinator.packs.isEmpty)
        SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("Share feedback, report a bug, or suggest an improvement to Whoa Type.")
                Label("Feedback and updates on GitHub", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Link("Send Feedback…", destination: URL(string: "https://github.com/WhoaStudio/whoa-type/issues")!)
                Link("View Project…", destination: URL(string: "https://github.com/WhoaStudio/whoa-type")!)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        SettingsGroup {
            LabeledContent("Whoa Type", value: "Keyboard sounds for macOS")
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        }
    }

    @ViewBuilder private var startupSettingsGroups: some View {
        SettingsGroup {
            Toggle("Start Whoa Type at login", isOn: Binding(
                get: { coordinator.loginItem.enabled },
                set: { coordinator.loginItem.setEnabled($0) }
            ))
            .toggleStyle(.switch)
        } header: {
            EmptyView()
        } footer: {
            Text("Whoa Type runs in the menu bar. Closing this window keeps keyboard sounds available.")
        }
        inputAccessSettingsGroups
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hotkey").foregroundStyle(.secondary)
                Spacer()
                Button("Edit…") { editingHotkey = true }
                    .accessibilityLabel("Configure sound hotkey")
            }
            .padding(.horizontal, 8)
            Button { editingHotkey = true } label: {
                SettingsGroup {
                    HStack(spacing: 6) {
                        shortcutKey("⇧").opacity(coordinator.hotkey.modifierChoice == 2 ? 1 : 0.35)
                        shortcutKey("⌃", caption: "ctrl").opacity(coordinator.hotkey.modifierChoice == 2 ? 0.35 : 1)
                        shortcutKey("⌥", caption: "opt").opacity(coordinator.hotkey.modifierChoice == 2 ? 0.35 : 1)
                        shortcutKey("⌘", caption: "cmd").opacity(coordinator.hotkey.modifierChoice == 0 ? 0.35 : 1)
                        shortcutKey(SoundHotkey.keys[SoundHotkey.keys.indices.contains(coordinator.hotkey.keyChoice) ? coordinator.hotkey.keyChoice : 0].0)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .help("Edit the sound toggle shortcut")
            .accessibilityLabel("Edit sound toggle shortcut")
        }
        .popover(isPresented: $editingHotkey) {
            Form {
                Picker("Modifiers", selection: $coordinator.hotkey.modifierChoice) {
                    Text("⌃ ⌥").tag(0)
                    Text("⌃ ⌥ ⌘").tag(1)
                    Text("⇧ ⌘").tag(2)
                }
                .pickerStyle(.menu)
                Picker("Key", selection: $coordinator.hotkey.keyChoice) {
                    ForEach(Array(SoundHotkey.keys.enumerated()), id: \.offset) { index, key in
                        Text(key.0).tag(index)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Enable global shortcut", isOn: $coordinator.hotkey.enabled)
                    .toggleStyle(.switch)
                if let message = coordinator.hotkey.message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(width: 320)
        }

    }

    private func shortcutKey(_ label: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if label == "⇧" { Spacer(minLength: 0) }
            Text(label)
                .font(.system(size: 18, weight: caption == nil && label != "⇧" ? .semibold : .medium))
            if let caption {
                Text(caption).font(.system(size: 13))
            }
        }
        .padding(9)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 56, maxHeight: 56,
               alignment: caption != nil || label == "⇧" ? .leading : .center)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
    }

    @ViewBuilder private var soundEffectsSettingsGroup: some View {
        SettingsGroup("Sound Effects") {
            VStack(spacing: 10) {
                HStack {
                    Text("Effects volume")
                    Spacer()
                    Text(coordinator.settings.effectsVolume, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                Slider(value: $coordinator.settings.effectsVolume, in: 0...1) {
                    Text("Effects volume")
                }
                .labelsHidden()
            }
            HStack {
                Text("Play mouse click sounds")
                Button { coordinator.previewMouse() } label: {
                    Image(systemName: "play.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(coordinator.packs.isEmpty)
                .accessibilityLabel("Preview mouse click sound")
                Spacer()
                Toggle("Play mouse click sounds", isOn: $coordinator.settings.mouseSoundsEnabled)
                    .labelsHidden().toggleStyle(.switch)
            }
            HStack {
                Text("Play ding sound on return key")
                Button { coordinator.previewDing() } label: {
                    Image(systemName: "play.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview return key ding")
                Spacer()
                Toggle("Play ding sound on return key", isOn: $coordinator.settings.returnDingEnabled)
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

}

// Configure chrome before installing SwiftUI so no scene can restore a title-bar strip.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(coordinator: AppCoordinator) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Whoa Type Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .settingsBackground
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        let content = NSHostingView(rootView: SettingsView(coordinator: coordinator))
        content.safeAreaRegions = []
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApplication.shared.setActivationPolicy(.regular)
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

private extension NSColor {
    static var settingsBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.16, alpha: 1)
                : NSColor(calibratedWhite: 0.93, alpha: 1)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    private let content: Content
    private var header: AnyView?
    private var footer: AnyView?

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.content = content()
        header = AnyView(Text(title))
    }

    init<H: View, F: View>(@ViewBuilder content: () -> Content,
                           @ViewBuilder header: () -> H,
                           @ViewBuilder footer: () -> F) {
        self.content = content()
        if H.self != EmptyView.self { self.header = AnyView(header()) }
        self.footer = AnyView(footer())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                header.foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        row
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            if let footer {
                footer.font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
    }
}

nonisolated private func wallpaperThumbnail(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1200
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

struct AboutKeyBanner: View {
    let preview: () -> Void
    @State private var wallpaper: NSImage?
    private let iconSize: CGFloat = 56

    private var trashIcon: NSImage {
        NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns")
            ?? NSWorkspace.shared.icon(forFile: NSHomeDirectory() + "/.Trash")
    }

    private func refreshWallpaper() {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            wallpaper = nil
            return
        }
        // Decode a downsampled thumbnail off the main thread; full wallpapers can be tens of MB.
        Task {
            let thumbnail = await Task.detached(priority: .utility) { wallpaperThumbnail(url) }.value
            wallpaper = thumbnail.map { NSImage(cgImage: $0, size: .zero) }
        }
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                if let wallpaper {
                    Image(nsImage: wallpaper)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Color(nsColor: .settingsBackground)
                }
            }
            HStack(alignment: .center, spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                Button(action: preview) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: iconSize, height: iconSize)
                }
                .buttonStyle(AboutKeyPressStyle())
                .help("Press to preview your selected switch sound")
                .accessibilityLabel("Preview switch sound")
                Divider()
                    .frame(height: iconSize - 8)
                    .padding(.horizontal, 8)
                Image(nsImage: trashIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
            }
        }
        .frame(height: 120)
        .onAppear { refreshWallpaper() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshWallpaper()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            refreshWallpaper()
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct AboutKeyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.92 : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 3 : 0)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.12 : 0.28),
                    radius: configuration.isPressed ? 1 : 3,
                    y: configuration.isPressed ? 1 : 4)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.25, bounce: 0.2),
                       value: configuration.isPressed)
    }
}
