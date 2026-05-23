/// HID `(page, usage)` pair. Identifies arbitrary buttons (volume, action, digital crown, …).
public struct HIDUsage: Equatable, Hashable, Sendable {
  public let page: UInt32
  public let usage: UInt32

  public init(page: UInt32, usage: UInt32) {
    self.page = page
    self.usage = usage
  }
}
