import AVFoundation
import CoreImage
import AppKit
import UniformTypeIdentifiers

/// A frame shape, named in its portrait form. `Config.landscape` lays it on its side, so 9:16
/// and 16:9 are one shape turned, not two choices.
enum Aspect: String, CaseIterable, Identifiable, Codable {
    case r9x16 = "9:16", r4x5 = "4:5", r3x4 = "3:4", r1x1 = "1:1"
    var id: String { rawValue }
    private var parts: (short: Int, long: Int) {
        let p = rawValue.split(separator: ":").compactMap { Int($0) }
        return (p[0], p[1])
    }
    var isSquare: Bool { self == .r1x1 }
    /// "9:16" upright, "16:9" on its side.
    func label(landscape: Bool) -> String { landscape ? "\(parts.long):\(parts.short)" : rawValue }
    /// Width over height.
    func ratio(landscape: Bool) -> CGFloat {
        landscape ? CGFloat(parts.long) / CGFloat(parts.short) : CGFloat(parts.short) / CGFloat(parts.long)
    }

    /// The shape and orientation written as "16:9" or "9:16".
    static func parse(_ text: String) -> (Aspect, landscape: Bool)? {
        for aspect in allCases {
            if text == aspect.label(landscape: false) { return (aspect, false) }
            if text == aspect.label(landscape: true) { return (aspect, true) }
        }
        return nil
    }
}

enum Resolution: Int, CaseIterable, Identifiable, Codable {
    case p720 = 720, p1080 = 1080, p1440 = 1440, p2160 = 2160
    var id: Int { rawValue }
    var label: String { self == .p2160 ? "4K" : "\(rawValue)p" }
}

enum FrameRate: String, CaseIterable, Identifiable, Codable {
    case f23_98 = "23.98", f24 = "24", f30 = "30", f60 = "60"
    var id: String { rawValue }
    var label: String { "\(rawValue) fps" }
    var value: Double { self == .f23_98 ? 24_000.0 / 1001 : Double(rawValue)! }
    var frameDuration: CMTime { self == .f23_98 ? CMTime(value: 1001, timescale: 24_000) : CMTime(value: 1, timescale: CMTimeScale(value)) }

    func fits(_ range: AVFrameRateRange) -> Bool {
        range.minFrameRate <= value + 0.01 && range.maxFrameRate >= value - 0.01
    }
}

/// Everything the person chose. The camera is always configured from one of these, in one place
/// (`Camera.apply`), so no setting can leave another half-applied.
struct Config: Equatable, Codable {
    var deviceID: String?
    var aspect: Aspect = .r9x16
    var landscape = false
    var resolution: Resolution = .p1080
    var frameRate: FrameRate = .f30
    var mirrored = true
    var micOn = true
    /// The microphone to record from; nil is the system's default input.
    var micID: String?
    /// Clockwise turn per camera, for one mounted sideways or upside down.
    var rotations: [String: Int] = [:]

    var rotation: Int {
        get { deviceID.flatMap { rotations[$0] } ?? 0 }
        set { if let deviceID { rotations[deviceID] = ((newValue % 360) + 360) % 360 } }
    }
    var aspectLabel: String { aspect.label(landscape: landscape) }
    var ratio: CGFloat { aspect.ratio(landscape: landscape) }

    /// Output size with the chosen resolution on the short side, both sides even for the encoder.
    var outputSize: CGSize {
        let short = resolution.rawValue
        let long = Int((CGFloat(short) * max(ratio, 1 / ratio) / 2).rounded()) * 2
        return ratio >= 1 ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
    }

    /// Short side of the largest region of a `width`×`height` frame this shape can be cut from.
    func nativeShort(width: Int, height: Int) -> Int {
        let w = CGFloat(width), h = CGFloat(height)
        let crop = w / h > ratio ? CGSize(width: h * ratio, height: h) : CGSize(width: w, height: w / ratio)
        return Int(min(crop.width, crop.height))
    }

    init() {}

    /// Every field is optional so a config saved by an older build keeps what it can, rotations
    /// above all, instead of resetting to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID)
        if let v = try? c.decodeIfPresent(Aspect.self, forKey: .aspect) { aspect = v }
        if let wide = try? c.decodeIfPresent(Bool.self, forKey: .landscape) { landscape = wide }
        if let v = try? c.decodeIfPresent(Resolution.self, forKey: .resolution) { resolution = v }
        if let v = try? c.decodeIfPresent(FrameRate.self, forKey: .frameRate) { frameRate = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .mirrored) { mirrored = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .micOn) { micOn = v }
        micID = try? c.decodeIfPresent(String.self, forKey: .micID)
        if let v = try? c.decodeIfPresent([String: Int].self, forKey: .rotations) { rotations = v }
    }

    static func load() -> Config {
        UserDefaults.standard.data(forKey: "config").flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "config") }
    }
}

/// What the chosen camera can actually do with the current config.
struct CameraMode: Equatable {
    var supportedRates: Set<FrameRate> = []
    /// The rate in use: the chosen one, or the nearest the camera has.
    var rate: FrameRate = .f30
    /// Real camera pixels on the short side behind the current aspect; larger outputs are upscaled.
    var nativeShort = 0
}

/// Owns the capture session and the single render pipeline. Every frame is turned, cropped to the
/// chosen aspect, scaled to the chosen resolution and mirrored once; that same buffer is shown in
/// the preview, written to a recording, and kept for the next photo, so files match the preview.
final class Camera: NSObject, ObservableObject {
    enum Access { case unknown, granted, denied }
    /// What the preview is getting, judged from the frames that actually arrive.
    enum Feed: Equatable { case off, waiting, live, black, suspended, noCamera }

    @Published var config: Config { didSet { configChanged(from: oldValue) } }
    @Published private(set) var mode = CameraMode()
    @Published private(set) var access: Access = .unknown
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var mics: [AVCaptureDevice] = []
    @Published private(set) var feed: Feed = .off
    @Published private(set) var recordingSince: Date?
    @Published private(set) var errorMessage: String?

    let displayLayer = AVSampleBufferDisplayLayer()
    /// Off for scripted captures so their flags never become the saved settings. Fixed at init
    /// because init itself can switch cameras, which saves.
    let persists: Bool
    var isRecording: Bool { recordingSince != nil }
    var deviceName: String { devices.first { $0.uniqueID == config.deviceID }?.localizedName ?? "the camera" }

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    /// Session inputs and the camera's format are only touched on this queue.
    private let sessionQueue = DispatchQueue(label: "vertcam.session")
    /// Frames, audio samples, the render settings and the recorder are only touched on this queue.
    private let frameQueue = DispatchQueue(label: "vertcam.frames", qos: .userInteractive)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // Session queue state.
    private var appliedMode: (device: AVCaptureDevice, format: AVCaptureDevice.Format, duration: CMTime)?

    // Frame queue state.
    private struct Render: Equatable { var deviceID: String?; var size: CGSize; var mirrored: Bool; var rotation: Int }
    private var renderState = Render(deviceID: nil, size: .zero, mirrored: true, rotation: 0)
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero
    private var lastFrame: CVPixelBuffer?
    private var recorder: Recorder?
    private var lastReport = Date.distantPast

    // Main queue state: when the frame queue last reported a frame, and whether it was black.
    private var lastFrameSeen = Date.distantPast
    private var lastFrameBlack = false
    private var running = false
    /// stop() was asked for during a recording; honoured when the recording ends.
    private var stopWhenDone = false
    private var healthTimer: Timer?
    private var appliedDeviceID: String?
    /// The camera the person picked, kept while a stand-in is used because it is unplugged.
    private var chosenDeviceID: String?
    private var switchingAutomatically = false
    /// A Mac's own camera is suspended while its lid is closed: connected, but sending nothing.
    private var suspensionWatches: [NSKeyValueObservation] = []

    init(persists: Bool) {
        self.persists = persists
        config = Config.load()
        super.init()
        chosenDeviceID = config.deviceID
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        audioOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        audioOutput.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshDevices() }
        }
        refreshDevices()
    }

    // MARK: Configuration

    private func configChanged(from old: Config) {
        guard config != old else { return }
        // The output size and camera are fixed for the length of a recording.
        if isRecording && (config.outputSize != old.outputSize || config.deviceID != old.deviceID || config.rotation != old.rotation) {
            config = old  // setting a property inside its own didSet does not re-enter didSet
            return
        }
        if config.deviceID != old.deviceID && !switchingAutomatically { chosenDeviceID = config.deviceID }
        if persists {
            var saved = config
            saved.deviceID = chosenDeviceID  // a stand-in camera is never remembered as the choice
            saved.save()
        }
        apply()
    }

    private func refreshDevices() {
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified).devices
        mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        suspensionWatches = devices.map { device in
            device.observe(\.isSuspended) { [weak self] _, _ in DispatchQueue.main.async { self?.refreshDevices() } }
        }
        // The camera you chose whenever it works; otherwise stay on the current one, or stand in
        // with the built-in camera, then any other. A suspended camera is used only when no other
        // works. Never mid-recording: recordingEnded() catches up.
        func pick(_ cameras: [AVCaptureDevice]) -> String? {
            [chosenDeviceID, config.deviceID].compactMap { $0 }.first { id in cameras.contains { $0.uniqueID == id } }
                ?? (cameras.first { $0.deviceType == .builtInWideAngleCamera } ?? cameras.first)?.uniqueID
        }
        let target = pick(devices.filter { !$0.isSuspended }) ?? pick(devices)
        if target != config.deviceID && !isRecording {
            switchingAutomatically = true
            config.deviceID = target  // didSet applies it
            switchingAutomatically = false
            return
        }
        apply()
    }

    /// Brings the session, the camera's format and the render settings in line with `config`.
    private func apply() {
        let config = config
        let device = devices.first { $0.uniqueID == config.deviceID }
        let render = Render(deviceID: device?.uniqueID, size: config.outputSize, mirrored: config.mirrored, rotation: config.rotation)
        if device?.uniqueID != appliedDeviceID {
            appliedDeviceID = device?.uniqueID
            lastFrameSeen = .distantPast  // the new camera is live only once its own frames arrive
            updateFeed()
        }
        frameQueue.async {
            if render.size != self.renderState.size || render.deviceID != self.renderState.deviceID || render.rotation != self.renderState.rotation {
                self.lastFrame = nil  // a photo must never be a frame from before the change
            }
            self.renderState = render
        }

        guard let device else {
            mode = CameraMode()
            feed = .noCamera
            sessionQueue.async { self.setCamera(nil) }
            return
        }

        let rates = Set(FrameRate.allCases.filter { rate in
            device.formats.contains { $0.videoSupportedFrameRateRanges.contains(where: rate.fits) }
        })
        let rate = rates.contains(config.frameRate) ? config.frameRate
            : rates.min { abs($0.value - config.frameRate.value) < abs($1.value - config.frameRate.value) }
        let sideways = config.rotation % 180 != 0
        func score(_ f: AVCaptureDevice.Format) -> (Int, Int) {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let w = Int(sideways ? d.height : d.width), h = Int(sideways ? d.width : d.height)
            return (config.nativeShort(width: w, height: h), -w * h)
        }
        // The mode that runs at the rate and keeps the most real pixels once turned and cropped,
        // such as the MacBook camera's 1080×1920 mode for 9:16.
        guard let rate, let format = device.formats
            .filter({ $0.videoSupportedFrameRateRanges.contains(where: rate.fits) })
            .max(by: { score($0) < score($1) }),
              let range = format.videoSupportedFrameRateRanges.first(where: rate.fits)
        else {
            mode = CameraMode()
            return report("\(device.localizedName) offers no video mode VertCam can use")
        }
        // AVFoundation raises an uncatchable exception for a duration outside the format's range,
        // and fixed-rate cameras such as the Cam Link 4K report 30 fps as a duration that is not
        // exactly 1/30, so the duration is clamped into the range the camera reported.
        let duration = min(max(rate.frameDuration, range.minFrameDuration), range.maxFrameDuration)
        mode = CameraMode(supportedRates: rates, rate: rate, nativeShort: score(format).0)
        sessionQueue.async {
            self.setCamera(device)
            self.appliedMode = (device, format, duration)
            self.applyMode()
        }
    }

    /// Session queue only. Swaps the video input when the camera changed; leaves the mic alone.
    private func setCamera(_ device: AVCaptureDevice?) {
        let cameras = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.filter { $0.device.hasMediaType(.video) }
        guard cameras.first?.device != device else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        cameras.forEach { session.removeInput($0) }
        appliedMode = nil
        guard let device else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CamError.message("\(device.localizedName) is in use by another app") }
            session.addInput(input)
            report(nil)
        } catch {
            report(error.localizedDescription)
        }
    }

    /// Session queue only. Sets the camera's format and frame rate. Starting or reconfiguring
    /// the session puts the camera back on its defaults, so this runs again after each.
    private func applyMode() {
        guard let m = appliedMode,
              session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device == m.device }) else { return }
        do {
            try m.device.lockForConfiguration()
            m.device.activeFormat = m.format
            m.device.activeVideoMinFrameDuration = m.duration
            m.device.activeVideoMaxFrameDuration = m.duration
            m.device.unlockForConfiguration()
        } catch {
            report("Couldn't set up \(m.device.localizedName): \(error.localizedDescription)")
        }
    }

    // MARK: Session

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
            stopWhenDone = false
            guard !running else { return }
            running = true
            lastFrameSeen = .distantPast
            updateFeed()
            sessionQueue.async {
                self.session.startRunning()
                self.applyMode()
            }
            healthTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateFeed() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    self.access = ok ? .granted : .denied
                    if ok { self.start() }
                }
            }
        default:
            access = .denied
        }
    }

    func stop() {
        guard running else { return }
        guard !isRecording else { stopWhenDone = true; return }
        running = false
        healthTimer?.invalidate()
        healthTimer = nil
        feed = .off
        sessionQueue.async { self.session.stopRunning() }
        frameQueue.async { self.lastFrame = nil }
    }

    /// Main queue. The feed is live while frames keep arriving; a camera can stay connected and
    /// send nothing (a Continuity Camera whose phone moved away) or send black (a capture card
    /// whose HDMI source went to sleep).
    private func updateFeed() {
        guard running else { return }
        let next: Feed
        if let device = devices.first(where: { $0.uniqueID == config.deviceID }) {
            next = device.isSuspended ? .suspended
                : Date().timeIntervalSince(lastFrameSeen) > 1.5 ? .waiting
                : lastFrameBlack ? .black : .live
        } else {
            next = .noCamera
        }
        if feed != next { feed = next }
    }

    private func report(_ message: String?) {
        DispatchQueue.main.async { self.errorMessage = message }
    }

    // MARK: Capture

    /// Words for a file name that make captures searchable: camera, aspect, resolution, and for
    /// video the frame rate, e.g. `cam-link-4k 9x16 1080p 30fps`.
    private func fileTags(video: Bool) -> [String] {
        // "Alex’s iPhone Camera" → "iphone": no owner's name in shared files, no "camera" on every one.
        let camera = deviceName
            .replacingOccurrences(of: #"^\S+[’']s\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+camera$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let fps = mode.rate.rawValue.replacingOccurrences(of: ".", with: "_") + "fps"
        return [camera.isEmpty ? "camera" : camera,
                config.aspectLabel.replacingOccurrences(of: ":", with: "x"),
                config.resolution.label.lowercased()] + (video ? [fps] : [])
    }

    /// Why a capture can't start right now, or nil when it can.
    private var notReady: String? {
        switch feed {
        // A black picture is shown as a hint only: a dark room or a covered lens is still a picture.
        case .live, .black: return nil
        case .suspended: return "\(deviceName) is off while the lid is closed"
        case .noCamera: return "No camera connected"
        default: return "No picture from \(deviceName) yet"
        }
    }

    func takePhoto(completion: @escaping (URL?) -> Void) {
        if let notReady {
            report(notReady)
            return completion(nil)
        }
        let url = Library.newURL(ext: "jpg", tags: fileTags(video: false))
        frameQueue.async {
            guard let frame = self.lastFrame,
                  let cg = self.ciContext.createCGImage(CIImage(cvPixelBuffer: frame), from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame)), format: .RGBA8, colorSpace: self.colorSpace)
            else {
                self.report("No picture from the camera yet")
                return DispatchQueue.main.async { completion(nil) }
            }
            var saved: URL?
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
                if CGImageDestinationFinalize(dest) { saved = url }
            }
            if saved == nil { self.report("Couldn't save the photo") }
            DispatchQueue.main.async { completion(saved) }
        }
    }

    /// Start and stop both pass through the session queue and then the frame queue, so a stop can
    /// never overtake the start it ends.
    func startRecording() {
        guard !isRecording else { return }
        if let notReady { return report(notReady) }
        // Ask for the microphone before recording starts, so a pending prompt never holds a Stop.
        if config.micOn, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.startRecording() } }
            return
        }
        let url = Library.newURL(ext: "mp4", tags: fileTags(video: true))
        let size = config.outputSize, rate = mode.rate
        // The chosen microphone while it is connected, otherwise the system's default input.
        let mic = config.micOn && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? mics.first { $0.uniqueID == config.micID } ?? AVCaptureDevice.default(for: .audio) : nil
        let audio = mic != nil
        if config.micOn && !audio {
            report("Recording without sound: allow VertCam in System Settings → Privacy & Security → Microphone")
        }
        recordingSince = Date()
        sessionQueue.async {
            // Adding the microphone pauses the camera for most of a second, so it joins before the
            // file starts; the file begins at the first frame after that pause.
            if let mic { self.setMic(mic) }
            self.frameQueue.async {
                do {
                    self.recorder = try Recorder(url: url, size: size, frameRate: rate, audio: audio)
                } catch {
                    self.report("Couldn't start recording: \(error.localizedDescription)")
                    self.sessionQueue.async { self.setMic(nil) }
                    DispatchQueue.main.async { self.recordingEnded() }
                }
            }
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else { return completion(nil) }
        sessionQueue.async {
            var recorder: Recorder?
            self.frameQueue.sync {
                recorder = self.recorder
                self.recorder = nil
            }
            self.setMic(nil)
            guard let recorder else {
                return DispatchQueue.main.async { self.recordingEnded(); completion(nil) }
            }
            recorder.finish { url in
                if url == nil { self.report(recorder.failure.map { "The recording couldn't be saved: \($0)" } ?? "No picture arrived from the camera") }
                DispatchQueue.main.async { self.recordingEnded(); completion(url) }
            }
        }
    }

    /// Main queue. The one place a recording ends, however it ended: settings frozen during the
    /// recording catch up (a camera unplugged meanwhile is replaced), and a stop asked for while
    /// recording happens now.
    private func recordingEnded() {
        recordingSince = nil
        refreshDevices()
        if stopWhenDone {
            stopWhenDone = false
            stop()
        }
    }

    /// Session queue only. The microphone joins the video session only while recording: one
    /// session keeps sound and picture on one clock, and the microphone indicator stays off while
    /// you are only looking. Puts `mic` in the session, or takes every microphone out for nil.
    private func setMic(_ mic: AVCaptureDevice?) {
        let inputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.filter { $0.device.hasMediaType(.audio) }
        guard inputs.map(\.device.uniqueID) != [mic?.uniqueID].compactMap({ $0 }) else { return }
        session.beginConfiguration()
        inputs.forEach { session.removeInput($0) }
        if let mic, let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        applyMode()
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Every camera here stamps frames on the host clock. A Continuity Camera's first frames can
        // carry a time from its own clock, minutes off, which would stretch a file to half an hour.
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard abs((CMClockGetTime(CMClockGetHostTimeClock()) - time).seconds) < 1 else { return }
        if output === audioOutput {
            recorder?.append(audio: sampleBuffer)
            return
        }
        // A frame still in flight from the camera before a switch is not this camera's picture.
        let from = (connection.inputPorts.first?.input as? AVCaptureDeviceInput)?.device.uniqueID
        guard from == renderState.deviceID, let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = render(source) else { return }
        lastFrame = frame
        recorder?.append(video: frame, at: time)
        show(frame, at: time)

        let now = Date()
        if now.timeIntervalSince(lastReport) > 0.25 {
            lastReport = now
            let black = Self.isBlack(source)
            DispatchQueue.main.async {
                self.lastFrameSeen = now
                self.lastFrameBlack = black
                self.updateFeed()
            }
        }
    }

    /// True when a grid of samples across the frame is all near black.
    private static func isBlack(_ buffer: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return false }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        for gy in 1...9 {
            for gx in 1...9 {
                let p = base + (h * gy / 10) * stride + (w * gx / 10) * 4
                if max(p[0], p[1], p[2]) > 16 { return false }
            }
        }
        return true
    }

    private func render(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let s = renderState
        let size = s.size
        guard size.width > 0, size.height > 0 else { return nil }
        // Mirror, then turn, then cut the aspect. Turning after mirroring means each press of
        // rotate turns the picture you see a quarter clockwise, mirrored or not; and a camera on
        // its side becomes an upright frame before the aspect is cut from it.
        var image = CIImage(cvPixelBuffer: source)
        if s.mirrored {
            image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: image.extent.width, ty: 0))
        }
        switch s.rotation {
        case 90: image = image.oriented(.right)
        case 180: image = image.oriented(.down)
        case 270: image = image.oriented(.left)
        default: break
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

        let extent = image.extent
        let ratio = size.width / size.height
        var crop = extent
        if extent.width / extent.height > ratio {
            crop.size.width = extent.height * ratio
            crop.origin.x = extent.midX - crop.width / 2
        } else {
            crop.size.height = extent.width / ratio
            crop.origin.y = extent.midY - crop.height / 2
        }
        let scale = size.width / crop.width
        image = image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        if pool == nil || poolSize != size {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
            poolSize = size
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return nil }
        ciContext.render(image, to: out, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        return out
    }

    private func show(_ frame: CVPixelBuffer, at time: CMTime) {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: frame, formatDescriptionOut: &format)
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: frame, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }
}

enum CamError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

/// Writes rendered frames and microphone samples to an H.264/AAC MP4. Used only on the frame queue.
final class Recorder {
    private let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var lastVideo = CMTime.negativeInfinity
    private var lastAudio = CMTime.negativeInfinity
    var failure: String? { writer.error?.localizedDescription }

    init(url: URL, size: CGSize, frameRate: FrameRate, audio: Bool) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // About 6 bits per pixel per second at 30 fps: 12 Mbit/s for 1080p, 50 for 4K.
        let bitrate = Double(size.width * size.height) * 6 * frameRate.value / 30
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(bitrate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate.value,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(videoInput) else { throw CamError.message("The video track was refused") }
        writer.add(videoInput)
        if audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CamError.message("The audio track was refused") }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        guard writer.startWriting() else { throw writer.error ?? CamError.message("The writer didn't start") }
    }

    /// Timestamps must rise; the writer fails the whole file on one that doesn't.
    func append(video frame: CVPixelBuffer, at time: CMTime) {
        guard time > lastVideo, writer.status == .writing else { return }
        lastVideo = time
        if startTime == nil {
            writer.startSession(atSourceTime: time)
            startTime = time
        }
        if videoInput.isReadyForMoreMediaData { adaptor.append(frame, withPresentationTime: time) }
    }

    func append(audio sample: CMSampleBuffer) {
        guard let startTime, let audioInput, audioInput.isReadyForMoreMediaData,
              writer.status == .writing else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard time >= startTime, time > lastAudio else { return }
        lastAudio = time
        audioInput.append(sample)
    }

    func finish(_ completion: @escaping (URL?) -> Void) {
        guard startTime != nil else {
            writer.cancelWriting()
            return completion(nil)
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [writer, url] in
            completion(writer.status == .completed ? url : nil)
        }
    }
}
