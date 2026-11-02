import SwiftUI
import AppKit

@MainActor
final class IntroWindowController: NSWindowController, NSWindowDelegate {
    private let coordinator: AppCoordinator
    private let previousActivationPolicy = NSApplication.shared.activationPolicy()
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 720),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Intro"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: IntroView(coordinator: coordinator) { [weak self] in
            self?.close()
        })
        window.delegate = self
        window.center()
        NSApplication.shared.setActivationPolicy(.regular)
    }
    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) {
        coordinator.settings.onboardingCompleted = true
        NSApplication.shared.setActivationPolicy(previousActivationPolicy)
    }
}

private struct IntroView: View {
    @Bindable var coordinator: AppCoordinator
    var finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private let colors: [Color] = [.gray, .purple, .brown, .orange, .yellow]

    private func scrollEdge(top: Bool) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: 40)
            .mask(LinearGradient(stops: [
                .init(color: .black.opacity(0.85), location: 0),
                .init(color: .black.opacity(0.65), location: 0.25),
                .init(color: .black.opacity(0.3), location: 0.55),
                .init(color: .black.opacity(0.08), location: 0.8),
                .init(color: .clear, location: 1)
            ], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    var body: some View {
        VStack(spacing: 22) {
            IntroLogoKey { coordinator.previewKey() }
                .disabled(coordinator.packs.isEmpty)
            Text("Intro").font(.system(size: 26, weight: .bold))
            if coordinator.permission.authorized {
                Label("Whoa Type is authorized.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.teal)
            } else {
                Button {
                    coordinator.permission.request()
                    coordinator.permission.openSystemSettings()
                } label: {
                    Label("Open Input Monitoring Settings", systemImage: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(red: 0.65, green: 0.22, blue: 0.10))
                .help("Enable Whoa Type in System Settings → Privacy & Security → Input Monitoring")
            }
            Text("Choose your preferred switch set.")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                .padding(.top, 10)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(coordinator.packs.enumerated()), id: \.element.id) { index, pack in
                        HStack(spacing: 12) {
                            Button { coordinator.select(pack.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus").font(.title3)
                                        .foregroundStyle(.white).frame(width: 28, height: 28)
                                        .background(colors[index % colors.count], in: RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Switch set").font(.system(size: 12)).foregroundStyle(.secondary)
                                        Text(pack.name).font(.system(size: 14, weight: .semibold))
                                    }
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(coordinator.settings.selectedPackID == pack.id ? .isSelected : [])
                            Button { coordinator.preview(pack.id) } label: {
                                Image(systemName: "play.fill").font(.system(size: 11))
                                    .frame(width: 28, height: 28).background(.white, in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel("Preview \(pack.name)")
                        }
                        .padding(12)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
                            coordinator.settings.selectedPackID == pack.id ? Color.teal : Color.black.opacity(0.08),
                            lineWidth: coordinator.settings.selectedPackID == pack.id ? 3 : 1))
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 12)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.22).delay(Double(index) * 0.04), value: appeared)
                    }
                }.padding(3).padding(.vertical, 14)
            }
            .overlay(alignment: .top) { scrollEdge(top: true) }
            .overlay(alignment: .bottom) { scrollEdge(top: false) }
            .mask {
                GeometryReader { geometry in
                    // Fade the material itself into the window to avoid a tinted rectangular seam.
                    let edge = min(0.45, 28 / max(geometry.size.height, 1))
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.15), location: edge * 0.25),
                        .init(color: .black.opacity(0.5), location: edge * 0.5),
                        .init(color: .black.opacity(0.85), location: edge * 0.75),
                        .init(color: .black, location: edge),
                        .init(color: .black, location: 1 - edge),
                        .init(color: .black.opacity(0.85), location: 1 - edge * 0.75),
                        .init(color: .black.opacity(0.5), location: 1 - edge * 0.5),
                        .init(color: .black.opacity(0.15), location: 1 - edge * 0.25),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
            if let error = coordinator.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Launch Whoa Type at Login", isOn: Binding(
                get: { coordinator.loginItem.enabled }, set: { coordinator.loginItem.setEnabled($0) }))
                .toggleStyle(.checkbox)
            if coordinator.loginItem.errorMessage != nil {
                Text(coordinator.loginItem.message).font(.caption)
            }
            Button("Done", action: finish).keyboardShortcut(.defaultAction)
        }
        .padding(32).padding(.top, 12)
        .frame(width: 420, height: 720)
        .background {
            Image("OnboardingBackground")
                .resizable()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .preferredColorScheme(.light)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: appeared)
        .onAppear { appeared = true }
    }
}

private struct IntroLogoKey: View {
    let preview: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: preview) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(IntroLogoPressStyle(hovered: hovered))
        .frame(width: 64, height: 64)
        .contentShape(Rectangle())
        .onHover { inside in
            guard hovered != inside else { return }
            hovered = inside
            if inside { preview() }
        }
        .help("Press to hear your selected switch")
        .accessibilityLabel("Preview selected switch keypress")
    }
}

private struct IntroLogoPressStyle: ButtonStyle {
    let hovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let depressed = hovered || configuration.isPressed
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.9 : hovered ? 0.95 : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 4 : hovered ? 2 : 0)
            .brightness(depressed ? -0.08 : 0)
            .shadow(color: .black.opacity(depressed ? 0.12 : 0.28),
                    radius: depressed ? 1 : 3, y: depressed ? 1 : 4)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
