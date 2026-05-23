/// Modifier keys bracketed around a `KeyboardKey` press. Each modifier itself lives on HID
/// page 7 (left-side variants).
public enum KeyModifier: String, Sendable, Hashable, CaseIterable {
  case shift
  case control
  case option
  case command

  public var hidUsage: HIDUsage {
    switch self {
    case .control: HIDUsage(page: 7, usage: 0xE0)
    case .shift: HIDUsage(page: 7, usage: 0xE1)
    case .option: HIDUsage(page: 7, usage: 0xE2)
    case .command: HIDUsage(page: 7, usage: 0xE3)
    }
  }
}
