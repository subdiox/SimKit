import Foundation
import ObjectiveC

/// Per-simulator audio routing — mirrors Simulator.app's "Device → Audio Input / Output"
/// menus. Backed by SimulatorKit's `SimDeviceAudioClient` (Swift class, ObjC-compatible)
/// reached through the ObjC runtime so no compile-time SimulatorKit link is required.
///
/// Selection is by **CoreAudio device UID** (NSString — `kAudioDevicePropertyDeviceUID`).
/// CoreSimulator does **not** persist the selection across boots; the calling app should
/// re-apply the chosen UID after each `simctl boot`.
public enum SimulatorAudio: Sendable {

  public enum Scope: Int, Sendable {
    case input = 0
    case output = 1
  }

  public struct HostDevice: Hashable, Sendable {
    public let uid: String
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
  }

  /// Snapshot of the routing state for one simulator. `useDefault*` mirrors the
  /// "System (defaults to Mac's selected device)" entry at the top of Simulator.app's
  /// audio submenu.
  public struct State: Sendable {
    public let inputDevices: [HostDevice]
    public let outputDevices: [HostDevice]
    public let selectedInput: HostDevice?
    public let selectedOutput: HostDevice?
    public let useDefaultInput: Bool
    public let useDefaultOutput: Bool
    public let effectiveDefaultInput: HostDevice?
    public let effectiveDefaultOutput: HostDevice?
  }

  /// Reads the current routing state. Returns nil if SimulatorKit isn't available
  /// (missing Xcode / unsupported version) or the device can't be resolved.
  @concurrent
  public static func currentState(udid: String) async -> State? {
    guard let client = makeClient(udid: udid) else { return nil }
    return readState(from: client)
  }

  /// Routes the simulator's input or output to the host device identified by
  /// `deviceUID`. Pass `nil` to fall back to "System" (the macOS default for that
  /// scope). Returns true on success.
  @concurrent
  @discardableResult
  public static func setRoute(udid: String, scope: Scope, deviceUID: String?) async -> Bool {
    guard let client = makeClient(udid: udid) else { return false }
    // SimulatorKit treats the empty UID as "no override — use the host system default".
    let targetUID = deviceUID ?? ""
    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      Self.invokeRouteGuest(
        on: client,
        scope: scope.rawValue,
        uid: targetUID,
        queue: .global(qos: .userInitiated)
      ) { error in
        continuation.resume(returning: error == nil)
      }
    }
  }

  // MARK: - private bridge

  /// Builds (and immediately discards) a `SimDeviceAudioClient`. SimulatorKit refreshes
  /// state every time we construct one, so a fresh client per call is enough for our
  /// query / set semantics without having to keep a long-lived observer alive.
  private static func makeClient(udid: String) -> NSObject? {
    let runtime = CoreSimulatorRuntime()
    do { try runtime.load() } catch { return nil }
    let resolver = SimDeviceResolver(runtime: runtime)
    guard let device = resolver.resolve(udid: udid) else { return nil }
    guard let cls = NSClassFromString("_TtC12SimulatorKit20SimDeviceAudioClient") else {
      return nil
    }
    // `cls.alloc()` is unavailable in Swift — use the ObjC runtime directly. The
    // class extra-bytes count comes from the binary; passing 0 is the standard
    // value for non-`+ allocWithZone:` callers.
    guard let allocated = class_createInstance(cls, 0) as? NSObject else { return nil }
    let initSel = NSSelectorFromString("initWithDevice:eventHandlerQueue:error:changedEventHandler:")
    guard let imp = class_getMethodImplementation(cls, initSel) else { return nil }
    typealias InitMsg =
      @convention(c) (
        AnyObject, Selector,
        AnyObject,
        AnyObject,
        AutoreleasingUnsafeMutablePointer<NSError?>?,
        @convention(block) (AnyObject?) -> Void
      ) -> AnyObject?
    let initFn = unsafeBitCast(imp, to: InitMsg.self)
    var error: NSError?
    // The change handler is required but we don't observe live updates here — re-query
    // on demand instead.
    let noop: @convention(block) (AnyObject?) -> Void = { _ in }
    let result = initFn(allocated, initSel, device, DispatchQueue.main, &error, noop)
    guard error == nil, let client = result as? NSObject else { return nil }
    return client
  }

  private static func readState(from client: NSObject) -> State? {
    guard let stateObj = client.value(forKey: "currentState") as? NSObject else { return nil }
    let inputs = devices(from: stateObj.value(forKey: "inputDevices"))
    let outputs = devices(from: stateObj.value(forKey: "outputDevices"))
    return State(
      inputDevices: inputs,
      outputDevices: outputs,
      selectedInput: device(from: stateObj.value(forKey: "selectedInputDevice")),
      selectedOutput: device(from: stateObj.value(forKey: "selectedOutputDevice")),
      useDefaultInput: (stateObj.value(forKey: "useDefaultInputDevice") as? Bool) ?? true,
      useDefaultOutput: (stateObj.value(forKey: "useDefaultOutputDevice") as? Bool) ?? true,
      effectiveDefaultInput: device(from: stateObj.value(forKey: "effectiveDefaultInputDevice")),
      effectiveDefaultOutput: device(from: stateObj.value(forKey: "effectiveDefaultOutputDevice"))
    )
  }

  private static func devices(from any: Any?) -> [HostDevice] {
    guard let array = any as? [NSObject] else { return [] }
    return array.compactMap(device(from:))
  }

  private static func device(from any: Any?) -> HostDevice? {
    guard let obj = any as? NSObject else { return nil }
    let uid = (obj.value(forKey: "UID") as? String) ?? ""
    let name = (obj.value(forKey: "name") as? String) ?? uid
    let inputChannels = (obj.value(forKey: "inputChannels") as? Int) ?? 0
    let outputChannels = (obj.value(forKey: "outputChannels") as? Int) ?? 0
    guard !uid.isEmpty else { return nil }
    return HostDevice(uid: uid, name: name, inputChannels: inputChannels, outputChannels: outputChannels)
  }

  private static func invokeRouteGuest(
    on client: NSObject,
    scope: Int,
    uid: String,
    queue: DispatchQueue,
    completion: @escaping @Sendable (NSError?) -> Void
  ) {
    let sel = NSSelectorFromString("routeGuestWithScope:to:completionQueue:completionHandler:")
    guard let imp = class_getMethodImplementation(type(of: client), sel) else {
      completion(NSError(domain: "SimulatorAudio", code: -1, userInfo: nil))
      return
    }
    typealias RouteMsg =
      @convention(c) (
        AnyObject, Selector,
        Int,
        NSString,
        AnyObject,
        @convention(block) (NSError?) -> Void
      ) -> Void
    let routeFn = unsafeBitCast(imp, to: RouteMsg.self)
    let block: @convention(block) (NSError?) -> Void = { error in completion(error) }
    routeFn(client, sel, scope, uid as NSString, queue, block)
  }
}
