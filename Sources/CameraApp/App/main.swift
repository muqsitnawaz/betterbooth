import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    let scripted = ["--photo", "--record", "--list"].contains { CommandLine.arguments.contains($0) }
    lazy var camera = Camera(persists: !scripted)
    private let library = Library()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    /// The popover dragged off, or opened from the menu: resizable, and it can go full screen.
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if runScripted() { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        camera.$recordingSince.sink { [weak self] since in self?.updateIcon(recording: since != nil) }.store(in: &cancellables)

        // Never shown for a menu-bar app, but its ⌘Q works while the popover is focused.
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: "Quit Camera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(appMenu)

        let host = NSHostingController(rootView: ContentView(camera: camera, library: library))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        // Dark like a viewfinder, whatever the system appearance.
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func updateIcon(recording: Bool) {
        let name = recording ? "record.circle.fill" : "camera.fill"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: recording ? "Camera, recording" : "Camera")
        image?.isTemplate = !recording
        statusItem.button?.image = recording
            ? image?.withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))
            : image
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open in Window", action: #selector(openWindow), keyEquivalent: "").target = self
            let current = UserDefaults.standard.object(forKey: "popoverSize") as? Int ?? PopoverSize.medium.rawValue
            for size in PopoverSize.allCases {
                let item = menu.addItem(withTitle: "\(size.name) Popover", action: #selector(setPopoverSize), keyEquivalent: "")
                item.target = self
                item.tag = size.rawValue
                item.state = size.rawValue == current ? .on : .off
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Open Camera Folder", action: #selector(openFolder), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Camera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            camera.start()
            library.reload()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    @objc private func openFolder() { NSWorkspace.shared.open(Library.folder) }

    @objc private func setPopoverSize(_ item: NSMenuItem) { UserDefaults.standard.set(item.tag, forKey: "popoverSize") }

    @objc private func openWindow() {
        popover.performClose(nil)
        let window = makeWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// While the window is open Camera is a regular app: in the Dock and ⌘-Tab, and able to go full screen.
    private func makeWindow() -> NSWindow {
        if let window { return window }
        camera.start()
        library.reload()
        let host = NSHostingController(rootView: ContentView(camera: camera, library: library, inWindow: true))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "Camera"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = .fullScreenPrimary
        window.contentMinSize = NSSize(width: 360, height: 520)
        window.setContentSize(NSSize(width: 600, height: 860))
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApp.setActivationPolicy(.regular)
        return window
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    func detachableWindow(for popover: NSPopover) -> NSWindow? { makeWindow() }

    func popoverDidClose(_ notification: Notification) {
        guard window == nil else { return }  // it was dragged off into the window, which keeps the camera
        camera.stop()
        RingLight.hide()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        camera.stop()
        RingLight.hide()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard camera.isRecording else { return }
        let done = DispatchSemaphore(value: 0)
        camera.stopRecording { _ in done.signal() }
        // Give the file up to 5 seconds to finish; never hold Quit forever on a stuck disk.
        let deadline = Date().addingTimeInterval(5)
        while done.wait(timeout: .now() + 0.05) == .timedOut, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
