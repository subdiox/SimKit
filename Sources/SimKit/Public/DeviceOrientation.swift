/// Booted simulator's interface orientation. Raw values match `UIDeviceOrientation` — the
/// 4-byte payload of a `GSEventTypeDeviceOrientationChanged` mach message at offset 0x4C
/// is exactly this number.
public enum DeviceOrientation: UInt32, Sendable, CaseIterable, Equatable {
  case portrait = 1
  case portraitUpsideDown = 2
  /// Home button on the right (rotated 90° CW).
  case landscapeRight = 3
  /// Home button on the left (rotated 90° CCW).
  case landscapeLeft = 4
}
