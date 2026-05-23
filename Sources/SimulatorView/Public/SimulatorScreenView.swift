import AppKit
import IOSurface
import QuartzCore
import Metal
import MetalKit

/// `MTKView` subclass that renders the live framebuffer of an iOS Simulator and forwards
/// mouse/keyboard/scroll events back to the simulator as HID input. Display goes through a
/// Metal pipeline that also composites touch indicators, so the live preview and any
/// recording consumer (via `onSurfaceFrame`) see pixel-identical output.
///
/// Usage:
/// ```swift
/// let view = SimulatorScreenView()
/// try view.attach(deviceUDID: "ABCD-...")
/// ```
@MainActor
public final class SimulatorScreenView: MTKView {
    public init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect, device: MTLCreateSystemDefaultDevice())
        commonInit()
    }

    public required init(coder: NSCoder) {
        super.init(coder: coder)
        if device == nil { device = MTLCreateSystemDefaultDevice() }
        commonInit()
    }

    private func commonInit() {
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        autoResizeDrawable = true
        // MTKView drives `draw(_:)` at the display refresh rate. iOS may update the
        // simulator's IOSurface in place between framebuffer callbacks, so re-rendering
        // every tick keeps the preview live.
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        layer?.backgroundColor = NSColor.black.cgColor
        renderer = MetalRenderer()
    }

    public override func draw(_ rect: NSRect) {
        guard let latestSurface else { return }
        present(surface: latestSurface)
    }

    private var renderer: MetalRenderer?

    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool { true }

    private var framebuffer: SimulatorFramebuffer?
    private var input: HIDInput?
    private var lastReportedImageSize: CGSize?
    /// Latest IOSurface from the simulator. iOS writes to the same surface in place when
    /// the UI updates, so we re-render this surface every display tick rather than waiting
    /// for explicit `frameCallback` invocations (which only fire on framebuffer *swap*,
    /// not on in-place modifications).
    private var latestSurface: IOSurface?

    /// Currently attached device UDID, or nil if not attached.
    public private(set) var attachedUDID: String?

    /// Fires whenever the underlying IOSurface changes dimensions (typically once per
    /// attach). The reported size is in pixels — divide by `backingScaleFactor` for points.
    /// Use this to letterbox the surrounding layout to the device's native aspect ratio.
    public var onImageSizeChange: (@MainActor (CGSize) -> Void)?

    /// Optional observable surface for overlay UIs (touch indicators, modifier hints, etc.).
    /// When set, `SimulatorScreenView` updates `cursorPosition`, `isOptionHeld`, and
    /// `activeTouches` as the user interacts with the view.
    public var interactionState: SimulatorInteractionState?

    /// Fires with each fresh IOSurface arriving from the simulator's framebuffer pipeline.
    /// Use this to drive native-resolution recorders / compositors without re-rendering the
    /// view contents. The callback is invoked on the main actor on every refresh tick.
    public var onSurfaceFrame: (@MainActor (IOSurface) -> Void)?

    /// Diameter of the rendered touch indicator as a fraction of the device screen's shorter
    /// side. Matches the SwiftUI overlay's "10% of min dimension" rule so display and
    /// recording look identical.
    public var touchIndicatorDiameterFraction: CGFloat = 0.10

    /// Whether the Metal renderer overlays active touches on top of the live framebuffer.
    /// Affects both the on-screen display and the composited IOSurface delivered via
    /// `onSurfaceFrame`, so toggling this here flows through to any recorder consuming the
    /// composited output.
    public var showTouchIndicators: Bool = true

    private var trackingArea: NSTrackingArea?

    /// Connect to the device's framebuffer and prepare the input pipeline. Throws if the
    /// device is missing or not booted.
    public func attach(deviceUDID udid: String) throws {
        detach()
        let runtime = CoreSimulatorRuntime()
        do {
            try runtime.load()
        } catch {
            throw SimulatorViewError.frameworkLoadFailed(detail: String(describing: error))
        }
        let resolver = SimDeviceResolver(runtime: runtime)
        guard let device = resolver.resolve(udid: udid) else {
            throw SimulatorViewError.deviceNotFound(udid: udid)
        }
        let fb = SimulatorFramebuffer(device: device) { [weak self] surface in
            Task { @MainActor [weak self] in
                self?.latestSurface = surface
            }
        }
        do {
            try fb.start()
        } catch let error as SimulatorFramebuffer.FramebufferError {
            switch error {
            case .ioUnavailable: throw SimulatorViewError.ioUnavailable
            case .noFramebuffer: throw SimulatorViewError.noFramebuffer
            case .callbackUnavailable: throw SimulatorViewError.callbackRegistrationFailed
            }
        }
        framebuffer = fb
        input = HIDInput(udid: udid, resolver: resolver, runtime: runtime)
        attachedUDID = udid
    }

    public func detach() {
        latestSurface = nil
        framebuffer?.stop()
        framebuffer = nil
        input = nil
        attachedUDID = nil
    }

    private func present(surface: IOSurface) {
        guard let metalLayer = layer as? CAMetalLayer, let renderer else { return }
        let size = CGSize(width: CGFloat(IOSurfaceGetWidth(surface)), height: CGFloat(IOSurfaceGetHeight(surface)))
        if size != lastReportedImageSize {
            lastReportedImageSize = size
            onImageSizeChange?(size)
        }

        let touchInputs: [MetalRenderer.TouchInput] = showTouchIndicators
            ? (interactionState?.activeTouches ?? []).map { point in
                MetalRenderer.TouchInput(position: point, diameterFraction: touchIndicatorDiameterFraction)
            }
            : []
        renderer.render(input: surface, touches: touchInputs, to: metalLayer)

        if let composited = renderer.outputIOSurface {
            onSurfaceFrame?(composited)
        }
    }

    // MARK: - Public input API

    /// Tap at a normalized point (0…1 in each axis, origin top-left of the device screen).
    @discardableResult
    public func tap(normalized point: CGPoint, duration: Double = 0) -> Bool {
        guard let input else { return false }
        return input.tap(
            at: SimulatorPoint(x: point.x, y: point.y),
            size: SimulatorSize(width: 1, height: 1),
            duration: duration
        )
    }

    /// Swipe between two normalized points.
    @discardableResult
    public func swipe(
        normalizedFrom start: CGPoint,
        to end: CGPoint,
        duration: Double = 0.25
    ) -> Bool {
        guard let input else { return false }
        return input.swipe(
            from: SimulatorPoint(x: start.x, y: start.y),
            to: SimulatorPoint(x: end.x, y: end.y),
            size: SimulatorSize(width: 1, height: 1),
            duration: duration
        )
    }

    /// Press a hardware button.
    @discardableResult
    public func press(_ button: DeviceButton, duration: Double = 0) -> Bool {
        guard let input else { return false }
        return input.button(button, duration: duration)
    }

    /// Send one key with optional modifiers.
    @discardableResult
    public func sendKey(
        _ key: KeyboardKey,
        modifiers: Set<KeyModifier> = [],
        duration: Double = 0
    ) -> Bool {
        guard let input else { return false }
        return input.key(key, modifiers: modifiers, duration: duration)
    }

    /// Type an ASCII string by decomposing each character into key + modifier presses.
    public func typeText(_ text: String) {
        guard let input else { return }
        for character in text {
            guard let pair = KeyboardKey.decompose(character: character) else { continue }
            _ = input.key(pair.key, modifiers: pair.modifiers, duration: 0)
        }
    }

    @discardableResult
    public func scroll(deltaX: Double, deltaY: Double) -> Bool {
        guard let input else { return false }
        return input.scroll(deltaX: deltaX, deltaY: deltaY)
    }

    // MARK: - NSResponder event forwarding

    /// Edge flag latched at `mouseDown` time and reused for the duration of the drag. iOS
    /// only recognises edge gestures (home indicator, control centre, notification centre)
    /// when *every* event in the sequence carries the right edge bit, so we must remember
    /// what we decided at touch start.
    private var currentDragEdge: DeviceEdge?
    /// Latched at `mouseDown` so a drag stays in 2-finger mode for its entire duration even
    /// if the user releases Option mid-gesture (matches Simulator.app).
    private var isTwoFingerDrag = false

    public override func mouseDown(with event: NSEvent) {
        guard let normalised = normalizedPoint(for: event) else { return }
        isTwoFingerDrag = event.modifierFlags.contains(.option)
        if isTwoFingerDrag {
            let p2 = mirror(normalised)
            _ = input?.touch2(phase: .down, first: normalised, second: p2, size: unitSize)
            currentDragEdge = nil
            publishTouches(primary: normalised, secondary: p2)
        } else {
            currentDragEdge = edgeForPoint(normalised)
            _ = input?.touch1(phase: .down, at: normalised, size: unitSize, edge: currentDragEdge)
            publishTouches(primary: normalised, secondary: nil)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let normalised = normalizedPoint(for: event) else { return }
        if isTwoFingerDrag {
            let p2 = mirror(normalised)
            _ = input?.touch2(phase: .move, first: normalised, second: p2, size: unitSize)
            publishTouches(primary: normalised, secondary: p2)
        } else {
            _ = input?.touch1(phase: .move, at: normalised, size: unitSize, edge: currentDragEdge)
            publishTouches(primary: normalised, secondary: nil)
        }
        publishCursor(normalised, optionHeld: event.modifierFlags.contains(.option))
    }

    public override func mouseUp(with event: NSEvent) {
        guard let normalised = normalizedPoint(for: event) else { return }
        if isTwoFingerDrag {
            _ = input?.touch2(phase: .up, first: normalised, second: mirror(normalised), size: unitSize)
            isTwoFingerDrag = false
        } else {
            _ = input?.touch1(phase: .up, at: normalised, size: unitSize, edge: currentDragEdge)
            currentDragEdge = nil
        }
        interactionState?.activeTouches = []
    }

    public override func mouseMoved(with event: NSEvent) {
        publishCursor(normalizedPoint(for: event), optionHeld: event.modifierFlags.contains(.option))
    }

    public override func mouseEntered(with event: NSEvent) {
        publishCursor(normalizedPoint(for: event), optionHeld: event.modifierFlags.contains(.option))
    }

    public override func mouseExited(with event: NSEvent) {
        interactionState?.cursorPosition = nil
        interactionState?.isOptionHeld = false
    }

    public override func flagsChanged(with event: NSEvent) {
        interactionState?.isOptionHeld = event.modifierFlags.contains(.option)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func scrollWheel(with event: NSEvent) {
        _ = input?.scroll(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY))
    }

    public override func keyDown(with event: NSEvent) {
        if let characters = event.characters, !event.modifierFlags.contains(.command) {
            for character in characters {
                if let pair = KeyboardKey.decompose(character: character) {
                    _ = input?.key(pair.key, modifiers: pair.modifiers, duration: 0)
                }
            }
        }
    }

    public override func keyUp(with event: NSEvent) {
        // Press path bundles down+up so AppKit's keyUp is a no-op.
    }

    // MARK: - private helpers

    private func publishCursor(_ point: SimulatorPoint?, optionHeld: Bool) {
        guard let interactionState else { return }
        interactionState.cursorPosition = point.map { CGPoint(x: $0.x, y: $0.y) }
        interactionState.isOptionHeld = optionHeld
    }

    private func publishTouches(primary: SimulatorPoint, secondary: SimulatorPoint?) {
        guard let interactionState else { return }
        var touches: [CGPoint] = [CGPoint(x: primary.x, y: primary.y)]
        if let secondary {
            touches.append(CGPoint(x: secondary.x, y: secondary.y))
        }
        interactionState.activeTouches = touches
    }

    private var unitSize: SimulatorSize { SimulatorSize(width: 1, height: 1) }

    /// Mirrors a point across the screen centre so two fingers pinch symmetrically — the
    /// same shape Simulator.app produces when you hold Option and drag.
    private func mirror(_ point: SimulatorPoint) -> SimulatorPoint {
        SimulatorPoint(x: 1.0 - point.x, y: 1.0 - point.y)
    }

    /// Picks the edge bitmask iOS expects for a touch that started at `point`. Touches
    /// inside the safe-area get `.none`; touches that started on the home indicator strip
    /// or above the status bar get `.bottom` / `.top` so iOS's system-gesture recognizers
    /// see them as edge gestures (swipe-to-home, control-centre pull, etc.).
    private func edgeForPoint(_ point: SimulatorPoint) -> DeviceEdge? {
        if point.y >= 0.985 { return .bottom }
        if point.y <= 0.015 { return .top }
        return nil
    }

    /// Returns a normalized (0…1) point in the device's screen for the given event.
    /// The SwiftUI host applies `.aspectRatio(... contentMode: .fit)` so this view's bounds
    /// already match the simulator screen — no in-view letterboxing math is needed.
    private func normalizedPoint(for event: NSEvent) -> SimulatorPoint? {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return nil }
        let normX = localPoint.x / bounds.width
        // NSView is non-flipped by default: y grows up. Flip to top-left origin so
        // multiplying by image height matches iOS's coordinate space.
        let normY = (bounds.height - localPoint.y) / bounds.height
        return SimulatorPoint(x: Double(normX), y: Double(normY))
    }
}
