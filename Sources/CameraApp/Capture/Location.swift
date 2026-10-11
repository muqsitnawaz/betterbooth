import CoreLocation
import ImageIO

/// Where the Mac is, while the camera runs with Save Location on. Main queue only.
final class Locator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private var latest: CLLocation?
    private var updating = false

    var denied: Bool { status == .denied || status == .restricted }
    /// A fix from the last 10 minutes; an older one may be somewhere else.
    var recent: CLLocation? { latest.flatMap { $0.horizontalAccuracy >= 0 && $0.timestamp.timeIntervalSinceNow > -600 ? $0 : nil } }

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        guard !updating else { return }
        updating = true
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func stop() {
        guard updating else { return }
        updating = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { status = manager.authorizationStatus }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { latest = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension CLLocation {
    /// The EXIF GPS block a photo carries, which Photos, Preview and Finder read.
    var exifGPS: [CFString: Any] {
        let utc = DateFormatter()
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.dateFormat = "yyyy:MM:dd"
        let date = utc.string(from: timestamp)
        utc.dateFormat = "HH:mm:ss.SS"
        var gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: abs(coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef: coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef: coordinate.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSHPositioningError: horizontalAccuracy,
            kCGImagePropertyGPSDateStamp: date,
            kCGImagePropertyGPSTimeStamp: utc.string(from: timestamp),
        ]
        if verticalAccuracy > 0 {
            gps[kCGImagePropertyGPSAltitude] = abs(altitude)
            gps[kCGImagePropertyGPSAltitudeRef] = altitude < 0 ? 1 : 0
        }
        return gps
    }

    /// "+37.3349-122.0090+12.5/", the ISO 6709 form a video's location is written in.
    var iso6709: String {
        var text = String(format: "%+08.4f%+09.4f", coordinate.latitude, coordinate.longitude)
        if verticalAccuracy > 0 { text += String(format: "%+.1f", altitude) }
        return text + "/"
    }
}
