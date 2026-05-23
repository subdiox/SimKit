/// Screen-edge a touch belongs to. Routes through iOS system gesture recognizers (home
/// indicator, control centre, notification centre) instead of the foreground app.
public enum DeviceEdge: String, Sendable, Equatable, Hashable, CaseIterable {
  case left
  case top
  case right
  case bottom
}
