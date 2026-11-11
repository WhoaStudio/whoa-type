import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let coordinator = AppCoordinator()
    private let popover = NSPopover()
    private var item: NSStatusItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let logo = NSImage(named: "MenuBarLogo")
    private lazy var dimmedLogo: NSImage? = {
        guard let logo else { return nil }
        let image = NSImage(size: logo.size, flipped: false) { rect in
            logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            return true
        }
        image.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        item.button?.target = self
        item.button?.action = #selector(handleClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeft
        item.button?.setAccessibilityLabel("Whoa Type")
        popover.behavior = .applicationDefined
        popover.delegate = self
        observeAppearance()
    }

    private func observeAppearance() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
    }

    private func updateButton() {
        guard let button = item?.button else { return }
        let settings = coordinator.settings
        button.image = settings.disableMenuBarIconOpacity || settings.soundEnabled ? logo : dimmedLogo
        button.title = switch settings.menuBarDisplay {
        case .none: ""
        case .switchName: coordinator.packs.first { $0.id == settings.selectedPackID }?.name ?? ""
        case .volume: settings.volume.formatted(.percent.precision(.fractionLength(0)))
        }
        button.setAccessibilityValue(button.title)
    }

    @objc private func handleClick(_ button: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let secondaryClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if !secondaryClick && coordinator.settings.menuBarClickAction == .toggleKeySounds {
            if popover.isShown { popover.performClose(nil) }
            coordinator.settings.soundEnabled.toggle()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentViewController = NSHostingController(rootView: MenuBarView(coordinator: coordinator) { [weak self] in
                self?.popover.performClose(nil)
            })
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if popover.isShown { monitorDismissal() }
        }
    }

    private func monitorDismissal() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) {
            [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53,
                      event.window === popover.contentViewController?.view.window
                else { return event }
                popover.performClose(nil)
                return nil
            }
            if let window = popover.contentViewController?.view.window, event.window === window {
                return event
            }
            if let button = item?.button, event.window === button.window,
               button.bounds.contains(button.convert(event.locationInWindow, from: nil)),
               event.type != .otherMouseDown {
                return event
            }
            popover.performClose(nil)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}
