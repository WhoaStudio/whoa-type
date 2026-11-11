import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPane: String, CaseIterable, Identifiable {
    case playback = "sound"
    case about
    case startup = "general"

    var title: String {
        switch self {
        case .playback: "Sound"
        case .about: "About"
        case .startup: "General"
        }
    }

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
    let updateWindowTitle: (String) -> Void
    @AppStorage("settings.lastPane") private var pane: SettingsPane = .startup
    @State private var isScrolled = false

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
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch pane {
                        case .playback:
                            playbackSettingsGroups
                            audioOutputSettingsGroup
                            soundEffectsSettingsGroup
                        case .about: aboutSettingsGroups
                        case .startup: generalSettingsGroups
                        }
                    }
                    .padding(16)
                    // Leave a little scroll room for panes that fit in the window.
                    .frame(minHeight: geometry.size.height - paneHeaderHeight + 24,
                           alignment: .topLeading)
                    .padding(.top, paneHeaderHeight)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 0.5
                } action: { _, scrolled in
                    isScrolled = scrolled
                }
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .controlSize(.regular)
                .pickerStyle(.menu)
                .overlay(alignment: .top) {
                    paneHeader
                }
            }
        }
        .background(Color(nsColor: .settingsBackground))
        .frame(width: 640, height: 620)
        .ignoresSafeArea(.container, edges: .top)

        .onAppear { coordinator.refresh() }
        .onChange(of: pane, initial: true) { _, pane in
            updateWindowTitle(pane.title)
        }
    }

    private let paneHeaderHeight: CGFloat = 38

    private var paneHeader: some View {
        HStack(spacing: 8) {
            paneIcon(pane, size: 22)
            Text(pane.title)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: paneHeaderHeight, maxHeight: paneHeaderHeight,
               alignment: .bottomLeading)
        .background {
            if isScrolled {
                Rectangle().fill(.thinMaterial)
            }
        }
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        Button {
            self.pane = pane
        } label: {
            HStack(spacing: 8) {
                paneIcon(pane, size: 22)
                Text(pane.title)
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

    private var playbackSettingsGroups: some View {
        SettingsGroup("Playback") {
            SoundSettingsView(coordinator: coordinator)
        }
    }

    private var audioOutputSettingsGroup: some View {
        let route = coordinator.audioReady ? coordinator.audioRoute : nil
        return SettingsGroup("Audio Output") {
            LabeledContent("Output", value: route?.status ?? "System output")
            if route?.isBluetooth == true {
                Text("Bluetooth can add a noticeable delay.")
                    .foregroundStyle(.secondary)
            }
            if let details = route?.details {
                DisclosureGroup("Output details") {
                    Text(details).foregroundStyle(.secondary)
                }
            }
            Link("Open Sound Settings…", destination: URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        }
    }

    private var inputAccessSettingsGroup: some View {
        SettingsGroup("Privacy & Input Monitoring") {
            PermissionOnboardingView(permission: coordinator.permission)
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
            LabeledContent("Version") {
                SettingsBadge(Text(coordinator.updater.currentVersion))
            }
        }
    }

    @ViewBuilder private var generalSettingsGroups: some View {
        SettingsGroup("Startup") {
            Toggle("Launch at login", isOn: Binding(
                get: { coordinator.loginItem.registrationRequested },
                set: { coordinator.loginItem.setEnabled($0) }
            ))
            .toggleStyle(SettingsToggleStyle())
            if coordinator.loginItem.requiresApproval || coordinator.loginItem.errorMessage != nil {
                Text(coordinator.loginItem.message)
                    .foregroundStyle(.secondary)
                if coordinator.loginItem.requiresApproval {
                    Button("Open Login Items…") { coordinator.loginItem.openSettings() }
                }
            }
        }
        menuBarSettingsGroup
        keyboardShortcutSettingsGroup
        inputAccessSettingsGroup
        UpdateSettingsView(updater: coordinator.updater)
    }

    private var menuBarSettingsGroup: some View {
        SettingsGroup("Menu Bar") {
            Picker("Text next to icon", selection: $coordinator.settings.menuBarDisplay) {
                ForEach(MenuBarDisplay.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            Toggle("Keep icon fully visible", isOn: $coordinator.settings.disableMenuBarIconOpacity)
            .toggleStyle(SettingsToggleStyle())
            Toggle("Preview switches on hover", isOn: Binding(
                get: { !coordinator.settings.disableSwitchPreviewOnHover },
                set: { coordinator.settings.disableSwitchPreviewOnHover = !$0 }
            ))
            .toggleStyle(SettingsToggleStyle())
            Picker(selection: $coordinator.settings.menuBarClickAction) {
                ForEach(MenuBarClickAction.allCases, id: \.self) { action in
                    Text(action.rawValue).tag(action)
                }
            } label: {
                HStack(spacing: 5) {
                    Text("When clicking menu bar icon")
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                        .help("Choose what a primary click does. Right-click or Control-click always opens the menu.")
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint("Right-click or Control-click always opens the menu.")
            if coordinator.settings.menuBarClickAction == .toggleKeySounds {
                Text("Right-click or Control-click the icon to open the menu.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keyboardShortcutSettingsGroup: some View {
        SettingsGroup {
            HotkeyKeycaps(
                modifierChoice: $coordinator.hotkey.modifierChoice,
                keyChoice: $coordinator.hotkey.keyChoice,
                enabled: $coordinator.hotkey.enabled
            )
        } header: {
            Text("Hotkey")
        } footer: {
            if !coordinator.hotkey.enabled {
                Text("Shortcut is off. Select a key to enable it.")
            } else if let message = coordinator.hotkey.message {
                Text(message)
            }
        }
    }

    @ViewBuilder private var soundEffectsSettingsGroup: some View {
        SettingsGroup("Sound Effects") {
            if coordinator.packs.isEmpty {
                Text(coordinator.loading
                     ? "Loading switch recordings…" : "Switch recordings are unavailable.")
                    .foregroundStyle(.secondary)
                if !coordinator.loading {
                    Button("Retry Loading") { coordinator.refresh() }
                }
            } else {
                SwitchSoundPicker(coordinator: coordinator)
            }
            VStack(spacing: 10) {
                HStack {
                    Text("Effects volume")
                    Spacer()
                    SettingsBadge(Text(coordinator.settings.effectsVolume,
                                       format: .percent.precision(.fractionLength(0))))
                }
                Slider(value: $coordinator.settings.effectsVolume, in: 0...1) {
                    Text("Effects volume")
                }
                .labelsHidden()
            }
            HStack {
                Text("Play mouse click sounds")
                Button { coordinator.previewMouse() } label: {
                    Image(systemName: "play.circle.fill").foregroundStyle(.teal)
                }
                .buttonStyle(.plain)
                .disabled(coordinator.packs.isEmpty)
                .accessibilityLabel("Preview mouse click sound")
                Spacer()
                Toggle("Play mouse click sounds", isOn: $coordinator.settings.mouseSoundsEnabled)
                    .labelsHidden().toggleStyle(SettingsToggleStyle())
            }
            HStack {
                Text("Play ding sound on return key")
                Button { coordinator.previewDing() } label: {
                    Image(systemName: "play.circle.fill").foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview return key ding")
                Spacer()
                Toggle("Play ding sound on return key", isOn: $coordinator.settings.returnDingEnabled)
                    .labelsHidden().toggleStyle(SettingsToggleStyle())
            }
        }
    }

}

// Configure chrome before installing SwiftUI so no scene can restore a title-bar strip.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var counted = false
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
        let content = NSHostingView(rootView: SettingsView(coordinator: coordinator) { [weak window] title in
            window?.title = "\(title) — Whoa Type Settings"
        })
        content.safeAreaRegions = []
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        if !counted { counted = true; WindowActivation.windowOpened() }
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    func windowWillClose(_ notification: Notification) {
        if counted { counted = false; WindowActivation.windowClosed() }
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

struct SettingsGroup<Content: View>: View {
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

@concurrent
private func wallpaperThumbnail(_ url: URL) async -> CGImage? {
    guard url.isFileURL else { return nil }
    var imageURL = url
    if url.pathExtension == "madesktop",
       let data = try? Data(contentsOf: url),
       let descriptor = try? PropertyListSerialization.propertyList(from: data, format: nil)
           as? [String: Any],
       let thumbnailPath = descriptor["thumbnailPath"] as? String {
        imageURL = URL(fileURLWithPath: thumbnailPath)
    }

    if let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, CGImageSourceGetPrimaryImageIndex(source), options as CFDictionary
        ) {
            return thumbnail
        }
    }

    guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true else {
        return nil
    }
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.maximumSize = CGSize(width: 1200, height: 1200)
    generator.appliesPreferredTrackTransform = true
    return try? await generator.image(at: .zero).image
}

struct AboutKeyBanner: View {
    let preview: () -> Void
    @State private var wallpaper: NSImage?
    @State private var wallpaperRevision = 0
    private let iconSize: CGFloat = 56

    private var trashIcon: NSImage {
        NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns")
            ?? NSWorkspace.shared.icon(forFile: NSHomeDirectory() + "/.Trash")
    }

    private func refreshWallpaper() async {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            wallpaper = nil
            return
        }
        let thumbnail = await wallpaperThumbnail(url)
        guard !Task.isCancelled else { return }
        wallpaper = thumbnail.map { NSImage(cgImage: $0, size: .zero) }
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
        .task(id: wallpaperRevision) { await refreshWallpaper() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            wallpaperRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { event in
            if event.object as? NSWindow === NSApp.keyWindow {
                wallpaperRevision += 1
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            wallpaperRevision += 1
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

/// Shows a Dock icon while any of our windows is open and hides it when the last one closes.
@MainActor
enum WindowActivation {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        NSApplication.shared.setActivationPolicy(.regular)
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 { NSApplication.shared.setActivationPolicy(.accessory) }
    }
}
