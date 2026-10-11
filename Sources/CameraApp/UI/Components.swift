import AVFoundation
import SwiftUI

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

struct LevelMeter: View {
    @ObservedObject var level: MicLevel
    var body: some View {
        let value = CGFloat(level.value)
        Capsule()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 4, height: 18)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(value > 0.85 ? Color.yellow : Color.green)
                    .frame(width: 4, height: max(2, 18 * value))
                    .animation(.linear(duration: 0.08), value: value)
            }
            .help("Microphone level")
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
