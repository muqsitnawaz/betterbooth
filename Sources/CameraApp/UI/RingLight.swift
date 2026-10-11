import AppKit
import CoreImage

/// White light around the screen's edges that lights your face; brighter than white with HDR headroom.
enum RingLight {
    enum Strength: Int, CaseIterable, Identifiable {
        case soft = 60, medium = 110, bright = 170
        var id: Int { rawValue }
        var label: String { ["Soft", "Medium", "Bright"][Self.allCases.firstIndex(of: self)!] }
    }

    private static var windows: [NSWindow] = []

    static func show(_ strength: Strength, on screens: [NSScreen]) {
        hide()
        windows = screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.contentView = Band(width: CGFloat(strength.rawValue), headroom: screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
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
