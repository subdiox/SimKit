import Foundation

func dlerrorString() -> String {
  guard let raw = dlerror() else { return "(no dlerror)" }
  return String(cString: raw)
}
