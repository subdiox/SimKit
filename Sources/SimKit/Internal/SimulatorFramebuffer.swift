import Foundation
import IOSurface
import ObjectiveC

/// Registers SimulatorKit framebuffer callbacks on every `com.apple.framebuffer.display`
/// descriptor of a SimDevice and forwards the IOSurface that has the largest live surface
/// area (which is always the main screen — secondary planes are smaller overlays).
///
/// One instance == one device. Caller owns the surface and may use it as `CALayer.contents`
/// to render at the device's native refresh rate with zero pixel copies.
///
/// Derived from baguette (Apache 2.0).
final class SimulatorFramebuffer: @unchecked Sendable {
  enum FramebufferError: Error, CustomStringConvertible {
    case ioUnavailable
    case noFramebuffer
    case callbackUnavailable

    var description: String {
      switch self {
      case .ioUnavailable: "SimDevice has no `io` (SimDeviceIOClient)."
      case .noFramebuffer: "No `com.apple.framebuffer.display` port on the device."
      case .callbackUnavailable: "registerScreenCallbacksWithUUID:… selector missing."
      }
    }
  }

  private let device: NSObject
  private let onFrame: @Sendable (IOSurface) -> Void
  private let queue = DispatchQueue(label: "SimulatorView.framebuffer", qos: .userInteractive)

  private var ioClient: NSObject?
  private var descriptors: [NSObject] = []
  private var callbackUUIDs: [ObjectIdentifier: NSUUID] = [:]

  init(device: NSObject, onFrame: @escaping @Sendable (IOSurface) -> Void) {
    self.device = device
    self.onFrame = onFrame
  }

  func start() throws {
    guard
      let io = device.perform(NSSelectorFromString("io"))?
        .takeUnretainedValue() as? NSObject
    else {
      throw FramebufferError.ioUnavailable
    }
    ioClient = io
    try wireFramebuffer()
  }

  func stop() {
    let unregSel = NSSelectorFromString("unregisterScreenCallbacksWithUUID:")
    for desc in descriptors {
      if let uuid = callbackUUIDs[ObjectIdentifier(desc)], desc.responds(to: unregSel) {
        desc.perform(unregSel, with: uuid)
      }
    }
    descriptors.removeAll()
    callbackUUIDs.removeAll()
    ioClient = nil
  }

  deinit {
    // Best-effort cleanup; deinit can't await main-actor isolation so we just unhook.
    let unregSel = NSSelectorFromString("unregisterScreenCallbacksWithUUID:")
    for desc in descriptors {
      if let uuid = callbackUUIDs[ObjectIdentifier(desc)], desc.responds(to: unregSel) {
        desc.perform(unregSel, with: uuid)
      }
    }
  }

  // MARK: - private

  private func wireFramebuffer() throws {
    guard let io = ioClient else { throw FramebufferError.ioUnavailable }
    io.perform(NSSelectorFromString("updateIOPorts"))

    guard let ports = io.value(forKey: "deviceIOPorts") as? [NSObject] else {
      throw FramebufferError.noFramebuffer
    }

    let pidSel = NSSelectorFromString("portIdentifier")
    let descSel = NSSelectorFromString("descriptor")
    let surfSel = NSSelectorFromString("framebufferSurface")

    var candidates: [NSObject] = []
    for port in ports where port.responds(to: pidSel) {
      guard let pid = port.perform(pidSel)?.takeUnretainedValue(),
        "\(pid)" == "com.apple.framebuffer.display",
        port.responds(to: descSel),
        let desc = port.perform(descSel)?.takeUnretainedValue() as? NSObject,
        desc.responds(to: surfSel)
      else { continue }
      candidates.append(desc)
    }
    guard !candidates.isEmpty else { throw FramebufferError.noFramebuffer }
    descriptors = candidates
    for desc in candidates {
      try registerCallbacks(on: desc)
    }
  }

  private func registerCallbacks(on desc: NSObject) throws {
    let regSel = NSSelectorFromString(
      "registerScreenCallbacksWithUUID:callbackQueue:frameCallback:"
        + "surfacesChangedCallback:propertiesChangedCallback:"
    )
    guard desc.responds(to: regSel) else { throw FramebufferError.callbackUnavailable }

    let uuid = NSUUID()
    callbackUUIDs[ObjectIdentifier(desc)] = uuid

    // Capture the serial queue locally so the SimulatorKit-side block doesn't have to
    // weakly re-resolve `self.queue` (which Swift 6 strict concurrency flags as a
    // captured-var-of-self in concurrently-executing code).
    let queue = self.queue
    let frame: @convention(block) () -> Void = { [weak self] in
      queue.async { [weak self] in self?.captureLatest() }
    }
    let surfaces: @convention(block) () -> Void = { [weak self] in
      queue.async { [weak self] in self?.captureLatest() }
    }
    let props: @convention(block) () -> Void = {}

    guard let imp = class_getMethodImplementation(type(of: desc), regSel) else {
      throw FramebufferError.callbackUnavailable
    }
    typealias Fn =
      @convention(c) (
        AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject, AnyObject
      ) -> Void
    unsafeBitCast(imp, to: Fn.self)(
      desc, regSel,
      uuid, queue as AnyObject,
      frame as AnyObject, surfaces as AnyObject, props as AnyObject
    )
  }

  private func captureLatest() {
    let surfSel = NSSelectorFromString("framebufferSurface")
    var best: IOSurface?
    var bestArea = 0
    for desc in descriptors {
      guard let surfObj = desc.perform(surfSel)?.takeUnretainedValue() else { continue }
      let surf = unsafeDowncast(surfObj, to: IOSurface.self)
      let area = IOSurfaceGetWidth(surf) * IOSurfaceGetHeight(surf)
      if area > bestArea {
        best = surf
        bestArea = area
      }
    }
    if let best { onFrame(best) }
  }
}
