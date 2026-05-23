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
