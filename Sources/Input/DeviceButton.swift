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
  case home
  case lock
  case power
  case action
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
      .pullDownToLockScreen, .pullDownToNotificationCenter:
      nil
    case .power: HIDUsage(page: 12, usage: 48)
    case .volumeUp: HIDUsage(page: 12, usage: 233)
    case .volumeDown: HIDUsage(page: 12, usage: 234)
    case .action: HIDUsage(page: 11, usage: 45)
    case .digitalCrown: HIDUsage(page: 12, usage: 64)
    case .sideButton: HIDUsage(page: 12, usage: 149)
    case .leftSideButton: HIDUsage(page: 65281, usage: 512)
    }
  }
}
