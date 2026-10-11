import AppKit
import CoreImage

extension EditorStore {
  var selectedIDs: Set<UUID> {
    Set(document.layers.filter { multiSelectedLayers.contains($0.id) || $0.id == document.selectedLayerID }.map(\.id))
  }
  func rootGroup(for layer: ImageLayer) -> ImageLayer {
    var current = layer
    var visited = Set<UUID>()
    while let id = current.parentID, visited.insert(id).inserted,
      let parent = document.layers.first(where: {$0.id == id}) {current = parent}
    return current
  }
  func descendants(of ids: Set<UUID>) -> Set<UUID> {
    var result = ids
    for _ in 0..<document.layers.count {
      let before = result.count
      for layer in document.layers where layer.parentID.map(result.contains) == true {result.insert(layer.id)}
      if before == result.count {break}
    }
    return result
  }
  func toggleLayerSelection(_ id: UUID) {
    var ids = selectedIDs
    if ids.contains(id) {ids.remove(id)} else {ids.insert(id)}
    multiSelectedLayers = ids
    active.document.selectedLayerID = ids.contains(id) ? id : document.layers.first(where: {ids.contains($0.id)})?.id
    inspector = selected?.defaultInspector ?? .base
    revision += 1
  }
  func selectLayerFromPanel(_ id: UUID) {
    if retouchPathID != nil, interactionTool == .retouch {applyRetouchPath(to:id);return}
    selectLayerFromPanel(id,modifiers:NSEvent.modifierFlags)
  }
  func selectLayerFromPanel(_ id:UUID,modifiers:NSEvent.ModifierFlags) {
    if modifiers.contains(.shift),let anchor = layerSelectionAnchor ?? document.selectedLayerID,
      let a = document.layers.firstIndex(where: {$0.id == anchor}),let b = document.layers.firstIndex(where: {$0.id == id}) {
      let range = Set(document.layers[min(a,b)...max(a,b)].map(\.id))
      multiSelectedLayers = modifiers.contains(.command) ? selectedIDs.union(range) : range
      active.document.selectedLayerID = id;revision += 1
    } else if modifiers.contains(.command) {toggleLayerSelection(id);layerSelectionAnchor = id}
    else {selectLayer(id);layerSelectionAnchor = id}
  }
  func moveSelection(from originals: [ImageLayer], delta: CGPoint) {
    let values = Dictionary(uniqueKeysWithValues: originals.map {($0.id, $0)})
    edit("移动图层") {doc in
      for i in doc.layers.indices {
        guard let old = values[doc.layers[i].id], !old.locked else {continue}
        doc.layers[i].x = old.x + delta.x; doc.layers[i].y = old.y + delta.y
      }
    }
  }
  func mergeSelectedLayers() {
    let ids = descendants(of: selectedIDs)
    guard ids.count > 1, let index = document.layers.firstIndex(where: {ids.contains($0.id)}),
      !document.layers.contains(where: {ids.contains($0.id) && $0.locked}) else {return}
    var isolated = document
    isolated.layers = document.layers.filter {ids.contains($0.id)}
    for i in isolated.layers.indices where isolated.layers[i].parentID.map(ids.contains) != true {isolated.layers[i].parentID = nil}
    guard let image = renderer.render(isolated, assets: active.assets, maxDimension: nil) else {return}
    do {
      var layer = ImageLayer(name: L("合并图层"), kind: .raster, width: document.width, height: document.height)
      layer.assetID = try active.assets.insert(image)
      layer.parentID = document.layers[index].parentID.flatMap {ids.contains($0) ? nil : $0}
      edit("合并选中图层") {doc in
        doc.layers.removeAll {ids.contains($0.id)}; doc.layers.insert(layer, at: min(index, doc.layers.count))
        doc.selectedLayerID = layer.id
      }
      multiSelectedLayers = []
    } catch {fail(error)}
  }
  func centerSelected(relativeTo ids: Set<UUID> = []) {
    let others = document.layers.filter {ids.contains($0.id) && $0.kind != .group && $0.kind != .adjustment}
    let bounds = others.reduce(CGRect.null) {$0.union(SnapEngine.bounds($1))}
    let center = bounds.isNull ? CGPoint(x: document.width/2, y: document.height/2) : CGPoint(x: bounds.midX, y: bounds.midY)
    let moving = descendants(of: selectedIDs)
    let current = document.layers.filter {moving.contains($0.id) && $0.kind != .group}
      .reduce(CGRect.null) {$0.union(SnapEngine.bounds($1))}
    guard !current.isNull else {return}
    moveSelection(from: document.layers.filter {moving.contains($0.id)}, delta: CGPoint(x: center.x-current.midX, y: center.y-current.midY))
  }
  @discardableResult func expandPixelBounds(including points:[CGPoint]) -> Bool {
    guard var layer = selected,!layer.locked,!points.isEmpty else {return false}
    let local = points.map {Point(TransformGeometry.contentPoint($0,layer:layer))}
    let radius = brushSize/2
    guard local.contains(where:{$0.x-radius<0 || $0.y-radius<0 || $0.x+radius>layer.width || $0.y+radius>layer.height}) else {return false}
    let before = layer
    if layer.quad != nil || layer.warpNodes != nil {
      guard bakeDrawingGeometry(&layer) else {return false}
    }
    let drawingPoints = points.map {Point(TransformGeometry.contentPoint($0,layer:layer))}
    _ = LayerExpansion.expand(&layer,including:drawingPoints,radius:radius+64)
    guard layer != before else {return false}
    edit("扩展图层") {doc in if let i = doc.layers.firstIndex(where:{$0.id == layer.id}) {doc.layers[i] = layer}}
    return true
  }
  /// Commit only non-affine geometry when a brush crosses its storage boundary.
  /// Effects and the independent mask remain editable; the source assets stay in
  /// the project so undo can restore the original transform without resampling.
  func bakeDrawingGeometry(_ layer: inout ImageLayer) -> Bool {
    var raw = layer
    raw.effects = [];raw.maskAssetID = nil;raw.maskStrokes = nil
    guard let baked = renderer.bakeLayer(raw,assets:active.assets) else {return false}
    do {
      let asset = try active.assets.insert(baked.image)
      var maskAsset: String?
      if layer.maskAssetID != nil {
        var mask = layer
        mask.maskDensity = nil;mask.maskOpacity = nil;mask.maskFeather = nil;mask.maskInverted = nil
        guard let image = renderer.renderMask(mask,assets:active.assets) else {return false}
        raw.kind = .raster;raw.assetID = try active.assets.insert(image)
        raw.rasterPlacement = nil;raw.contentPlacement = nil;raw.strokes = []
        guard let aligned = renderer.bakeLayer(raw,assets:active.assets),
          let grayscale = ImageRenderer.opaqueGrayscale(aligned.image) else {return false}
        maskAsset = try active.assets.insert(grayscale)
      }
      layer.kind = .raster;layer.assetID = asset;layer.strokes = []
      layer.x = baked.bounds.minX;layer.y = baked.bounds.minY
      layer.width = baked.bounds.width;layer.height = baked.bounds.height
      layer.rotation = 0;layer.quad = nil;layer.warpNodes = nil
      layer.flippedX = nil;layer.flippedY = nil
      layer.rasterPlacement = nil;layer.contentPlacement = nil
      if let maskAsset {layer.maskAssetID = maskAsset;layer.maskStrokes = nil;layer.maskPlacement = nil}
      return true
    } catch {fail(error);return false}
  }
  func beginPathRetouch(_ pathID: UUID? = nil) {
    guard let path = document.layers.first(where: {$0.id == (pathID ?? selected?.id) && $0.isPath}) else {return}
    retouchPathID = path.id; showInspector = false; showEffects = false
    showLayers = true; showTools = true
  }
  func applyRetouchPath(to id: UUID) {
    guard let pathID = retouchPathID, let path = document.layers.first(where: {$0.id == pathID}),
      let target = document.layers.first(where: {$0.id == id}), !target.locked,
      ![.group,.adjustment].contains(target.kind),!target.isPath, interactionTool == .retouch else {return}
    let points = pathSamples(path).map(\.cg)
    selectLayer(id); beginTransaction("修饰路径")
    applyPixelBrush(points: points); endTransaction()
    retouchPathID = nil; showTools = false
  }
}

/// Expand storage bounds while leaving the original pixels, masks and stroke
/// locations at the same world position. Scaling a layer is a separate action.
enum LayerExpansion {
  static func expand(_ layer: inout ImageLayer, including points: [Point], radius: Double) -> CGPoint {
    guard ![.group,.adjustment].contains(layer.kind), !layer.isPath, layer.quad == nil, layer.warpNodes == nil, !points.isEmpty else {return .zero}
    let minX = min(0, floor((points.map(\.x).min() ?? 0)-radius))
    let minY = min(0, floor((points.map(\.y).min() ?? 0)-radius))
    let maxX = max(layer.width, ceil((points.map(\.x).max() ?? 0)+radius))
    let maxY = max(layer.height, ceil((points.map(\.y).max() ?? 0)+radius))
    guard minX != 0 || minY != 0 || maxX != layer.width || maxY != layer.height,
      maxX-minX <= 32768, maxY-minY <= 32768 else {return .zero}
    let old = layer, dx = -minX, dy = -minY
    let origin = TransformGeometry.displayPoint(CGPoint(x: minX, y: minY), layer: old)
    layer.width = maxX-minX; layer.height = maxY-minY
    let shifted = TransformGeometry.displayPoint(.zero, layer: layer)
    layer.x += origin.x-shifted.x; layer.y += origin.y-shifted.y
    if [.text,.shape,.gradient].contains(layer.kind) {
      let p = old.contentPlacement ?? CGRect(x:0,y:0,width:1,height:1)
      layer.contentPlacement = CGRect(x:(p.minX*old.width+dx)/layer.width,y:(p.minY*old.height+dy)/layer.height,
        width:p.width*old.width/layer.width,height:p.height*old.height/layer.height)
    }
    if layer.kind == .raster {
      let placement = old.rasterPlacement ?? CGRect(x:0,y:0,width:1,height:1)
      layer.rasterPlacement = CGRect(x:(placement.minX*old.width+dx)/layer.width,
        y:(placement.minY*old.height+dy)/layer.height,
        width:placement.width*old.width/layer.width,height:placement.height*old.height/layer.height)
    }
    if layer.maskAssetID != nil {
      let placement = old.maskPlacement ?? CGRect(x:0,y:0,width:1,height:1)
      layer.maskPlacement = CGRect(x:(placement.minX*old.width+dx)/layer.width,
        y:(placement.minY*old.height+dy)/layer.height,
        width:placement.width*old.width/layer.width,height:placement.height*old.height/layer.height)
    }
    for i in layer.strokes.indices {
      layer.strokes[i].points = layer.strokes[i].points.map {Point(x:$0.x+dx,y:$0.y+dy)}
      if var clip = layer.strokes[i].clip {clip.points = clip.points.map {Point(x:$0.x+dx,y:$0.y+dy)};layer.strokes[i].clip = clip}
    }
    if var strokes = layer.maskStrokes {
      for i in strokes.indices {strokes[i].points = strokes[i].points.map {Point(x:$0.x+dx,y:$0.y+dy)}}
      layer.maskStrokes = strokes
    }
    return CGPoint(x: dx, y: dy)
  }
}
