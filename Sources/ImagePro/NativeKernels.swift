import Foundation
import CoreImage

enum NativeKernels {
  static let library: Data? = {
    // Bundle resources in the app; source resource fallback supports SwiftPM tests.
    let source = URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .appendingPathComponent("Resources/ImageKernels.metallib")
    let url = Bundle.main.url(forResource:"ImageKernels",withExtension:"metallib") ?? source
    return try? Data(contentsOf:url)
  }()
  static func color(_ name:String) -> CIColorKernel? {
    guard let library else { return nil }
    return try? CIColorKernel(functionName:name,fromMetalLibraryData:library)
  }
  static func warp(_ name:String) -> CIWarpKernel? {
    guard let library else { return nil }
    return try? CIWarpKernel(functionName:name,fromMetalLibraryData:library)
  }
}
