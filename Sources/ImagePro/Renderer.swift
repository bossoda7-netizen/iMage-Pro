import AppKit
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Original assets are immutable. The compositor evaluates layer parameters and effects on demand.
final class AssetLibrary: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  private(set) var data: [String: Data] = [:]
  private var decoded: [String: CGImage] = [:]
  @discardableResult func insert(_ value: Data, id: String = UUID().uuidString) -> String {
    lock.lock()
    defer { lock.unlock() }
    data[id] = value
    return id
  }
  func snapshot() -> [String:Data] {lock.lock();defer {lock.unlock()};return data}
  func insertTransient(_ image: CGImage) -> String {
    lock.lock();defer {lock.unlock()}
    let id = UUID().uuidString;decoded[id] = image;return id
  }
  func image(_ id: String?) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    guard let id else { return nil }
    if let cached = decoded[id] { return cached }
    guard let bytes = data[id], let source = CGImageSourceCreateWithData(bytes as CFData, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 16384,
    ]
    let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    decoded[id] = image
    return image
  }
  func insert(_ image: CGImage) throws -> String {
    insert(try Self.encode(image, type: UTType.png.identifier))
  }
  static func encode(_ image: CGImage, type: String, quality: Double = 0.92, dpi: Double = 300)
    throws -> Data
  {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil)
    else {
      throw ImageProError.message("系统不支持该格式的编码。")
    }
    CGImageDestinationAddImage(
      destination, image,
      [
        kCGImageDestinationLossyCompressionQuality: quality,
        kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
      ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImageProError.message("图像编码失败。") }
    return output as Data
  }
}

struct LayerPreview {
  var image: CGImage
  var extent: CGRect
  var contentSize: CGSize
}

final class ImageRenderer: @unchecked Sendable {
  func previewLayer(_ layer: ImageLayer, assets: AssetLibrary, scale: Double) -> LayerPreview? {
    guard let image = cachedLayer(layer, assets: assets, scale: scale) else { return nil }
    let p = Self.outset(layer)
    return LayerPreview(image: image,
      extent: CGRect(x: -p, y: -p, width: layer.width + 2*p, height: layer.height + 2*p),
      contentSize: CGSize(width: layer.width, height: layer.height))
  }
  let context = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .cacheIntermediates: false,
  ])
  static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  private let cacheLock = NSLock()
  private var baseCache: [UUID: (ImageLayer, Double, CGImage)] = [:]
  private var layerCache: [UUID: (ImageLayer, Double, CGImage)] = [:]
  func clearLayerCache() {
    cacheLock.lock()
    layerCache.removeAll()
    baseCache.removeAll()
    cacheLock.unlock()
    context.clearCaches()
  }
  func cachedLayer(_ layer: ImageLayer, assets: AssetLibrary, scale: Double) -> CGImage? {
    var content = layer
    content.x = 0
    content.y = 0
    content.rotation = 0
    content.quad = nil
    content.opacity = 1
    content.blend = .normal
    content.visible = true
    content.locked = false
    content.parentID = nil
    content.aspectLocked = nil
    content.flippedX = nil
    content.flippedY = nil
    content.name = ""
    cacheLock.lock()
    let cached = layerCache[layer.id]
    cacheLock.unlock()
    if let cached, cached.0 == content, abs(cached.1 - scale) < 0.005 { return cached.2 }
    guard let image = renderLayer(layer, assets: assets, scale: scale, includeOutsets: true) else {
      return nil
    }
    cacheLock.lock()
    if layerCache.count > 160, let key = layerCache.keys.first {layerCache.removeValue(forKey:key)}
    layerCache[layer.id] = (content, scale, image)
    cacheLock.unlock()
    return image
  }
  func render(
    _ document: ImageDocument, assets: AssetLibrary, maxDimension: Double? = 1800,
    whiteBackground: Bool = false
  ) -> CGImage? {
    let scale = maxDimension.map { min(1, $0 / max(document.width, document.height)) } ?? 1
    if document.layers.contains(where: { $0.kind == .group || $0.kind == .adjustment || $0.blend.requiresCI || $0.quad != nil || $0.clippingMask }) {
      var previews: [UUID: LayerPreview] = [:]
      for layer in document.layers where layer.kind != .group && layer.kind != .adjustment {
        previews[layer.id] = previewLayer(layer, assets: assets, scale: scale)
      }
      return composite(document, previews: previews, assets: assets, scale: scale, whiteBackground: whiteBackground)
    }
    let w = max(1, Int((document.width * scale).rounded()))
    let h = max(1, Int((document.height * scale).rounded()))
    guard let cg = Self.bitmap(w, h) else { return nil }
    if whiteBackground {
      cg.setFillColor(NSColor.white.cgColor)
      cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    cg.translateBy(x: 0, y: CGFloat(h))
    cg.scaleBy(x: scale, y: -scale)
    for layer in document.layers.reversed() where layer.kind != .group && document.isVisible(layer)
    {
      guard let image = cachedLayer(layer, assets: assets, scale: scale) else { continue }
      cg.saveGState()
      cg.setAlpha(document.effectiveOpacity(layer))
      cg.setBlendMode(layer.blend.cg)
      cg.translateBy(x: layer.x + layer.width / 2, y: layer.y + layer.height / 2)
      cg.rotate(by: layer.rotation * .pi / 180)
      cg.scaleBy(x: layer.flippedX == true ? -1 : 1, y: layer.flippedY == true ? -1 : 1)
      let p = Self.outset(layer)
      Self.draw(
        image,
        in: CGRect(
          x: -layer.width / 2 - p, y: -layer.height / 2 - p, width: layer.width + 2 * p,
          height: layer.height + 2 * p), context: cg)
      cg.restoreGState()
    }
    return cg.makeImage()
  }
  func renderLayer(
    _ layer: ImageLayer, assets: AssetLibrary, scale: Double = 1, includeOutsets: Bool = false
  ) -> CGImage? {
    // Bound off-canvas layers as well as the canvas itself to avoid accidental huge allocations.
    let safeScale = min(
      scale, 8192 / max(layer.width, layer.height), sqrt(40_000_000 / (layer.width * layer.height)))
    let w = max(1, Int(ceil(layer.width * safeScale)))
    let h = max(1, Int(ceil(layer.height * safeScale)))
    var baseKey = layer
    baseKey.effects = [];baseKey.maskAssetID = nil;baseKey.maskStrokes = nil
    baseKey.maskDensity = nil;baseKey.maskFeather = nil;baseKey.maskOpacity = nil;baseKey.maskInverted = nil
    baseKey.x = 0;baseKey.y = 0;baseKey.rotation = 0;baseKey.opacity = 1;baseKey.blend = .normal
    baseKey.visible = true;baseKey.locked = false;baseKey.name = "";baseKey.parentID = nil
    baseKey.quad = nil;baseKey.warpNodes = nil;baseKey.flippedX = nil;baseKey.flippedY = nil
    cacheLock.lock();let cachedBase = baseCache[layer.id];cacheLock.unlock()
    let base: CGImage
    if let cachedBase, cachedBase.0 == baseKey, abs(cachedBase.1-safeScale) < 0.005 {
      base = cachedBase.2
    } else {
    guard let cg = Self.bitmap(w, h) else { return nil }
    cg.translateBy(x: 0, y: CGFloat(h))
    cg.scaleBy(x: safeScale, y: -safeScale)
    var content = layer
    let placement = layer.contentPlacement ?? CGRect(x:0,y:0,width:1,height:1)
    let special = [.text,.shape,.gradient].contains(layer.kind)
    cg.saveGState()
    if special {cg.translateBy(x:placement.minX*layer.width,y:placement.minY*layer.height);content.width *= placement.width;content.height *= placement.height}
    let bounds = CGRect(x:0,y:0,width:content.width,height:content.height)
    switch layer.kind {
    case .raster:
      if let image = assets.image(layer.assetID) {
        let p = layer.rasterPlacement ?? CGRect(x:0,y:0,width:1,height:1)
        Self.draw(image, in: CGRect(x:p.minX*layer.width,y:p.minY*layer.height,width:p.width*layer.width,height:p.height*layer.height), context: cg)
      }
    case .text:
      if let appearance = layer.importedTextAppearance, appearance == TextAppearance(layer),
        let image = assets.image(layer.assetID) {
        Self.draw(image, in: bounds, context: cg)
        break
      }
      TextLayout.draw(content,in:bounds,context:cg)
    case .shape:
      if content.isPath {break}
      cg.setFillColor(content.color.ns.cgColor)
      cg.setStrokeColor(content.color.ns.cgColor)
      if let anchors = content.bezierAnchors {
        cg.addPath(BezierGeometry.path(anchors, closed: content.pathClosed == true, size: bounds.size))
        if content.pathClosed == true { cg.fillPath() }
        else { cg.setLineWidth(max(1, content.cornerRadius)); cg.setLineCap(.round); cg.strokePath() }
      } else if let outline = content.vectorOutline {
        cg.addPath(VectorNode.path(outline, size: bounds.size))
        cg.fillPath()
      } else if let points = content.vectorPoints, let first = points.first {
        cg.move(to: CGPoint(x: first.x * content.width, y: first.y * content.height))
        for p in points.dropFirst() {
          cg.addLine(to: CGPoint(x: p.x * content.width, y: p.y * content.height))
        }
        if content.shape == "freePath" || content.shape == "line" {
          cg.setLineWidth(max(1, content.cornerRadius))
          cg.setLineCap(.round)
          cg.strokePath()
        } else {
          cg.closePath()
          cg.fillPath()
        }
      } else if content.shape == "line" {
        cg.setLineWidth(max(2, content.cornerRadius))
        cg.setLineCap(.round)
        cg.move(to: CGPoint(x: 0, y: content.height))
        cg.addLine(to: CGPoint(x: content.width, y: 0))
        cg.strokePath()
      } else {
        cg.addPath(
          ShapeGeometry.path(
            content.shape, rect: bounds, radius: content.cornerRadius, sides: content.shapeSides ?? 6))
        cg.drawPath(using: ["ring", "crescent"].contains(content.shape) ? .eoFill : .fill)
      }
    case .paint, .group, .adjustment: break
    case .gradient: if let gradient = content.gradient { Self.draw(GradientRenderer.render(gradient, width: max(1,Int(content.width*safeScale)), height: max(1,Int(content.height*safeScale))), in: bounds, context: cg) }
    }
    cg.restoreGState()
    for stroke in layer.strokes { Self.drawStroke(stroke, context: cg) }
    guard let rendered = cg.makeImage() else { return nil }
    base = rendered
    cacheLock.lock()
    if baseCache.count > 160, let key = baseCache.keys.first {baseCache.removeValue(forKey:key)}
    baseCache[layer.id] = (baseKey, safeScale, rendered)
    cacheLock.unlock()
    }
    var result = CIImage(cgImage: base)
    let extent = result.extent
    let pad = includeOutsets ? Self.outset(layer) * safeScale : 0
    let outputExtent = extent.insetBy(dx: -pad, dy: -pad)
    if layer.maskEnabled, let mask = renderMask(layer, assets: assets, scale: safeScale) {
      let raw = CIImage(cgImage: mask)
      let scaled = raw.transformed(
        by: CGAffineTransform(
          scaleX: extent.width / raw.extent.width, y: extent.height / raw.extent.height))
      let transparent = CIImage(color: .clear).cropped(to: extent)
      result = result.applyingFilter(
        "CIBlendWithMask",
        parameters: [kCIInputBackgroundImageKey: transparent, kCIInputMaskImageKey: scaled])
    }
    if let nodes = layer.warpNodes { result = WarpRenderer.apply(result, nodes: nodes, extent: outputExtent) }
    for effect in layer.effects where effect.enabled {
      result = apply(effect, to: result, scale: safeScale).cropped(to: outputExtent)
    }
    return context.createCGImage(
      result, from: outputExtent, format: .RGBA8, colorSpace: Self.colorSpace)
  }
  static func outset(_ layer: ImageLayer) -> Double {
    let warpPad = (layer.warpNodes ?? []).reduce(0.0) { max($0, max(max(0,-$1.x,$1.x-1)*layer.width, max(0,-$1.y,$1.y-1)*layer.height)) }
    return warpPad + layer.effects.filter {
      $0.enabled && [.outline, .shadow, .outerGlow].contains($0.kind)
        && !($0.kind == .outline && $0.style == "inside")
    }.reduce(0) {
      $0 + min(500, $1.radius * 3 + ($1.kind == .shadow ? $1.value("distance", 8) : 0))
    }
  }
  func apply(_ effect: ImageEffect, to image: CIImage, scale: Double) -> CIImage {
    var full = effect;full.amount = 1
    let processed = applyAtFullStrength(full,to:image,scale:scale)
    let extent = processed.extent.isInfinite ? image.extent : processed.extent.union(image.extent)
    let extended = image.composited(over:CIImage(color:.clear).cropped(to:extent))
    return AdvancedEffects.blend(processed,over:extended,amount:effect.amount)
  }
  private func applyAtFullStrength(_ effect: ImageEffect, to image: CIImage, scale: Double) -> CIImage {
    if let advanced = AdvancedEffects.apply(effect, image: image, scale: scale) { return advanced }
    let radius = max(0, min(500, effect.radius)) * scale
    let amount = max(0, min(1, effect.amount))
    switch effect.kind {
    case .color:
      return image.applyingFilter(
        "CIColorControls",
        parameters: [
          kCIInputBrightnessKey: effect.brightness,
          kCIInputContrastKey: effect.contrast, kCIInputSaturationKey: effect.saturation,
        ]
      )
      .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: effect.exposure])
    case .blur:
      return image.clampedToExtent().applyingFilter(
        "CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * amount])
    case .sharpen:
      return image.applyingFilter(
        "CISharpenLuminance", parameters: [kCIInputSharpnessKey: amount * 2])
    case .bloom:
      return image.clampedToExtent().applyingFilter(
        "CIBloom", parameters: [kCIInputRadiusKey: radius, kCIInputIntensityKey: amount])
    case .shadow:
      let silhouette = image.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount),
        ]
      )
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
      .transformed(by: CGAffineTransform(translationX: radius / 2, y: -radius / 2))
      return image.composited(over: silhouette)
    case .outline:
      let alpha = image.applyingFilter(
        "CIMorphologyMaximum", parameters: [kCIInputRadiusKey: min(30, radius)])
      let color = alpha.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0.1),
          "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0.25),
          "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0.5),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount),
        ])
      return image.composited(over: color)
    case .grain:
      // A fixed seed-equivalent procedural pattern: reopening and exporting preserves the exact grain.
      let bytes = (0..<(128 * 128)).flatMap { i -> [UInt8] in
        let value = UInt8(truncatingIfNeeded: (i &* 1_103_515_245 &+ 12345) >> 13)
        return [value, value, value, 255]
      }
      let noise = CIImage(
        bitmapData: Data(bytes), bytesPerRow: 128 * 4, size: CGSize(width: 128, height: 128),
        format: .RGBA8, colorSpace: Self.colorSpace
      )
      .applyingFilter("CIAffineTile").cropped(to: image.extent)
      .applyingFilter(
        "CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount * 0.25)])
      let processed = noise.applyingFilter(
        "CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
      return processed.applyingFilter(
        "CIBlendWithAlphaMask",
        parameters: [
          kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
          kCIInputMaskImageKey: image,
        ])
    case .pixelate:
      return blend(
        image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(1, radius)]),
        over: image, amount: amount)
    case .vignette:
      return image.applyingFilter(
        "CIVignette", parameters: [kCIInputIntensityKey: amount * 2, kCIInputRadiusKey: radius * 5])
    case .monochrome:
      return image.applyingFilter(
        "CIColorControls", parameters: [kCIInputSaturationKey: 1 - amount])
    case .hdr:
      return image.applyingFilter(
        "CIHighlightShadowAdjust",
        parameters: ["inputShadowAmount": amount, "inputHighlightAmount": 1 - amount * 0.65])
    case .custom:
      guard let name = effect.filterName, ExtensionManifest.allowedFilters.contains(name),
        let filter = CIFilter(name: name)
      else { return image }
      filter.setValue(image, forKey: kCIInputImageKey)
      if filter.inputKeys.contains(kCIInputIntensityKey) {
        filter.setValue(1, forKey: kCIInputIntensityKey)
      }
      guard let processed = filter.outputImage else { return image }
      return blend(processed, over: image, amount: amount)
    default: return image
    }
  }
  private func blend(_ processed: CIImage, over original: CIImage, amount: Double) -> CIImage {
    let mask = CIImage(color: CIColor(red: amount, green: amount, blue: amount, alpha: 1)).cropped(
      to: original.extent)
    return processed.applyingFilter(
      "CIBlendWithMask",
      parameters: [kCIInputBackgroundImageKey: original, kCIInputMaskImageKey: mask])
  }
  static func bitmap(_ width: Int, _ height: Int) -> CGContext? {
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  }
  static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
  }
  static func drawStroke(_ stroke: BrushStroke, context: CGContext) {
    if stroke.dynamics != nil {
      BrushEngine.draw(stroke, context: context)
      return
    }
    guard let first = stroke.points.first else { return }
    context.saveGState()
    if let clip = stroke.clip {
      context.addPath(clip.path)
      context.clip()
    }
    context.setBlendMode(stroke.erasing ? .destinationOut : .normal)
    context.setAlpha(stroke.opacity)
    context.setStrokeColor(stroke.color.ns.cgColor)
    context.setFillColor(stroke.color.ns.cgColor)
    context.setLineWidth(stroke.size)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    if stroke.hardness < 0.95 && !stroke.erasing {
      context.setShadow(
        offset: .zero, blur: stroke.size * (1 - stroke.hardness) * 0.3,
        color: stroke.color.ns.cgColor)
    }
    if stroke.points.count == 1 {
      context.fillEllipse(
        in: CGRect(
          x: first.x - stroke.size / 2, y: first.y - stroke.size / 2, width: stroke.size,
          height: stroke.size))
    } else {
      context.move(to: first.cg)
      for point in stroke.points.dropFirst() { context.addLine(to: point.cg) }
      context.strokePath()
    }
    context.restoreGState()
  }
}

struct ExportFormat: Identifiable {
  var name: String
  var ext: String
  var identifier: String
  var id: String { ext }
  static var available: [ExportFormat] {
    var result = [
      ExportFormat(name: "PNG", ext: "png", identifier: UTType.png.identifier),
      .init(name: "JPEG", ext: "jpg", identifier: UTType.jpeg.identifier),
      .init(name: "TIFF", ext: "tiff", identifier: UTType.tiff.identifier),
      .init(name: "PSD · 分层", ext: "psd", identifier: "com.adobe.photoshop-image"),
      .init(name: "PDF", ext: "pdf", identifier: "pdf"),
      .init(name: "SVG · 合成图", ext: "svg", identifier: "svg"),
    ]
    let encoders = CGImageDestinationCopyTypeIdentifiers() as! [String]
    for format in [
      ExportFormat(name: "WebP", ext: "webp", identifier: "org.webmproject.webp"),
      .init(name: "AVIF", ext: "avif", identifier: "public.avif"),
    ] where encoders.contains(format.identifier) { result.append(format) }
    return result
  }
}
