import Foundation
import ObjectiveC

/// Resolves an active `SimDevice` instance by UDID by walking
/// `SimServiceContext.defaultDeviceSet.availableDevices`.
///
/// Derived from baguette (Apache 2.0).
struct SimDeviceResolver: Sendable {
  let runtime: CoreSimulatorRuntime
  let deviceSetPath: String?

  init(runtime: CoreSimulatorRuntime, deviceSetPath: String? = nil) {
    self.runtime = runtime
    self.deviceSetPath = deviceSetPath
  }

  func resolve(udid: String) -> NSObject? {
    guard let set = resolveSet() else { return nil }
    for device in availableDevices(in: set) {
      if (device.value(forKey: "UDID") as? NSUUID)?.uuidString == udid {
        return device
      }
    }
    return nil
  }

  private func resolveSet() -> NSObject? {
    guard let ctx = sharedServiceContext() else { return nil }
    if let path = deviceSetPath {
      return customDeviceSet(context: ctx, path: path) ?? defaultDeviceSet(context: ctx)
    }
    return defaultDeviceSet(context: ctx)
  }

  private func sharedServiceContext() -> NSObject? {
    guard let cls = NSClassFromString("SimServiceContext") else { return nil }
    let sel = NSSelectorFromString("sharedServiceContextForDeveloperDir:error:")
    var err: NSError?
    return RuntimeInvoke.classWithArgAndError(
      cls, sel, runtime.developerDir as NSString, &err, returning: NSObject.self
    )
  }

  private func defaultDeviceSet(context: NSObject) -> NSObject? {
    let sel = NSSelectorFromString("defaultDeviceSetWithError:")
    guard context.responds(to: sel) else { return nil }
    var err: NSError?
    return RuntimeInvoke.instanceWithError(context, sel, &err, returning: NSObject.self)
  }

  private func customDeviceSet(context: NSObject, path: String) -> NSObject? {
    let candidates = [path, (path as NSString).appendingPathComponent("Devices")]
    let withPathSel = NSSelectorFromString("deviceSetWithPath:error:")
    guard context.responds(to: withPathSel) else { return nil }
    for candidate in candidates where existsAsDirectory(candidate) {
      var err: NSError?
      if let set = RuntimeInvoke.instanceWithArgAndError(
        context, withPathSel, candidate as NSString, &err, returning: NSObject.self
      ), hasDevices(set) {
        return set
      }
    }
    return nil
  }

  private func availableDevices(in set: NSObject) -> [NSObject] {
    (set.value(forKey: "availableDevices") as? [NSObject]) ?? []
  }

  private func existsAsDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
  }

  private func hasDevices(_ set: NSObject) -> Bool {
    ((set.value(forKey: "availableDevices") as? [Any])?.count ?? 0) > 0
  }
}
