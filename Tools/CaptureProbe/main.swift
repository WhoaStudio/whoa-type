import AppKit
import CoreGraphics

// Disposable feasibility app. Never inspects, counts, or stores input events.
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Whoa Type Capture Probe"
        let explanation = NSTextField(wrappingLabelWithString:
            "Tests passive Input Monitoring access. No key data is read or recorded. Enable access explicitly, then retry after changing System Settings. Closing this window quits.")
        let enable = NSButton(title: "Enable Input Monitoring", target: self, action: #selector(requestAccess))
        let retry = NSButton(title: "Retry", target: self, action: #selector(refresh))
        let stack = NSStackView(views: [explanation, status, enable, retry])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)
        ])
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func requestAccess() {
        _ = CGRequestListenEventAccess()
        refresh()
    }

    @objc private func refresh() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        guard CGPreflightListenEventAccess() else {
            status.stringValue = "Input Monitoring unavailable. Grant access in Privacy & Security → Input Monitoring; relaunch may be required."
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .listenOnly, eventsOfInterest: mask,
                               callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                               userInfo: nil)
        guard let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            status.stringValue = "Listen access granted; tap creation failed. This does not establish permission denial."
            return
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status.stringValue = "Listen access granted; passive session tap created. No event data is inspected."
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
