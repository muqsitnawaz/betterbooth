import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let scripted = ["--photo", "--record", "--list"].contains { CommandLine.arguments.contains($0) }
    lazy var camera = Camera(persists: !scripted)
    private let library = Library()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if runScripted() { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        camera.$recordingSince.sink { [weak self] since in self?.updateIcon(recording: since != nil) }.store(in: &cancellables)

        let host = NSHostingController(rootView: ContentView(camera: camera, library: library))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func updateIcon(recording: Bool) {
        let name = recording ? "record.circle.fill" : "camera.fill"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: recording ? "BetterBooth, recording" : "BetterBooth")
        image?.isTemplate = !recording
        statusItem.button?.image = recording
            ? image?.withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))
            : image
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open BetterBooth Folder", action: #selector(openFolder), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit BetterBooth", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown {
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

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    func popoverDidClose(_ notification: Notification) {
        camera.stop()
        RingLight.hide()
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
