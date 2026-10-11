import AppKit
import CInpaintingTools

enum MIGANInpainting {
  static let toolIDs = ["miganHeal"]
  static func isHealing(_ id: String) -> Bool { id == "miganHeal" }
  static var modelURL: URL? {
    Bundle.module.url(forResource: "migan_pipeline_v2", withExtension: "onnx", subdirectory: "InpaintingModels")
  }
  static var runtimeURL: URL {
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libonnxruntime.1.30.0.dylib")
    if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
    // SwiftPM command-line builds and tests use the pinned workspace dependency.
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("ThirdParty/ONNXRuntime/lib/libonnxruntime.1.30.0.dylib")
  }
  static func run(original: [UInt8], coverage: [UInt8], width: Int, height: Int,
    opacity: Float, backend: String) throws -> CGImage {
    guard width > 0, height > 0, width <= 8192, height <= 8192,
      original.count == width * height * 4, coverage.count == width * height,
      backend == "miganHeal" else { throw ImageProError.message(L("修复参数无效")) }
    var result = original, error = [CChar](repeating: 0, count: 1024)
    let model = modelURL?.path ?? "", runtime = runtimeURL.path
    let status = result.withUnsafeMutableBufferPointer { pixels in
      coverage.withUnsafeBufferPointer { mask in
        model.withCString { model in runtime.withCString { runtime in
          imagepro_inpaint(pixels.baseAddress, mask.baseAddress, width, height, opacity,
            model, runtime, &error, error.count)
        }}
      }
    }
    guard status == 0 else {
      let detail = String(cString: error)
      throw ImageProError.message(L("修复失败：{0}", detail))
    }
    guard let provider = CGDataProvider(data: Data(result) as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: ImageRenderer.colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
      throw ImageProError.message(L("修复笔触处理失败"))
    }
    return image
  }
}
