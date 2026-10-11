import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let scripted = CommandLine.arguments.contains("--photo") || CommandLine.arguments.contains("--record")
    private lazy var camera = Camera(persists: !scripted)
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
        let image = NSImage(systemSymbolName: name, accessibilityDescription: recording ? "VertCam, recording" : "VertCam")
        image?.isTemplate = !recording
        statusItem.button?.image = recording
            ? image?.withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))
            : image
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open VertCam Folder", action: #selector(openFolder), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit VertCam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    // Dragging the popover off the menu bar turns it into a floating window.
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    func popoverDidClose(_ notification: Notification) { camera.stop() }

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

    /// `--photo` or `--record <seconds>`, optionally with `--aspect 9:16`, `--res 1080`, `--fps 23.98`, `--camera <name>`, `--mic <name>`, `--rotate 90`:
    /// capture without showing UI, print the saved path, and quit.
    private func runScripted() -> Bool {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        let photo = args.contains("--photo")
        guard photo || args.contains("--record") else { return false }
        let seconds = value(after: "--record").flatMap(Double.init)
        if args.contains("--record") && !(seconds.map { $0 > 0 } ?? false) {
            print("error: --record needs a length in seconds, such as --record 5")
            exit(1)
        }
        if let (aspect, landscape) = value(after: "--aspect").flatMap(Aspect.parse) {
            camera.config.aspect = aspect
            camera.config.landscape = landscape
        }
        if let name = value(after: "--camera") {
            let wanted = name.lowercased()
            let names = camera.devices.map { ($0, $0.localizedName.lowercased()) }
            guard let device = (names.first(where: { $0.1.hasPrefix(wanted) }) ?? names.first(where: { $0.1.contains(wanted) }))?.0 else {
                print("error: no camera matching \(name)")
                exit(1)
            }
            camera.config.deviceID = device.uniqueID
        }
        if let name = value(after: "--mic")?.lowercased() {
            guard let mic = camera.mics.first(where: { $0.localizedName.lowercased().contains(name) }) else {
                print("error: no microphone matching \(name)")
                exit(1)
            }
            camera.config.micOn = true
            camera.config.micID = mic.uniqueID
        }
        if let degrees = value(after: "--rotate").flatMap(Int.init), [0, 90, 180, 270].contains(degrees) { camera.config.rotation = degrees }
        if let res = value(after: "--res").flatMap(Int.init).flatMap(Resolution.init(rawValue:)) { camera.config.resolution = res }
        if let fps = value(after: "--fps").flatMap(FrameRate.init(rawValue:)) { camera.config.frameRate = fps }

        func finish(_ url: URL?) {
            // After the main-queue work already pending, so a reason reported just before is printed.
            DispatchQueue.main.async { [camera] in
                print(url?.path ?? "error: \(camera.errorMessage ?? "nothing captured")")
                exit(url == nil ? 1 : 0)
            }
        }
        camera.start()
        // Wait for a live picture (up to 6 seconds), then a second more for exposure to settle.
        // A camera that never goes live makes the capture fail with the reason.
        let deadline = Date().addingTimeInterval(6)
        func act() {
            if photo {
                camera.takePhoto(completion: finish)
            } else if let seconds {
                camera.startRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [camera] in camera.stopRecording(completion: finish) }
            }
        }
        func poll() {
            if camera.feed == .live {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: act)
            } else if Date() > deadline {
                act()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
            }
        }
        poll()
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
