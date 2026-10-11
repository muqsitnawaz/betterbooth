import SwiftUI
import AVFoundation
import AVKit

enum Mode: String { case photo, video }

struct ContentView: View {
    @ObservedObject var camera: Camera
    @ObservedObject var library: Library
    @AppStorage("mode") private var mode: Mode = .photo
    @AppStorage("timer") private var timerOn = false
    @State private var countdown: Int?
    @State private var flash = false
    @State private var countdownTask: Task<Void, Never>?
    /// A capture shown in place of the live picture.
    @State private var viewing: URL?

    /// The preview's long side is 512 points; the short side follows the aspect.
    private var previewSize: CGSize {
        let r = camera.config.ratio
        return r >= 1 ? CGSize(width: 512, height: (512 / r).rounded()) : CGSize(width: (512 * r).rounded(), height: 512)
    }

    private var feedMessage: String? {
        switch camera.feed {
        case .live, .off: return nil
        case .waiting: return "Waiting for \(camera.deviceName)…"
        case .black: return "The picture from \(camera.deviceName) is black.\nIf it shouldn't be, check the camera is on and plugged in."
        case .suspended: return "\(camera.deviceName) is off while the lid is closed.\nPick another camera from the ⋯ menu."
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
        .frame(width: max(previewSize.width, 420) + 28)
        .animation(.easeInOut(duration: 0.25), value: camera.config.ratio)
        // Closing the popover stops the camera; a countdown must not fire into a stopped camera.
        .onDisappear {
            countdownTask?.cancel()
            countdown = nil
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            PreviewView(layer: camera.displayLayer)
            if camera.access == .denied {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill").font(.title)
                    Text("VertCam needs camera access.").font(.callout)
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

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("Aspect ratio", selection: $camera.config.aspect) {
                    ForEach(Aspect.allCases) { Text($0.label(landscape: camera.config.landscape)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Aspect ratio: 9:16 for Reels, Shorts and TikTok")

                let landscape = camera.config.landscape
                Button { camera.config.landscape.toggle() } label: {
                    Image(systemName: landscape ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
                        .frame(width: 22)
                }
                .buttonStyle(.borderless)
                .imageScale(.large)
                .keyboardShortcut("r", modifiers: [])
                .disabled(camera.config.aspect.isSquare)
                .help(camera.config.aspect.isSquare ? "A square has no orientation"
                      : "Turn the frame to \(landscape ? "portrait" : "landscape") (\(camera.config.aspect.label(landscape: !landscape))) · R")
            }

            HStack(spacing: 10) {
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

                toggle(camera.config.mirrored, on: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
                       off: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Mirror") {
                    camera.config.mirrored.toggle()
                }
                micMenu
                toggle(timerOn, on: "timer", off: "timer", help: "3-second timer") { timerOn.toggle() }

                Menu {
                    Picker("Camera", selection: $camera.config.deviceID) {
                        ForEach(camera.devices, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                    }
                    .pickerStyle(.inline)
                    // For a camera mounted on its side or upside down; remembered per camera.
                    Picker("Turn Picture", selection: $camera.config.rotation) {
                        ForEach([0, 90, 180, 270], id: \.self) { Text($0 == 0 ? "Upright" : "\($0)° Clockwise").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Divider()
                    Button("Open VertCam Folder") { NSWorkspace.shared.open(Library.folder) }
                    Button("Quit VertCam") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Camera and more")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .buttonStyle(.borderless)
            .imageScale(.large)
        }
        .disabled(camera.isRecording)
    }

    /// "off", "" for the system default, or a microphone's ID.
    private var micChoice: Binding<String> {
        Binding(
            get: { camera.config.micOn ? camera.config.micID ?? "" : "off" },
            set: { choice in
                camera.config.micOn = choice != "off"
                if choice != "off" { camera.config.micID = choice.isEmpty ? nil : choice }
            })
    }

    private var micMenu: some View {
        let systemDefault = AVCaptureDevice.default(for: .audio)?.localizedName
        let chosen = camera.mics.first { $0.uniqueID == camera.config.micID }?.localizedName ?? systemDefault
        return Menu {
            Picker("Microphone", selection: micChoice) {
                Text("No Sound").tag("off")
                Text(systemDefault.map { "System Default (\($0))" } ?? "System Default").tag("")
                ForEach(camera.mics, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: camera.config.micOn ? "mic.fill" : "mic.slash")
                .foregroundStyle(camera.config.micOn ? Color.accentColor : Color.secondary)
                .frame(width: 22)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(camera.config.micOn ? "Recording sound from \(chosen ?? "the default microphone")" : "No sound; click to pick a microphone")
    }

    private func toggle(_ isOn: Bool, on: String, off: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? on : off)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 22)
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
            .help("Open the VertCam folder")
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

    /// Steps through the strip from the capture being viewed; the strip is newest first.
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
                for n in stride(from: 3, through: 1, by: -1) {
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

/// Shows a photo, or plays a video, from the strip inside the preview area.
struct CaptureViewer: View {
    let url: URL
    @ObservedObject var library: Library
    let close: () -> Void
    let step: (Int) -> Void
    @State private var player: AVPlayer?
    @State private var image: NSImage?

    private var isVideo: Bool { url.pathExtension.lowercased() == "mp4" }

    var body: some View {
        ZStack {
            Color.black
            if isVideo, let player {
                VideoPlayer(player: player)
            } else if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            }
            VStack {
                HStack(spacing: 6) {
                    pill("Camera", icon: "chevron.left", help: "Back to the camera (Esc)", action: close)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    pill(nil, icon: "arrow.up.forward.app", help: "Open in \(isVideo ? "QuickTime" : "Preview")") { NSWorkspace.shared.open(url) }
                    pill(nil, icon: "folder", help: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    pill(nil, icon: "trash", help: "Move to Trash") {
                        library.trash(url)
                        close()
                    }
                }
                Spacer()
                HStack {
                    pill(nil, icon: "chevron.left", help: "Newer (←)") { step(-1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Spacer()
                    Text(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "VertCam ", with: ""))
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    pill(nil, icon: "chevron.right", help: "Older (→)") { step(1) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .padding(.bottom, isVideo ? 44 : 0)  // clear of the player's controls
            }
            .padding(8)
        }
        .task(id: url) {
            player?.pause()
            if isVideo {
                let p = AVPlayer(url: url)
                player = p
                image = nil
                p.play()
            } else {
                player = nil
                image = NSImage(contentsOf: url)
            }
        }
        .onDisappear { player?.pause() }
    }

    private func pill(_ title: String?, icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                if let title { Text(title) }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ShutterButton: View {
    let mode: Mode
    let recording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.primary.opacity(0.8), lineWidth: 3).frame(width: 52, height: 52)
                RoundedRectangle(cornerRadius: recording ? 5 : 21)
                    .fill(mode == .photo ? Color.white : Color.red)
                    .frame(width: recording ? 22 : 42, height: recording ? 22 : 42)
                    .shadow(color: .black.opacity(0.2), radius: 1)
            }
            .contentShape(Circle())
            .animation(.spring(duration: 0.25), value: recording)
        }
        .buttonStyle(.plain)
        .help(mode == .photo ? "Take photo (Space)" : recording ? "Stop recording (Space)" : "Start recording (Space)")
    }
}

struct RecordingBadge: View {
    let since: Date
    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let s = max(0, Int(context.date.timeIntervalSince(since)))
            HStack(spacing: 5) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(String(format: "%02d:%02d", s / 60, s % 60)).font(.caption.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
        }
    }
}

struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if url.pathExtension.lowercased() == "mp4" {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(4)
                    .shadow(radius: 2)
            }
        }
        .help(url.lastPathComponent)
        .task(id: url) { image = await Library.thumbnail(for: url, size: 128) }
    }
}

struct PreviewView: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> LayerHost {
        let view = LayerHost()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: LayerHost, context: Context) {}

    final class LayerHost: NSView {
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.sublayers?.forEach { $0.frame = bounds }
            CATransaction.commit()
        }
    }
}
