import AppKit
import CoreImage

extension ImageEffect {
  func curvePoints(_ prefix:String) -> [Point] {
    if let points = tonalCurves?[prefix],points.count>=2 {return points.sorted {$0.x<$1.x}}
    if !(0...4).contains(where:{parameters?["\(prefix)\($0)"] != nil}) {return [Point(x:0,y:0),Point(x:1,y:1)]}
    return (0...4).map {Point(x:Double($0)/4,y:value("\(prefix)\($0)",Double($0)/4))}
  }
}
extension AdvancedEffects {
  /// Shape-preserving Hermite interpolation. The graph and colour cube use this same curve.
  static func evaluateCurve(_ points:[Point],_ input:Double) -> Double {
    guard points.count>=2 else {return input}
    let p = points.sorted {$0.x<$1.x}
    if input<=p[0].x {return p[0].y}
    if input>=p.last!.x {return p.last!.y}
    let slopes = (0..<p.count-1).map {(p[$0+1].y-p[$0].y)/max(0.00001,p[$0+1].x-p[$0].x)}
    var tangent = [slopes[0]]
    for i in 1..<p.count-1 {
      let a = slopes[i-1],b = slopes[i]
      tangent.append(a*b<=0 ? 0 : 2*a*b/(a+b))
    }
    tangent.append(slopes.last!)
    let i = (0..<p.count-1).first {input<=p[$0+1].x} ?? p.count-2
    let width = max(0.00001,p[i+1].x-p[i].x),t = (input-p[i].x)/width
    let result = (2*t*t*t-3*t*t+1)*p[i].y + (t*t*t-2*t*t+t)*width*tangent[i]
      + (-2*t*t*t+3*t*t)*p[i+1].y + (t*t*t-t*t)*width*tangent[i+1]
    return min(1,max(0,result))
  }
  static func professional(_ e:ImageEffect,image:CIImage,scale:Double) -> CIImage? {
    let extent = image.extent,r = e.radius*scale
    switch e.kind {
    case .sharpen:
      let sharpened = image.clampedToExtent().applyingFilter("CIUnsharpMask",parameters:[kCIInputRadiusKey:max(0.1,r),kCIInputIntensityKey:e.value("sharpness",1)])
      // Preserve flat regions below the threshold, based on the high-frequency luminance difference.
      let difference = sharpened.applyingFilter("CIDifferenceBlendMode",parameters:[kCIInputBackgroundImageKey:image])
      let threshold = e.value("threshold",0.02)
      let mask = difference.applyingFilter("CIColorMatrix",parameters:[
        "inputRVector":CIVector(x:5,y:5,z:5,w:0),"inputGVector":CIVector(x:5,y:5,z:5,w:0),"inputBVector":CIVector(x:5,y:5,z:5,w:0),
        "inputBiasVector":CIVector(x:-threshold*15,y:-threshold*15,z:-threshold*15,w:0)])
      return blend(sharpened.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:mask]),over:image,amount:e.amount).cropped(to:extent)
    case .bloom:
      let bright = image.applyingFilter("CIColorClamp",parameters:["inputMinComponents":CIVector(x:e.value("threshold",0.7),y:e.value("threshold",0.7),z:e.value("threshold",0.7),w:0)])
      let highlight = bright.applyingFilter("CIColorMatrix",parameters:["inputBiasVector":CIVector(x:-e.value("threshold",0.7),y:-e.value("threshold",0.7),z:-e.value("threshold",0.7),w:0)])
      let glow = highlight.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:r])
      return blend(glow.applyingFilter("CIScreenBlendMode",parameters:[kCIInputBackgroundImageKey:image]),over:image,amount:e.amount).cropped(to:extent)
    case .grain: return FilmGrain.apply(e,image:image,scale:scale)
    case .pixelate:
      // CIPixellate samples outside the image with transparent black at high
      // scales. Clamp first and crop last so edge alpha remains untouched.
      let pixel = image.clampedToExtent().applyingFilter("CIPixellate",parameters:[kCIInputScaleKey:max(1,r),kCIInputCenterKey:CIVector(x:extent.minX+extent.width*e.value("centerX",0.5),y:extent.minY+extent.height*(1-e.value("centerY",0.5)))])
      return blend(pixel,over:image,amount:e.amount).cropped(to:extent)
    case .vignette:
      let center = CIVector(x:extent.minX+extent.width*e.value("centerX",0.5),y:extent.minY+extent.height*(1-e.value("centerY",0.5)))
      let radius = min(extent.width,extent.height)*e.value("vignetteSize",0.6)
      return image.applyingFilter("CIVignetteEffect",parameters:[kCIInputCenterKey:center,kCIInputIntensityKey:e.amount*e.value("intensity",1),kCIInputRadiusKey:radius,"inputFalloff":e.value("falloff",0.5)]).cropped(to:extent)
    case .monochrome:
      // Six hue ranges determine the luminance of coloured objects independently.
      let dim = 24
      var cube = [Float]()
      let hues = [0.0,1.0/6,1.0/3,0.5,2.0/3,5.0/6]
      for b in 0..<dim {for g in 0..<dim {for r in 0..<dim {
        let rgb = [Double(r)/23,Double(g)/23,Double(b)/23]
        let (h,s,_) = rgbToHSV(rgb[0],rgb[1],rgb[2])
        var l = rgb[0]*0.2126+rgb[1]*0.7152+rgb[2]*0.0722
        for i in 0..<6 {let distance = abs(h-hues[i]);l += max(0,1-min(distance,1-distance)*6)*s*e.value("mono\(i)")*0.5}
        l = min(1,max(0,l));cube += [Float(l),Float(l),Float(l),1]
      }}}
      let result = image.applyingFilter("CIColorCube",parameters:["inputCubeDimension":dim,"inputCubeData":cube.withUnsafeBufferPointer {Data(buffer:$0)}])
      return blend(result,over:image,amount:e.amount)
    case .hdr:
      let result = image.applyingFilter("CIHighlightShadowAdjust",parameters:["inputShadowAmount":e.value("shadows",0.4),"inputHighlightAmount":1-e.value("highlights",0.4)])
        .applyingFilter("CIUnsharpMask",parameters:[kCIInputRadiusKey:max(1,r),kCIInputIntensityKey:e.value("detail",0.2)])
      return blend(result,over:image,amount:e.amount).cropped(to:extent)
    default:return nil
    }
  }
}
extension EditorStore {
  func effectInput(_ id:UUID) -> CGImage? {
    guard var layer = selected,let index = layer.effects.firstIndex(where:{$0.id == id}) else {return preview}
    layer.effects = Array(layer.effects.prefix(index))
    if layer.kind == .adjustment,let layerIndex = document.layers.firstIndex(where:{$0.id == layer.id}) {
      var input = document
      input.layers = Array(input.layers.dropFirst(layerIndex+1))
      // Ancestor groups carry opacity/visibility even when the selected adjustment lies inside one.
      var ancestors = Set<UUID>(),parent = layer.parentID
      while let id = parent,let group = document.layers.first(where:{$0.id == id}) {ancestors.insert(id);parent = group.parentID}
      input.layers.insert(contentsOf:document.layers.filter {group in ancestors.contains(group.id) && !input.layers.contains(where:{$0.id == group.id})},at:0)
      for i in input.layers.indices {if let id = input.layers[i].parentID,!input.layers.contains(where:{$0.id == id}) {input.layers[i].parentID = nil}}
      input.selectedLayerID = nil
      if let cached = adjustmentInputCache,cached.0 == input,cached.1 == layer {return cached.2}
      var ci = renderer.render(input,assets:active.assets,maxDimension:512).map {CIImage(cgImage:$0)}
      if let original = ci {for e in layer.effects where e.enabled {ci = renderer.apply(e,to:ci ?? original,scale:Double(original.extent.width)/document.width)}}
      let image = ci.flatMap {renderer.context.createCGImage($0,from:$0.extent)}
      adjustmentInputCache = (input,layer,image);return image
    }
    if let cached = effectInputCache, cached.0 == layer {return cached.1}
    let result = renderer.renderLayer(layer,assets:active.assets,scale:min(1,512/max(layer.width,layer.height)))
    effectInputCache = (layer,result);return result
  }
}
