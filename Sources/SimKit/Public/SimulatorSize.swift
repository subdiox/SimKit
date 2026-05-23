import Foundation

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
