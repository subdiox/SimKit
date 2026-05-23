import Foundation

/// A point in screen coordinates (top-left origin). Coordinates are in *points* — the
/// adapter divides by the simulator's device size to feed the HID layer normalized values.
public struct SimulatorPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Screen size in points. Required because IndigoHID expects coordinates normalized to
/// the device screen.
public struct SimulatorSize: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Phase of a streaming touch gesture.
public enum GesturePhase: String, Sendable, Equatable, CaseIterable {
    case down, move, up
}

/// HID `(page, usage)` pair. Identifies arbitrary buttons (volume, action, digital crown, …).
public struct HIDUsage: Equatable, Hashable, Sendable {
    public let page: UInt32
    public let usage: UInt32
    public init(page: UInt32, usage: UInt32) {
        self.page = page
        self.usage = usage
    }
}

/// Screen-edge a touch belongs to. Routes through iOS system gesture recognizers (home
/// indicator, control centre, notification centre) instead of the foreground app.
public enum DeviceEdge: String, Sendable, Equatable, Hashable, CaseIterable {
    case left, top, right, bottom
}

/// Hardware buttons that can be pressed on the simulated device.
///
/// `home` / `lock` ride `IndigoHIDMessageForButton`. Side buttons (`power` / `volumeUp` /
/// `volumeDown` / `action`) ride `IndigoHIDMessageForHIDArbitrary` keyed by HID usagePage /
/// usage codes copied from each device's chrome.json.
///
/// Virtual buttons (`appSwitcher`, `swipeToHome`, etc.) have no physical counterpart but
/// keep the wire surface uniform — `appSwitcher` decomposes into two home presses;
/// `swipeToHome` / `pullDownToNotificationCenter` synthesize edge-flagged drags.
public enum DeviceButton: String, Sendable, Equatable, Hashable {
    case home, lock
    case power, action
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
    case digitalCrown = "digital-crown"
    case sideButton = "side-button"
    case leftSideButton = "left-side-button"
    case appSwitcher = "app-switcher"
    case swipeToAppSwitcher = "swipe-to-app-switcher"
    case swipeToHome = "swipe-to-home"
    case pullDownToLockScreen = "pull-down-to-lock-screen"
    case pullDownToNotificationCenter = "pull-down-to-notification-center"

    /// Standard HID `(page, usage)` for arbitrary-HID side buttons. `home`/`lock` / virtual
    /// buttons return nil — they ride a different SimulatorKit symbol.
    public var standardHIDUsage: HIDUsage? {
        switch self {
        case .home, .lock, .appSwitcher, .swipeToAppSwitcher, .swipeToHome,
             .pullDownToLockScreen, .pullDownToNotificationCenter: return nil
        case .power:          return HIDUsage(page: 12, usage: 48)
        case .volumeUp:       return HIDUsage(page: 12, usage: 233)
        case .volumeDown:     return HIDUsage(page: 12, usage: 234)
        case .action:         return HIDUsage(page: 11, usage: 45)
        case .digitalCrown:   return HIDUsage(page: 12, usage: 64)
        case .sideButton:     return HIDUsage(page: 12, usage: 149)
        case .leftSideButton: return HIDUsage(page: 65281, usage: 512)
        }
    }
}
