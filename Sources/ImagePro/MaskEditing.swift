import AppKit
import CoreImage
import SwiftUI
import Vision

extension ImageLayer {
  mutating func resetMaskParameters() {
    maskStrokes = nil; maskDensity = nil; maskOpacity = nil
    maskFeather = nil; maskInverted = nil; maskPlacement = nil
  }
}

extension ImageRenderer {
  func renderMask(_ layer: ImageLayer, assets: AssetLibrary, scale: Double = 1) -> CGImage? {
    guard let original = assets.image(layer.maskAssetID) else { return nil }
    let s = min(scale, 4096 / max(layer.width, layer.height))
    let w = max(1, Int(ceil(layer.width*s))), h = max(1, Int(ceil(layer.height*s)))
    guard let cg = Self.bitmap(w, h) else { return nil }
    cg.translateBy(x: 0, y: Double(h)); cg.scaleBy(x: s, y: -s)
    cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x:0,y:0,width:layer.width,height:layer.height))
    let p = layer.maskPlacement ?? CGRect(x:0,y:0,width:1,height:1)
    Self.draw(original, in: CGRect(x:p.minX*layer.width,y:p.minY*layer.height,width:p.width*layer.width,height:p.height*layer.height), context: cg)
    for var stroke in layer.maskStrokes ?? [] {
      // Masks are always opaque grayscale: erasing reveals instead of creating alpha holes.
      if stroke.erasing { stroke.color = RGBA(r: 1, g: 1, b: 1); stroke.erasing = false }
      Self.drawStroke(stroke, context: cg)
    }
    guard let painted = cg.makeImage() else { return nil }
    var ci = CIImage(cgImage: painted)
    if layer.maskInverted == true { ci = ci.applyingFilter("CIColorInvert") }
    let density = layer.maskDensity ?? 1, opacity = layer.maskOpacity ?? 1
    ci = ci.applyingFilter("CIColorMatrix", parameters: [
      "inputRVector": CIVector(x: density*opacity, y: 0, z: 0, w: 0),
      "inputGVector": CIVector(x: 0, y: density*opacity, z: 0, w: 0),
      "inputBVector": CIVector(x: 0, y: 0, z: density*opacity, w: 0),
      "inputBiasVector": CIVector(x: (1-density)*opacity, y: (1-density)*opacity,
        z: (1-density)*opacity, w: 0)])
    if (layer.maskFeather ?? 0) > 0 {
      ci = ci.clampedToExtent().applyingFilter("CIGaussianBlur",
        parameters: [kCIInputRadiusKey: (layer.maskFeather ?? 0)*s])
    }
    return context.createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h))
  }
}

extension ImageRenderer {
  /// Premultiplied luminance makes transparent pixels hide the target; the mask
  /// itself stays opaque so density/inversion always work on a grayscale image.
  static func opaqueGrayscale(_ image: CGImage) -> CGImage? {
    guard var surface = PixelRetouch.Surface(image) else {return nil}
    for i in stride(from:0,to:surface.pixels.count,by:4) {
      let red = Double(surface.pixels[i])*0.2126
      let green = Double(surface.pixels[i+1])*0.7152
      let blue = Double(surface.pixels[i+2])*0.0722
      let l = UInt8((red+green+blue).rounded())
      surface.pixels[i] = l;surface.pixels[i+1] = l;surface.pixels[i+2] = l;surface.pixels[i+3] = 255
    }
    return surface.image()
  }
  static func alignedMask(_ image: CGImage, canvasSize: CGSize, target: ImageLayer, width: Int, height: Int) -> CGImage? {
    guard let surface = PixelRetouch.Surface(image),let context = bitmap(width,height),
      let output = context.data?.assumingMemoryBound(to:UInt8.self) else {return nil}
    let sx = Double(image.width)/canvasSize.width,sy = Double(image.height)/canvasSize.height
    // Evaluate the smooth transform on a dense lattice once. Bilinear lookup of
    // this coordinate field avoids millions of bicubic mesh evaluations.
    let n = 256
    let map = (0...n).flatMap { y in (0...n).map {x in
      TransformGeometry.displayPoint(CGPoint(x:Double(x)*target.width/Double(n),y:Double(y)*target.height/Double(n)),layer:target)
    }}
    for y in 0..<height {
      let v = (Double(y)+0.5)/Double(height)*Double(n),iy = min(n-1,Int(v)),fy = v-Double(iy)
      for x in 0..<width {
        let u = (Double(x)+0.5)/Double(width)*Double(n),ix = min(n-1,Int(u)),fx = u-Double(ix)
        let a = map[iy*(n+1)+ix],b = map[iy*(n+1)+ix+1],c = map[(iy+1)*(n+1)+ix],d = map[(iy+1)*(n+1)+ix+1]
        let px = ((a.x*(1-fx)+b.x*fx)*(1-fy)+(c.x*(1-fx)+d.x*fx)*fy)*sx-0.5
        let py = ((a.y*(1-fx)+b.y*fx)*(1-fy)+(c.y*(1-fx)+d.y*fx)*fy)*sy-0.5
        var luminance = 0.0
        if px.isFinite,py.isFinite,px >= -1,py >= -1,px < Double(image.width),py < Double(image.height) {
          let xx = Int(floor(px)),yy = Int(floor(py)),dx = px-Double(xx),dy = py-Double(yy)
          for row in 0...1 {for column in 0...1 {
            let xx = xx+column,yy = yy+row
            if xx>=0,yy>=0,xx<image.width,yy<image.height {
              let i = (yy*image.width+xx)*4
              let value = Double(surface.pixels[i])*0.2126+Double(surface.pixels[i+1])*0.7152+Double(surface.pixels[i+2])*0.0722
              luminance += value*(column == 0 ? 1-dx : dx)*(row == 0 ? 1-dy : dy)
            }
          }}
        }
        let i = (y*width+x)*4,l = UInt8(min(255,max(0,luminance.rounded())))
        output[i] = l;output[i+1] = l;output[i+2] = l;output[i+3] = 255
      }
    }
    return context.makeImage()
  }
}

extension EditorStore {
  @discardableResult func detachMask(_ id: UUID) -> UUID? {
    guard let source = document.layers.first(where:{$0.id == id}), !source.locked,
      let image = renderer.renderMask(source,assets:active.assets) else { return nil }
    do {
      var mask = ImageLayer(name:source.name+L(" · 蒙版"),kind:.raster,width:source.width,height:source.height)
      mask.x = source.x;mask.y = source.y;mask.rotation = source.rotation
      mask.flippedX = source.flippedX;mask.flippedY = source.flippedY
      mask.quad = source.quad;mask.warpNodes = source.warpNodes
      mask.assetID = try active.assets.insert(image);mask.detachedMaskSource = id
      mask.parentID = source.parentID
      edit("分离蒙版") { doc in
        guard let index = doc.layers.firstIndex(where:{$0.id == id}) else { return }
        doc.layers[index].maskAssetID = nil;doc.layers[index].resetMaskParameters()
        doc.layers[index].maskEnabled = true
        doc.layers.insert(mask,at:index);doc.selectedLayerID = mask.id
      }
      editingMask = false;inspector = .base
      return mask.id
    } catch { fail(error);return nil }
  }
  func transferMask(from source: UUID, to target: UUID) {
    guard source != target, let layer = document.layers.first(where:{$0.id == source}),
      layer.maskAssetID != nil, !layer.locked,
      document.layers.contains(where:{$0.id == target && !$0.locked}) else { return }
    beginTransaction("移动蒙版")
    if let detached = detachMask(source) { attachLayerAsMask(detached,to:target) }
    endTransaction()
  }
  func attachLayerAsMask(_ source: UUID, to target: UUID) {
    guard source != target,
      let layer = document.layers.first(where:{$0.id == source}), !layer.locked, layer.kind != .group,
      let destination = document.layers.first(where:{$0.id == target}), !destination.locked else { return }
    if layer.detachedMaskSource == target,layer.x == destination.x,layer.y == destination.y,
      layer.width == destination.width,layer.height == destination.height,layer.rotation == destination.rotation,
      layer.quad == destination.quad,layer.warpNodes == destination.warpNodes,
      layer.flippedX == destination.flippedX,layer.flippedY == destination.flippedY,
      let asset = layer.assetID,layer.effects.isEmpty,layer.strokes.isEmpty,layer.opacity == 1,layer.maskAssetID == nil {
      edit("还原蒙版") {doc in
        guard let i = doc.layers.firstIndex(where:{$0.id == target}) else {return}
        doc.layers[i].maskAssetID = asset;doc.layers[i].maskEnabled = true;doc.layers[i].resetMaskParameters()
        doc.layers.removeAll {$0.id == source};doc.selectedLayerID = target
      }
      editingMask = true;inspector = .mask;return
    }
    var isolated = document;isolated.layers = [layer]
    isolated.layers[0].parentID = nil;isolated.layers[0].clippingMask = false;isolated.layers[0].visible = true
    let size = min(4096/max(destination.width,destination.height),1)
    guard let image = renderer.render(isolated,assets:active.assets,maxDimension:4096),
      let cg = ImageRenderer.bitmap(max(1,Int(destination.width*size)),max(1,Int(destination.height*size))) else { return }
    let mask: CGImage
    if destination.quad != nil || destination.warpNodes != nil {
      // A mask is stored before the target's deformation. Sample the canvas at
      // each forward-deformed local pixel so attaching never deforms it twice.
      guard let aligned = ImageRenderer.alignedMask(image, canvasSize: CGSize(width:document.width,height:document.height),
        target: destination, width: cg.width, height: cg.height) else {return}
      mask = aligned
    } else {
      cg.translateBy(x:0,y:Double(cg.height));cg.scaleBy(x:size,y:-size)
      cg.translateBy(x:destination.width/2,y:destination.height/2)
      cg.scaleBy(x:destination.flippedX == true ? -1 : 1,y:destination.flippedY == true ? -1 : 1)
      cg.rotate(by:-destination.rotation * .pi/180)
      cg.translateBy(x:-destination.x-destination.width/2,y:-destination.y-destination.height/2)
      ImageRenderer.draw(image,in:CGRect(x:0,y:0,width:document.width,height:document.height),context:cg)
      guard let aligned = cg.makeImage(),let grayscale = ImageRenderer.opaqueGrayscale(aligned) else {return}
      mask = grayscale
    }
    do {
      let asset = try active.assets.insert(mask)
      edit("图层转为蒙版") { doc in
        guard let index = doc.layers.firstIndex(where:{$0.id == target}) else { return }
        doc.layers[index].maskAssetID = asset;doc.layers[index].maskEnabled = true
        doc.layers[index].resetMaskParameters()
        doc.layers.removeAll {$0.id == source};doc.selectedLayerID = target
      }
      editingMask = true;inspector = .mask;showInspector = true
    } catch { fail(error) }
  }
  func selectMask(_ id: UUID) {
    selectLayer(id)
    guard selected?.maskAssetID != nil else { return }
    editingMask = true; inspector = .mask; showInspector = true
    foreground = RGBA(r: 0, g: 0, b: 0)
    chooseTool(.brush)
    inspector = .mask
  }
  func appendMaskStroke(_ stroke: BrushStroke) {
    guard selected?.locked != true, selected?.maskAssetID != nil else { return }
    var maskStroke = stroke
    let white = maskReveal || stroke.erasing
    maskStroke.color = RGBA(r: white ? 1 : 0, g: white ? 1 : 0, b: white ? 1 : 0)
    maskStroke.erasing = false
    updateSelected(white ? "蒙版显示描边" : "蒙版隐藏描边") {
      if $0.maskStrokes == nil { $0.maskStrokes = [] }
      $0.maskStrokes?.append(maskStroke)
    }
  }
  func beginRefiningSelection() {
    guard selection != nil, !refiningSelection else { return }
    refineOriginal = selection; refineInput = selection
    refinePreviousInspector = inspector; refinePreviousVisibility = showInspector
    refineRoundness = 0; refineExpand = 0; refineSoftness = selection?.feather ?? 0
    refineOutput = "selection"
    refiningSelection = true; showInspector = true; showEffects = false
  }
  func updateRefinement() {
    guard let source = refineInput else { return }
    refineGeneration += 1
    let token = refineGeneration, project = activeID
    let size = CGSize(width: document.width, height: document.height)
    let round = refineRoundness, expand = refineExpand, feather = refineSoftness
    selectionQueue.async { [weak self] in
      let region = SelectionRefinement.refine(source, size: size, roundness: round,
        expand: expand, feather: feather)
      DispatchQueue.main.async {
        guard let self, self.refiningSelection, self.refineGeneration == token,
          self.activeID == project else { return }
        self.selection = region
      }
    }
  }
  func refineSelectionBrush(_ points: [CGPoint]) {
    guard refiningSelection, !points.isEmpty else { return }
    refineGeneration += 1
    let token = refineGeneration, project = activeID
    let source = refineInput ?? SelectionRegion(type: "rectangle", points: [.init(x:0,y:0),.init(x:0,y:0)])
    let image = preview, size = CGSize(width:document.width,height:document.height)
    let brush = refineBrush, diameter = refineBrushSize, mode = refineMode, tolerance = selectionTolerance
    selectionQueue.async { [weak self] in
      let result = SelectionRefinement.paint(source, image:image, size:size, points:points,
        diameter:diameter, brush:brush, mode:mode, tolerance:tolerance)
      DispatchQueue.main.async {
        guard let self, self.refiningSelection, self.activeID == project,
          self.refineGeneration == token else { return }
        self.refineInput = result; self.updateRefinement()
      }
    }
  }
  func snapSelectionEdges() {
    guard refiningSelection, let source = refineInput, let image = preview else { return }
    refineGeneration += 1
    let token = refineGeneration, project = activeID
    let size = CGSize(width:document.width,height:document.height)
    selectionQueue.async { [weak self] in
      let region = SelectionRefinement.snapEdges(source,image:image,size:size,radius:8)
      DispatchQueue.main.async {
        guard let self, self.refiningSelection, self.activeID == project,
          self.refineGeneration == token else { return }
        self.refineInput = region; self.updateRefinement()
      }
    }
  }
  func finishRefinement(cancel: Bool = false) {
    guard refiningSelection else { return }
    refineGeneration += 1
    if cancel { selection = refineOriginal }
    else if let source = refineInput {
      selection = SelectionRefinement.refine(source,
        size: CGSize(width: document.width, height: document.height), roundness: refineRoundness,
        expand: refineExpand, feather: refineSoftness)
      switch refineOutput {
      case "mask": maskFromSelection()
      case "newMask":
        if let id = selected?.id { beginTransaction("新建带蒙版图层"); duplicateLayer(id); maskFromSelection(); endTransaction() }
      case "newLayer": _ = extractSelection()
      default: break
      }
    }
    refiningSelection = false; inspector = refinePreviousInspector
    showInspector = refinePreviousVisibility || !cancel
    refineOriginal = nil; refineInput = nil
  }
  func selectSubject() {
    guard !busy, let image = preview else { return }
    cancelColorSelection()
    let token = selectionToken
    let size = CGSize(width: document.width, height: document.height), project = activeID
    busy = true
    Task.detached(priority: .userInitiated) {
      do {
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
          throw ImageProError.message("未找到清晰的主体，请用快速选择画笔添加区域。")
        }
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let ci = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let mask = context.createCGImage(ci, from: ci.extent),
          let region = SelectionRefinement.region(mask, size: size) else {
          throw ImageProError.message("无法生成主体选区。")
        }
        await MainActor.run {
          self.busy = false
          guard self.activeID == project, self.selectionToken == token else { return }
          self.selection = region
          if self.refiningSelection { self.refineInput = region; self.updateRefinement() }
        }
      } catch { await MainActor.run {
        self.busy = false
        if self.activeID == project, self.selectionToken == token { self.fail(error) }
      } }
    }
  }
}

enum SelectionRefinement {
  static let context = CIContext()
  static func paint(_ source:SelectionRegion, image:CGImage?, size:CGSize, points:[CGPoint],
    diameter:Double, brush:String, mode:String, tolerance:Double) -> SelectionRegion {
    if brush == "quick", let image {
      var result = source
      let step = max(1, points.count/12)
      for i in stride(from:0,to:points.count,by:step) {
        if let region = SelectionEngine.region(image:image,point:points[i],canvasSize:size,
          tolerance:tolerance,contiguous:true) {
          result = SelectionEngine.combine(result,region,mode:mode,size:size)
        }
      }
      return result
    }
    var hard = source; hard.feather = 0
    guard let oldMask = SelectionEngine.mask(hard,size:size,maxSize:900),
      let cg = ImageRenderer.bitmap(oldMask.width,oldMask.height) else { return source }
    let w = oldMask.width, h = oldMask.height, scale = Double(w)/size.width
    cg.setFillColor(NSColor.black.cgColor);cg.fill(CGRect(x:0,y:0,width:w,height:h))
    cg.translateBy(x:0,y:Double(h));cg.scaleBy(x:scale,y:-scale)
    let stroke = BrushStroke(points:points.map(Point.init),color:.init(r:1,g:1,b:1),
      size:diameter,opacity:1,hardness:1)
    ImageRenderer.drawStroke(stroke,context:cg)
    guard let brushMask = cg.makeImage(), let a = ImageRenderer.bitmap(w,h), let b = ImageRenderer.bitmap(w,h)
    else { return source }
    a.draw(oldMask,in:CGRect(x:0,y:0,width:w,height:h));b.draw(brushMask,in:CGRect(x:0,y:0,width:w,height:h))
    let boundary:CGImage?
    if brush == "edge" {
      let ci = CIImage(cgImage:oldMask), r = max(1,diameter*scale*0.25)
      let outer = ci.applyingFilter("CIMorphologyMaximum",parameters:[kCIInputRadiusKey:r])
      let inner = ci.applyingFilter("CIMorphologyMinimum",parameters:[kCIInputRadiusKey:r])
      boundary = context.createCGImage(outer.applyingFilter("CIDifferenceBlendMode",parameters:[kCIInputBackgroundImageKey:inner]),from:ci.extent)
    } else { boundary = nil }
    let band = ImageRenderer.bitmap(w,h)
    if let boundary { band?.draw(boundary,in:CGRect(x:0,y:0,width:w,height:h)) }
    guard let ap = a.data?.assumingMemoryBound(to:UInt8.self),let bp = b.data?.assumingMemoryBound(to:UInt8.self) else { return source }
    let ep = boundary == nil ? nil : band?.data?.assumingMemoryBound(to:UInt8.self)
    let pixels = (0..<w*h).map { i -> UInt8 in
      let painted = bp[i*4] > 127 && (ep == nil || ep![i*4] > 127)
      return painted ? (mode == "subtract" ? 0 : 1) : (ap[i*4] > 127 ? 1 : 0)
    }
    return SelectionEngine.spans(pixels,width:w,height:h,size:size)
      ?? SelectionRegion(type:"rectangle",points:[.init(x:0,y:0),.init(x:0,y:0)])
  }
  /// Color-guided local boundary fitting. This is deterministic, not a neural hair-matting model.
  static func snapEdges(_ source:SelectionRegion,image:CGImage,size:CGSize,radius:Int) -> SelectionRegion {
    var hard = source;hard.feather = 0
    guard let mask = SelectionEngine.mask(hard,size:size,maxSize:700),
      let a = ImageRenderer.bitmap(mask.width,mask.height),let b = ImageRenderer.bitmap(mask.width,mask.height) else { return source }
    let w = mask.width,h = mask.height
    a.draw(mask,in:CGRect(x:0,y:0,width:w,height:h));b.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
    guard let ap = a.data?.assumingMemoryBound(to:UInt8.self),let bp = b.data?.assumingMemoryBound(to:UInt8.self) else { return source }
    var selected = (0..<w*h).map { ap[$0*4] > 127 ? UInt8(1) : 0 }
    let directions = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)]
    for y in 0..<h { for x in 0..<w {
      let i = y*w+x
      var fg = Double.infinity,bg = Double.infinity
      for distance in [2,radius] { for (dx,dy) in directions {
        let xx = x+dx*distance, yy = y+dy*distance
        if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
        let j = yy*w+xx
        let delta = (0..<4).reduce(0.0) { $0+pow(Double(bp[i*4+$1])-Double(bp[j*4+$1]),2) } + Double(distance*distance)*4
        if ap[j*4] > 127 { fg = min(fg,delta) } else { bg = min(bg,delta) }
      } }
      if fg.isFinite && bg.isFinite { selected[i] = fg <= bg ? 1 : 0 }
    } }
    return SelectionEngine.spans(selected,width:w,height:h,size:size) ?? source
  }
  static func region(_ mask: CGImage, size: CGSize) -> SelectionRegion? {
    let s = min(1, 900/Double(max(mask.width, mask.height)))
    let w = max(1, Int(Double(mask.width)*s)), h = max(1, Int(Double(mask.height)*s))
    guard let cg = ImageRenderer.bitmap(w, h) else { return nil }
    cg.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let p = cg.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    return SelectionEngine.spans((0..<w*h).map { p[$0*4] > 127 ? 1 : 0 }, width: w, height: h, size: size)
  }
  static func refine(_ selection: SelectionRegion, size: CGSize, roundness: Double,
    expand: Double, feather: Double) -> SelectionRegion {
    var source = selection; source.feather = 0
    guard let mask = SelectionEngine.mask(source, size: size, maxSize: 900) else { return selection }
    let scale = Double(mask.width)/size.width
    var ci = CIImage(cgImage: mask)
    let extent = ci.extent
    if roundness > 0 {
      ci = ci.clampedToExtent().applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: roundness*scale])
        .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: roundness*scale]).cropped(to: extent)
    }
    if expand != 0 {
      ci = ci.applyingFilter(expand > 0 ? "CIMorphologyMaximum" : "CIMorphologyMinimum",
        parameters: [kCIInputRadiusKey: abs(expand)*scale]).cropped(to: extent)
    }
    guard let image = context.createCGImage(ci, from: extent), var result = region(image, size: size)
    else { return SelectionRegion(type: "rectangle", points: [.init(x: 0, y: 0), .init(x: 0, y: 0)]) }
    result.feather = feather
    return result
  }
}

struct MaskInspector: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var layer: ImageLayer
  var body: some View {
    VStack(spacing: 20) {
      Picker(L("画笔"), selection: $store.maskReveal) {
        Text(L("隐藏 · 黑色")).tag(false); Text(L("显示 · 白色")).tag(true)
      }.id(AppLocalization.language).pickerStyle(.segmented)
      Toggle(L("显示蒙版预览"), isOn: $store.maskOverlay)
      Toggle(L("启用蒙版"), isOn: Binding(get: { layer.maskEnabled }, set: { v in store.updateSelected("切换蒙版") { $0.maskEnabled = v } }))
      ParameterSlider(store: store, title: "密度", value: layer.maskDensity ?? 1, range: 0...1, unit: "%", percentage: true, defaultValue: 1) { v in store.updateSelected("调整蒙版密度") { $0.maskDensity = v } }
      ParameterSlider(store: store, title: "不透明度", value: layer.maskOpacity ?? 1, range: 0...1, unit: "%", percentage: true) { v in store.updateSelected("调整蒙版透明度") { $0.maskOpacity = v } }
      ParameterSlider(store: store, title: "羽化", value: layer.maskFeather ?? 0, range: 0...100, unit: " px") { v in store.updateSelected("调整蒙版羽化") { $0.maskFeather = v } }
      Button(L("反转蒙版")) { store.updateSelected("反转蒙版") { $0.maskInverted = !($0.maskInverted ?? false) } }
      Button(L("移除蒙版"), role: .destructive) {
        store.removeMask(layer.id)
      }
      Text(L("选择图层旁的蒙版缩略图，再使用画笔隐藏或显示区域。原始图像始终保留。"))
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }
  }
}

struct RefineSelectionInspector: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var body: some View {
    VStack(spacing: 19) {
      HStack(spacing:10) {
        Button(L("选择主体")) {store.selectSubject()}.disabled(store.busy)
        Button(L("细化边缘")) {store.snapSelectionEdges()}
      }.buttonStyle(.bordered).controlSize(.large).frame(maxWidth:.infinity,alignment:.leading)
      SectionCaption(title:"边缘")
      ParameterSlider(store: store, title: "形状圆度", value: store.refineRoundness, range: 0...40, unit: " px") { store.refineRoundness = $0; store.updateRefinement() }
      ParameterSlider(store: store, title: "边缘柔化", value: store.refineSoftness, range: 0...100, unit: " px") { store.refineSoftness = $0; store.updateRefinement() }
      ParameterSlider(store: store, title: "selection.expand", value: store.refineExpand, range: -100...100, unit: " px") { store.refineExpand = $0; store.updateRefinement() }
      Divider()
      SectionCaption(title: "调整画笔")
      Picker(L("画笔类型"), selection: $store.refineBrush) {
        Text(L("边缘画笔")).tag("edge"); Text(L("快速选择")).tag("quick"); Text(L("基础画笔")).tag("basic")
      }.id(AppLocalization.language)
      Picker(L("操作"), selection: $store.refineMode) { Text(L("添加")).tag("add"); Text(L("减去")).tag("subtract") }.id(AppLocalization.language).pickerStyle(.segmented)
      ParameterSlider(store: store, title: "大小", value: store.refineBrushSize, range: 1...500, unit: " px", defaultValue: 40) { store.refineBrushSize = $0 }
      HStack {
        Button(L("反选")) { store.invertSelection(); store.refineInput = store.selection; store.updateRefinement() }
        Button(L("清除")) { store.selection = nil; store.refineInput = nil }
      }
      Divider()
      SectionCaption(title:"预览与输出")
      Picker(L("叠加预览"), selection: $store.refineOverlay) {
        Text(L("红色")).tag("red"); Text(L("黄色")).tag("yellow"); Text(L("黑色")).tag("black"); Text(L("白色")).tag("white")
      }.id(AppLocalization.language)
      Picker(L("输出"), selection: $store.refineOutput) {
        Text(L("选区")).tag("selection"); Text(L("蒙版")).tag("mask")
        Text(L("带蒙版的新图层")).tag("newMask"); Text(L("新图层")).tag("newLayer")
      }.id(AppLocalization.language)
      HStack {
        Button(L("重置")) { store.refineInput = store.refineOriginal; store.refineRoundness = 0; store.refineExpand = 0; store.refineSoftness = 0; store.updateRefinement() }
        Spacer()
        Button(L("取消")) { withAnimation(.smooth) { store.finishRefinement(cancel: true) } }
        Button(L("应用")) { withAnimation(.smooth) { store.finishRefinement() } }.buttonStyle(.borderedProminent)
      }
    }
  }
}
