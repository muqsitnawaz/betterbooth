import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let scripted = ["--photo", "--record", "--list"].contains { CommandLine.arguments.contains($0) }
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
    /// capture without showing UI, print the saved path, and quit. `--list` prints the cameras and microphones.
    private func runScripted() -> Bool {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        func fail(_ message: String) -> Never {
            print("error: \(message)")
            exit(1)
        }
        /// The value after `flag` parsed by `parse`; nil when the flag is absent, an error when its value is not one of `expected`.
        func option<T>(_ flag: String, _ expected: String, _ parse: (String) -> T?) -> T? {
            guard args.contains(flag) else { return nil }
            if let parsed = value(after: flag).flatMap(parse) { return parsed }
            fail("\(flag) takes \(expected)")
        }
        // A mistyped flag such as --phot must fail, not open the app or capture with defaults.
        let known: Set = ["--list", "--photo", "--record", "--aspect", "--res", "--fps", "--camera", "--mic", "--rotate", "--blur", "--brighten"]
        if let unknown = args.dropFirst().first(where: { $0.hasPrefix("--") && !known.contains($0) }) {
            fail("unknown option \(unknown); the options are \(known.sorted().joined(separator: " "))")
        }
        let name = { (flag: String) in option(flag, "part of a name from --list") { $0.isEmpty || $0.hasPrefix("--") ? nil : $0 } }
        if args.contains("--list") {
            print("cameras:")
            camera.devices.forEach { print("  \($0.localizedName)\($0.isSuspended ? " (off: lid closed)" : "")") }
            print("microphones:")
            camera.mics.forEach { print("  \($0.localizedName)") }
            exit(0)
        }
        let photo = args.contains("--photo")
        guard photo || args.contains("--record") else { return false }
        let seconds = option("--record", "a length in seconds, such as --record 5") { Double($0).flatMap { $0 > 0 && $0.isFinite ? $0 : nil } }
        if let (aspect, landscape) = option("--aspect", "9:16, 4:5, 3:4, 1:1, 16:9, 5:4 or 4:3", Aspect.parse) {
            camera.config.aspect = aspect
            camera.config.landscape = landscape
        }
        if let name = name("--camera") {
            let wanted = name.lowercased()
            let names = camera.devices.map { ($0, $0.localizedName.lowercased()) }
            guard let device = (names.first(where: { $0.1.hasPrefix(wanted) }) ?? names.first(where: { $0.1.contains(wanted) }))?.0 else {
                fail("no camera matching \(name); --list shows them")
            }
            camera.config.deviceID = device.uniqueID
        }
        if let name = name("--mic")?.lowercased() {
            guard let mic = camera.mics.first(where: { $0.localizedName.lowercased().contains(name) }) else {
                fail("no microphone matching \(name); --list shows them")
            }
            camera.config.micOn = true
            camera.config.micID = mic.uniqueID
        }
        if let degrees = option("--rotate", "0, 90, 180 or 270", { Int($0).flatMap { [0, 90, 180, 270].contains($0) ? $0 : nil } }) {
            camera.config.rotation = degrees
        }
        if let res = option("--res", "720, 1080, 1440 or 2160", { Int($0).flatMap(Resolution.init(rawValue:)) }) { camera.config.resolution = res }
        if let fps = option("--fps", "23.98, 24, 30 or 60", FrameRate.init(rawValue:)) { camera.config.frameRate = fps }
        if let radius = option("--blur", "a radius in pixels at 1080p, such as --blur 16", { Double($0).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil } }) {
            camera.config.blurBackground = true
            camera.config.blurRadius = radius
        }
        if let stops = option("--brighten", "stops of exposure from -2 to 2, such as --brighten 1", { Double($0).flatMap { abs($0) <= 2 ? $0 : nil } }) {
            camera.config.brighten = true
            camera.config.brightness = stops
        }
        // No location prompt in a script, and no microphone for a photo.
        camera.config.saveLocation = false
        if photo { camera.config.micOn = false }

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
