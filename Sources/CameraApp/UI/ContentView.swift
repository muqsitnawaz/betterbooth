import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var camera: Camera
    @ObservedObject var library: Library
    @AppStorage("timer") private var timerOn = false
    @AppStorage("timerSeconds") private var timerSeconds = 3
    @AppStorage("ringLightLevel") private var ringLight = RingLight.Level.off
    /// The displays the ring light shines from, by ID; empty is the main display.
    @AppStorage("ringLightDisplays") private var ringLightDisplays = ""
    @State private var overlay: Overlay?
    @State private var countdown: Int?
    @State private var flash = false
    @State private var countdownTask: Task<Void, Never>?
    /// A capture shown in place of the live picture.
    @State private var viewing: URL?

    enum Overlay { case settings, effects }

    private var mode: Mode { camera.config.mode }

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
        VStack(spacing: 14) {
            preview
            AspectPicker(config: $camera.config)
                .disabled(camera.isRecording)
            modePicker
            shutterRow
            if !library.items.isEmpty { strip }
        }
        .padding(14)
        .frame(width: max(previewSize.width, 300) + 28)
        .animation(.easeInOut(duration: 0.25), value: camera.config.ratio)
        // Closing the popover stops the camera; a countdown must not fire into a stopped camera.
        .onDisappear {
            countdownTask?.cancel()
            countdown = nil
        }
        .onChange(of: shownRingLight, initial: true) { RingLight.show(shownRingLight, on: ringLightScreens) }
        .onChange(of: ringLightDisplays) { RingLight.show(shownRingLight, on: ringLightScreens) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            RingLight.show(shownRingLight, on: ringLightScreens)
        }
    }

    private var shownRingLight: RingLight.Level { camera.feed == .off ? .off : ringLight }

    private var ringLightScreens: [NSScreen] { RingLight.screens(chosen: ringLightDisplays) }

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
            if let viewing {
                CaptureViewer(url: viewing, library: library, close: { self.viewing = nil }, step: step)
            } else {
                previewOverlays
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var previewOverlays: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                if let since = camera.recordingSince {
                    Spacer()
                    RecordingBadge(since: since)
                    Spacer()
                } else {
                    CameraMenu(camera: camera)
                    Spacer(minLength: 8)
                    Button { toggle(.settings) } label: {
                        Text(mode == .video ? "\(camera.config.resolution.badge) · \(camera.mode.rate.rawValue)" : camera.config.resolution.badge)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .overlayChip()
                    }
                    .buttonStyle(.plain)
                    .help("Camera Settings")
                }
            }
            if overlay == .settings {
                SettingsPanel(camera: camera, close: { overlay = nil })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if let error = camera.errorMessage {
                Text(error)
                    .font(.caption)
                    .padding(6)
                    .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
            }
            if overlay == .effects {
                EffectsTray(config: $camera.config, ringLight: $ringLight, ringLightDisplays: $ringLightDisplays)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack {
                Spacer()
                Button { toggle(.effects) } label: {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(effectsOn ? Color.black : Color.white)
                        .frame(width: 28, height: 28)
                        .background(effectsOn ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.black.opacity(0.45)), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Effects: portrait blur, brighten, ring light")
            }
        }
        .padding(8)
        .animation(.easeOut(duration: 0.2), value: overlay)
    }

    private var effectsOn: Bool { camera.config.blur != .off || camera.config.brighten != .off || ringLight != .off }

    private func toggle(_ shown: Overlay) { overlay = overlay == shown ? nil : shown }

    // MARK: Controls

    private var modePicker: some View {
        HStack(spacing: 22) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button { camera.config.mode = m } label: {
                    Text(m.rawValue.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(m == mode ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(camera.isRecording || countdown != nil)
    }

    private var shutterRow: some View {
        HStack {
            HStack(spacing: 10) {
                timerButton
                if mode == .video { mic }
            }
            .frame(width: 90, alignment: .leading)
            Spacer()
            ShutterButton(mode: mode, recording: camera.isRecording, returnsToCamera: viewing != nil, action: shutter)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(camera.access != .granted || countdown != nil)
            Spacer()
            Button { NSWorkspace.shared.open(Library.folder) } label: {
                Image(systemName: "folder")
            }
            .help("Open the Camera folder in Finder")
            .frame(width: 90, alignment: .trailing)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
    }

    private var timerButton: some View {
        Button { timerOn.toggle() } label: {
            Image(systemName: "timer")
                .foregroundStyle(timerOn ? Color.yellow : Color.secondary)
                .overlay(alignment: .bottomTrailing) {
                    if timerOn { Text("\(timerSeconds)").font(.system(size: 8, weight: .bold)).foregroundStyle(.yellow).offset(x: 5, y: 3) }
                }
        }
        .help(timerOn ? "\(timerSeconds)-second timer · right-click for others" : "No timer · right-click for 3 or 10 seconds")
        .contextMenu {
            Picker("Timer", selection: Binding(get: { timerSeconds }, set: { timerSeconds = $0; timerOn = true })) {
                Text("3 Seconds").tag(3)
                Text("10 Seconds").tag(10)
            }
            .pickerStyle(.inline)
        }
        .disabled(camera.isRecording)
    }

    private var mic: some View {
        let systemDefault = AVCaptureDevice.default(for: .audio)?.localizedName
        let chosen = camera.mics.first { $0.uniqueID == camera.config.micID }?.localizedName ?? systemDefault ?? "the default microphone"
        return HStack(spacing: 3) {
            Button { camera.config.micOn.toggle() } label: {
                Image(systemName: camera.config.micOn ? "mic.fill" : "mic.slash")
                    .foregroundStyle(camera.config.micOn ? Color.yellow : Color.secondary)
            }
            .help(camera.config.micOn ? "Recording sound from \(chosen) · click to mute, right-click to pick a microphone"
                                      : "Muted · click to record sound, right-click to pick a microphone")
            .contextMenu {
                Picker("Microphone", selection: Binding(get: { camera.config.micID }, set: { camera.config.micID = $0; camera.config.micOn = true })) {
                    Text(systemDefault.map { "System Default (\($0))" } ?? "System Default").tag(String?.none)
                    ForEach(camera.mics, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                .pickerStyle(.inline)
            }
            if camera.config.micOn { LevelMeter(level: camera.micLevel) }
        }
        .disabled(camera.isRecording)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(library.items, id: \.self) { url in
                    Thumbnail(url: url)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.yellow, lineWidth: viewing == url ? 2 : 0))
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                        .onTapGesture { viewing = url; overlay = nil }
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .contextMenu {
                            ShareLink("Share…", item: url)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([url as NSURL])
                            }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button("Move to Trash") { library.trash(url) }
                        }
                }
            }
        }
        .frame(height: 48)
    }

    // MARK: Actions

    /// The strip is newest first.
    private func step(_ by: Int) {
        guard let viewing, let i = library.items.firstIndex(of: viewing) else { return }
        let j = i + by
        if library.items.indices.contains(j) { self.viewing = library.items[j] }
    }

    private func shutter() {
        overlay = nil
        if viewing != nil {
            viewing = nil
            return
        }
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
