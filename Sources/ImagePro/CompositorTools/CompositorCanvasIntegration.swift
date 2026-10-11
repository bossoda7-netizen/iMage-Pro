// Adapted from Compositor's Crop, TransformDrag, CloneStamp and TypeTool (MIT).
// Copyright (c) 2026 Wonder Assembly LLC. See ThirdParty/Compositor/LICENSE.
import AppKit

extension CTPlacement {
  init(_ layer:ImageLayer) {
    origin = CGPoint(x:layer.x,y:layer.y);size = CGSize(width:layer.width,height:layer.height)
    rotation = layer.rotation;flipX = layer.flippedX == true;flipY = layer.flippedY == true
  }
  func applying(to layer:ImageLayer) -> ImageLayer {
    var l = layer;l.x = origin.x;l.y = origin.y;l.width = size.width;l.height = size.height
    l.rotation = rotation;l.flippedX = flipX;l.flippedY = flipY;return l
  }
}

extension CanvasNSView {
  func cancelCompositorGesture() {
    compositorStroke = nil;compositorDocumentPoints = [];compositorProject = nil;compositorMove = nil;compositorCrop = nil
    compositorTextBox = false;compositorSampleClick = false;compositeKey = nil
    if store?.compositorToolID != nil { initialLayer = nil;draft = nil;store?.endTransaction() }
  }
  func beginCompositorGesture(_ event:NSEvent) -> Bool {
    guard let store,let toolID = store.compositorToolID else {return false}
    compositorProject = store.document.id
    compositorSampleClick = false
    switch toolID {
    case "miganHeal","smudge","liquify":
      guard !store.busy else {store.notify("正在处理修复笔触");return true}
      store.beginTransaction(store.branch.title)
      compositorDocumentPoints = [start];store.expandPixelBounds(including:[start])
      compositorStroke = CompositorPixelStroke(store:store)
      compositorStroke?.appendDocument(start,store:store)
      return true
    case "crop":
      let current = store.selection?.type == "crop" ? store.selection?.bounds : nil
      let found = current.flatMap {CTCropGeometry.handle(at:start,in:$0,scale:scale)}
      let mode: CTCropDrag.Mode = found.map { .resize($0) } ?? (current?.contains(start) == true ? .move : .create)
      compositorCrop = CTCropDrag(start:start,original:current ?? CGRect(origin:start,size:.zero),mode:mode)
      draft = SelectionRegion(type:"crop",points:[Point(start),Point(start)])
      if let current {draft = SelectionRegion(type:"crop",points:[Point(current.origin),Point(x:current.maxX,y:current.maxY)])}
      return true
    case "horizontalText":
      if let layer = hit(start),layer.kind == .text {
        store.selectLayer(layer.id);store.textEditingLayerID = layer.id;syncTextEditor()
      } else {compositorTextBox = true;draft = SelectionRegion(type:"textBox",points:[Point(start),Point(start)])}
      return true
    default:return false
    }
  }
  func dragCompositorGesture(_ event:NSEvent,point:CGPoint) -> Bool {
    guard let store,let toolID = store.compositorToolID,compositorProject == store.document.id,!panning else {return false}
    if compositorStroke != nil {
      compositorDocumentPoints.append(point)
      if store.expandPixelBounds(including:compositorDocumentPoints) {
        compositorStroke = CompositorPixelStroke(store:store)
        if !event.modifierFlags.contains(.shift) {for p in compositorDocumentPoints {compositorStroke?.appendDocument(p,store:store)}}
      }
      guard let stroke = compositorStroke else {return true}
      if event.modifierFlags.contains(.shift) {
        stroke.resetToOriginal();stroke.appendDocument(start,store:store)
        stroke.appendDocument(TransformGeometry.constrained(point,around:start),store:store)
      } else {stroke.appendDocument(point,store:store)}
      compositeKey = nil;return true
    }
    if compositorSampleClick {return true}
    if let drag = compositorCrop {
      let parts = store.cropRatio.split(separator:":").compactMap {Double($0)}
      let ratio:CGFloat? = parts.count == 2 ? parts[0]/parts[1] : event.modifierFlags.contains(.shift) ? 1 : nil
      var r = drag.updated(to:point,ratio:ratio,symmetric:event.modifierFlags.contains(.option))
      if store.snapping && !event.modifierFlags.contains(.control) {
        let targets = store.snapTargets(excluding:nil)
        r = CTCropSnap(xs:targets.x.map { CGFloat($0) },ys:targets.y.map { CGFloat($0) },tolerance:10/scale).apply(r,drag:drag,point:point,ratio:ratio,symmetric:event.modifierFlags.contains(.option))
      }
      draft = SelectionRegion(type:"crop",points:[Point(r.origin),Point(x:r.maxX,y:r.maxY)]);return true
    }
    if compositorTextBox {
      let rect = CGRect(x:min(start.x,point.x),y:min(start.y,point.y),width:abs(point.x-start.x),height:abs(point.y-start.y))
      draft = SelectionRegion(type:"textBox",points:[Point(rect.origin),Point(x:rect.maxX,y:rect.maxY)]);return true
    }
    return ["miganHeal","smudge","liquify","crop","horizontalText"].contains(toolID)
  }
  func finishCompositorGesture(_ event:NSEvent) -> Bool {
    guard let store,!store.rulerMode,let _ = store.compositorToolID,!panning else {return false}
    guard compositorProject == store.document.id else {cancelCompositorGesture();return true}
    if let stroke = compositorStroke {
      compositorStroke = nil;compositeKey = nil
      if stroke.changed {
        if MIGANInpainting.isHealing(stroke.mode) {
          let job = stroke.healingJob(),project = stroke.project,layer = stroke.layer
          let title = store.branch.title
          healingStroke = stroke
          store.busy = true
          store.selectionQueue.async { [weak store,weak self] in
            let result = Result { try job.repairedImage() }
            DispatchQueue.main.async {
              guard let store else {return};store.busy = false
              switch result {
              case .success(let image):store.commitCompositorPixels(image,project:project,original:layer,title:title)
              case .failure(let error):store.fail(error)
              }
              self?.healingStroke = nil;self?.compositeKey = nil;self?.needsDisplay = true
            }
          }
        } else if let result = stroke.result() {
          store.commitCompositorPixels(result,project:stroke.project,original:stroke.layer,title:store.branch.title)
        }
      }
    } else if let drag = compositorCrop,let region = draft,CTCropGeometry.valid(region.bounds) {
      if case .create = drag.mode,region.bounds.width<2 || region.bounds.height<2 {} else {store.selection = region}
    } else if compositorTextBox {
      let r = draft?.bounds ?? .zero
      let box = r.width*scale > 4 && r.height*scale > 4
      let rect = box ? r : CGRect(origin:start,size:CGSize(width:120,height:100))
      compositorNewTextBefore = store.document
      store.beginTransaction("新建文字")
      store.addLayer(.text,rect:rect)
      store.updateSelected("新建文字") {l in
        l.text = "";var style = l.textStyle ?? TextStyle();style.pointText = !box;l.textStyle = style
      }
      store.textEditingLayerID = store.selected?.id;syncTextEditor()
      // Text creation and typing share one transaction, committed when editing finishes.
    }
    compositorMove = nil;compositorCrop = nil;compositorTextBox = false;compositorSampleClick = false
    compositorProject = nil;draft = nil;initialLayer = nil;handle = nil
    if textEditor == nil {store.endTransaction()}
    return true
  }
}

extension EditorStore {
  func commitCompositorPixels(_ image:CGImage,project:UUID,original:ImageLayer,title:String) {
    guard document.id == project,document.layers.first(where:{$0.id == original.id}) == original else {
      notify("图层已变化，未应用笔触");return
    }
    do {
      let id = try active.assets.insert(image)
      edit(title) {doc in
        guard let i = doc.layers.firstIndex(where:{$0.id == original.id}) else {return}
        doc.layers[i].kind = .raster;doc.layers[i].assetID = id;doc.layers[i].strokes = [];doc.layers[i].rasterPlacement = nil;doc.layers[i].contentPlacement = nil
        // Placement, layer effects, clipping and mask ownership stay editable.
      }
      // Publish the same pixels as the final live frame before clearing the gesture.
      if let updated = document.layers.first(where:{$0.id == original.id}) {
        layerPreviews[original.id] = renderer.previewLayer(updated,assets:active.assets,scale:min(1,1200/max(updated.width,updated.height)))
        previewRevision += 1
      }
    } catch {fail(error)}
  }
}
