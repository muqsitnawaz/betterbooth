import AVFoundation
import SwiftUI

enum Mode: String { case photo, video }

struct ContentView: View {
    @ObservedObject var camera: Camera
    @ObservedObject var library: Library
    @AppStorage("mode") private var mode: Mode = .photo
    @AppStorage("timer") private var timerOn = false
    @AppStorage("timerSeconds") private var timerSeconds = 3
    @AppStorage("ringLight") private var ringLightOn = false
    @AppStorage("ringLightStrength") private var ringLightStrength = RingLight.Strength.medium.rawValue
    /// The displays the ring light shines from, by ID; empty is the main display.
    @AppStorage("ringLightDisplays") private var ringLightDisplays = ""
    @State private var countdown: Int?
    @State private var flash = false
    @State private var countdownTask: Task<Void, Never>?
    /// A capture shown in place of the live picture.
    @State private var viewing: URL?

    private var previewSize: CGSize {
        let r = camera.config.ratio
        return r >= 1 ? CGSize(width: 512, height: (512 / r).rounded()) : CGSize(width: (512 * r).rounded(), height: 512)
    }

    private var feedMessage: String? {
        switch camera.feed {
        case .live, .off: return nil
        case .waiting: return "Waiting for \(camera.deviceName)…"
        case .black: return "The picture from \(camera.deviceName) is black.\nIf it shouldn't be, check the camera is on and plugged in."
        case .suspended: return "\(camera.deviceName) is off while the lid is closed.\nPick another camera from the camera menu."
        case .noCamera: return "No camera connected"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            preview
            controls
            shutterRow
            if !library.items.isEmpty { strip }
        }
        .padding(14)
        .frame(width: max(previewSize.width, 470) + 28)
        .animation(.easeInOut(duration: 0.25), value: camera.config.ratio)
        // Closing the popover stops the camera; a countdown must not fire into a stopped camera.
        .onDisappear {
            countdownTask?.cancel()
            countdown = nil
        }
        .onChange(of: ringLight, initial: true) { _, strength in
            if let strength { RingLight.show(strength, on: ringLightScreens) } else { RingLight.hide() }
        }
        .onChange(of: ringLightDisplays) { if let ringLight { RingLight.show(ringLight, on: ringLightScreens) } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            if let ringLight { RingLight.show(ringLight, on: ringLightScreens) }
        }
    }

    private var chosenDisplays: Set<String> { Set(ringLightDisplays.split(separator: ",").map(String.init)) }

    private var ringLightScreens: [NSScreen] {
        let chosen = NSScreen.screens.filter { chosenDisplays.contains($0.displayID) }
        return chosen.isEmpty ? [NSScreen.main].compactMap { $0 } : chosen
    }

    private var ringLight: RingLight.Strength? {
        ringLightOn && camera.feed != .off ? RingLight.Strength(rawValue: ringLightStrength) ?? .medium : nil
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            PreviewView(layer: camera.displayLayer)
            if camera.access == .denied {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill").font(.title)
                    Text("Camera needs access to your camera.").font(.callout)
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                }
                .foregroundStyle(.white)
            }
            if camera.access == .granted, let message = feedMessage {
                VStack(spacing: 8) {
                    if camera.feed == .waiting { ProgressView().controlSize(.small) }
                    Text(message).font(.callout).multilineTextAlignment(.center)
                }
                .padding(12)
                .foregroundStyle(.white.opacity(0.9))
            }
            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .transition(.scale.combined(with: .opacity))
                    .id(countdown)
            }
            Color.white.opacity(flash ? 1 : 0).allowsHitTesting(false)
            VStack {
                HStack {
                    if let since = camera.recordingSince { RecordingBadge(since: since) }
                    Spacer()
                    Text("\(Int(camera.config.outputSize.width))×\(Int(camera.config.outputSize.height)) · \(camera.mode.rate.label)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                if let error = camera.errorMessage {
                    Text(error)
                        .font(.caption)
                        .padding(6)
                        .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                }
            }
            .padding(8)
            if let viewing {
                CaptureViewer(url: viewing, library: library, close: { self.viewing = nil }, step: step)
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Controls

    // Every icon does one thing on a click, and a right-click shows its choices.
    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                cameraMenu

                Picker("Aspect ratio", selection: $camera.config.aspect) {
                    ForEach(Aspect.allCases) { Text($0.label(landscape: camera.config.landscape)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Aspect ratio: 9:16 for Reels, Shorts and TikTok")

                rotateButton
            }

            HStack(spacing: 8) {
                Picker("Resolution", selection: $camera.config.resolution) {
                    ForEach(Resolution.allCases) { r in
                        Text(r.rawValue > camera.mode.nativeShort ? "\(r.label) (upscaled)" : r.label).tag(r)
                    }
                }
                .help("Resolution of the short side; this camera gives \(camera.mode.nativeShort) real pixels at \(camera.config.aspectLabel)")

                Picker("Frame rate", selection: $camera.config.frameRate) {
                    ForEach(FrameRate.allCases) { f in
                        Text(f.label).tag(f).selectionDisabled(!camera.mode.supportedRates.contains(f))
                    }
                }
                .help("Frame rate; greyed-out rates are ones this camera can't deliver")

                Spacer(minLength: 0)

                toggle(camera.config.mirrored, icon: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
                       off: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Mirror") {
                    camera.config.mirrored.toggle()
                }

                toggle(camera.config.blurBackground, icon: "person.and.background.dotted",
                       help: "Blur the background · right-click for how much") { camera.config.blurBackground.toggle() }
                    .contextMenu {
                        Picker("Blur", selection: choosing(\.blurRadius, turnsOn: \.blurBackground)) {
                            Text("Soft").tag(8.0)
                            Text("Medium").tag(16.0)
                            Text("Strong").tag(32.0)
                        }
                        .pickerStyle(.inline)
                    }

                toggle(camera.config.brighten, icon: "sun.max.fill", off: "sun.max",
                       help: "Brighten the picture · right-click for how much") { camera.config.brighten.toggle() }
                    .contextMenu {
                        Picker("Brighten", selection: choosing(\.brightness, turnsOn: \.brighten)) {
                            Text("A Little").tag(0.5)
                            Text("More").tag(1.0)
                            Text("A Lot").tag(1.5)
                        }
                        .pickerStyle(.inline)
                    }

                toggle(ringLightOn, icon: "lightbulb.fill", off: "lightbulb",
                       help: "Ring light: light your face from the edges of the screen · right-click for how bright") { ringLightOn.toggle() }
                    .contextMenu {
                        Picker("Ring Light", selection: Binding(get: { ringLightStrength }, set: { ringLightStrength = $0; ringLightOn = true })) {
                            ForEach(RingLight.Strength.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.inline)
                        if NSScreen.screens.count > 1 {
                            Section("Displays") {
                                ForEach(NSScreen.screens, id: \.displayID) { screen in
                                    Toggle(screen.localizedName, isOn: displayBinding(screen))
                                }
                            }
                        }
                    }

                mic

                toggle(timerOn, icon: "timer", badge: timerOn ? "\(timerSeconds)" : nil,
                       help: timerOn ? "\(timerSeconds)-second timer · right-click for others" : "No timer · right-click for 3 or 10 seconds") {
                    timerOn.toggle()
                }
                .contextMenu {
                    Picker("Timer", selection: Binding(get: { timerSeconds }, set: { timerSeconds = $0; timerOn = true })) {
                        Text("3 Seconds").tag(3)
                        Text("10 Seconds").tag(10)
                    }
                    .pickerStyle(.inline)
                }

                moreMenu
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .buttonStyle(.borderless)
            .imageScale(.large)
        }
        .disabled(camera.isRecording)
    }

    private var cameraMenu: some View {
        let current = camera.devices.first { $0.uniqueID == camera.config.deviceID }
        return Menu {
            Picker("Camera", selection: $camera.config.deviceID) {
                ForEach(camera.devices, id: \.uniqueID) { device in
                    Text(device.isSuspended ? "\(device.localizedName) (off: lid closed)" : device.localizedName)
                        .tag(Optional(device.uniqueID))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: current?.deviceType == .continuityCamera ? "iphone" : "web.camera")
                .frame(width: 22)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.borderless)
        .imageScale(.large)
        .help("Camera: \(camera.deviceName)")
    }

    /// Click: portrait or landscape. Right-click: turn a sideways camera's picture.
    private var rotateButton: some View {
        let landscape = camera.config.landscape, square = camera.config.aspect.isSquare
        return Button { if !square { camera.config.landscape.toggle() } } label: {
            Image(systemName: landscape ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
                .foregroundStyle(square ? Color.secondary.opacity(0.5) : Color.primary)
                .frame(width: 22)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .keyboardShortcut("r", modifiers: [])
        .help((square ? "A square has no orientation" : "Turn the frame to \(landscape ? "portrait" : "landscape") (\(camera.config.aspect.label(landscape: !landscape))) · R")
              + " · right-click if the camera is mounted sideways")
        .contextMenu {
            Picker("Camera Mounted", selection: $camera.config.rotation) {
                ForEach([0, 90, 180, 270], id: \.self) { Text($0 == 0 ? "Upright" : "Turn Picture \($0)° Clockwise").tag($0) }
            }
            .pickerStyle(.inline)
        }
    }

    private var mic: some View {
        let systemDefault = AVCaptureDevice.default(for: .audio)?.localizedName
        let chosen = camera.mics.first { $0.uniqueID == camera.config.micID }?.localizedName ?? systemDefault ?? "the default microphone"
        return HStack(spacing: 2) {
            toggle(camera.config.micOn, icon: "mic.fill", off: "mic.slash",
                   help: camera.config.micOn ? "Recording sound from \(chosen) · click to mute, right-click to pick a microphone"
                                             : "Muted · click to record sound, right-click to pick a microphone") {
                camera.config.micOn.toggle()
            }
            .contextMenu {
                Picker("Microphone", selection: Binding(get: { camera.config.micID }, set: { camera.config.micID = $0; camera.config.micOn = true })) {
                    Text(systemDefault.map { "System Default (\($0))" } ?? "System Default").tag(String?.none)
                    ForEach(camera.mics, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                .pickerStyle(.inline)
            }
            if camera.config.micOn { LevelMeter(level: camera.micLevel) }
        }
    }

    private var moreMenu: some View {
        Menu {
            Toggle(camera.locator.denied ? "Save Location (off in System Settings)" : "Save Location in Photos and Videos",
                   isOn: $camera.config.saveLocation)
            if camera.config.saveLocation && camera.locator.denied {
                Button("Open Location Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                }
            }
            Button("macOS Video Effects…") { AVCaptureDevice.showSystemUserInterface(.videoEffects) }
            Divider()
            Button("Open Camera Folder") { NSWorkspace.shared.open(Library.folder) }
            Button("Quit Camera") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private func displayBinding(_ screen: NSScreen) -> Binding<Bool> {
        Binding(
            get: { ringLightScreens.contains(screen) },
            set: { on in
                var chosen = Set(ringLightScreens.map(\.displayID))
                if on { chosen.insert(screen.displayID) } else { chosen.remove(screen.displayID) }
                // Unchecking the last display turns the light off rather than back to the main one.
                guard !chosen.isEmpty else { ringLightOn = false; return }
                ringLightDisplays = chosen.sorted().joined(separator: ",")
                ringLightOn = true
            })
    }

    /// A binding for an effect's amount: picking one also turns the effect on.
    private func choosing(_ amount: WritableKeyPath<Config, Double>, turnsOn flag: WritableKeyPath<Config, Bool>) -> Binding<Double> {
        Binding(get: { camera.config[keyPath: amount] }, set: { camera.config[keyPath: amount] = $0; camera.config[keyPath: flag] = true })
    }

    private func toggle(_ isOn: Bool, icon: String, off: String? = nil, badge: String? = nil, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? icon : off ?? icon)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 22)
                .overlay(alignment: .bottomTrailing) {
                    if let badge { Text(badge).font(.system(size: 8, weight: .bold)).foregroundStyle(Color.accentColor).offset(x: 4, y: 3) }
                }
        }
        .help(help)
    }

    private var shutterRow: some View {
        HStack {
            Picker("Mode", selection: $mode) {
                Text("Photo").tag(Mode.photo)
                Text("Video").tag(Mode.video)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(camera.isRecording || countdown != nil)
            Spacer()
            ShutterButton(mode: mode, recording: camera.isRecording, action: shutter)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(camera.access != .granted || countdown != nil)
            Spacer()
            Button { NSWorkspace.shared.open(Library.folder) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .imageScale(.large)
            .help("Open the Camera folder")
            .frame(width: 130, alignment: .trailing)
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(library.items, id: \.self) { url in
                    Thumbnail(url: url)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: viewing == url ? 2 : 0))
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                        .onTapGesture { viewing = url }
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .contextMenu {
                            Button("Open") { NSWorkspace.shared.open(url) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            ShareLink("Share…", item: url)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([url as NSURL])
                            }
                            Divider()
                            Button("Move to Trash") { library.trash(url) }
                        }
                }
            }
        }
        .frame(height: 64)
    }

    // MARK: Actions

    /// The strip is newest first.
    private func step(_ by: Int) {
        guard let viewing, let i = library.items.firstIndex(of: viewing) else { return }
        let j = i + by
        if library.items.indices.contains(j) { self.viewing = library.items[j] }
    }

    private func shutter() {
        viewing = nil
        if mode == .video && camera.isRecording {
            camera.stopRecording { _ in library.reload() }
            return
        }
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            if timerOn {
                for n in stride(from: timerSeconds, through: 1, by: -1) {
                    withAnimation(.spring(duration: 0.3)) { countdown = n }
                    try? await Task.sleep(for: .seconds(1))
                }
                withAnimation { countdown = nil }
                guard !Task.isCancelled else { return }
            }
            if mode == .photo {
                flash = true
                withAnimation(.easeOut(duration: 0.45)) { flash = false }
                NSSound(named: "Tink")?.play()
                camera.takePhoto { _ in library.reload() }
            } else {
                camera.startRecording()
            }
        }
    }
}
