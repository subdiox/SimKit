# SimulatorView

Embed a live iOS Simulator screen inside any macOS app via a single SwiftUI/AppKit view.

```swift
import SwiftUI
import SimulatorView

struct MySimulator: View {
    var body: some View {
        SimulatorScreen(deviceUDID: "<UDID-of-a-booted-simulator>")
            .aspectRatio(9.0/19.5, contentMode: .fit)
    }
}
```

Frames come straight from SimulatorKit's `IOSurface` framebuffer pipeline — zero pixel
copies, runs at the device's native refresh rate (60/120 Hz). No `simctl io screenshot`
polling.

## Try it

```sh
git clone https://github.com/subdiox/SimulatorView
cd SimulatorView
xcrun simctl boot "iPhone 17 Pro"   # or any installed device
swift run SimulatorViewExample
```

The example app in `Examples/SimulatorViewExample/` lists every currently-booted simulator
and renders the selected one inside the window.

## Status (v0.1)

- ✅ Display (`SimulatorScreen` / `SimulatorScreenView`)
- ⏳ Input (tap / swipe / scroll / keyboard) — planned for v0.2

## Requirements

- macOS 14+
- Xcode installed (CoreSimulator + SimulatorKit are reached via the active developer
  directory; `xcode-select -p` is used first, with a fallback scan of `/Applications`
  for `Xcode*.app`).
- The target simulator must be **booted** before `attach` (use `xcrun simctl boot`).

## How it works

The package never `import`s SimulatorKit or CoreSimulator. Instead it `dlopen`s both at
runtime and reaches into the classes via the Objective-C runtime:

1. `SimServiceContext.sharedServiceContextForDeveloperDir:error:`
2. `defaultDeviceSet.availableDevices` → find `SimDevice` by UDID
3. `device.io.deviceIOPorts` → ports whose `portIdentifier` is `com.apple.framebuffer.display`
4. `port.descriptor.registerScreenCallbacksWithUUID:...` → callbacks fire on every frame
5. `port.descriptor.framebufferSurface` returns an `IOSurface` we assign to `CALayer.contents`

Linking the frameworks at build time would bake `LC_LOAD_DYLIB` entries that dyld must
resolve before `main()`, which breaks when Xcode lives outside `/Applications/Xcode.app`.
Runtime `dlopen` handles every install location.

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

This package adapts the IOSurface streaming logic from
[tddworks/baguette](https://github.com/tddworks/baguette) (Apache 2.0). NOTICE lists the
modifications.
