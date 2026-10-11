import AppKit
import CoreImage

enum EffectStyles {
  static let blur = [
    ("gaussian", "高斯"), ("box", "方框"), ("disc", "磁盘"), ("motion", "运动"), ("zoom", "缩放"),
    ("spin", "旋转"), ("bokeh", "散景"), ("tilt", "倾斜移位"), ("focus", "聚焦"),
  ]
  static let distort = [
    ("bump", "凹凸"), ("pinch", "收缩"), ("stretch", "拉伸"), ("circle", "圆圈飞溅"), ("hole", "孔"),
    ("tunnel", "光隧道"), ("twirl", "旋转"), ("vortex", "旋涡"),
  ]
}
enum AdvancedEffects {
  static let bevelKernel = NativeKernels.color("contourBevel")
  private static let cubeLock = NSLock()
  private static var cubes: [UUID:(ImageEffect,Data)] = [:]
  static func apply(_ e: ImageEffect, image: CIImage, scale: Double) -> CIImage? {
    if let professional = professional(e,image:image,scale:scale) {return professional}
    let r = max(0, min(500, e.radius)) * scale
    let amount = max(0, min(1, e.amount))
    let extent = image.extent
    let center = CIVector(
      x: extent.minX + extent.width * e.value("centerX", 0.5),
      y: extent.minY + extent.height * (1 - e.value("centerY", 0.5)))
    switch e.kind {
    case .color:
      var result = colorCube(e, image: image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: e.exposure]))
        .applyingFilter(
          "CIColorControls",
          parameters: [
            kCIInputBrightnessKey: e.brightness, kCIInputContrastKey: e.contrast,
            kCIInputSaturationKey: e.saturation,
          ])
      let detail = e.value("texture") + e.value("clarity")
      if detail != 0 {
        result = result.applyingFilter(
          "CIUnsharpMask",
          parameters: [
            kCIInputRadiusKey: max(1, (3 + e.value("clarity") * 12) * scale),
            kCIInputIntensityKey: detail,
          ])
      }
      if e.value("blackPoint") != 0 {
        let black = e.value("blackPoint") * 0.25
        result = result.applyingFilter(
          "CIColorMatrix",
          parameters: [
            "inputRVector": CIVector(x: 1 + black, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1 + black, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1 + black, w: 0),
            "inputBiasVector": CIVector(x: -black, y: -black, z: -black, w: 0),
          ])
      }
      return blend(result,over:image,amount:amount)
    case .blur, .gaussianBlur, .motionBlur, .focusBlur:
      let blurred: CIImage
      switch e.kind.independentStyle ?? e.style ?? "gaussian" {
      case "box":
        blurred = image.clampedToExtent().applyingFilter(
          "CIBoxBlur", parameters: [kCIInputRadiusKey: r])
      case "bokeh":
        blurred = image.clampedToExtent().applyingFilter(
          "CIBokehBlur",
          parameters: [
            kCIInputRadiusKey: r, "inputRingAmount": e.value("ringAmount", 0.5),
            "inputRingSize": e.value("ringSize", 0.1), "inputSoftness": e.value("softness", 1),
          ])
      case "disc":
        blurred = image.clampedToExtent().applyingFilter(
          "CIDiscBlur", parameters: [kCIInputRadiusKey: r])
      case "motion":
        blurred = image.clampedToExtent().applyingFilter(
          "CIMotionBlur",
          parameters: [kCIInputRadiusKey: r, kCIInputAngleKey: e.value("angle") * .pi / 180])
      case "zoom":
        blurred = image.applyingFilter(
          "CIZoomBlur", parameters: [kCIInputCenterKey: center, kCIInputAmountKey: r])
      case "spin":
        var sum = CIImage(color: .clear).cropped(to: extent)
        let count = 13
        for i in 0..<count {
          let a = (Double(i) / Double(count - 1) - 0.5) * r * 0.005
          let t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: a)
            .translatedBy(x: -center.x, y: -center.y)
          let sample = image.clampedToExtent().transformed(by: t).cropped(to: extent)
            .applyingFilter(
              "CIColorMatrix",
              parameters: [
                "inputRVector": CIVector(x: 1 / Double(count), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 / Double(count), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 / Double(count), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1 / Double(count)),
              ])
          sum = sample.applyingFilter(
            "CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: sum])
        }
        blurred = sum
      case "focus", "tilt":
        let soft = image.clampedToExtent().applyingFilter(
          "CIGaussianBlur", parameters: [kCIInputRadiusKey: r])
        let mask: CIImage
        if (e.kind.independentStyle ?? e.style) == "focus" {
          mask = CIFilter(
            name: "CIRadialGradient",
            parameters: [
              kCIInputCenterKey: center, "inputRadius0": min(extent.width,extent.height)*e.value("regionSize",0.15),
              "inputRadius1": min(extent.width,extent.height)*(e.value("regionSize",0.15)+e.value("transition",0.3)), "inputColor0": CIColor.black,
              "inputColor1": CIColor.white,
            ])!.outputImage!
        } else {
          let width = extent.height*e.value("regionSize",0.15)
          let transition = extent.height*e.value("transition",0.3)
          let top = CIFilter(
            name: "CILinearGradient",
            parameters: [
              "inputPoint0": CIVector(x: 0, y: center.y + width),
              "inputPoint1": CIVector(x: 0, y: center.y + width + transition), "inputColor0": CIColor.black,
              "inputColor1": CIColor.white,
            ])!.outputImage!
          let bottom = CIFilter(
            name: "CILinearGradient",
            parameters: [
              "inputPoint0": CIVector(x: 0, y: center.y - width),
              "inputPoint1": CIVector(x: 0, y: center.y - width - transition), "inputColor0": CIColor.black,
              "inputColor1": CIColor.white,
            ])!.outputImage!
          mask = top.applyingFilter(
            "CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: bottom])
        }
        blurred = soft.applyingFilter(
          "CIBlendWithMask",
          parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask.cropped(to: extent),
          ])
      default:
        blurred = image.clampedToExtent().applyingFilter(
          "CIGaussianBlur", parameters: [kCIInputRadiusKey: r])
      }
      return blend(blurred.cropped(to: extent), over: image, amount: amount)
    case .body: return blend(PortraitEffects.body(e,image:image),over:image,amount:amount)
    case .distort, .bumpDistort, .pinchDistort, .stretchDistort, .twirlDistort, .waveDistort:
      let radius = max(1, e.value("regionSize", 0.35) * min(extent.width, extent.height))
      let style = e.kind.independentStyle ?? e.style ?? "bump"
      let name: String
      let params: [String: Any]
      if style == "wave" {return WaveDistortion.apply(e,image:image,scale:scale)}
      switch style {
      case "pinch":
        name = "CIPinchDistortion"
        params = [
          kCIInputCenterKey: center, kCIInputRadiusKey: radius,
          kCIInputScaleKey: e.value("deformation", 0.3),
        ]
      case "stretch":
        name = "CIBumpDistortionLinear"
        params = [
          kCIInputCenterKey: center, kCIInputRadiusKey: radius,
          kCIInputScaleKey: e.value("deformation", 0.3),
          kCIInputAngleKey: e.value("angle") * .pi / 180,
        ]
      case "circle":
        name = "CICircleSplashDistortion"
        params = [kCIInputCenterKey: center, kCIInputRadiusKey: radius]
      case "hole":
        name = "CIHoleDistortion"
        params = [kCIInputCenterKey: center, kCIInputRadiusKey: radius]
      case "tunnel":
        name = "CILightTunnel"
        params = [
          kCIInputCenterKey: center, kCIInputRadiusKey: radius,
          "inputRotation": e.value("angle") * .pi / 180,
        ]
      case "twirl":
        name = "CITwirlDistortion"
        params = [
          kCIInputCenterKey: center, kCIInputRadiusKey: radius,
          kCIInputAngleKey: e.value("angle", 45) * .pi / 180,
        ]
      case "vortex":
        name = "CIVortexDistortion"
        params = [
          kCIInputCenterKey: center, kCIInputRadiusKey: radius,
          kCIInputAngleKey: e.value("angle", 90) * .pi / 180,
        ]
      default:
        name = "CIBumpDistortion"
        params = [
          kCIInputCenterKey: center, kCIInputRadiusKey: radius,
          kCIInputScaleKey: e.value("deformation", 0.3),
        ]
      }
      return blend(
        image.clampedToExtent().applyingFilter(name, parameters: params).cropped(to: extent),
        over: image, amount: amount)
    case .levels, .hue, .selective, .wheels, .replace, .removeColor, .fade, .colorize, .channels:
      let mapped = colorCube(e,image:image)
      return [.levels,.hue,.selective,.wheels,.channels].contains(e.kind) ? blend(mapped,over:image,amount:amount) : mapped
    case .curves:
      return blend(curveCube(e,image:image,channel:nil),over:image,amount:amount)
    case .lut:
      guard let data = e.lutData, let dimension = e.lutDimension, (2...64).contains(dimension),
        data.count == dimension * dimension * dimension * 16
      else { return image }
      let result = image.applyingFilter(
        "CIColorCube", parameters: ["inputCubeDimension": dimension, "inputCubeData": data])
      return blend(result, over: image, amount: amount)
    case .beauty: return PortraitEffects.beauty(e,image:image)
    case .outline, .shadow, .innerShadow, .outerGlow, .innerGlow, .bevel, .fillStyle:
      return layerStyle(e, image: image, scale: scale)
    default: return nil
    }
  }
  static func blend(_ processed: CIImage, over original: CIImage, amount: Double) -> CIImage {
    let v = max(0, min(1, amount))
    let mask = CIImage(color: CIColor(red: v, green: v, blue: v, alpha: 1)).cropped(
      to: original.extent)
    return processed.applyingFilter(
      "CIBlendWithMask",
      parameters: [kCIInputBackgroundImageKey: original, kCIInputMaskImageKey: mask])
  }
  static func curveValue(_ effect: ImageEffect, prefix: String, _ input: Double) -> Double {
    evaluateCurve(effect.curvePoints(prefix),input)
  }

  static func curveCube(_ e: ImageEffect, image: CIImage, channel: String?) -> CIImage {
    let dim = 24
    var cube = [Float](); cube.reserveCapacity(dim * dim * dim * 4)
    let prefixes = ["curve", "redCurve", "greenCurve", "blueCurve"]
    for b in 0..<dim {
      for g in 0..<dim {
        for r in 0..<dim {
          let input = [Double(r) / Double(dim - 1), Double(g) / Double(dim - 1), Double(b) / Double(dim - 1)]
          var output = input
          for i in 0..<3 {
            let combined = curveValue(e,prefix:"curve",input[i])
            output[i] = curveValue(e,prefix:prefixes[i+1],combined)
          }
          cube.append(contentsOf: output.map { Float(max(0, min(1, $0))) } + [1])
        }
      }
    }
    let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
    return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": dim, "inputCubeData": data])
  }
  static func silhouette(_ image: CIImage, color: RGBA, opacity: Double = 1) -> CIImage {
    image.applyingFilter(
      "CIColorMatrix",
      parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: color.r * opacity * color.a),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: color.g * opacity * color.a),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: color.b * opacity * color.a),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity * color.a),
      ])
  }
  static func layerStyle(_ e: ImageEffect, image: CIImage, scale: Double) -> CIImage {
    let extent = image.extent
    let r = max(0.1, min(100, e.radius) * scale)
    let amount = e.amount
    let spreadValue = e.value("spread")
    let spreadFraction = min(1,max(0,spreadValue > 1 ? spreadValue/50 : spreadValue))
    let spreadRadius = r * spreadFraction
    let softness = max(0.01,r * (1-spreadFraction))
    let transparent = CIImage(color: .clear).cropped(to: extent.insetBy(dx: -r * 5, dy: -r * 5))
    let expanded = image.composited(over: transparent)
    let tint =
      e.tint
      ?? RGBA(
        r: e.kind == .shadow || e.kind == .innerShadow ? 0 : 1,
        g: e.kind == .shadow || e.kind == .innerShadow ? 0 : 1,
        b: e.kind == .shadow || e.kind == .innerShadow ? 0 : 1)
    let alpha = silhouette(expanded, color: RGBA(r: 1, g: 1, b: 1))
    switch e.kind {
    case .outline:
      let position = e.style ?? "outside"
      let half = position == "center" ? r/2 : r
      let outer = position == "inside" ? alpha : alpha.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: half])
      let inner = position == "outside" ? alpha : alpha.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: half])
      let ring = outer.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
      return silhouette(ring,color:tint,opacity:amount).composited(over:image)
    case .shadow:
      let angle = e.value("angle", 45) * .pi / 180
      let distance = e.value("distance", 8) * scale
      let spread = expanded.applyingFilter("CIMorphologyMaximum",parameters:[kCIInputRadiusKey:spreadRadius])
      let shadow = silhouette(spread, color: tint, opacity: amount).applyingFilter(
        "CIGaussianBlur", parameters: [kCIInputRadiusKey: softness]
      )
      .transformed(
        by: CGAffineTransform(translationX: cos(angle) * distance, y: -sin(angle) * distance))
      return image.composited(over: shadow)
    case .outerGlow:
      let spread = expanded.applyingFilter("CIMorphologyMaximum",parameters:[kCIInputRadiusKey:spreadRadius])
      let glow = silhouette(spread, color: tint, opacity: amount).applyingFilter(
        "CIGaussianBlur", parameters: [kCIInputRadiusKey: softness])
      return image.composited(over: glow)
    case .innerShadow:
      let distance = e.kind == .innerShadow ? e.value("distance", 8) * scale : 0
      let angle = e.value("angle", 45) * .pi / 180
      let contracted = alpha.applyingFilter("CIMorphologyMinimum",parameters:[kCIInputRadiusKey:spreadRadius])
      let shifted = contracted.transformed(
        by: CGAffineTransform(translationX: cos(angle) * distance, y: -sin(angle) * distance)
      )
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: softness])
      let edge = alpha.applyingFilter(
        "CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: shifted])
      return silhouette(edge, color: tint, opacity: amount).composited(over: image)
    case .innerGlow:
      // Build the glow from the interior ring (alpha minus its eroded mask).
      // The previous source-out order produced an inverted mask, so increasing
      // the radius made the white glow turn black on opaque artwork.
      let inner = alpha.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: max(0.1, r)])
      let ring = inner.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: alpha])
        .applyingFilter("CIMaskToAlpha")
      let glow = silhouette(ring, color: tint, opacity: amount)
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: r * 0.55])
      return glow.composited(over: image)
    case .bevel:
      guard let bevelKernel else { return image }
      let height = alpha.applyingFilter("CIHeightFieldFromMask",parameters:[kCIInputRadiusKey:r])
      let step = max(1,scale)
      let angle = e.value("angle",45) * .pi/180, altitude = e.value("altitude",35) * .pi/180
      return bevelKernel.apply(extent:extent,arguments:[image,
        height.transformed(by:CGAffineTransform(translationX:step,y:0)),
        height.transformed(by:CGAffineTransform(translationX:-step,y:0)),
        height.transformed(by:CGAffineTransform(translationX:0,y:step)),
        height.transformed(by:CGAffineTransform(translationX:0,y:-step)),
        e.value("depth",4),CIVector(x:cos(angle)*cos(altitude),y:sin(angle)*cos(altitude),z:sin(altitude)),
        CIVector(x:tint.r,y:tint.g,z:tint.b),amount]) ?? image
    case .fillStyle:
      let fill:CIImage
      if let gradient = e.gradient, e.style != "solid" {
        let cg = GradientRenderer.render(gradient,width:max(1,Int(extent.width)),height:max(1,Int(extent.height)))
        fill = CIImage(cgImage:cg).transformed(by:CGAffineTransform(translationX:extent.minX,y:extent.minY))
      } else if e.style == "gradient" {
        let angle = e.value("angle",90) * .pi/180
        let distance = hypot(extent.width,extent.height)/2
        fill = CIFilter(name:"CILinearGradient",parameters:[
          "inputPoint0":CIVector(x:extent.midX-cos(angle)*distance,y:extent.midY-sin(angle)*distance),
          "inputPoint1":CIVector(x:extent.midX+cos(angle)*distance,y:extent.midY+sin(angle)*distance),
          "inputColor0":CIColor(color:tint.ns)!,"inputColor1":CIColor(color:(e.targetColor ?? RGBA(r:0.3,g:0.4,b:1)).ns)!])!.outputImage!.cropped(to:extent)
      } else if e.style == "radial" {
        let radius = min(extent.width, extent.height) * e.value("gradientRadius", 0.7)
        fill = CIFilter(name: "CIRadialGradient", parameters: [
          "inputCenter": CIVector(x: extent.midX, y: extent.midY),
          "inputRadius0": max(1, radius * 0.08),
          "inputRadius1": max(1, radius),
          "inputColor0": CIColor(color: tint.ns)!,
          "inputColor1": CIColor(color: (e.targetColor ?? RGBA(r: 0.3, g: 0.4, b: 1)).ns)!
        ])!.outputImage!.cropped(to: extent)
      } else { fill = CIImage(color:CIColor(color:tint.ns)!).cropped(to:extent) }
      let painted = fill.applyingFilter("CISourceInCompositing",parameters:[kCIInputBackgroundImageKey:image])
      return blend(painted,over:image,amount:amount)
    default: return image
    }
  }
  static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let maxV = max(r, g, b)
    let minV = min(r, g, b)
    let d = maxV - minV
    var h: Double = 0
    if d > 0 {
      h = maxV == r ? (g - b) / d : maxV == g ? 2 + (b - r) / d : 4 + (r - g) / d
      h = h / 6
      if h < 0 { h += 1 }
    }
    return (h, maxV == 0 ? 0 : d / maxV, maxV)
  }
  static func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    let hue = h - floor(h)
    let i = Int(hue * 6)
    let f = hue * 6 - Double(i)
    let p = v * (1 - s)
    let q = v * (1 - f * s)
    let t = v * (1 - (1 - f) * s)
    switch i % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
  }
  static func colorCube(_ e: ImageEffect, image: CIImage) -> CIImage {
    let dim = 24
    cubeLock.lock();let cached = cubes[e.id];cubeLock.unlock()
    if let cached, cached.0 == e {
      return image.applyingFilter("CIColorCube",parameters:["inputCubeDimension":dim,"inputCubeData":cached.1])
    }
    var cube = [Float]()
    cube.reserveCapacity(dim * dim * dim * 4)
    let source = e.sourceColor ?? RGBA(r: 1, g: 0, b: 0)
    let target = e.targetColor ?? RGBA(r: 0, g: 0.4, b: 1)
    for b in 0..<dim {
      for g in 0..<dim {
        for r in 0..<dim {
          var red = Double(r) / Double(dim - 1)
          var green = Double(g) / Double(dim - 1)
          var blue = Double(b) / Double(dim - 1)
          var alpha = 1.0
          var (h, s, v) = rgbToHSV(red, green, blue)
          switch e.kind {
          case .color:
            let luminance = red*0.2126 + green*0.7152 + blue*0.0722
            let highlights = pow(max(0,(luminance-0.35)/0.65),2) * e.value("highlights") * 0.55
            let shadows = pow(max(0,(0.65-luminance)/0.65),2) * e.value("shadows") * 0.55
            func tone(_ v: Double) -> Double {
              let shift = highlights+shadows
              return shift >= 0 ? v + (1-v)*shift : v + v*shift
            }
            red = tone(red); green = tone(green); blue = tone(blue)
          case .hue:
            h += e.value("hue") / 360
            s *= 1 + e.value("saturation")
            v += e.value("lightness")
            (red, green, blue) = hsvToRGB(h, min(1, max(0, s)), min(1, max(0, v)))
          case .selective:
            let targets = [0.0, 1.0 / 12, 1.0 / 6, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 5.0 / 6]
            var hueShift = 0.0
            var saturation = 0.0
            var lightness = 0.0
            for i in 0..<8 {
              let d = abs(h - targets[i])
              let weight = max(0, 1 - min(d, 1 - d) * 12) * s
              hueShift += e.value("hue\(i)") * weight
              saturation += e.value("sat\(i)") * weight
              lightness += e.value("light\(i)") * weight
            }
            (red, green, blue) = hsvToRGB(
              h + hueShift / 360, min(1, max(0, s * (1 + saturation))),
              min(1, max(0, v + lightness)))
          case .wheels:
            let luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
            for (i, weight) in [
              (0, pow(luma, 2)), (1, max(0, 1 - abs(luma - 0.5) * 2)), (2, pow(1 - luma, 2)),
            ] {
              let x = e.value("wheelX\(i)")
              let y = e.value("wheelY\(i)")
              let strength = min(1, hypot(x, y)) * 0.3 * weight
              let c = hsvToRGB(atan2(y, x) / (2 * .pi), 1, 1)
              red += (c.0 - 0.5) * strength
              green += (c.1 - 0.5) * strength
              blue += (c.2 - 0.5) * strength
              let lift = e.value("wheelLift\(i)") * weight
              red += lift
              green += lift
              blue += lift
            }
          case .levels:
            func map(_ x:Double,_ prefix:String)->Double {
              let black = min(0.95,e.value(prefix+"black")),white = max(black+0.001,e.value(prefix+"white",1))
              let low = e.value(prefix+"outBlack"),high = e.value(prefix+"outWhite",1)
              return low+pow(min(1,max(0,(x-black)/(white-black))),1/max(0.1,e.value(prefix+"gamma",1)))*(high-low)
            }
            red = map(map(red,""),"red_");green = map(map(green,""),"green_");blue = map(map(blue,""),"blue_")
          case .replace, .removeColor:
            let distance =
              sqrt(pow(red - source.r, 2) + pow(green - source.g, 2) + pow(blue - source.b, 2))
              / sqrt(3)
            let range = max(0.005, e.value("range", 0.2))
            let strength = min(1, max(0, (range - distance) / max(0.005, range * 0.25))) * e.amount
            if e.kind == .removeColor {
              alpha = 1 - strength
            } else {
              red += (target.r - red) * strength
              green += (target.g - green) * strength
              blue += (target.b - blue) * strength
            }
          case .fade:
            let l = red*0.2126+green*0.7152+blue*0.0722
            let strength = e.amount*(e.value("fadeShadows",0.5)*(1-l)+e.value("fadeHighlights",0.2)*l)*0.4
            red = red * (1 - strength) + strength * 0.7
            green = green * (1 - strength) + strength * 0.65
            blue = blue * (1 - strength) + strength * 0.55
          case .colorize:
            let c = e.tint ?? RGBA(r: 0.7, g: 0.4, b: 0.2)
            let l = red * 0.2126 + green * 0.7152 + blue * 0.0722
            red += (c.r * l * 1.7 - red) * e.amount
            green += (c.g * l * 1.7 - green) * e.amount
            blue += (c.b * l * 1.7 - blue) * e.amount
          case .channels:
            let initial = [red, green, blue]
            func channel(_ i: Int) -> Double {
              (0..<3).reduce(e.value("bias\(i)")) {
                $0 + initial[$1] * e.value("channel\(i)_\($1)", i == $1 ? 1 : 0)
              }
            }
            red = channel(0)
            green = channel(1)
            blue = channel(2)
          default: break
          }
          cube.append(contentsOf: [
            Float(min(1, max(0, red)) * alpha), Float(min(1, max(0, green)) * alpha),
            Float(min(1, max(0, blue)) * alpha),
            Float(alpha),
          ])
        }
      }
    }
    let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
    cubeLock.lock()
    if cubes.count > 100 { cubes.removeAll() }
    cubes[e.id] = (e,data);cubeLock.unlock()
    return image.applyingFilter(
      "CIColorCube", parameters: ["inputCubeDimension": dim, "inputCubeData": data])
  }
  static func parseLUT(_ text: String) throws -> (Int, Data) {
    var dimension = 0
    var values = [Float]()
    for line in text.components(separatedBy: .newlines) {
      let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      if words.first == "LUT_3D_SIZE", words.count > 1 {
        dimension = Int(words[1]) ?? 0
        continue
      }
      if words.count >= 3, let r = Float(words[0]), let g = Float(words[1]),
        let b = Float(words[2]), r.isFinite, g.isFinite, b.isFinite
      {
        values.append(contentsOf: [r, g, b, 1])
      }
    }
    guard (2...64).contains(dimension), values.count == dimension * dimension * dimension * 4 else {
      throw ImageProError.message("LUT 需要是 2–64 阶的有效 .cube 文件。")
    }
    return (dimension, values.withUnsafeBufferPointer { Data(buffer: $0) })
  }
}
