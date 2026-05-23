extension SimulatorStatusBar {
  public enum BatteryState: String, Sendable, CaseIterable {
    case unplugged
    case charging
    case charged
  }
}
