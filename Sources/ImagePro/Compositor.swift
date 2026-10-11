import AppKit
import CoreImage

extension ImageRenderer {
  func composite(_ doc: ImageDocument, previews: [UUID: LayerPreview], assets: AssetLibrary,
    scale: Double, whiteBackground: Bool = false) -> CGImage? {
    let extent = CGRect(x: 0, y: 0, width: max(1, round(doc.width*scale)), height: max(1, round(doc.height*scale)))
    var output = CIImage(color: whiteBackground ? .white : .clear).cropped(to: extent)
    func contentSource(_ layer: ImageLayer, override: LayerPreview? = nil) -> CIImage? {
      guard let preview = override ?? previews[layer.id] else { return nil }
      let sx = layer.width/preview.contentSize.width, sy = layer.height/preview.contentSize.height
      let logical = preview.extent.applying(CGAffineTransform(scaleX: sx, y: sy))
      let raw = CIImage(cgImage: preview.image)
      var local = raw.transformed(by: CGAffineTransform(scaleX: logical.width/raw.extent.width, y: logical.height/raw.extent.height))
        .transformed(by: CGAffineTransform(translationX: logical.minX-layer.width/2, y: -logical.maxY+layer.height/2))
      if let q = layer.quad, q.count == 4 {
        func corner(_ i: Int) -> CIVector { CIVector(x:(q[i].x-0.5)*layer.width,y:(0.5-q[i].y)*layer.height) }
        local = local.applyingFilter("CIPerspectiveTransformWithExtent", parameters:[
          "inputExtent": CIVector(cgRect:CGRect(x:-layer.width/2,y:-layer.height/2,width:layer.width,height:layer.height)),
          "inputTopLeft":corner(0),"inputTopRight":corner(1),"inputBottomRight":corner(2),"inputBottomLeft":corner(3)])
      }
      let t = CGAffineTransform(scaleX: scale, y: scale)
        .translatedBy(x: layer.x+layer.width/2, y: doc.height-layer.y-layer.height/2)
        .rotated(by: -layer.rotation * .pi/180)
        .scaledBy(x: layer.flippedX == true ? -1 : 1, y: layer.flippedY == true ? -1 : 1)
      let opacity = layer.opacity
      let source = local.transformed(by: t).applyingFilter("CIColorMatrix", parameters: [
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
      return source
    }
    func opacity(_ image: CIImage, _ value: Double) -> CIImage {
      image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x:0,y:0,z:0,w:value)])
    }
    func members(_ group: UUID) -> Set<UUID> {
      var ids: Set<UUID> = [group]
      for _ in 0..<doc.layers.count {
        let before = ids.count
        for layer in doc.layers where layer.parentID.map(ids.contains) == true {ids.insert(layer.id)}
        if ids.count == before {break}
      }
      ids.remove(group); return ids
    }
    let roots = doc.layers.filter {$0.parentID == nil}
    // Build each folder as one image before evaluating its effects. Children
    // are not individually assigned duplicate effects or group opacity.
    func groupSource(_ group: ImageLayer) -> CIImage? {
      let ids = members(group.id)
      var childDoc = doc; childDoc.layers = doc.layers.filter {ids.contains($0.id)}
      for i in childDoc.layers.indices where childDoc.layers[i].parentID == group.id {childDoc.layers[i].parentID = nil}
      guard let merged = composite(childDoc, previews: previews, assets: assets, scale: scale) else {return nil}
      var image = CIImage(cgImage: merged)
      for effect in group.effects where effect.enabled {image = apply(effect, to: image, scale: scale).cropped(to: extent)}
      return opacity(image, group.opacity)
    }
    var index = roots.count - 1
    while index >= 0 {
      let layer = roots[index]
      guard doc.isVisible(layer) else {index -= 1;continue}
      if layer.kind == .group {
        if let source = groupSource(layer) {output = LayerBlending.apply(layer.blend, source: source, background: output, extent: extent)}
        index -= 1; continue
      }
      if layer.kind == .adjustment {
        var processed = output
        for e in layer.effects where e.enabled {processed = apply(e, to: processed, scale: scale).cropped(to: extent)}
        if layer.maskEnabled, let mask = renderMask(layer, assets: assets, scale: scale) {
          let m = CIImage(cgImage: mask).transformed(by: CGAffineTransform(scaleX: extent.width/Double(mask.width), y: extent.height/Double(mask.height)))
          processed = processed.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: output, kCIInputMaskImageKey: m])
        }
        output = AdvancedEffects.blend(processed, over: output, amount: layer.opacity)
        index -= 1;continue
      }
      var first = index
      while first > 0 && roots[first-1].clippingMask {first -= 1}
      guard var cluster = contentSource(layer) else {index -= 1;continue}
      // Shielded styles remain independent. Unshielded styles extend the
      // clipping silhouette so the upper image also paints the stroke/shadow.
      // Applying a solid style after clipping would always hide that image.
      if first < index {
        var alphaLayer = layer
        alphaLayer.effects.removeAll {$0.kind.isLayerStyle && $0.value("ignoreClipping",1) >= 0.5}
        let alpha = contentSource(alphaLayer, override: previewLayer(alphaLayer, assets: assets, scale: scale)) ?? cluster
        for clipIndex in stride(from: index-1, through: first, by: -1) {
          let clipped = roots[clipIndex]
          guard doc.isVisible(clipped), var source = contentSource(clipped) else {continue}
          source = source.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), kCIInputMaskImageKey: alpha.cropped(to: extent)])
          cluster = LayerBlending.apply(clipped.blend, source: source, background: cluster, extent: extent)
        }
      }
      output = LayerBlending.apply(layer.blend, source: cluster, background: output, extent: extent)
      index = first - 1
    }
    return context.createCGImage(output.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: Self.colorSpace)
  }
}

enum LayerBlending {
  // Standard formulas missing from Core Image's built-in blend family.
  static let special = NativeKernels.color("specialBlend")
  static let dissolve = NativeKernels.color("dissolve")
  static func apply(_ mode: BlendMode, source: CIImage, background: CIImage, extent: CGRect) -> CIImage {
    if [.hardMix, .darkerColor, .lighterColor].contains(mode), let special,
      let output = special.apply(extent: extent, arguments: [source, background, mode == .hardMix ? 0.0 : mode == .darkerColor ? 1.0 : 2.0]) { return output }
    let s = mode == .dissolve ? dissolve?.apply(extent: extent, arguments: [source]) ?? source : source
    return s.applyingFilter(mode.ciFilter, parameters: [kCIInputBackgroundImageKey: background]).cropped(to: extent)
  }
}

extension EditorStore {
  func addAdjustmentLayer(_ kind: EffectKind? = nil) {
    var layer = ImageLayer(name: kind.map { L($0.title) + L(" · 调整") } ?? L("调整图层"), kind: .adjustment, width: document.width, height: document.height)
    if let kind { layer.effects = [ImageEffect(kind)] }
    beginTransaction("添加 FX 调整图层")
    edit("添加 FX 调整图层") { doc in
      let i = doc.layers.firstIndex { $0.id == doc.selectedLayerID } ?? 0
      doc.layers.insert(layer, at: i); doc.selectedLayerID = layer.id
    }
    if selection != nil { maskFromSelection() }
    endTransaction()
    if let effect = layer.effects.first {
      inspector = .effect(effect.id)
    } else {
      inspector = .base
    }
    showInspector = true; showEffects = false
  }
}

extension EffectKind {
  var isLayerStyle: Bool {[.outline, .shadow, .innerShadow, .outerGlow, .innerGlow, .bevel, .fillStyle].contains(self)}
}
