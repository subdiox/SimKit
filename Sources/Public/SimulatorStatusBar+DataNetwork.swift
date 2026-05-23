extension SimulatorStatusBar {
  public enum DataNetwork: String, Sendable, CaseIterable {
    case wifi
    case hide
    case lte = "lte"
    case threeG = "3g"
    case fourG = "4g"
    case fiveG = "5g"
  }
}
