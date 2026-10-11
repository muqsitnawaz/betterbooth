import AVKit
import SwiftUI

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
                PlayerView(player: player)
            } else if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            }
            VStack {
                HStack(spacing: 6) {
                    pill("Camera", icon: "chevron.left", help: "Back to the camera (Esc)", action: close)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    ShareLink(item: url) { pillLabel(nil, icon: "square.and.arrow.up") }
                        .buttonStyle(.plain)
                        .help("Share")
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
                    Text(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: #"^(Camera|BetterBooth) "#, with: "", options: .regularExpression))
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
        Button(action: action) { pillLabel(title, icon: icon) }
            .buttonStyle(.plain)
            .help(help)
    }

    private func pillLabel(_ title: String?, icon: String) -> some View {
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
}

/// SwiftUI's `VideoPlayer` aborts unless AVKit is linked, so this hosts `AVPlayerView` directly.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}
