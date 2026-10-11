import AppKit
import CoreImage

struct ClipboardContent: Codable {
  var layers: [ImageLayer] = []
  var assets: [ClipboardAsset] = []
  var effect: ImageEffect?
  var measurements: [RulerMeasurement]?
}

extension EditorStore {
  func copySelectedLayer() {
    var payload = ClipboardContent()
    if rulerMode {
      payload.measurements = rulerMeasurements.filter { selectedRulerID == nil || $0.id == selectedRulerID }
      guard payload.measurements?.isEmpty == false else {return}
    } else if showInspector,case .effect(let id) = inspector,let effect = selected?.effects.first(where:{$0.id == id}) {
      payload.effect = effect
    } else if let selection {
      var isolated = document
      let ids = descendants(of:selectedIDs)
      isolated.layers = document.layers.filter {ids.contains($0.id)}
      for i in isolated.layers.indices where isolated.layers[i].parentID.map(ids.contains) != true {isolated.layers[i].parentID = nil}
      guard !isolated.layers.isEmpty,
        let image = renderer.render(isolated,assets:active.assets,maxDimension:nil),
        let mask = SelectionEngine.mask(selection,size:CGSize(width:document.width,height:document.height)) else {return}
      let ci = CIImage(cgImage:image)
      let result = ci.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:CIImage(color:.clear).cropped(to:ci.extent),kCIInputMaskImageKey:CIImage(cgImage:mask)])
      let bounds = selection.inverted == true ? ci.extent : selection.bounds.integral.intersection(CGRect(x:0,y:0,width:document.width,height:document.height))
      guard !bounds.isEmpty,let cropped = renderer.context.createCGImage(result,from:CGRect(x:bounds.minX,y:document.height-bounds.maxY,width:bounds.width,height:bounds.height)),
        let data = try? AssetLibrary.encode(cropped,type:"public.png") else {return}
      var layer = ImageLayer(name:(selected?.name ?? L("内容"))+L(" · 选区"),kind:.raster,width:bounds.width,height:bounds.height)
      let id = UUID().uuidString;layer.assetID = id;layer.x = bounds.minX;layer.y = bounds.minY
      payload.layers = [layer];payload.assets = [ClipboardAsset(id:id,data:data)]
    } else {
      let ids = descendants(of:selectedIDs)
      payload.layers = document.layers.filter {ids.contains($0.id)}
      guard !payload.layers.isEmpty else {return}
      for i in payload.layers.indices where payload.layers[i].parentID.map(ids.contains) != true {payload.layers[i].parentID = nil}
      let assets = Set(payload.layers.flatMap {[$0.assetID,$0.maskAssetID].compactMap {$0}})
      let snapshot = active.assets.snapshot()
      payload.assets = assets.compactMap {id in snapshot[id].map {ClipboardAsset(id:id,data:$0)}}
    }
    guard let data = try? JSONEncoder().encode(payload) else {return}
    let pb = NSPasteboard.general;pb.clearContents();pb.setData(data,forType:.init("com.imagepro.content"))
    if payload.layers.count == 1,let id = payload.layers[0].assetID,let data = payload.assets.first(where:{$0.id == id})?.data {pb.setData(data,forType:.png)}
    notify(payload.effect != nil ? "已复制效果器" : rulerMode ? "已复制标尺" : "已复制内容")
  }
  func pasteLayer() {
    let pb = NSPasteboard.general
    var payload:ClipboardContent
    if let data = pb.data(forType:.init("com.imagepro.content")),let decoded = try? JSONDecoder().decode(ClipboardContent.self,from:data) {payload = decoded}
    else if let data = pb.data(forType:.init("com.imagepro.layer")),let old = try? JSONDecoder().decode(ClipboardLayerPayload.self,from:data) {payload = ClipboardContent(layers:[old.layer],assets:old.assets)}
    else if !rulerMode,let image = NSImage(pasteboard:pb)?.cgImage(forProposedRect:nil,context:nil,hints:nil),let data = try? AssetLibrary.encode(image,type:"public.png") {
      var layer = ImageLayer(name:L("粘贴图像"),kind:.raster,width:Double(image.width),height:Double(image.height))
      let id = UUID().uuidString;layer.assetID = id
      payload = ClipboardContent(layers:[layer],assets:[ClipboardAsset(id:id,data:data)])
    } else {return}
    if rulerMode {
      guard let measurements = payload.measurements else {return}
      rulerUndoSnapshot()
      for var measurement in measurements {measurement.id = UUID();measurement.start.x += 16;measurement.end.x += 16;rulerMeasurements.append(measurement);selectedRulerID = measurement.id}
      return
    }
    if let effect = payload.effect {
      guard selected != nil else {return};var copy = effect;copy.id = UUID()
      updateSelected("粘贴效果器") {$0.effects.append(copy)};inspector = .effect(copy.id);showInspector = true;return
    }
    guard !showWelcome,!payload.layers.isEmpty else {return}
    let ids = Dictionary(uniqueKeysWithValues:payload.layers.map {($0.id,UUID())})
    let folderCopy = payload.layers.first?.kind == .group
    let parent = selected?.kind == .group && !folderCopy ? selected?.id : selected?.parentID
    for i in payload.layers.indices {
      let old = payload.layers[i];payload.layers[i].id = ids[old.id]!
      payload.layers[i].parentID = old.parentID.flatMap {ids[$0]} ?? parent
      payload.layers[i].x += 16;payload.layers[i].y += 16
    }
    for asset in payload.assets {active.assets.insert(asset.data,id:asset.id)}
    edit("粘贴内容") {doc in
      let index = folderCopy ? (doc.layers.firstIndex(where:{$0.id == doc.selectedLayerID}) ?? 0) : doc.insertionIndex
      doc.layers.insert(contentsOf:payload.layers,at:index);doc.selectedLayerID = payload.layers.first?.id
    }
    multiSelectedLayers = Set(payload.layers.map(\.id));showLayers = true
  }
}
extension ImageDocument {
  var insertionIndex: Int {
    guard let i = layers.firstIndex(where:{$0.id == selectedLayerID}) else {return 0}
    return i
  }
  var insertionParent:UUID? {selectedLayer?.parentID}
}
