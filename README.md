# SimKit

Swift Package that bridges Apple's private `CoreSimulator` / `SimulatorKit`
frameworks and exposes high-level APIs for driving a booted iOS Simulator from a
macOS host app.

```swift
import SimKit
import SwiftUI

struct MySimulator: View {
    var body: some View {
        SimulatorScreen(deviceUDID: "<UDID-of-a-booted-simulator>")
            .aspectRatio(9.0 / 19.5, contentMode: .fit)
    }
}
```

Frames come straight from SimulatorKit's `IOSurface` framebuffer pipeline — zero
pixel copies, runs at the device's native refresh rate (60/120 Hz). No `simctl
io screenshot` polling.

## What's included

- **`SimulatorScreenView`** — `MTKView` that renders the live framebuffer and
  forwards mouse / keyboard / scroll events back as HID input.
- **`SimulatorScreen`** — `NSViewRepresentable` wrapper for SwiftUI.
- **`SimulatorInteractionState`** — `@Observable` channel for cursor / touch
  state, for overlay UIs.
- **`SimulatorBiometrics`** — Face ID / Touch ID match / non-match / enrolled
  toggle.
- **`SimulatorControl`** — erase, restart, openURL, appearance (light/dark),
  pasteboard, memory warning, iCloud sync, Darwin notifications.
- **`SimulatorLocation`** — clear / set / play `simctl` route presets.
- **`SimulatorOrientation`** — rotate the simulator via mach-message dispatch.
- **`SimulatorStatusBar`** — App-Store-screenshot status-bar overrides.

Used by [SimDeck](https://github.com/subdiox/SimDeck).

## Requirements

- macOS 14+
- Xcode 26+ (Swift 6.3 toolchain)
- An Xcode install in `/Applications/` (SimKit locates `SimulatorKit` at
  runtime via `dlopen` — `xcode-select -p` first, then a `/Applications/` scan).
- The target simulator must be **booted** before `attach` (use `xcrun simctl
  boot`).

## First-time setup

```sh
./scripts/install-hooks.sh
```

Installs the pre-commit hook that runs `swift format` over staged Swift files
using `.swift-format`.

## Project layout

```
Sources/
  Display/   — SimulatorScreen, SimulatorScreenView, MetalRenderer,
               SimulatorFramebuffer, SimulatorInteractionState
  Input/     — Device buttons / edges / keys / sizes, plus the HID
               dispatchers (HIDInput, IOHIDDigitizerDispatch)
  Control/   — simctl/mach wrappers (Biometrics, Control, Location,
               Orientation, StatusBar)
  Runtime/   — Framework bridging (CoreSimulatorRuntime, SimDeviceResolver,
               RuntimeInvoke / dlerrorString)
  SimKitError.swift
```

## Concurrency

The package builds in Swift 6 language mode with
`NonisolatedNonsendingByDefault` upcoming feature enabled, so `@concurrent` is
available on async methods. UI types (`SimulatorScreenView`, `MetalRenderer`,
`SimulatorInteractionState`, `ScreenViewBox`, `ScreenRecorder`) are
`@MainActor`; everything else (Process / mach / dlopen wrappers) is plain
`Sendable`.

## How it works

The package never `import`s SimulatorKit or CoreSimulator. Instead it
`dlopen`s both at runtime and reaches into the classes via the Objective-C
runtime:

1. `SimServiceContext.sharedServiceContextForDeveloperDir:error:`
2. `defaultDeviceSet.availableDevices` → find `SimDevice` by UDID
3. `device.io.deviceIOPorts` → ports whose `portIdentifier` is
   `com.apple.framebuffer.display`
4. `port.descriptor.registerScreenCallbacksWithUUID:...` → callbacks fire on
   every frame
5. `port.descriptor.framebufferSurface` returns an `IOSurface` we hand to
   the Metal renderer.

Linking the frameworks at build time would bake `LC_LOAD_DYLIB` entries that
dyld must resolve before `main()`, which breaks when Xcode lives outside
`/Applications/Xcode.app`. Runtime `dlopen` handles every install location.

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

This package adapts the IOSurface streaming logic from
[tddworks/baguette](https://github.com/tddworks/baguette) (Apache 2.0).
NOTICE lists the modifications.
