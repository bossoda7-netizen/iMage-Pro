import CoreImage
import Foundation

enum WaveDistortion {
  static let kernel = NativeKernels.warp("waveDistortion")
  static func apply(_ effect:ImageEffect,image:CIImage,scale:Double)->CIImage {
    guard let kernel else {return image}
    let result = kernel.apply(extent:image.extent,roiCallback:{_,rect in rect.insetBy(dx:-effect.value("amplitude",12)*scale-2,dy:-effect.value("amplitude",12)*scale-2)},image:image.clampedToExtent(),arguments:[
      effect.value("amplitude",12)*scale,max(1,effect.value("wavelength",80)*scale),effect.value("angle") * .pi/180,effect.value("phase") * .pi/180]) ?? image
    return AdvancedEffects.blend(result,over:image,amount:effect.amount).cropped(to:image.extent)
  }
}
enum FilmGrain {
  static let kernel = NativeKernels.color("filmGrain")
  static func apply(_ effect:ImageEffect,image:CIImage,scale:Double)->CIImage {
    guard let kernel else {return image}
    let strength = max(0, effect.value("strength", 0.55)) * effect.amount
    return kernel.apply(extent:image.extent,arguments:[image,max(0.5,effect.value("grainSize",1)),strength,effect.value("colored"),effect.value("style",0),max(0.0001,scale)]) ?? image
  }
}
