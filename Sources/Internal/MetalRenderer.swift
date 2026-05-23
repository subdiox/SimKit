import CoreVideo
import IOSurface
import Metal
import QuartzCore

/// Renders the simulator framebuffer plus touch indicators on the GPU. Both the live
/// `CAMetalLayer` display and the recording pipeline consume the *same* output IOSurface,
/// so display and video are pixel-identical by construction.
///
/// Per-frame work is roughly: sample one texture + a tight loop over up to ~8 touch points
/// per fragment. Comfortably under 2 % GPU on Apple Silicon at 60 fps for a 1206×2622
/// surface.
@MainActor
final class MetalRenderer {
  /// Touch point in normalized device-screen coordinates (top-left origin, 0…1).
  struct TouchInput: Sendable {
    let position: CGPoint
    /// Diameter as a fraction of the shorter image side; matches the SwiftUI overlay's
    /// "10 % of min dimension" rule so they look identical.
    let diameterFraction: CGFloat
  }

  let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState

  /// Composited output (input framebuffer with touch indicators baked in). Re-allocated
  /// whenever the source IOSurface size changes.
  private(set) var outputIOSurface: IOSurface?
  private var outputTexture: MTLTexture?
  private var outputSize: CGSize = .zero
  /// Retained for the lifetime of `outputIOSurface` — the IOSurface here comes from a
  /// CVPixelBuffer (so CoreVideo gets the row-alignment right for Apple-Silicon GPUs),
  /// and we have to keep the pixel buffer alive to keep the surface alive.
  private var outputPixelBuffer: CVPixelBuffer?

  init?() {
    guard let device = MTLCreateSystemDefaultDevice() else {
      assertionFailure("No Metal device available — simulator preview will be blank.")
      return nil
    }
    guard let queue = device.makeCommandQueue() else {
      assertionFailure("MTLDevice.makeCommandQueue returned nil.")
      return nil
    }
    self.device = device
    self.commandQueue = queue

    do {
      let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
      guard let vertexFn = library.makeFunction(name: "simulator_vertex"),
        let fragmentFn = library.makeFunction(name: "simulator_fragment")
      else {
        assertionFailure("MetalRenderer shader functions missing — shader source out of sync.")
        return nil
      }
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = vertexFn
      descriptor.fragmentFunction = fragmentFn
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
      assertionFailure("MetalRenderer pipeline build failed: \(error)")
      return nil
    }
  }

  /// Renders one frame of the simulator framebuffer + touches, presenting to `layer` and
  /// updating `outputIOSurface` for any recording consumer.
  func render(
    input: IOSurface,
    touches: [TouchInput],
    to layer: CAMetalLayer
  ) {
    let width = IOSurfaceGetWidth(input)
    let height = IOSurfaceGetHeight(input)
    let imageSize = CGSize(width: width, height: height)

    if outputIOSurface == nil || outputSize != imageSize {
      allocateOutput(width: width, height: height)
    }
    guard let outputTexture, outputIOSurface != nil,
      let inputTexture = makeTexture(from: input, width: width, height: height)
    else {
      return
    }

    layer.drawableSize = imageSize
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true

    // Build the touch uniform array in pixel space — the shader does its distance check
    // in pixels so circles stay round on non-square framebuffers.
    let pixelTouches: [PackedTouch] = touches.map { touch in
      let shorter = CGFloat(min(width, height))
      let diameter = shorter * touch.diameterFraction
      return PackedTouch(
        position: SIMD2<Float>(
          Float(touch.position.x * CGFloat(width)),
          Float(touch.position.y * CGFloat(height))
        ),
        radius: Float(diameter * 0.5),
        _padding: 0
      )
    }
    let uniforms = Uniforms(
      textureSize: SIMD2<Float>(Float(width), Float(height)),
      touchCount: UInt32(pixelTouches.count),
      _padding: SIMD2<Float>(0, 0)
    )

    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

    // 1. Render composite into the offscreen IOSurface-backed texture.
    let renderPass = MTLRenderPassDescriptor()
    renderPass.colorAttachments[0].texture = outputTexture
    renderPass.colorAttachments[0].loadAction = .dontCare
    renderPass.colorAttachments[0].storeAction = .store

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
    encoder.setRenderPipelineState(pipelineState)
    encoder.setFragmentTexture(inputTexture, index: 0)
    if !pixelTouches.isEmpty {
      pixelTouches.withUnsafeBytes { raw in
        encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
      }
    } else {
      // Setting at least one byte avoids a Metal validation warning when the buffer
      // would otherwise be zero-length; the shader gates on `touchCount`.
      var stub = PackedTouch(position: .zero, radius: 0, _padding: 0)
      encoder.setFragmentBytes(&stub, length: MemoryLayout<PackedTouch>.size, index: 0)
    }
    var uniformsLocal = uniforms
    encoder.setFragmentBytes(&uniformsLocal, length: MemoryLayout<Uniforms>.size, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    // 2. Composite the offscreen result into the drawable via a copy render pass.
    if let drawable = layer.nextDrawable() {
      let copyPass = MTLRenderPassDescriptor()
      copyPass.colorAttachments[0].texture = drawable.texture
      copyPass.colorAttachments[0].loadAction = .dontCare
      copyPass.colorAttachments[0].storeAction = .store
      if let copyEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: copyPass) {
        copyEncoder.setRenderPipelineState(pipelineState)
        copyEncoder.setFragmentTexture(outputTexture, index: 0)
        var stub = PackedTouch(position: .zero, radius: 0, _padding: 0)
        copyEncoder.setFragmentBytes(&stub, length: MemoryLayout<PackedTouch>.size, index: 0)
        var copyUniforms = Uniforms(
          textureSize: SIMD2<Float>(Float(width), Float(height)),
          touchCount: 0,
          _padding: SIMD2<Float>(0, 0)
        )
        copyEncoder.setFragmentBytes(&copyUniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        copyEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        copyEncoder.endEncoding()
      }
      commandBuffer.present(drawable)
    }
    commandBuffer.commit()
  }

  // MARK: - private

  /// Creates an output pixel buffer (and its backing IOSurface) via CoreVideo so the row
  /// stride matches what Metal's texture validator wants on the current GPU. Going through
  /// `IOSurfaceCreate` directly with `bytesPerRow = width * 4` aborts on Apple Silicon
  /// (G16+ wants 256-byte alignment for BGRA render targets).
  private func allocateOutput(width: Int, height: Int) {
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferWidthKey: width,
      kCVPixelBufferHeightKey: height,
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer
    )
    guard status == kCVReturnSuccess,
      let pixelBuffer,
      let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
    else {
      return
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
      return
    }
    outputPixelBuffer = pixelBuffer
    outputIOSurface = surface
    outputTexture = texture
    outputSize = CGSize(width: width, height: height)
  }

  private func makeTexture(from surface: IOSurface, width: Int, height: Int) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    return device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
  }

  // MARK: - shader

  private struct PackedTouch {
    var position: SIMD2<Float>
    var radius: Float
    var _padding: Float
  }
  private struct Uniforms {
    var textureSize: SIMD2<Float>
    var touchCount: UInt32
    var _padding: SIMD2<Float>
  }

  private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    // Fullscreen triangle covers the entire viewport in 3 vertices, with UV mapped so that
    // (0,0) is top-left to match the IOSurface's display orientation.
    vertex VertexOut simulator_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 uvs[3] = { float2(0, 1), float2(2, 1), float2(0, -1) };
        VertexOut out;
        out.position = float4(positions[vid], 0, 1);
        out.uv = uvs[vid];
        return out;
    }

    struct PackedTouch {
        float2 position;
        float  radius;
        float  _padding;
    };

    struct Uniforms {
        float2 textureSize;
        uint   touchCount;
        float2 _padding;
    };

    fragment float4 simulator_fragment(
        VertexOut in [[stage_in]],
        texture2d<float, access::sample> base [[texture(0)]],
        constant PackedTouch* touches [[buffer(0)]],
        constant Uniforms& uniforms [[buffer(1)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 color = base.sample(s, in.uv);

        if (uniforms.touchCount == 0u) { return color; }

        float2 pixel = in.uv * uniforms.textureSize;
        for (uint i = 0u; i < uniforms.touchCount; i++) {
            float r = touches[i].radius;
            float d = distance(pixel, touches[i].position);
            if (d <= r) {
                // 1-pixel anti-aliased fill / border.
                float border = max(r * 0.05, 1.5);
                float3 fill   = float3(0.78);
                float3 stroke = float3(0.55);
                float t = smoothstep(r - border - 1.0, r - border, d);
                float3 c = mix(fill, stroke, t);
                float edge = 1.0 - smoothstep(r - 1.0, r, d);
                color = float4(mix(color.rgb, c, edge), 1.0);
            }
        }
        return color;
    }
    """
}
