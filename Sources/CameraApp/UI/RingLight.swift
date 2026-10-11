import AppKit
import CoreImage

/// White light around the screen's edges that lights your face; brighter than white with HDR headroom.
enum RingLight {
    enum Level: String, CaseIterable, Identifiable {
        case off, soft, bright
        var id: Self { self }
        /// How far the band reaches in from the screen's edges, in points.
        var width: CGFloat { [Self.off: 0, .soft: 60, .bright: 170][self]! }
    }

    private static var windows: [NSWindow] = []

    /// The connected displays among `chosen` (IDs joined by commas), else the main display.
    static func screens(chosen: String) -> [NSScreen] {
        let ids = Set(chosen.split(separator: ",").map(String.init))
        let screens = NSScreen.screens.filter { ids.contains($0.displayID) }
        return screens.isEmpty ? [NSScreen.main].compactMap { $0 } : screens
    }

    static func show(_ level: Level, on screens: [NSScreen]) {
        hide()
        guard level != .off else { return }
        windows = screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.contentView = Band(width: level.width, headroom: screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            w.setFrame(screen.frame, display: false)
            w.orderFrontRegardless()
            return w
        }
    }

    static func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private final class Band: NSView {
        private let width: CGFloat
        private let shape = CAShapeLayer()

        init(width: CGFloat, headroom: CGFloat) {
            self.width = width
            super.init(frame: .zero)
            wantsLayer = true
            layerUsesCoreImageFilters = true
            // Only an EDR layer may hold colors above 1.0; elsewhere they clip to white.
            layer?.wantsExtendedDynamicRangeContent = true
            let white = min(headroom, 8)
            shape.fillColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                      components: [white, white, white * 0.96, 1])
            shape.fillRule = .evenOdd
            // A narrow feather keeps most of the band at full brightness.
            shape.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: width / 10])!]
            layer?.addSublayer(shape)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shape.frame = bounds
            let path = CGMutablePath()
            path.addRect(bounds.insetBy(dx: -width, dy: -width))
            path.addRoundedRect(in: bounds.insetBy(dx: width, dy: width), cornerWidth: width, cornerHeight: width)
            shape.path = path
            CATransaction.commit()
        }
    }
}

extension NSScreen {
    /// Stable across launches while the display stays connected.
    var displayID: String {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { "\($0.uint32Value)" } ?? localizedName
    }
}
