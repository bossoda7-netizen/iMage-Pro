import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorStore {
  func zoomCanvas(_ factor: Double) { zoom = max(0.05, min(16, zoom * factor)) }
  func beginTransform() {
    guard selected != nil, !transformActive else { return }
    chooseTool(.move)
    transformSnapshot = document
    transformActive = true
    transformMode = .free
    beginTransaction("自由变换")
    showInspector = true
    inspector = .base
  }
  func finishTransform(cancel: Bool = false) {
    let snapshot = transformSnapshot
    transformActive = false
    transformSnapshot = nil
    if cancel, let snapshot { cancelTransaction(snapshot) } else { endTransaction() }
  }
  func rotateSelected(_ degrees: Double) {
    updateSelected("旋转对象") {
      $0.rotation = ($0.rotation + degrees).truncatingRemainder(dividingBy: 360)
    }
  }
  func flipSelected(horizontal: Bool) {
    updateSelected(horizontal ? "水平翻转" : "垂直翻转") {
      if horizontal {
        $0.flippedX = !($0.flippedX ?? false)
      } else {
        $0.flippedY = !($0.flippedY ?? false)
      }
    }
  }
  func rasterizeSelected() {
    guard let layer = selected, layer.kind != .group, layer.kind != .adjustment,
      let baked = renderer.bakeLayer(layer, assets: active.assets)
    else { return }
    do {
      let id = try active.assets.insert(baked.image)
      updateSelected("转换为像素") {
        $0.kind = .raster
        $0.rasterPlacement = nil; $0.maskPlacement = nil;$0.contentPlacement = nil
        $0.assetID = id
        $0.strokes = []
        $0.effects = []
        $0.maskAssetID = nil
        $0.resetMaskParameters()
        $0.x = baked.bounds.minX; $0.y = baked.bounds.minY
        $0.width = baked.bounds.width; $0.height = baked.bounds.height
        $0.rotation = 0; $0.quad = nil; $0.warpNodes = nil
        $0.flippedX = nil; $0.flippedY = nil
        $0.importedTextAppearance = nil; $0.textRuns = nil
      }
    } catch { fail(error) }
  }
  func applySelection(_ region: SelectionRegion, mode: String? = nil) {
    var result = SelectionEngine.combine(
      selection, region, mode: mode ?? selectionMode,
      size: CGSize(width: document.width, height: document.height))
    result.feather = selectionFeather
    selection = result
  }
  func selectColor(at point: CGPoint, contiguous: Bool, mode: String? = nil, queued: Bool = false) {
    guard let image = preview else { return }
    let mode = mode ?? selectionMode
    if mode == "new" && !queued {
      selectionToken += 1
      pendingColorSamples = []
    }
    if selectingRegion {
      pendingColorSamples.append((point, mode))
      if pendingColorSamples.count > 12 { pendingColorSamples.removeFirst() }
      return
    }
    if mode == "add", branch.id != "smart", let selection,
      SelectionEngine.contains(
        selection, point: point, canvas: CGSize(width: document.width, height: document.height))
    {
      return
    }
    selectingRegion = true
    let size = CGSize(width: document.width, height: document.height)
    let tolerance = selectionTolerance
    let diameter = branch.id == "smart" ? brushSize : 0
    let token = selectionToken
    let project = activeID
    let branchID = branch.id
    selectionQueue.async { [weak self] in
      let region = SelectionEngine.region(
        image: image, point: point, canvasSize: size, tolerance: tolerance, contiguous: contiguous, brushDiameter:diameter)
      DispatchQueue.main.async {
        guard let self else { return }
        self.selectingRegion = false
        if self.activeID == project, self.selectionToken == token, self.tool == .selection,
          self.branch.id == branchID, let region
        {
          self.applySelection(region, mode: mode)
        }
        if !self.pendingColorSamples.isEmpty {
          let sample = self.pendingColorSamples.removeFirst()
          self.selectColor(
            at: sample.0, contiguous: self.branch.id != "colorRange", mode: sample.1, queued: true)
        }
      }
    }
  }
  func cancelColorSelection() {
    selectionToken += 1
    pendingColorSamples = []
  }
  func deselect() {
    cancelColorSelection()
    selection = nil
  }
  func clearCanvasFocus() {
    deselect()
    multiSelectedLayers = []
    active.document.selectedLayerID = nil
    showInspector = false
    showLayers = false
    showEffects = false
    inspector = .base
    revision += 1
  }
  func addMaskSelected(_ shape: String? = nil) {
    guard let layer = selected, !layer.locked else { return }
    if shape == nil, selection != nil {
      maskFromSelection()
      return
    }
    do {
      var region = SelectionRegion(
        type: shape.map { "shape:" + $0 } ?? "rectangle",
        points: [Point(x: 0, y: 0), Point(x: layer.width, y: layer.height)])
      region.feather = 0
      guard
        let image = SelectionEngine.mask(
          region, size: CGSize(width: layer.width, height: layer.height), maxSize: 4096)
      else { return }
      let id = try active.assets.insert(image)
      updateSelected("添加蒙版") {
        $0.maskAssetID = id
        $0.maskEnabled = true
        $0.resetMaskParameters()
      }
    } catch { fail(error) }
  }
  func invertSelection() {
    if selection != nil { selection?.inverted = !(selection?.inverted ?? false) }
  }
  @discardableResult func extractSelection(cut: Bool = false) -> UUID? {
    guard let selection, let layer = selected, layer.kind != .group else {
      if let id = selected?.id { duplicateLayer(id) }
      return selected?.id
    }
    do {
      var temp = document
      var isolated = layer
      isolated.opacity = 1
      isolated.blend = .normal
      isolated.parentID = nil
      isolated.visible = true
      temp.layers = [isolated]
      guard let rendered = renderer.render(temp, assets: active.assets, maxDimension: nil),
        let mask = SelectionEngine.mask(
          selection, size: CGSize(width: document.width, height: document.height))
      else { return nil }
      let ci = CIImage(cgImage: rendered)
      let masked = ci.applyingFilter(
        "CIBlendWithMask",
        parameters: [
          kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: ci.extent),
          kCIInputMaskImageKey: CIImage(cgImage: mask),
        ])
      let bounds =
        selection.inverted == true
        ? CGRect(x: 0, y: 0, width: document.width, height: document.height)
        : selection.bounds.integral.intersection(
          CGRect(x: 0, y: 0, width: document.width, height: document.height))
      guard bounds.width >= 1, bounds.height >= 1,
        let image = renderer.context.createCGImage(
          masked,
          from: CGRect(
            x: bounds.minX, y: document.height - bounds.maxY, width: bounds.width,
            height: bounds.height))
      else { return nil }
      let id = try active.assets.insert(image)
      var copy = ImageLayer(
        name: layer.name + L(" · 选区"), kind: .raster, width: bounds.width, height: bounds.height)
      copy.assetID = id
      copy.x = bounds.minX
      copy.y = bounds.minY
      copy.opacity = layer.opacity
      copy.blend = layer.blend
      copy.parentID = layer.parentID
      if cut { deleteSelection() }
      edit(cut ? "移动选区内容" : "提取选区到新图层") { doc in
        let index = doc.layers.firstIndex { $0.id == layer.id } ?? 0
        doc.layers.insert(copy, at: index)
        doc.selectedLayerID = copy.id
      }
      return copy.id
    } catch {
      fail(error)
      return nil
    }
  }
  func deleteSelection() {
    guard let selection, let layer = selected, !layer.locked, layer.kind != .group else { return }
    do {
      let local = localSelection(selection, layer: layer)
      guard
        let selectedMask = SelectionEngine.mask(
          local, size: CGSize(width: layer.width, height: layer.height), maxSize: 4096)
      else { return }
      let ci = CIImage(cgImage: selectedMask).applyingFilter("CIColorInvert")
      let extent = ci.extent
      var result = ci
      if let existing = renderer.renderMask(layer, assets: active.assets), layer.maskEnabled {
        let old = CIImage(cgImage: existing)
        let scaled = old.transformed(
          by: CGAffineTransform(
            scaleX: extent.width / old.extent.width, y: extent.height / old.extent.height))
        result = ci.applyingFilter(
          "CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: scaled])
      }
      guard let mask = renderer.context.createCGImage(result, from: extent) else { return }
      let id = try active.assets.insert(mask)
      updateSelected("删除选区内容") {
        $0.maskAssetID = id
        $0.maskEnabled = true
        $0.resetMaskParameters()
      }
    } catch { fail(error) }
  }
  func moveLayer(_ source: UUID, before target: UUID, after: Bool = false) {
    guard source != target else { return }
    edit("调整图层顺序") { doc in
      guard doc.layers.contains(where: { $0.id == source }),
        let targetLayer = doc.layers.first(where: { $0.id == target })
      else { return }
      var ids: Set<UUID> = [source]
      var changed = true
      while changed {
        changed = false
        for layer in doc.layers
        where layer.parentID.map(ids.contains) == true && !ids.contains(layer.id) {
          ids.insert(layer.id)
          changed = true
        }
      }
      guard !ids.contains(target) else { return }
      guard let root = doc.layers.first(where:{$0.id == source}) else {return}
      let moving = [root] + doc.layers.filter {ids.contains($0.id) && $0.id != source}
      doc.layers.removeAll { ids.contains($0.id) }
      var targetIDs:Set<UUID> = [target]
      if after,targetLayer.kind == .group {
        var added = true
        while added {
          added = false
          for layer in doc.layers where layer.parentID.map(targetIDs.contains) == true && !targetIDs.contains(layer.id) {
            targetIDs.insert(layer.id);added = true
          }
        }
      }
      let index = after
        ? (doc.layers.lastIndex {targetIDs.contains($0.id)}.map {$0+1} ?? doc.layers.count)
        : (doc.layers.firstIndex {$0.id == target} ?? doc.layers.count)
      var adjusted = moving
      if !adjusted.isEmpty { adjusted[0].parentID = targetLayer.parentID }
      doc.layers.insert(contentsOf: adjusted, at: min(index, doc.layers.count))
    }
  }
  func moveLayerIntoGroup(_ source:UUID,group:UUID) {
    guard source != group,let folder = document.layers.first(where:{$0.id == group}),folder.kind == .group,!folder.locked,
      let layer = document.layers.first(where:{$0.id == source}),!layer.locked else {return}
    var parent = folder.parentID
    while let id = parent {if id == source {return};parent = document.layers.first {$0.id == id}?.parentID}
    beginTransaction("放入文件夹")
    moveLayer(source,before:group,after:true)
    edit("放入文件夹") {doc in if let i = doc.layers.firstIndex(where:{$0.id == source}) {doc.layers[i].parentID = group}}
    endTransaction()
  }
  func sampleColor(_ point: CGPoint) -> RGBA? {
    guard let image = preview else { return nil }
    return CanvasPixelSample.read(image,point:point,canvas:CGSize(width:document.width,height:document.height))?.color
  }
  func fill(at point: CGPoint) {
    guard selected?.locked != true else { return }
    if branch.id == "bucket", let image = preview {
      selection = SelectionEngine.region(
        image: image, point: point,
        canvasSize: CGSize(width: document.width, height: document.height),
        tolerance: selectionTolerance, contiguous: true)
    }
    let prior = selection
    beginTransaction("颜色填充")
    var layer = ImageLayer(name: L("颜色填充"), kind: .gradient, width: document.width, height: document.height)
    layer.gradient = GradientDefinition(style: "solid", nodes: [GradientNode(point: Point(x: 0, y: 0), color: foreground)])
    edit("颜色填充") { doc in
      layer.parentID = doc.insertionParent;doc.layers.insert(layer,at:doc.insertionIndex)
      doc.selectedLayerID = layer.id
    }
    if prior != nil {
      selection = prior
      maskFromSelection()
    }
    endTransaction()
    selection = prior;inspector = .special;showInspector = true
  }
  func drawGradient(from start: CGPoint, to end: CGPoint) { addGradient(from: start, to: end) }
  func importLUT(_ effect: ImageEffect) {
    let panel = NSOpenPanel()
    panel.title = L("导入 .cube LUT…")
    panel.prompt = L("导入 LUT")
    panel.allowedContentTypes = [UTType(filenameExtension: "cube") ?? .plainText]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let (size, data) = try AdvancedEffects.parseLUT(String(contentsOf: url, encoding: .utf8))
      updateEffect(effect.id, "导入 LUT") {
        $0.lutDimension = size
        $0.lutData = data
        $0.name = "LUT · " + url.deletingPathExtension().lastPathComponent
      }
    } catch { fail(error) }
  }
}

extension EditorStore {
  func localSelection(_ selection: SelectionRegion, layer: ImageLayer) -> SelectionRegion {
    func map(_ p: Point) -> Point {
      Point(TransformGeometry.contentPoint(p.cg,layer:layer))
    }
    var result = selection
    result.points = result.points.map(map)
    if let contours = selection.contours {
      result.spans = nil
      result.contours = contours.map { $0.map(map) }
    } else if let spans = selection.spans {
      result.spans = nil
      result.contours = spans.map { r in
        [
          Point(x: r.x, y: r.y), Point(x: r.x + r.width, y: r.y),
          Point(x: r.x + r.width, y: r.y + r.height), Point(x: r.x, y: r.y + r.height),
        ].map(map)
      }
    }

    else if ["rectangle", "crop"].contains(selection.type) {
      let r = selection.bounds
      result.type = "lasso"
      result.points = [
        Point(x: r.minX, y: r.minY), Point(x: r.maxX, y: r.minY), Point(x: r.maxX, y: r.maxY),
        Point(x: r.minX, y: r.maxY),
      ].map(map)
    } else if selection.type == "ellipse" {
      let r = selection.bounds
      result.type = "lasso"
      result.points = (0..<96).map {
        let a = Double($0) * 2 * .pi / 96
        return map(Point(x: r.midX + cos(a) * r.width / 2, y: r.midY + sin(a) * r.height / 2))
      }
    }
    return result
  }
  func createPath(_ points: [Point]) {
    createBezierPath(BezierGeometry.freehand(points),closed:false)
  }

  func applyPixelBrush(points: [CGPoint]) {
    expandPixelBounds(including:points)
    if let id = compositorToolID,["miganHeal","smudge","liquify"].contains(id) {
      guard !busy else {notify("正在处理修复笔触");return}
      guard let stroke = CompositorPixelStroke(store:self) else {return}
      for point in points {stroke.appendDocument(point,store:self)}
      guard stroke.changed else {return}
      if MIGANInpainting.isHealing(id) {
        let job = stroke.healingJob(),project = stroke.project,original = stroke.layer
        busy = true
        selectionQueue.async { [weak self] in
          let result = Result { try job.repairedImage() }
          DispatchQueue.main.async {
            guard let self else {return};self.busy = false
            switch result {
            case .success(let image):self.commitCompositorPixels(image,project:project,original:original,title:"修复路径")
            case .failure(let error):self.fail(error)
            }
          }
        }
        return
      }
      guard let result = stroke.result() else {return}
      commitCompositorPixels(result,project:stroke.project,original:stroke.layer,title:branch.title)
      return
    }
    if branch.id == "smudge",points.count<2 {return}
    guard let originalLayer = selected, !originalLayer.locked, !points.isEmpty else { return }
    let layer = originalLayer
    var raw = layer;raw.effects = [];raw.maskAssetID = nil;raw.maskStrokes = nil;raw.warpNodes = nil
    guard let first = points.first,let image = renderer.renderLayer(raw,assets:active.assets) else {return}
    let local = localSelection(
      SelectionRegion(type: "lasso", points: points.map(Point.init)), layer: layer
    ).points
    let ci = CIImage(cgImage: image)
    let extent = ci.extent
    let processed: CIImage
    let behavior: ToolCategory = branch.id == "stamp" ? .clone
      : ["dodge", "burn", "sponge"].contains(branch.id) ? .dodge
      : ["blurBrush", "sharpenBrush", "smudge"].contains(branch.id) ? .detail : tool
    switch behavior {
    case .clone:
      guard let source = cloneSource else {
        notify("按住 ⌥ 点击设置仿制来源")
        return
      }
      let sourceRegion = localSelection(
        SelectionRegion(type: "lasso", points: [Point(source), Point(first)]), layer: layer
      ).points
      processed = ci.transformed(
        by: CGAffineTransform(
          translationX: sourceRegion[1].x - sourceRegion[0].x,
          y: sourceRegion[0].y - sourceRegion[1].y))
    case .retouch:
      if branch.id == "heal" {
        let factor = Double(image.width)/layer.width
        let sample = cloneSource.map { TransformGeometry.contentPoint($0,layer:layer) }
        let p = local.map { CGPoint(x:$0.x*factor,y:$0.y*factor) }
        guard let repaired = PixelRetouch.heal(image,points:p,radius:brushSize*factor/2,
          source:sample.map { CGPoint(x:$0.x*factor,y:$0.y*factor) }) else { return }
        processed = CIImage(cgImage:repaired)
      } else {
        processed = ci.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.12,"inputSharpness":0.15])
      }
    case .dodge:
      processed =
        branch.id == "sponge"
        ? ci.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.3])
        : ci.applyingFilter(
          "CIExposureAdjust", parameters: [kCIInputEVKey: branch.id == "burn" ? -0.6 : 0.6])
    case .detail:
      if branch.id == "smudge" {
        let factor = Double(image.width)/layer.width
        guard let smudged = PixelRetouch.smudge(image,points:local.map { CGPoint(x:$0.x*factor,y:$0.y*factor) },
          radius:brushSize*factor/2,hardness:brushHardness,strength:brushOpacity*brushFlow) else { return }
        processed = CIImage(cgImage:smudged)
      } else if branch.id == "sharpenBrush" {
        processed = ci.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:1.2])
      } else {
        processed = ci.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:brushSize*0.08])
      }
    default: return
    }
    guard let cg = ImageRenderer.bitmap(image.width, image.height) else { return }
    cg.translateBy(x: 0, y: extent.height)
    cg.scaleBy(x: extent.width / layer.width, y: -extent.height / layer.height)
    if let selection {
      let clip = localSelection(selection, layer: layer)
      if clip.inverted == true {
        cg.addRect(CGRect(x: 0, y: 0, width: layer.width, height: layer.height))
      }
      cg.addPath(clip.path)
      cg.clip(using: clip.inverted == true ? .evenOdd : .winding)
    }
    let stroke = BrushStroke(
      points: local, color: RGBA(r: 1, g: 1, b: 1), size: brushSize, opacity: branch.id == "smudge" ? 1 : brushOpacity,
      hardness: brushHardness, erasing: false, clip: nil, dynamics: brushDynamics)
    ImageRenderer.drawStroke(stroke, context: cg)
    guard let mask = cg.makeImage(),
      let patch = renderer.context.createCGImage(
        processed.applyingFilter(
          "CIBlendWithAlphaMask",
          parameters: [
            kCIInputBackgroundImageKey: ci,
            kCIInputMaskImageKey: CIImage(cgImage: mask),
          ]), from: extent)
    else { return }
    do {
      let assetID = try active.assets.insert(patch)
      updateSelected(branch.title) {
        $0.kind = .raster; $0.assetID = assetID
        $0.strokes = [];$0.rasterPlacement = nil;$0.contentPlacement = nil
      }
    } catch { fail(error) }
  }
}
