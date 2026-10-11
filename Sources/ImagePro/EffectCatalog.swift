import Foundation

enum EffectCatalog {
  static let groups:[(String,[EffectKind])] = [
    ("色彩调整",[.color,.hue,.selective,.levels,.curves,.wheels,.replace,.removeColor,.fade,.hdr,.monochrome,.colorize,.channels,.lut]),
    ("模糊与锐化",[.gaussianBlur,.motionBlur,.focusBlur,.sharpen]),("扭曲",[.bumpDistort,.pinchDistort,.stretchDistort,.twirlDistort,.waveDistort]),("光效与纹理",[.bloom,.grain,.vignette,.pixelate]),
    ("图层样式",[.outline,.shadow,.innerShadow,.outerGlow,.innerGlow,.bevel,.fillStyle]),("人像",[.beauty,.body])
  ]
}
