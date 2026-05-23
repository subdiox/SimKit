import Darwin.Mach
import Foundation
import ObjectiveC

/// Sends a `GSEventTypeDeviceOrientationChanged` mach message to the simulator's
/// `PurpleWorkspacePort`, the same path Simulator.app's `Device → Rotate / Orientation`
/// menu uses. The mach buffer layout was reverse-engineered against
/// `[SimDevice gsEventsSendOrientation:]`.
///
/// Derived from baguette (Apache 2.0).
public enum SimulatorOrientation: Sendable {

  /// Rotates the booted simulator. Returns `false` when the `PurpleWorkspacePort` is not
  /// vended (typically: device not booted, or booted but pre-SpringBoard). The guest can
  /// still reject the rotation if the foreground app's `UISupportedInterfaceOrientations`
  /// excludes it; that's a guest-side decision and surfaces as no visual change.
  ///
  /// `@concurrent` so the blocking `mach_msg_send` runs on the cooperative pool instead
  /// of the caller's actor.
  @concurrent
  @discardableResult
  public static func set(_ orientation: DeviceOrientation, udid: String) async -> Bool {
    let runtime = CoreSimulatorRuntime()
    do { try runtime.load() } catch { return false }
    let resolver = SimDeviceResolver(runtime: runtime)
    guard let device = resolver.resolve(udid: udid) else { return false }
    guard let port = lookupMachPort(on: device, named: "PurpleWorkspacePort"), port != 0 else {
      return false
    }
    let data = patched(buildMachMessage(orientation: orientation), remotePort: port)
    return sendMachMessage(data)
  }

  // MARK: - mach message construction

  /// Builds the 112-byte mach buffer. Caller must patch `msgh_remote_port` (offset 0x08)
  /// before sending — `set(_:udid:)` does so.
  private static func buildMachMessage(orientation: DeviceOrientation) -> Data {
    var bytes = [UInt8](repeating: 0, count: 112)
    write(0x13, at: 0x00, into: &bytes)  // msgh_bits = MACH_MSG_TYPE_COPY_SEND
    write(108, at: 0x04, into: &bytes)  // msgh_size
    write(0x7B, at: 0x14, into: &bytes)  // msgh_id = GSEventMachMessageID
    write(50 | 0x20000, at: 0x18, into: &bytes)  // GSEvent.type | GSEventHostFlag
    write(4, at: 0x48, into: &bytes)  // record_info_size
    write(orientation.rawValue, at: 0x4C, into: &bytes)  // record_info_data
    return Data(bytes)
  }

  private static func patched(_ data: Data, remotePort: UInt32) -> Data {
    var copy = data
    write(remotePort, at: 0x08, into: &copy)
    return copy
  }

  private static func write<T: BinaryInteger>(_ value: T, at offset: Int, into bytes: inout [UInt8]) {
    let raw = UInt32(value)
    bytes[offset] = UInt8(raw & 0xFF)
    bytes[offset + 1] = UInt8((raw >> 8) & 0xFF)
    bytes[offset + 2] = UInt8((raw >> 16) & 0xFF)
    bytes[offset + 3] = UInt8((raw >> 24) & 0xFF)
  }

  private static func write<T: BinaryInteger>(_ value: T, at offset: Int, into data: inout Data) {
    let raw = UInt32(value)
    data[offset] = UInt8(raw & 0xFF)
    data[offset + 1] = UInt8((raw >> 8) & 0xFF)
    data[offset + 2] = UInt8((raw >> 16) & 0xFF)
    data[offset + 3] = UInt8((raw >> 24) & 0xFF)
  }

  // MARK: - SimDevice port lookup + mach dispatch

  /// Mirrors `[simDevice lookup:@"…" error:&err]`. Returns nil when CoreSimulator hasn't
  /// vended that port yet.
  private static func lookupMachPort(on device: NSObject, named name: String) -> UInt32? {
    let sel = NSSelectorFromString("lookup:error:")
    guard device.responds(to: sel) else { return nil }
    let imp = device.method(for: sel)
    typealias Lookup =
      @convention(c) (
        AnyObject, Selector, NSString, UnsafeMutablePointer<NSError?>?
      ) -> UInt32
    let fn = unsafeBitCast(imp, to: Lookup.self)
    var err: NSError?
    let port = fn(device, sel, name as NSString, &err)
    return port == 0 ? nil : port
  }

  private static func sendMachMessage(_ data: Data) -> Bool {
    var copy = data
    let kr: kern_return_t = copy.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return KERN_FAILURE }
      let header = base.assumingMemoryBound(to: mach_msg_header_t.self)
      return mach_msg_send(header)
    }
    return kr == KERN_SUCCESS
  }
}
