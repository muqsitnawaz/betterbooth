import AVFoundation
import SwiftUI

/// The camera's name on the preview; click it to pick another camera.
struct CameraMenu: View {
    @ObservedObject var camera: Camera

    var body: some View {
        let current = camera.devices.first { $0.uniqueID == camera.config.deviceID }
        Menu {
            Picker("Camera", selection: $camera.config.deviceID) {
                ForEach(camera.devices, id: \.uniqueID) { device in
                    Text(device.isSuspended ? "\(device.localizedName) (off: lid closed)" : device.localizedName)
                        .tag(Optional(device.uniqueID))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: current?.deviceType == .continuityCamera ? "iphone" : "camera.fill")
                Text(current?.localizedName ?? "No Camera").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .overlayChip()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(camera.isRecording)
        .help("Camera")
    }
}

/// 9:16, 4:5, 3:4, 1:1, and the button that turns the frame on its side.
struct AspectPicker: View {
    @Binding var config: Config

    var body: some View {
        let landscape = config.landscape, square = config.aspect.isSquare
        HStack(spacing: 4) {
            ForEach(Aspect.allCases) { aspect in
                Button { config.aspect = aspect } label: {
                    Text(aspect.label(landscape: landscape))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(aspect == config.aspect ? Color.black : Color.secondary)
                        .background(aspect == config.aspect ? Color.white.opacity(0.9) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Button { if !square { config.landscape.toggle() } } label: {
                Image(systemName: landscape ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
                    .foregroundStyle(square ? Color.secondary.opacity(0.5) : Color.secondary)
                    .padding(.leading, 6)
            }
            .buttonStyle(.borderless)
            .imageScale(.large)
            .keyboardShortcut("r", modifiers: [])
            .help((square ? "A square has no orientation" : "Turn the frame to \(landscape ? "portrait" : "landscape") · R")
                  + " · right-click if the camera is mounted sideways")
            .contextMenu {
                Picker("Camera Mounted", selection: $config.rotation) {
                    ForEach([0, 90, 180, 270], id: \.self) { Text($0 == 0 ? "Upright" : "Turn Picture \($0)° Clockwise").tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

/// Opened from the format badge: the settings that change the file rather than the picture.
struct SettingsPanel: View {
    @ObservedObject var camera: Camera
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Camera Settings").font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.bottom, 6)
            row("Resolution", note: upscaled ? "Above \(camera.mode.nativeShort)p this camera's picture is upscaled." : nil) {
                Picker("Resolution", selection: $camera.config.resolution) {
                    ForEach(Resolution.allCases) { Text($0.label).tag($0) }
                }
            }
            if camera.config.mode == .video {
                Divider()
                row("Frame rate") {
                    Picker("Frame rate", selection: Binding(get: { camera.mode.rate }, set: { camera.config.frameRate = $0 })) {
                        ForEach(FrameRate.allCases.filter(camera.mode.supportedRates.contains)) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            Divider()
            toggle("Mirror", note: "Flip like a selfie camera.", isOn: $camera.config.mirrored)
            Divider()
            toggle("Location", note: camera.config.saveLocation && camera.locator.denied
                   ? "Off in System Settings → Privacy & Security → Location Services."
                   : "Adds where photos and videos were taken.", isOn: $camera.config.saveLocation)
            Button { NSApp.terminate(nil) } label: {
                HStack {
                    Text("Quit Camera")
                    Spacer()
                    Text("⌘Q").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .padding(.top, 6)
        }
        .controlSize(.small)
        .font(.callout)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .disabled(camera.isRecording)
    }

    private var upscaled: Bool { camera.mode.nativeShort > 0 && camera.config.resolution.rawValue > camera.mode.nativeShort }

    private func row(_ title: String, note: String? = nil, @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title, note: note)
            control().pickerStyle(.segmented).labelsHidden()
        }
        .padding(.vertical, 7)
    }

    private func toggle(_ title: String, note: String, isOn: Binding<Bool>) -> some View {
        HStack {
            label(title, note: note)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 7)
    }

    private func label(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).fixedSize()
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Over the bottom of the picture, so each change shows as it is made.
struct EffectsTray: View {
    @Binding var config: Config
    @Binding var ringLight: RingLight.Level
    @Binding var ringLightDisplays: String

    var body: some View {
        VStack(spacing: 8) {
            row("Portrait blur", icon: "camera.aperture", selection: $config.blur)
            row("Brighten", icon: "sun.max", selection: $config.brighten)
            row("Ring light", icon: "display", selection: $ringLight)
                .help(NSScreen.screens.count > 1 ? "Light your face from the edges of the screen · right-click to pick displays"
                                                 : "Light your face from the edges of the screen")
                .contextMenu {
                    if NSScreen.screens.count > 1 {
                        Section("Displays") {
                            ForEach(NSScreen.screens, id: \.displayID) { Toggle($0.localizedName, isOn: displayBinding($0)) }
                        }
                    }
                }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row<Level: CaseIterable & Hashable & RawRepresentable<String>>(
        _ title: String, icon: String, selection: Binding<Level>
    ) -> some View where Level.AllCases: RandomAccessCollection {
        HStack {
            Label(title, systemImage: icon).font(.callout).fixedSize()
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                ForEach(Level.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
        }
    }

    private var chosenDisplays: Set<String> { Set(RingLight.screens(chosen: ringLightDisplays).map(\.displayID)) }

    private func displayBinding(_ screen: NSScreen) -> Binding<Bool> {
        Binding(
            get: { chosenDisplays.contains(screen.displayID) },
            set: { on in
                var chosen = chosenDisplays
                if on { chosen.insert(screen.displayID) } else { chosen.remove(screen.displayID) }
                // Unchecking the last display turns the light off rather than back to the main one.
                guard !chosen.isEmpty else { ringLight = .off; return }
                ringLightDisplays = chosen.sorted().joined(separator: ",")
                if ringLight == .off { ringLight = .soft }
            })
    }
}
