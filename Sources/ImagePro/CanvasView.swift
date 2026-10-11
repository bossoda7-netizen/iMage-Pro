import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorCanvas: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  func makeNSView(context: Context) -> CanvasNSView {
    let view = CanvasNSView()
    view.store = store
    view.installDraftUndo()
    return view
  }
  func updateNSView(_ view: CanvasNSView, context: Context) {
    if view.previousTool != store.tool || view.previousBranch != store.branch.id || view.previousProject != store.document.id {
      view.cancelCompositorGesture()
      view.draft = nil
      view.pathPoints = []
      view.resetPenDraft()
      view.selectedPenAnchor = nil
      view.stroke = nil
      view.previousBranch = store.branch.id
      view.previousTool = store.tool
      view.previousProject = store.document.id
    }
    view.store = store
    view.setAccessibilityLabel(L("图像编辑画布"))
    view.syncTextEditor()
    view.needsDisplay = true
    view.window?.invalidateCursorRects(for: view)
  }
}

final class CanvasNSView: NSView {
  weak var store: EditorStore?
  var compositorStroke: CompositorPixelStroke?
  var compositorDocumentPoints: [CGPoint] = []
  var healingStroke: CompositorPixelStroke?
  var compositorProject: UUID?
  var compositorMove: CTTransformDrag?
  var compositorCrop: CTCropDrag?
  var compositorNewTextBefore: ImageDocument?
  var compositorTextBox = false
  var compositorSampleClick = false
  var paletteSampleClick = false
  var synchronizingText = false
  var textEditor: CanvasTextView?
  var textBefore: ImageLayer?
  var textProjectID: UUID?
  var cursorSignature: String?
  var previousBranch: String?
  var previousTool: ToolCategory?
  var previousProject: UUID?
  var start = CGPoint.zero, last = CGPoint.zero, startView = CGPoint.zero
  var startPan = CGSize.zero
  var moveOriginals: [ImageLayer] = []
  var gestureMoved = false
  var pendingInspectorClick = false
  var hitBitmaps: [UUID: NSBitmapImageRep] = [:]
  var hitBitmapRevision = -1
  var lastPaintEndpoint: CGPoint?
  var initialLayer: ImageLayer?
  var stroke: BrushStroke?
  var draft: SelectionRegion?
  var pathPoints = [Point]()
  var lastSmudgeUpdate = 0.0
  var pixelPoints = [CGPoint]()
  var penAnchors = [BezierAnchor]()
  var penUndo = [[BezierAnchor]](), penRedo = [[BezierAnchor]]()
  var pendingPenEdit: (Int,Int)?
  var penPointer = CGPoint.zero
  var penDrag: Int?
  var penEdit: (Int, Int)?
  var selectedPenAnchor: (layer: UUID, anchor: UUID)?
  var finishPenOnUp = false
  var shapeStart = CGPoint.zero
  var handle: Int?
  var didExtract = false
  var rotating = false, spaceHeld = false, panning = false, movingSelection = false
  var rotationStart: Double = 0
  var cropBefore: SelectionRegion?
  var movingCrop = false
  var gradientDrag: UUID?
  var warpDrag: Int?
  var pointer: CGPoint?
  var animationTimer: Timer?
  var antsPhase: Double = 0
  var hoverPoint: CGPoint?
  var rulerEditingBefore: RulerMeasurement?
  var rulerDraft: RulerMeasurement?
  var compositeImage: CGImage?
  var compositeKey: (UUID, Int, Int)?
  var overlaySelection: SelectionRegion?
  var overlayColor = ""
  var overlayImage: CGImage?
  var maskOverlayLayer: ImageLayer?
  var maskOverlayImage: CGImage?
  var accentNSColor: NSColor {
    switch store?.themeColor {
    case "purple": return .systemPurple
    case "pink": return .systemPink
    case "red": return .systemRed
    case "orange": return .systemOrange
    case "yellow": return .systemYellow
    case "green": return .systemGreen
    case "graphite": return .systemGray
    default: return .controlAccentColor
    }
  }
  override func layout() {super.layout();store?.canvasViewport = bounds.size;syncTextEditor()}
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
  }
  override func mouseMoved(with event: NSEvent) {
    pointer = convert(event.locationInWindow, from: nil)
    hoverPoint = pointer.map(documentPoint)
    if CanvasColorSampling.shared.active || store?.interactionTool == .eyedropper {NSCursor.arrow.set()}
    needsDisplay = true
  }
  override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
  override func mouseExited(with event: NSEvent) { pointer = nil; needsDisplay = true }
  deinit { animationTimer?.invalidate() }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    registerForDraggedTypes([.fileURL])
    animationTimer?.invalidate()
    if window != nil {
      let timer = Timer(timeInterval: 1.0/24, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self,self.window?.isVisible == true else { return }
          self.refreshPointer()
          if self.store?.selection != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.antsPhase += 0.7;self.needsDisplay = true
          }
        }
      }
      RunLoop.main.add(timer, forMode: .common)
      animationTimer = timer
    }
    setAccessibilityLabel(L("图像编辑画布"))
    setAccessibilityRole(.image)
  }
  var imageRect: CGRect {
    guard let store else { return .zero }
    let working = store.showRulers ? bounds.insetBy(dx:42,dy:100).offsetBy(dx:12,dy:0) : bounds
    let fit = min(working.width / store.document.width, working.height / store.document.height) * (store.interactionTool == .crop ? 0.82 : 1)
    let w = store.document.width * fit * store.zoom
    let h = store.document.height * fit * store.zoom
    return CGRect(
      x: working.midX - w / 2 + store.pan.width, y: working.midY - h / 2 + store.pan.height, width: w,
      height: h)
  }
  func refreshPointer() {
    guard let window,let content = window.contentView,let parent = content.superview else { return }
    let windowPoint = window.mouseLocationOutsideOfEventStream
    let overCanvas = window.isKeyWindow && content.hitTest(parent.convert(windowPoint,from:nil)) === self
    let current = overCanvas ? convert(windowPoint,from:nil) : nil
    if pointer != current { pointer = current;hoverPoint = current.map(documentPoint);needsDisplay = true }
    if overCanvas, !panning {
      let signature = "\(store?.interactionTool.rawValue ?? "")/\(store?.branch.id ?? "")/\(String(describing:store?.foreground))/\(spaceHeld)/\(store?.interactionTool == .crop ? String(describing:hoverPoint) : "")"
      if cursorSignature != signature {
        cursorSignature = signature
        (spaceHeld || store?.interactionTool == .hand ? NSCursor.openHand : store?.interactionTool == .text ? .iBeam : store?.interactionTool == .move ? .arrow : toolCursor).set()
      }
    } else { cursorSignature = nil }
  }
  var scale: Double { max(0.0001, imageRect.width / (store?.document.width ?? 1)) }
  func documentPoint(_ p: CGPoint) -> CGPoint {
    CGPoint(x: (p.x - imageRect.minX) / scale, y: (p.y - imageRect.minY) / scale)
  }
  func localPoint(_ p: CGPoint, layer: ImageLayer) -> CGPoint {
    let dx = p.x - layer.x - layer.width / 2
    let dy = p.y - layer.y - layer.height / 2
    let a = -layer.rotation * .pi / 180
    return CGPoint(
      x: dx * cos(a) - dy * sin(a) + layer.width / 2,
      y: dx * sin(a) + dy * cos(a) + layer.height / 2)
  }
  func objectTransform(_ layer: ImageLayer, _ ctx: CGContext) {
    ctx.translateBy(x: layer.x + layer.width / 2, y: layer.y + layer.height / 2)
    ctx.rotate(by: layer.rotation * .pi / 180)
    ctx.scaleBy(x: layer.flippedX == true ? -1 : 1, y: layer.flippedY == true ? -1 : 1)
    ctx.translateBy(x: -layer.width / 2, y: -layer.height / 2)
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let store, let ctx = NSGraphicsContext.current?.cgContext else { return }
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    let rect = imageRect
    ctx.saveGState()
    if store.roundedCanvas {
      ctx.addPath(CGPath(roundedRect: rect, cornerWidth: min(24, rect.width / 2), cornerHeight: min(24, rect.height / 2), transform: nil))
      ctx.clip()
    } else {
      ctx.clip(to: rect)
    }
    ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
    ctx.fill(rect)
    let tile = 14.0
    let columns = min(300, Int(ceil(rect.width / tile)))
    let rows = min(300, Int(ceil(rect.height / tile)))
    ctx.setFillColor(NSColor.secondaryLabelColor.withAlphaComponent(0.09).cgColor)
    if columns > 0 && rows > 0 {
      for x in 0..<columns {
        for y in 0..<rows where (x + y).isMultiple(of: 2) {
          ctx.fill(
            CGRect(
              x: rect.minX + Double(x) * tile, y: rect.minY + Double(y) * tile, width: tile,
              height: tile))
        }
      }
    }
    ctx.translateBy(x: rect.minX, y: rect.minY)
    ctx.scaleBy(x: scale, y: scale)
    let drawingDocument = store.document
    var drawingPreviews = store.layerPreviews
    if let compositorStroke, let preview = compositorStroke.preview(store: store) { drawingPreviews[compositorStroke.layer.id] = preview }
    if textEditor != nil,let layer = store.selected,layer.kind == .text,
      let preview = store.renderer.previewLayer(layer,assets:store.active.assets,scale:min(1,1200/max(layer.width,layer.height))) {
      drawingPreviews[layer.id] = preview
    }
    if compositorStroke != nil || textEditor != nil || store.document.layers.contains(where: { $0.kind == .group || $0.kind == .adjustment || $0.blend.requiresCI || $0.quad != nil || $0.clippingMask }) {
      let key = (store.document.id,store.revision,store.previewRevision)
      if compositorStroke != nil || textEditor != nil || compositeKey == nil || compositeKey!.0 != key.0 || compositeKey!.1 != key.1 || compositeKey!.2 != key.2 {
        compositeImage = store.renderer.composite(drawingDocument, previews: drawingPreviews, assets: store.active.assets, scale: min(1,1200/max(store.document.width,store.document.height)))
        compositeKey = key
      }
      if let image = compositeImage {
        ImageRenderer.draw(image, in: CGRect(x: 0, y: 0, width: store.document.width, height: store.document.height), context: ctx)
      }
    } else if store.layerPreviews.isEmpty, let image = store.preview {
      ImageRenderer.draw(
        image, in: CGRect(x: 0, y: 0, width: store.document.width, height: store.document.height),
        context: ctx)
    } else {
      for layer in store.document.layers.reversed()
      where layer.kind != .group && store.document.isVisible(layer) {
        guard let preview = drawingPreviews[layer.id] else { continue }
        ctx.saveGState()
        ctx.setAlpha(store.document.effectiveOpacity(layer))
        ctx.setBlendMode(layer.blend.cg)
        objectTransform(layer, ctx)
        // A preview carries the geometry used when it was rendered. Never apply a new
        // effect's padding to an older image while the next GPU render is in flight.
        let sx = layer.width / preview.contentSize.width
        let sy = layer.height / preview.contentSize.height
        let extent = preview.extent.applying(CGAffineTransform(scaleX: sx, y: sy))
        ImageRenderer.draw(preview.image, in: extent, context: ctx)
        ctx.restoreGState()
      }
    }
    if let pending = compositorStroke ?? healingStroke,let overlay = pending.coverageImage() {
      ctx.saveGState();objectTransform(pending.layer,ctx)
      ImageRenderer.draw(overlay,in:CGRect(x:0,y:0,width:pending.layer.width,height:pending.layer.height),context:ctx)
      ctx.restoreGState()
    }
    if let stroke, let layer = store.selected {
      ctx.saveGState()
      objectTransform(layer, ctx)
      var display = stroke
      if display.erasing {
        display.erasing = false
        display.color = RGBA(r: 0.8, g: 0.8, b: 0.8, a: 0.5)
      }
      ImageRenderer.drawStroke(display, context: ctx)
      ctx.restoreGState()
    }
    if store.interactionTool == .shape, let draft {
      ctx.saveGState()
      ctx.setFillColor(store.foreground.ns.cgColor)
      ctx.setStrokeColor(store.foreground.ns.cgColor)
      let name = store.branch.id == "custom" ? store.customShape : store.branch.id
      if name == "line" {
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.move(to: draft.points[0].cg)
        ctx.addLine(to: draft.points[1].cg)
        ctx.strokePath()
      } else {
        ctx.addPath(ShapeGeometry.path(name, rect: draft.bounds, sides: store.shapeSides))
        ctx.drawPath(using: ["ring", "crescent"].contains(name) ? .eoFill : .fill)
      }
      ctx.restoreGState()
    }
    if store.editingMask, store.maskOverlay, let layer = store.selected {
      if maskOverlayLayer != layer {
        maskOverlayLayer = layer
        maskOverlayImage = store.renderer.renderMask(layer, assets: store.active.assets, scale: min(1,900/max(layer.width,layer.height)))
      }
      if let mask = maskOverlayImage {
        ctx.saveGState(); objectTransform(layer, ctx)
        ImageRenderer.draw(mask, in: CGRect(x: 0, y: 0, width: layer.width, height: layer.height), context: ctx)
        ctx.restoreGState()
      }
    }
    if store.showGrid {
      ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.12).cgColor)
      ctx.setLineWidth(0.5 / scale)
      let step = max(16 / scale, 100.0)
      var x = 0.0
      while x < store.document.width {
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: store.document.height))
        x += step
      }
      var y = 0.0
      while y < store.document.height {
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: store.document.width, y: y))
        y += step
      }
      ctx.strokePath()
    }
    if store.showRulers {
      for measurement in store.rulerMeasurements where rulerEditingBefore?.id != measurement.id {drawMeasurement(measurement, context:ctx)}
      if let rulerDraft {drawMeasurement(rulerDraft,context:ctx)}
    }
    if !store.snapGuides.isEmpty {
      ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.5).cgColor);ctx.setLineWidth(0.75/scale);ctx.setLineDash(phase:0,lengths:[4/scale,3/scale])
      for guide in store.snapGuides {
        if guide.axis == 0 { ctx.move(to:CGPoint(x:guide.position,y:0));ctx.addLine(to:CGPoint(x:guide.position,y:store.document.height)) }
        else { ctx.move(to:CGPoint(x:0,y:guide.position));ctx.addLine(to:CGPoint(x:store.document.width,y:guide.position)) }
      };ctx.strokePath();ctx.setLineDash(phase:0,lengths:[])
    }
    // Crop controls extend into the workspace so expanding the canvas remains reachable.
    ctx.restoreGState();ctx.saveGState()
    ctx.translateBy(x:rect.minX,y:rect.minY);ctx.scaleBy(x:scale,y:scale)
    if store.interactionTool == .crop, let region = draft ?? store.selection {
      ctx.setFillColor(NSColor.black.withAlphaComponent(0.48).cgColor)
      ctx.addRect(CGRect(x:-rect.minX/scale,y:-rect.minY/scale,width:bounds.width/scale,height:bounds.height/scale))
      ctx.addRect(region.bounds)
      ctx.drawPath(using: .eoFill)
      ctx.setStrokeColor(NSColor.white.cgColor)
      ctx.setLineWidth(1 / scale)
      ctx.stroke(region.bounds)
      for i in 1...2 {
        let x = region.bounds.minX + region.bounds.width * Double(i) / 3
        let y = region.bounds.minY + region.bounds.height * Double(i) / 3
        ctx.move(to: CGPoint(x: x, y: region.bounds.minY))
        ctx.addLine(to: CGPoint(x: x, y: region.bounds.maxY))
        ctx.move(to: CGPoint(x: region.bounds.minX, y: y))
        ctx.addLine(to: CGPoint(x: region.bounds.maxX, y: y))
      }
      ctx.strokePath()
      drawHandles(region.bounds, ctx)
    } else if store.refiningSelection, let selection = store.selection {
      let colors: [String: NSColor] = ["red": .systemRed, "yellow": .systemYellow, "black": .black, "white": .white]
      if overlaySelection != selection || overlayColor != store.refineOverlay {
        overlaySelection = selection;overlayColor = store.refineOverlay
        if let mask = SelectionEngine.mask(selection,size:CGSize(width:store.document.width,height:store.document.height),maxSize:900) {
          let ci = CIImage(cgImage:mask).applyingFilter("CIColorInvert")
          let color = RGBA(colors[store.refineOverlay] ?? .systemRed)
          let tinted = ci.applyingFilter("CIColorMatrix",parameters:[
            "inputRVector":CIVector(x:color.r*0.48,y:0,z:0,w:0),
            "inputGVector":CIVector(x:color.g*0.48,y:0,z:0,w:0),
            "inputBVector":CIVector(x:color.b*0.48,y:0,z:0,w:0),
            "inputAVector":CIVector(x:0.48,y:0,z:0,w:0)])
          overlayImage = store.renderer.context.createCGImage(tinted,from:ci.extent)
        }
      }
      if let overlayImage { ImageRenderer.draw(overlayImage,in:CGRect(x:0,y:0,width:store.document.width,height:store.document.height),context:ctx) }
    } else if let region = draft ?? store.selection, store.interactionTool != .shape {
      ctx.setLineWidth(1.4 / scale)
      ctx.setStrokeColor(NSColor.white.cgColor)
      ctx.addPath(region.path)
      ctx.strokePath()
      ctx.setLineDash(phase: antsPhase / scale, lengths: [5 / scale, 5 / scale])
      ctx.setStrokeColor(NSColor.black.cgColor)
      ctx.addPath(region.path)
      ctx.strokePath()
      ctx.setLineDash(phase: 0, lengths: [])
    }
    if !penAnchors.isEmpty {
      drawBezier(penAnchors, closed:false, context:ctx)
      if let end = penAnchors.last, let hoverPoint {
        ctx.move(to:end.point.cg); ctx.addLine(to:hoverPoint); ctx.setLineDash(phase:0,lengths:[3/scale,3/scale]); ctx.strokePath(); ctx.setLineDash(phase:0,lengths:[])
      }
    }
    if store.interactionTool == .path, let layer = store.selected, let anchors = layer.bezierAnchors, penAnchors.isEmpty {
      ctx.saveGState(); objectTransform(layer,ctx)
      drawBezier(anchors.map { a in a.mapped { Point(x:$0.x*layer.width,y:$0.y*layer.height) } },closed:layer.pathClosed == true,context:ctx)
      ctx.restoreGState()
    }
    if pathPoints.count > 0 {
      ctx.setStrokeColor(accentNSColor.cgColor)
      ctx.setLineWidth(2 / scale)
      if store.interactionTool == .path,store.branch.id == "freePath" {
        ctx.addPath(BezierGeometry.path(BezierGeometry.freehand(pathPoints,spacing:max(1,3/scale)),closed:false));ctx.strokePath()
      } else {
        ctx.move(to:pathPoints[0].cg)
        for p in pathPoints.dropFirst() {ctx.addLine(to:p.cg)}
        if let hoverPoint {ctx.addLine(to:hoverPoint)};ctx.strokePath()
        ctx.setFillColor(NSColor.white.cgColor)
        for p in pathPoints {ctx.fillEllipse(in:CGRect(x:p.x-3/scale,y:p.y-3/scale,width:6/scale,height:6/scale))}
      }
    }
    ctx.restoreGState()
    if store.interactionTool == .move,store.selectedIDs.count > 1,let selectionBounds = store.selectedContentBounds {
      ctx.saveGState();ctx.translateBy(x:rect.minX,y:rect.minY);ctx.scaleBy(x:scale,y:scale)
      ctx.setStrokeColor(accentNSColor.cgColor);ctx.setLineWidth(1/scale)
      ctx.stroke(selectionBounds);ctx.restoreGState()
    } else if store.interactionTool == .move, let layer = store.selected, layer.kind != .group {
      ctx.saveGState()
      ctx.translateBy(x: rect.minX, y: rect.minY)
      ctx.scaleBy(x: scale, y: scale)
      ctx.translateBy(x: layer.x + layer.width / 2, y: layer.y + layer.height / 2)
      ctx.rotate(by: layer.rotation * .pi / 180)
      ctx.translateBy(x: -layer.width / 2, y: -layer.height / 2)
      ctx.setStrokeColor(accentNSColor.cgColor)
      ctx.setLineWidth(1 / scale)
      let positions = TransformGeometry.displayHandles(layer)
      ctx.move(to:CGPoint(x:positions[0].x*layer.width,y:positions[0].y*layer.height))
      for i in [2,4,6] { ctx.addLine(to:CGPoint(x:positions[i].x*layer.width,y:positions[i].y*layer.height)) }
      ctx.closePath();ctx.strokePath()
      for p in positions {
        let r = CGRect(x:p.x*layer.width-4/scale,y:p.y*layer.height-4/scale,width:8/scale,height:8/scale)
        ctx.fill(r);ctx.stroke(r)
      }
      if store.transformActive, store.transformMode == .warp {
        let nodes = layer.warpNodes ?? TransformGeometry.denseWarpGrid
        let dimension = max(2, Int(Double(nodes.count).squareRoot().rounded()))
        func meshPoint(_ p: Point) -> CGPoint {
          let mapped = layer.quad.flatMap {ProjectiveMap($0)}?.destination(p) ?? p
          return CGPoint(x:(layer.flippedX == true ? 1-mapped.x : mapped.x)*layer.width,y:(layer.flippedY == true ? 1-mapped.y : mapped.y)*layer.height)
        }
        func strokeSmooth(_ line: [Point]) {
          guard let first = line.first else { return }
          ctx.move(to: meshPoint(first))
          for i in 1..<line.count {
            let previous = line[i - 1], current = line[i]
            let before = i > 1 ? line[i - 2] : Point(x:2*previous.x-current.x,y:2*previous.y-current.y)
            let after = i + 1 < line.count ? line[i + 1] : Point(x:2*current.x-previous.x,y:2*current.y-previous.y)
            let c1 = Point(x: previous.x + (current.x - before.x) / 6, y: previous.y + (current.y - before.y) / 6)
            let c2 = Point(x: current.x - (after.x - previous.x) / 6, y: current.y - (after.y - previous.y) / 6)
            ctx.addCurve(to: meshPoint(current), control1: meshPoint(c1), control2: meshPoint(c2))
          }
          ctx.strokePath()
        }
        for row in 0..<dimension where row * dimension < nodes.count {
          strokeSmooth((0..<dimension).compactMap { col in
            let i = row * dimension + col
            return i < nodes.count ? nodes[i] : nil
          })
        }
        for col in 0..<dimension where col < nodes.count {
          strokeSmooth((0..<dimension).compactMap { row in
            let i = row * dimension + col
            return i < nodes.count ? nodes[i] : nil
          })
        }
        for node in nodes {let p = meshPoint(node);ctx.fillEllipse(in:CGRect(x:p.x-4/scale,y:p.y-4/scale,width:8/scale,height:8/scale))}
      }
      ctx.move(to: CGPoint(x: layer.width / 2, y: 0))
      ctx.addLine(to: CGPoint(x: layer.width / 2, y: -24 / scale))
      ctx.strokePath()
      ctx.setFillColor(NSColor.white.cgColor)
      ctx.fillEllipse(
        in: CGRect(
          x: layer.width / 2 - 4 / scale, y: -28 / scale, width: 8 / scale, height: 8 / scale))
      ctx.strokeEllipse(
        in: CGRect(
          x: layer.width / 2 - 4 / scale, y: -28 / scale, width: 8 / scale, height: 8 / scale))
      ctx.restoreGState()
    }
    if store.interactionTool == .fill, let layer = store.selected, let gradient = layer.gradient {
      ctx.saveGState(); ctx.translateBy(x: rect.minX,y:rect.minY); ctx.scaleBy(x:scale,y:scale); objectTransform(layer,ctx)
      for node in gradient.canvasNodes {
        let p = CGPoint(x:node.point.x*layer.width,y:node.point.y*layer.height)
        ctx.setFillColor(node.color.ns.cgColor); ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2/scale)
        let r = CGRect(x:p.x-6/scale,y:p.y-6/scale,width:12/scale,height:12/scale)
        ctx.fillEllipse(in:r); ctx.strokeEllipse(in:r)
      }
      ctx.restoreGState()
    }
    drawWorkspaceRulers(ctx)
    drawToolCursor(ctx)
  }
  func drawBezier(_ anchors:[BezierAnchor], closed:Bool, context ctx:CGContext) {
    ctx.setStrokeColor(accentNSColor.cgColor); ctx.setLineWidth(1.5/scale)
    ctx.addPath(BezierGeometry.path(anchors,closed:closed)); ctx.strokePath()
    for anchor in anchors {
      for h in [anchor.incoming,anchor.outgoing].compactMap({$0}) {
        ctx.move(to:anchor.point.cg);ctx.addLine(to:h.cg);ctx.strokePath()
        ctx.setFillColor(NSColor.white.cgColor);let r = CGRect(x:h.x-3/scale,y:h.y-3/scale,width:6/scale,height:6/scale)
        ctx.fillEllipse(in:r);ctx.strokeEllipse(in:r)
      }
      ctx.setFillColor(accentNSColor.cgColor)
      ctx.fill(CGRect(x:anchor.point.x-3/scale,y:anchor.point.y-3/scale,width:6/scale,height:6/scale))
      if anchor.id == selectedPenAnchor?.anchor {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(CGRect(x:anchor.point.x-4/scale,y:anchor.point.y-4/scale,width:8/scale,height:8/scale))
        ctx.setStrokeColor(accentNSColor.cgColor)
      }
    }
  }
  func drawToolCursor(_ ctx: CGContext) {
    guard let pointer, let store, !spaceHeld else { return }
    if !CanvasColorSampling.shared.active && (store.refiningSelection || [.brush, .eraser, .retouch, .clone, .dodge, .detail].contains(store.interactionTool)
      || (store.interactionTool == .selection && store.branch.id == "smart")) {
      let size = (store.refiningSelection ? store.refineBrushSize : store.brushSize) * scale
      let width = max(2, size), height = max(2, size * store.brushDynamics.roundness)
      ctx.saveGState(); ctx.translateBy(x: pointer.x, y: pointer.y)
      ctx.rotate(by: store.brushDynamics.angle * .pi/180)
      let r = CGRect(x: -width/2, y: -height/2, width: width, height: height)
      ctx.setLineWidth(2.5); ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor); ctx.strokeEllipse(in: r)
      ctx.setLineWidth(1); ctx.setStrokeColor(NSColor.white.cgColor); ctx.strokeEllipse(in: r)
      ctx.move(to: CGPoint(x: -3, y: 0)); ctx.addLine(to: CGPoint(x: 3, y: 0))
      ctx.move(to: CGPoint(x: 0, y: -3)); ctx.addLine(to: CGPoint(x: 0, y: 3)); ctx.strokePath()
      ctx.restoreGState()
    }
    if CanvasColorSampling.shared.active || store.interactionTool == .eyedropper || (store.interactionTool == .selection && store.branch.id == "colorRange"), let image = store.preview {
      let p = documentPoint(pointer)
      guard let sample = CanvasPixelSample.read(image,point:p,canvas:CGSize(width:store.document.width,height:store.document.height)) else {return}
      let x = sample.x,y = sample.y
      let sideX = min(11,image.width),sideY = min(11,image.height)
      let source = CGRect(x:min(max(0,x-5),image.width-sideX),y:min(max(0,y-5),image.height-sideY),width:sideX,height:sideY)
      if let crop = image.cropping(to: source) {
        let r = CGRect(x:min(max(8,pointer.x+18),bounds.width-116),y:min(max(8,pointer.y-96),bounds.height-132),width:88,height:88)
        ctx.saveGState(); ctx.addEllipse(in: r); ctx.clip(); ctx.interpolationQuality = .none
        ImageRenderer.draw(crop, in: r, context: ctx)
        let pixel = CGRect(x:r.minX+(Double(x)-source.minX)*r.width/source.width,y:r.minY+(Double(y)-source.minY)*r.height/source.height,width:r.width/source.width,height:r.height/source.height)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor);ctx.setLineWidth(2.5);ctx.stroke(pixel)
        ctx.setStrokeColor(NSColor.white.cgColor);ctx.setLineWidth(1);ctx.stroke(pixel)
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(3); ctx.strokeEllipse(in: r)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor);ctx.setLineWidth(0.5);ctx.strokeEllipse(in:r)
        let badge = CGRect(x:r.minX-8,y:r.maxY+6,width:108,height:27)
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor)
        ctx.addPath(CGPath(roundedRect:badge,cornerWidth:7,cornerHeight:7,transform:nil));ctx.fillPath()
        ctx.setFillColor(sample.color.ns.cgColor);ctx.fill(CGRect(x:badge.minX+8,y:badge.minY+7,width:13,height:13))
        sample.hex.draw(at:CGPoint(x:badge.minX+27,y:badge.minY+6),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.labelColor])
      }
    }
  }
  func drawHandles(_ rect: CGRect, _ ctx: CGContext) {
    ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(accentNSColor.cgColor)
    ctx.setLineWidth(1 / scale)
    for (x, y) in TransformGeometry.handles {
      let r = CGRect(
        x: rect.minX + x * rect.width - 4 / scale, y: rect.minY + y * rect.height - 4 / scale,
        width: 8 / scale, height: 8 / scale)
      ctx.fill(r)
      ctx.stroke(r)
    }
  }
  override func resetCursorRects() {
    addCursorRect(
      bounds,
      cursor: spaceHeld || store?.interactionTool == .hand
        ? .openHand : store?.interactionTool == .text ? .iBeam : store?.interactionTool == .move ? .arrow : toolCursor)
  }
  var cropCursor: NSCursor {
    guard let store,let point = hoverPoint,let region = draft ?? store.selection,region.type == "crop" else {return .crosshair}
    if let i = CTCropGeometry.handle(at:point,in:region.bounds,scale:scale) {
      if i == 1 || i == 5 {return .resizeUpDown}
      if i == 3 || i == 7 {return .resizeLeftRight}
      return ToolCursors.cropResize(diagonal:i == 0 || i == 4)
    }
    return region.bounds.contains(point) ? .openHand : .crosshair
  }
  var toolCursor: NSCursor {
    if CanvasColorSampling.shared.active || store?.interactionTool == .eyedropper {return .arrow}
    let name: String
    switch store?.interactionTool {
    case .zoom: name = "magnifyingglass"
    case .eyedropper: name = "eyedropper"
    case .fill:
      // A super-gradient is a preset layer operation; keep the normal arrow cursor
      // instead of implying that the canvas is waiting for a colour drag.
      if store?.branch.id == "mesh" { return .arrow }
      if ["bucket", "solid"].contains(store?.branch.id ?? "") {
        return ToolCursors.drop(store?.foreground ?? RGBA())
      }
      return .crosshair
    case .path: return ToolCursors.pen
    case .crop: return cropCursor
    default: return .crosshair
    }
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return .crosshair }
    image.size = NSSize(width: 18, height: 18)
    return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: 16))
  }
  func layerContains(_ layer: ImageLayer, point p: CGPoint) -> Bool {
    guard let store else {return false}
    if layer.kind == .group {
      let ids = store.descendants(of: [layer.id])
      return store.document.layers.contains {$0.kind != .group && ids.contains($0.id) && store.document.isVisible($0) && layerContains($0, point:p)}
    }
    let local = TransformGeometry.contentPoint(p, layer: layer)
    guard CGRect(x:0,y:0,width:layer.width,height:layer.height).contains(local) else {return false}
    if layer.isPath {return store.pathSamples(layer).contains {hypot($0.x-p.x,$0.y-p.y)*scale < 8}}
    if hitBitmapRevision != store.previewRevision {hitBitmaps = [:];hitBitmapRevision = store.previewRevision}
    guard let preview = store.layerPreviews[layer.id] else {
      return layer.kind != .paint || !layer.strokes.isEmpty
    }
    let bitmap = hitBitmaps[layer.id] ?? NSBitmapImageRep(cgImage: preview.image)
    hitBitmaps[layer.id] = bitmap
    let x = Int((local.x-preview.extent.minX)/preview.extent.width*Double(bitmap.pixelsWide))
    let y = Int((local.y-preview.extent.minY)/preview.extent.height*Double(bitmap.pixelsHigh))
    guard x>=0,y>=0,x<bitmap.pixelsWide,y<bitmap.pixelsHigh else {return false}
    return (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.03
  }
  func hit(_ p: CGPoint) -> ImageLayer? {
    store?.document.layers.first {layer in
      layer.kind != .group && layer.kind != .adjustment && store?.document.isVisible(layer) == true && layerContains(layer,point:p)
    }
  }
  func modifierMode(_ event: NSEvent) -> String {
    event.modifierFlags.contains(.shift)
      ? (event.modifierFlags.contains(.option) ? "intersect" : "add")
      : event.modifierFlags.contains(.option) ? "subtract" : store?.selectionMode ?? "new"
  }
  override func mouseDown(with event: NSEvent) {
    guard let store else { return }
    if CanvasColorSampling.shared.active {
      paletteSampleClick = true
      let p = documentPoint(convert(event.locationInWindow,from:nil))
      if let color = store.sampleColor(p) {CanvasColorSampling.shared.commit(color);window?.invalidateCursorRects(for:self)}
      needsDisplay = true;return
    }
    if textEditor != nil {finishTextEditing()}
    window?.makeFirstResponder(self)
    startView = convert(event.locationInWindow, from: nil)
    start = documentPoint(startView)
    last = start
    shapeStart = start
    startPan = store.pan
    didExtract = false
    pixelPoints = [start]
    lastSmudgeUpdate = 0
    moveOriginals = []; gestureMoved = false; pendingInspectorClick = false
    initialLayer = store.selected
    handle = nil
    rotating = false
    movingSelection = false
    cropBefore = nil
    movingCrop = false
    pointer = startView
    gradientDrag = nil
    warpDrag = nil
    if let pathID = store.retouchPathID, let target = hit(start), target.id != pathID {
      if store.interactionTool == .retouch {store.applyRetouchPath(to: target.id);needsDisplay = true;return}
    }
    if !store.rulerMode,event.clickCount > 1,let layer = hit(start),layer.kind == .text {
      if store.compositorToolID != nil {compositorProject = store.document.id}
      store.selectLayer(layer.id);store.textEditingLayerID = layer.id;syncTextEditor();return
    }
    if store.rulerMode {
      let p = CGPoint(x: min(store.document.width, max(0, start.x)), y: min(store.document.height, max(0, start.y)))
      rulerEditingBefore = store.rulerMeasurements.last(where: {$0.locked != true && $0.distance(to:p)*scale < 9})
      if let old = rulerEditingBefore {store.selectedRulerID = old.id; rulerDraft = old}
      else {store.selectedRulerID = nil; rulerDraft = RulerMeasurement(start: Point(p), end: Point(p), tool: store.activeRulerTool)}
      needsDisplay = true
      return
    }
    if store.interactionTool == .fill, let layer = store.selected, let nodes = layer.gradient?.canvasNodes {
      let p = localPoint(start,layer:layer)
      if let node = nodes.first(where:{ hypot($0.point.x*layer.width-p.x,$0.point.y*layer.height-p.y)*scale < 12 }) {
        gradientDrag = node.id; store.gradientPoint = node.id; store.beginTransaction("移动渐变节点"); return
      }
    }
    if !store.layerPanelPinned { store.showLayers = false }
    panning = spaceHeld || store.interactionTool == .hand
    if panning {
      NSCursor.closedHand.set()
      return
    }
    guard imageRect.contains(startView) || [.move,.crop,.path,.brush,.eraser,.retouch].contains(store.interactionTool) else {
      store.clearCanvasFocus()
      return
    }
    if store.refiningSelection { return }
    if [.brush,.eraser].contains(store.interactionTool), event.modifierFlags.contains(.option) {
      if let color = store.sampleColor(start) {store.foreground = color}
      pixelPoints = [];return
    }
    if beginCompositorGesture(event) { needsDisplay = true; return }
    switch store.interactionTool {
    case .brush, .eraser:
      if store.selected == nil || store.selected?.kind == .group { store.addLayer(.paint) }
      guard let layer = store.selected, !layer.locked else { return }
      let begin = event.modifierFlags.contains(.shift) ? (lastPaintEndpoint ?? start) : start
      if event.modifierFlags.contains(.shift) {start = begin}
      stroke = BrushStroke(
        points: [Point(TransformGeometry.contentPoint(begin,layer:layer)),Point(TransformGeometry.contentPoint(documentPoint(convert(event.locationInWindow,from:nil)),layer:layer))], color: store.foreground,
        size: store.brushSize, opacity: store.brushOpacity * store.brushFlow,
        hardness: store.brushHardness, erasing: store.interactionTool == .eraser, clip: nil,
        dynamics: store.brushDynamics,
        pressures: [Double(event.pressure) > 0 ? Double(event.pressure) : 1])
      if let selection = store.selection {
        stroke?.clip = store.localSelection(selection, layer: layer)
      }
    case .move:
      if event.modifierFlags.contains(.shift),!store.transformActive {
        if let direct = hit(start) {store.toggleLayerSelection(store.rootGroup(for:direct).id)}
        handle = nil;rotating = false;initialLayer = nil;pendingInspectorClick = false
        needsDisplay = true;return
      }
      if let layer = store.selected, !layer.locked,store.selectedIDs.count == 1 {
        let p = localPoint(start, layer: layer)
        if store.transformActive, store.transformMode == .warp {
          let nodes = layer.warpNodes ?? TransformGeometry.denseWarpGrid
          let warpedPoint = TransformGeometry.deformationPoint(start,layer:layer)
          warpDrag = nodes.indices.first { hypot((warpedPoint.x-nodes[$0].x)*layer.width,(warpedPoint.y-nodes[$0].y)*layer.height)*scale < 12 }
          if warpDrag != nil { store.beginTransformGesture("变形");return }
        }
        let positions = TransformGeometry.displayHandles(layer)
        handle = positions.indices.first { i in
          let h = positions[i]
          return hypot(p.x - layer.width * h.x, p.y - layer.height * h.y) * scale < 11
        }
        rotating = hypot(p.x - layer.width / 2, p.y + 24 / scale) * scale < 12
        if store.transformActive, store.transformMode == .rotate, handle != nil { rotating = true;handle = nil }
        rotationStart = atan2(
          start.y - layer.y - layer.height / 2, start.x - layer.x - layer.width / 2)
      }
      if handle == nil && !rotating, let selection = store.selection,
        SelectionEngine.contains(
          selection, point: start,
          canvas: CGSize(width: store.document.width, height: store.document.height)),
        store.selected?.locked != true
      {
        movingSelection = true
        return
      }
      if handle == nil && !rotating {
        let direct = hit(start)
        if event.modifierFlags.contains(.shift), let direct {
          store.toggleLayerSelection(store.rootGroup(for: direct).id)
        } else if event.clickCount > 1, let direct {
          store.selectLayer(direct.id, revealInspector: false)
        } else if let direct,store.selectedIDs.contains(direct.id) || store.selectedIDs.contains(store.rootGroup(for:direct).id) {
          // Dragging any selected object keeps the complete selection intact.
        } else if let selected = store.selected, layerContains(selected, point:start) {
          // Keep the explicit selection, even when another layer overlaps it.
        } else if let direct {
          let target = store.rootGroup(for: direct)
          store.selectLayer(target.id, revealInspector: false)
        } else {store.clearCanvasFocus()}
        pendingInspectorClick = store.selected != nil
      }
      initialLayer = store.selected
      let moving = store.descendants(of: store.selectedIDs)
      moveOriginals = store.document.layers.filter {moving.contains($0.id)}
      if store.selected?.locked != true {
        store.beginTransformGesture(handle != nil ? "缩放对象" : rotating ? "旋转对象" : "移动对象")
      }
    case .selection:
      if let selection = store.selection,
        SelectionEngine.contains(
          selection, point: start,
          canvas: CGSize(width: store.document.width, height: store.document.height)),
        store.selectionMode == "new", !event.modifierFlags.contains(.shift),
        !event.modifierFlags.contains(.option),
        !["colorRange", "smart", "polygonLasso"].contains(store.branch.id)
      {
        movingSelection = true
        return
      }
      if ["smart", "colorRange"].contains(store.branch.id) {
        if store.branch.id == "colorRange" { store.colorRangeSample = start }
        store.selectColor(at: start, contiguous: store.branch.id != "colorRange", mode: modifierMode(event))
      } else if store.branch.id == "polygonLasso" {
        let close = pathPoints.count > 2 && pathPoints.first.map { hypot($0.x-start.x, $0.y-start.y)*scale < 10 } == true
        if !close { pathPoints.append(Point(start)) }
        if (close || event.clickCount > 1) && pathPoints.count > 2 {
          store.applySelection(
            SelectionRegion(type: "lasso", points: pathPoints), mode: modifierMode(event))
          pathPoints = []
        }
      } else {
        draft = SelectionRegion(type: store.branch.id, points: [Point(start), Point(start)])
      }
    case .crop:
      if let region = store.selection, region.type == "crop" {
        handle = TransformGeometry.handles.indices.first { i in
          let h = TransformGeometry.handles[i]
          return hypot(
            start.x - region.bounds.minX - region.bounds.width * h.0,
            start.y - region.bounds.minY - region.bounds.height * h.1) * scale < 12
        }
        if handle != nil || region.bounds.contains(start) {
          cropBefore = region
          draft = region
          movingCrop = handle == nil
          return
        }
      }
      draft = SelectionRegion(type: "crop", points: [Point(start), Point(start)])
    case .shape:
      draft = SelectionRegion(type: store.branch.id, points: [Point(start), Point(start)])
    case .text:
      if let layer = hit(start), layer.kind == .text {
        store.selectLayer(layer.id)
        store.showInspector = true
        if event.clickCount > 1 { store.textEditingLayerID = layer.id }
      } else {
        store.addLayer(.text, at: start)
        store.textEditingLayerID = store.selected?.id
        syncTextEditor()
        store.showInspector = true
      }
    case .zoom: zoom(event.modifierFlags.contains(.option) ? 0.8 : 1.25, anchor: startView)
    case .eyedropper: if let color = store.sampleColor(start) {store.foreground = color;store.notify("颜色已取样")}
    case .fill:
      if ["linear", "radial", "mesh"].contains(store.branch.id) {
        if store.branch.id == "mesh" {
          // Selecting the tool creates its editable layer. Empty canvas clicks
          // only select/edit nodes and must never create additional layers.
          needsDisplay = true
          return
        }
        draft = SelectionRegion(type: "lasso", points: [Point(start), Point(start)])
      } else { store.fill(at: start) }
    case .clone:
      if event.modifierFlags.contains(.option) {
        store.cloneSource = start
        store.notify("已设置仿制来源")
      }
    case .retouch, .dodge, .detail:
      if ["stamp","heal"].contains(store.branch.id), event.modifierFlags.contains(.option) {
        store.cloneSource = start; store.notify("已设置仿制来源")
      }
    case .gradient: draft = SelectionRegion(type: "lasso", points: [Point(start), Point(start)])
    case .path:
      if store.branch.id == "freePath" { pathPoints = [Point(start)] }
      else {
        penEdit = nil; penDrag = nil; pendingPenEdit = nil; finishPenOnUp = false;penPointer = start
        if !penAnchors.isEmpty {
          outer: for (i,a) in penAnchors.enumerated() {
            for (part,p) in [a.point,a.incoming,a.outgoing].enumerated() {
              if let p,hypot(p.x-start.x,p.y-start.y)*scale<9 {
                if i == 0 && part == 0 && penAnchors.count>2 && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) {break outer}
                savePenUndo();pendingPenEdit = (i,part)
                if part == 0,event.modifierFlags.contains(.option) {BezierGeometry.toggleSmooth(&penAnchors,index:i,closed:false)}
                needsDisplay = true;return
              }
            }
          }
        }
        if penAnchors.isEmpty, let layer = store.selected, let anchors = layer.bezierAnchors {
          let p = TransformGeometry.contentPoint(start,layer:layer)
          outer: for (i,a) in anchors.enumerated() {
            for (j,h) in [a.point,a.incoming,a.outgoing].enumerated() {
              if let h, hypot(h.x*layer.width-p.x,h.y*layer.height-p.y)*scale < 10 {
                penEdit = (i,j); store.beginTransaction("编辑路径节点"); break outer
              }
            }
          }
          if let (i,part) = penEdit {
            selectedPenAnchor = (layer.id,anchors[i].id)
            if part == 0, event.clickCount > 1 {
              store.updateSelected("切换路径节点类型") { l in
                guard var nodes = l.bezierAnchors else { return }
                BezierGeometry.toggleSmooth(&nodes,index:i,closed:l.pathClosed == true)
                l.bezierAnchors = nodes
              }
              penEdit = nil;store.endTransaction()
            }
            needsDisplay = true;return
          }
        }
        selectedPenAnchor = nil
        if penAnchors.count > 2, let first = penAnchors.first,
          hypot(first.point.x-start.x,first.point.y-start.y)*scale < 10 {
          store.createBezierPath(penAnchors,closed:true);resetPenDraft();return
        }
        let anchorPoint = event.modifierFlags.contains(.shift) && !penAnchors.isEmpty
          ? TransformGeometry.constrained(start,around:penAnchors.last!.point.cg) : start
        savePenUndo()
        penAnchors.append(BezierAnchor(point:Point(anchorPoint)))
        publishPenHistory()
        penDrag = penAnchors.count-1
        finishPenOnUp = event.clickCount > 1 && penAnchors.count > 1
      }
    case .hand, .canvas: break
    }
    needsDisplay = true
  }
  override func mouseDragged(with event: NSEvent) {
    guard let store else { return }
    let viewPoint = convert(event.locationInWindow, from: nil)
    var point = documentPoint(viewPoint)
    let canPaint = [.brush,.eraser,.retouch,.clone,.dodge,.detail].contains(store.interactionTool)
    if canPaint, event.modifierFlags.contains(.shift) {point = TransformGeometry.constrained(point,around:start)}
    if hypot(point.x-start.x,point.y-start.y)*scale > 3 {gestureMoved = true}
    pointer = viewPoint
    if store.interactionTool == .eyedropper {if let color = store.sampleColor(point) {store.foreground = color};needsDisplay = true;return}
    if dragCompositorGesture(event, point: point) { last = point; needsDisplay = true; return }
    if store.rulerMode {
      let p = CGPoint(x: min(store.document.width, max(0, point.x)), y: min(store.document.height, max(0, point.y)))
      if let before = rulerEditingBefore {
        guard before.locked != true else {return}
        let dx = p.x-start.x, dy = p.y-start.y
        var draft = before
        draft.start = Point(x:before.start.x+dx,y:before.start.y+dy);draft.end = Point(x:before.end.x+dx,y:before.end.y+dy)
        rulerDraft = draft
      } else if var draft = rulerDraft {
        draft.end = Point(event.modifierFlags.contains(.shift) ? TransformGeometry.constrained(p,around:draft.start.cg) : p)
        rulerDraft = draft
      }
      needsDisplay = true
      return
    }
    if store.interactionTool == .path, store.branch.id == "pen" {
      if let (index,part) = penEdit, let layer = store.selected {
        let p = TransformGeometry.contentPoint(point,layer:layer)
        store.updateSelected("编辑路径节点") { l in
          guard var anchors = l.bezierAnchors, anchors.indices.contains(index) else { return }
          let normalized = Point(x:p.x/l.width,y:p.y/l.height)
          if part == 0 {
            let dx = normalized.x-anchors[index].point.x, dy = normalized.y-anchors[index].point.y
            anchors[index] = anchors[index].mapped { Point(x:$0.x+dx,y:$0.y+dy) }
          } else {
            // Constrain in content pixels so non-square layer bounds do not distort angles.
            var pixelAnchor = anchors[index].mapped { Point(x:$0.x*l.width,y:$0.y*l.height) }
            pixelAnchor.moveHandle(to:p,incoming:part == 1,independent:event.modifierFlags.contains(.option),constrained:event.modifierFlags.contains(.shift))
            anchors[index] = pixelAnchor.mapped { Point(x:$0.x/l.width,y:$0.y/l.height) }
          }
          l.bezierAnchors = anchors
        }
      } else if let (i,part) = pendingPenEdit,penAnchors.indices.contains(i) {
        if part == 0 || spaceHeld {
          let dx = point.x-penPointer.x,dy = point.y-penPointer.y
          penAnchors[i] = penAnchors[i].mapped {Point(x:$0.x+dx,y:$0.y+dy)}
        } else {penAnchors[i].moveHandle(to:point,incoming:part == 1,independent:event.modifierFlags.contains(.option),constrained:event.modifierFlags.contains(.shift))}
      } else if let i = penDrag, penAnchors.indices.contains(i) {
        if spaceHeld {
          let dx = point.x-penPointer.x,dy = point.y-penPointer.y
          penAnchors[i] = penAnchors[i].mapped {Point(x:$0.x+dx,y:$0.y+dy)}
        } else {penAnchors[i].moveHandle(to:point,incoming:false,independent:event.modifierFlags.contains(.option),constrained:event.modifierFlags.contains(.shift))}
      }
      penPointer = point
      needsDisplay = true; return
    }
    if let gradientDrag, let layer = store.selected {
      let p = localPoint(point,layer:layer)
      store.updateSelected("移动渐变节点") { l in
        let point = Point(x:p.x/layer.width,y:p.y/layer.height)
        if l.gradient?.style == "mesh" {
          if let i = l.gradient?.nodes.firstIndex(where:{$0.id == gradientDrag}) { l.gradient?.nodes[i].point = point }
        } else if l.gradient?.nodes.first?.id == gradientDrag { l.gradient?.axisStart = point }
        else { l.gradient?.axisEnd = point }
      }
      return
    }
    if store.refiningSelection {
      pixelPoints.append(point); needsDisplay = true; return
    }
    if panning {
      store.pan = CGSize(
        width: startPan.width + viewPoint.x - startView.x,
        height: startPan.height + viewPoint.y - startView.y)
      return
    }
    if var stroke, let layer = store.selected {
      let p = TransformGeometry.contentPoint(point,layer:layer)
      if let previous = stroke.points.last, hypot(p.x - previous.x, p.y - previous.y) > 0.5 {
        let pressure = event.pressure > 0 ? Double(event.pressure) : 1
        if event.modifierFlags.contains(.shift), let first = stroke.points.first {
          // Constrained straight brush strokes: keep one clean segment
          // from the first point to the current pointer location.
          stroke.points = [first, Point(p)]
          stroke.pressures = [stroke.pressures?.first ?? 1, pressure]
        } else {
          stroke.points.append(Point(p))
          stroke.pressures?.append(pressure)
        }
        self.stroke = stroke
      }
    } else if store.interactionTool == .move, !movingSelection, let layer = initialLayer, !layer.locked {
      let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
      var proposed = layer; proposed.x += delta.x;proposed.y += delta.y
      let snapped = store.snappedPosition(proposed,scale:scale)
      if handle == nil && !rotating && warpDrag == nil {
        if gestureMoved {store.showInspector = false}
        var delta = CGPoint(x:(event.modifierFlags.contains(.control) ? proposed.x : snapped.x)-layer.x,
          y:(event.modifierFlags.contains(.control) ? proposed.y : snapped.y)-layer.y)
        if event.modifierFlags.contains(.shift) {
          if abs(delta.x)>abs(delta.y) {delta.y = 0} else {delta.x = 0}
        }
        store.moveSelection(from: moveOriginals, delta: delta)
      } else {store.updateSelected("变换对象") { l in
        if let warpDrag {
          let p = TransformGeometry.deformationPoint(point,layer:layer)
          let nodes = layer.warpNodes ?? TransformGeometry.denseWarpGrid
          l.warpNodes = TransformGeometry.dragWarp(nodes,index:warpDrag,to:p)
        } else if let handle, store.transformActive, [.skew,.distort,.perspective].contains(store.transformMode) {
          l = TransformGeometry.deform(layer,handle:handle,delta:delta,mode:store.transformMode)
        } else if let handle {
          l = TransformGeometry.resize(
            layer, handle: handle, delta: delta,
            keepAspect: (layer.aspectLocked ?? false) != event.modifierFlags.contains(.shift),
            fromCenter: event.modifierFlags.contains(.option))
        } else if rotating {
          let angle = atan2(
            point.y - layer.y - layer.height / 2, point.x - layer.x - layer.width / 2)
          let v = layer.rotation + (angle - rotationStart) * 180 / .pi
          l.rotation = event.modifierFlags.contains(.shift) ? (v / 15).rounded() * 15 : v
        } else {
          l.x = event.modifierFlags.contains(.control) ? proposed.x : snapped.x
          l.y = event.modifierFlags.contains(.control) ? proposed.y : snapped.y
        }
      }}
    } else if movingSelection {
      if !didExtract {
        didExtract = true
        store.beginTransaction("移动选区内容")
        _ = store.extractSelection(cut: true)
        initialLayer = store.selected
        store.deselect()
      }
      if let layer = initialLayer {
        store.updateSelected("移动选区内容") {
          $0.x = layer.x + point.x - start.x
          $0.y = layer.y + point.y - start.y
        }
      }
    } else if var region = draft {
      if spaceHeld && [.shape, .selection, .crop].contains(store.interactionTool) {
        let dx = point.x - last.x
        let dy = point.y - last.y
        shapeStart.x += dx
        shapeStart.y += dy
        region.points = region.points.map { Point(x: $0.x + dx, y: $0.y + dy) }
        if store.interactionTool == .shape, !event.modifierFlags.contains(.control) {
          var shape = ImageLayer(name:"",kind:.shape,width:max(1,region.bounds.width),height:max(1,region.bounds.height))
          shape.x = region.bounds.minX;shape.y = region.bounds.minY
          let snapped = store.snappedPosition(shape,scale:scale)
          let delta = CGPoint(x:snapped.x-shape.x,y:snapped.y-shape.y)
          shapeStart.x += delta.x;shapeStart.y += delta.y
          region.points = region.points.map {Point(x:$0.x+delta.x,y:$0.y+delta.y)}
        }
      } else if store.interactionTool == .crop, movingCrop, let before = cropBefore {
        let dx = min(store.document.width-before.bounds.maxX, max(-before.bounds.minX, point.x-start.x))
        let dy = min(store.document.height-before.bounds.maxY, max(-before.bounds.minY, point.y-start.y))
        region.points = before.points.map { Point(x: $0.x+dx, y: $0.y+dy) }
      } else if store.interactionTool == .crop, let before = cropBefore, let handle {
        var l = ImageLayer(
          name: "", kind: .shape, width: before.bounds.width, height: before.bounds.height)
        l.x = before.bounds.minX
        l.y = before.bounds.minY
        l = TransformGeometry.resize(
          l, handle: handle, delta: CGPoint(x: point.x - start.x, y: point.y - start.y),
          keepAspect: store.cropRatio != "free")
        region.points = [Point(x: l.x, y: l.y), Point(x: l.x + l.width, y: l.y + l.height)]
      } else if region.type == "lasso" && store.interactionTool == .selection {
        region.points.append(Point(point))
      } else {
        var end = [.shape,.crop].contains(store.interactionTool) && !event.modifierFlags.contains(.control) ? store.snappedPoint(point,scale:scale) : point
        var ratio = event.modifierFlags.contains(.shift) ? 1.0 : 0.0
        if store.interactionTool == .shape, store.branch.id == "line", event.modifierFlags.contains(.shift) {
          end = TransformGeometry.constrained(end,around:shapeStart)
          ratio = 0
        }
        if store.interactionTool == .crop, store.cropRatio != "free" {
          let parts = store.cropRatio.split(separator: ":").compactMap { Double($0) }
          if parts.count == 2 { ratio = parts[0] / parts[1] }
        }
        if ratio > 0 {
          let dx = end.x - shapeStart.x
          let dy = end.y - shapeStart.y
          end.y = shapeStart.y + (dy < 0 ? -1 : 1) * abs(dx) / ratio
        }
        let origin =
          event.modifierFlags.contains(.option) && store.interactionTool == .shape
          ? CGPoint(
            x: shapeStart.x - (end.x - shapeStart.x), y: shapeStart.y - (end.y - shapeStart.y))
          : shapeStart
        region.points = [Point(origin), Point(end)]
      }
      draft = region
    } else if store.interactionTool == .selection && store.branch.id == "smart"
      && hypot(point.x - last.x, point.y - last.y) * scale > 8
    {
      store.selectColor(
        at: point, contiguous: true,
        mode: event.modifierFlags.contains(.option) ? "subtract" : "add")
    } else if store.interactionTool == .path && store.branch.id == "freePath" {
      pathPoints.append(Point(point))
    }
    if [.clone, .retouch, .dodge, .detail].contains(store.interactionTool) {
      if store.branch.id == "smudge", let previous = pixelPoints.last, hypot(point.x-previous.x,point.y-previous.y)>1 {
        store.beginTransaction("涂抹")
        if event.modifierFlags.contains(.shift), let first = pixelPoints.first {
          pixelPoints = [first, point]
        } else {
          pixelPoints.append(point)
        }
        if event.timestamp-lastSmudgeUpdate>=1.0/30 {
          store.applyPixelBrush(points:pixelPoints);pixelPoints = [point];lastSmudgeUpdate = event.timestamp
        }
      } else if event.modifierFlags.contains(.shift), let first = pixelPoints.first {
        pixelPoints = [first, point]
      } else { pixelPoints.append(point) }
    }
    last = point
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    if paletteSampleClick {paletteSampleClick = false;needsDisplay = true;return}
    guard let store else { return }
    store.snapGuides = []
    if store.compositorToolID != nil,!panning {
      _ = dragCompositorGesture(event,point:documentPoint(convert(event.locationInWindow,from:nil)))
    }
    if finishCompositorGesture(event) { needsDisplay = true; return }
    if store.rulerMode {
      if let measurement = rulerDraft, measurement.length > 0.5 {
        if rulerEditingBefore != nil {store.updateRulerMeasurement(measurement)} else {store.addRulerMeasurement(measurement)}
        store.selectedRulerID = measurement.id;store.showRulers = true
      }
      rulerDraft = nil; rulerEditingBefore = nil
      needsDisplay = true
      return
    }
    if store.interactionTool == .path, store.branch.id == "pen" {
      if finishPenOnUp { store.createBezierPath(penAnchors,closed:false);resetPenDraft() }
      penDrag = nil;penEdit = nil;pendingPenEdit = nil;publishPenHistory();store.endTransaction();needsDisplay = true;return
    }
    if gradientDrag != nil { gradientDrag = nil; store.endTransaction(); return }
    if store.refiningSelection {
      store.refineSelectionBrush(pixelPoints)
      return
    }
    if let stroke {
      lastPaintEndpoint = stroke.points.last.map {p in store.selected.map {TransformGeometry.displayPoint(p.cg,layer:$0)} ?? p.cg}
      if store.editingMask { store.appendMaskStroke(stroke) } else { store.appendStroke(stroke) }
      // Publish the finished stroke's preview before the asynchronous renderer swaps
      // the cache. This keeps the last painted frame on screen and removes the
      // one-frame flash visible at the end of every brush/eraser gesture.
      if !store.editingMask, let layer = store.selected {
        store.layerPreviews[layer.id] = store.renderer.previewLayer(
          layer, assets: store.active.assets,
          scale: min(1, 1200 / max(layer.width, layer.height)))
      }
      self.stroke = nil
    }
    if let region = draft,
      (region.bounds.width > 1 && region.bounds.height > 1)
        || ((store.interactionTool == .gradient || store.interactionTool == .fill || (store.interactionTool == .shape && store.branch.id == "line")) && hypot(region.bounds.width, region.bounds.height) > 1)
    {
      if store.interactionTool == .shape {
        store.beginTransaction("绘制形状")
        var bounds = region.bounds
        if store.branch.id == "line" { bounds = bounds.insetBy(dx:-2,dy:-2) }
        bounds.size.width = max(1, bounds.width); bounds.size.height = max(1, bounds.height)
        store.addLayer(.shape, rect: bounds)
        if store.branch.id == "line" {
          store.updateSelected("绘制直线") { l in
            l.vectorPoints = region.points.map {
              Point(
                x: ($0.x - bounds.minX) / bounds.width,
                y: ($0.y - bounds.minY) / bounds.height)
            }
          }
        }
      } else if store.interactionTool == .selection {
        store.applySelection(region, mode: modifierMode(event))
      } else if store.interactionTool == .crop {
        store.selection = region
      } else if store.interactionTool == .gradient || store.interactionTool == .fill {
        store.drawGradient(
          from: start, to: documentPoint(convert(event.locationInWindow, from: nil)))
      }
    }
    if [.clone, .retouch, .dodge, .detail].contains(store.interactionTool), !panning,
      !((store.interactionTool == .clone || ["stamp","heal"].contains(store.branch.id)) && event.modifierFlags.contains(.option))
    {
      store.applyPixelBrush(points: pixelPoints)
    }
    if store.interactionTool == .path && store.branch.id == "freePath" {
      store.createPath(pathPoints)
      pathPoints = []
    }
    if store.interactionTool == .selection, modifierMode(event) == "new", !movingSelection,
      !["smart", "colorRange", "polygonLasso"].contains(store.branch.id),
      hypot(last.x-start.x, last.y-start.y)*scale < 3 {
      store.deselect()
    }
    if store.interactionTool == .shape, let layer = store.selected {
      // Publish this cheap vector render immediately so the live draft does not disappear for one frame.
      store.layerPreviews[layer.id] = store.renderer.previewLayer(layer, assets: store.active.assets, scale: min(1, 1200/max(layer.width, layer.height)))
    }
    if store.interactionTool == .move, pendingInspectorClick, !gestureMoved, store.selected != nil {store.showInspector = true}
    moveOriginals = []; pendingInspectorClick = false
    draft = nil
    initialLayer = nil
    handle = nil
    movingSelection = false
    store.endTransaction()
    needsDisplay = true
  }
  func zoom(_ factor: Double, anchor: CGPoint) {
    guard let store else { return }
    let before = documentPoint(anchor)
    store.zoomCanvas(factor)
    let after = documentPoint(anchor)
    store.pan.width += (after.x - before.x) * scale
    store.pan.height += (after.y - before.y) * scale
  }
  override func scrollWheel(with event: NSEvent) {
    if event.modifierFlags.contains(.shift) {
      store?.pan.width -= event.scrollingDeltaY
      store?.pan.height -= event.scrollingDeltaX
    } else {
      zoom(exp(event.scrollingDeltaY * 0.012), anchor: convert(event.locationInWindow, from: nil))
    }
  }
  override func magnify(with event: NSEvent) {
    zoom(1 + event.magnification, anchor: convert(event.locationInWindow, from: nil))
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53,CanvasColorSampling.shared.active {CanvasColorSampling.shared.cancel();window?.invalidateCursorRects(for:self);needsDisplay = true;return}
    guard let store else { return }
    if event.keyCode == 49 {
      spaceHeld = true
      window?.invalidateCursorRects(for: self)
      return
    }
    if store.rulerMode {
      if event.keyCode == 53 {store.cancelRulerMode()}
      else if event.keyCode == 36 {store.finishRulerMode()}
      else if event.keyCode == 51 || event.keyCode == 117 {store.deleteSelectedRulerMeasurement()}
      else if event.modifierFlags.contains(.command) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": if event.modifierFlags.contains(.shift) {store.redo()} else {store.undo()}
        case "c":store.copySelectedLayer()
        case "v":store.pasteLayer()
        case "0":store.fitCanvas()
        case "1":store.actualPixels()
        case "+", "=":store.zoomCanvas(1.2)
        case "-":store.zoomCanvas(1/1.2)
        default:break
        }
      }
      needsDisplay = true;return
    }
    if event.keyCode == 53 {
      cancelCompositorGesture()
      draft = nil
      pathPoints = []
      resetPenDraft(); penDrag = nil; penEdit = nil
      selectedPenAnchor = nil
      if store.refiningSelection { store.finishRefinement(cancel: true); return }
      store.deselect()
      if store.rulerMode { store.cancelRulerMode() }
      store.finishTransform(cancel: true)
      store.showTools = false
      needsDisplay = true
      return
    }
    if event.keyCode == 36 && event.modifierFlags.contains([.command,.shift]) {store.pathToSelection();return}
    if event.keyCode == 36 {
      if store.interactionTool == .crop { store.cropToSelection() }
      if store.interactionTool == .path {
        if store.branch.id == "pen" { store.createBezierPath(penAnchors,closed:event.modifierFlags.contains(.shift)); resetPenDraft() }
        else { store.createPath(pathPoints); pathPoints = [] }
        needsDisplay = true
      }
      store.finishTransform()
      return
    }
    if event.keyCode == 51 {
    if store.rulerMode, !store.rulerMeasurements.isEmpty { store.deleteSelectedRulerMeasurement(); needsDisplay = true; return }
    if store.interactionTool == .path, !penAnchors.isEmpty { savePenUndo();penAnchors.removeLast();publishPenHistory();needsDisplay = true;return }
      if store.interactionTool == .path, let selectedPenAnchor, let layer = store.selected,
        selectedPenAnchor.layer == layer.id, let nodes = layer.bezierAnchors,
        let index = nodes.firstIndex(where:{$0.id == selectedPenAnchor.anchor}) {
        guard nodes.count > 2 else { store.notify("路径至少保留两个节点");return }
        store.updateSelected("删除路径节点") { $0.bezierAnchors?.remove(at:index) }
        let remaining = store.selected?.bezierAnchors
        self.selectedPenAnchor = remaining?.first.map { (layer.id,$0.id) }
        needsDisplay = true;return
      }
      if store.interactionTool == .selection, store.branch.id == "polygonLasso", !pathPoints.isEmpty { pathPoints.removeLast();needsDisplay = true;return }
      if store.selection != nil {
        store.deleteSelection()
      } else if let layer = store.selected, !layer.locked {
        store.deleteLayer(layer.id)
      }
      return
    }
    if event.modifierFlags.contains(.command) {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "t": store.beginTransform()
      case "j": store.extractSelection(cut:event.modifierFlags.contains(.shift))
      case "g":
        if event.modifierFlags.contains(.option),let id = store.selected?.id {store.toggleClippingMask(id)}
        else if event.modifierFlags.contains(.shift),let id = store.selected?.id,store.selected?.kind == .group {store.ungroup(id)}
        else {store.groupSelected()}
      case "[", "]":store.reorderSelected(up:event.charactersIgnoringModifiers == "]",edge:event.modifierFlags.contains(.shift))
      case "0":store.fitCanvas()
      case "1":store.actualPixels()
      case "a": store.selectAll()
      case "d": store.deselect()
      case "i": if event.modifierFlags.contains(.shift) {store.invertSelection()}
      case "z": if event.modifierFlags.contains(.shift) {store.redo()} else {store.undo()}
      case "c": if event.modifierFlags.contains(.option) == false { store.copySelectedLayer() }
      case "v": if event.modifierFlags.contains(.option) == false { store.pasteLayer() }
      case "+", "=": store.zoomCanvas(1.2)
      case "-": store.zoomCanvas(1 / 1.2)
      default: super.keyDown(with: event)
      }
      return
    }
    if [123, 124, 125, 126].contains(Int(event.keyCode)) {
      let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
      store.updateSelected("微调位置") { l in
        if event.keyCode == 123 { l.x -= step }
        if event.keyCode == 124 { l.x += step }
        if event.keyCode == 125 { l.y += step }
        if event.keyCode == 126 { l.y -= step }
      }
      return
    }
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if store.selectToolShortcut(key,cycle:event.modifierFlags.contains(.shift)) { return }
    if let digit = Int(key), (0...9).contains(digit) {
      let value = Double(digit == 0 ? 10 : digit)/10
      if event.modifierFlags.contains(.shift) {store.brushFlow = value} else {store.brushOpacity = value}
      return
    }
    switch key {
    case "x": swap(&store.foreground,&store.secondaryColor); if store.editingMask { store.maskReveal.toggle() }
    case "d": store.foreground = RGBA(r:0,g:0,b:0);store.secondaryColor = RGBA(r:1,g:1,b:1)
    case "[", "]", "{", "}":
      let negative = key == "[" || key == "{"
      if event.modifierFlags.contains(.shift) {
        store.brushHardness = min(1,max(0,store.brushHardness+(negative ? -0.1 : 0.1)))
      } else { store.brushSize = min(1000,max(1,store.brushSize+(negative ? -5 : 5))) }
    default: super.keyDown(with:event)
    }
  }
  override func keyUp(with event: NSEvent) {
    if event.keyCode == 49 {
      spaceHeld = false
      window?.invalidateCursorRects(for: self)
    } else {
      super.keyUp(with: event)
    }
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    guard let store else { return nil }
    let p = documentPoint(convert(event.locationInWindow, from: nil))
    if !store.rulerMode,!store.transformActive, let layer = hit(p),!store.selectedIDs.contains(layer.id) { store.selectLayer(layer.id) }
    let menu = NSMenu()
    func add(_ name: String, _ action: String) {
      let item = NSMenuItem(title: L(name), action: #selector(contextAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action
      menu.addItem(item)
    }
    if store.showRulers || store.rulerMode {
      let units = NSMenu()
      for (title, unit) in [("像素（px）", "px"), ("毫米（mm）", "mm"), ("厘米（cm）", "cm"), ("英寸（in）", "in")] {
        let item = NSMenuItem(title: L(title), action: #selector(contextAction(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = "rulerUnit:" + unit
        item.state = store.rulerUnit == unit ? .on : .off
        units.addItem(item)
      }
      let rulerItem = NSMenuItem(title: L("标尺单位"), action: nil, keyEquivalent: "")
      rulerItem.submenu = units; menu.addItem(rulerItem)
      menu.addItem(.separator())
    }
    if store.rulerMode {
      if let selected = store.rulerMeasurements.last(where: {$0.distance(to:p)*scale < 10}) {store.selectedRulerID = selected.id}
      if let selected = store.rulerMeasurements.first(where: {$0.id == store.selectedRulerID}) {
        add(selected.locked == true ? "解锁辅助线" : "锁定辅助线", "lockRuler")
        if selected.locked != true {add("删除选中标尺", "deleteRuler")}
      }
      return menu
    }
    if store.transformActive {
      for mode in TransformMode.allCases { add(mode == .scale ? "transform.scale" : mode.rawValue,"mode:"+mode.rawValue) }
      let gridMenu = NSMenu()
      for n in [3,5,7,9] {
        let item = NSMenuItem(title:L("{0} × {1} 分段", n-1, n-1),action:#selector(contextAction(_:)),keyEquivalent:"")
        item.target = self;item.representedObject = "warpGrid:\(n)"
        gridMenu.addItem(item)
      }
      let gridItem = NSMenuItem(title:L("变形网格"),action:nil,keyEquivalent:"")
      gridItem.submenu = gridMenu;menu.addItem(gridItem)
      menu.addItem(.separator())
      add("水平翻转","flipX");add("垂直翻转","flipY")
      menu.addItem(.separator());add("应用变换","applyTransform");add("取消变换","cancelTransform")
      return menu
    }
    if store.selectedIDs.count > 1 {
      add("编组", "group");add("合并选中图层", "mergeSelected")
      menu.addItem(.separator());add("删除选中图层","deleteMulti")
      return menu
    }
    if store.interactionTool == .path, !penAnchors.isEmpty {
      add("完成路径", "finishPath"); add("闭合路径", "closePath"); return menu
    }
    if store.selected?.bezierAnchors != nil || store.selected?.vectorPoints != nil {
      add("路径转选区", "pathSelection");add("画笔描边路径", "strokePath");add("修饰工具沿路径", "retouchPath")
      if store.selected?.isPath == true {add("填充路径", "fillPath");add("用于下方图层蒙版", "pathMask")}
      menu.addItem(.separator())
    }
    add("自由变换   ⌘T", "transform")
    add("复制到新图层   ⌘J", "copy")
    menu.addItem(.separator())
    add("水平翻转", "flipX")
    add("垂直翻转", "flipY")
    add("顺时针旋转 90°", "rotate90")
    add("逆时针旋转 90°", "rotate-90")
    add("旋转 180°", "rotate180")
    menu.addItem(.separator())
    add("添加蒙版", "mask")
    let shapeMasks = NSMenu()
    for shape in ShapePreset.all {
      let item = NSMenuItem(
        title: L(shape.name), action: #selector(contextAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = "maskShape:" + shape.id
      shapeMasks.addItem(item)
    }
    let shapeItem = NSMenuItem(title: L("形状蒙版"), action: nil, keyEquivalent: "")
    shapeItem.submenu = shapeMasks
    menu.addItem(shapeItem)
    add("添加效果…", "effects")
    if let layer = store.selected, layer.kind != .group {
      add(layer.kind == .text ? "复制文字" : "提取图片文字", layer.kind == .text ? "extractText" : "extractImageText")
    }
    add("转换为普通图层", "raster")
    add("合并下方所有图层", "merge")
    if store.selectedIDs.count > 1 {add("合并选中图层", "mergeSelected")}
    menu.addItem(.separator())
    add("锁定 / 解锁", "lock")
    add("删除选区或图层", "delete")
    let layers = NSMenu()
    for layer in store.document.layers where layer.kind != .group && store.document.isVisible(layer)
    {
      let item = NSMenuItem(
        title: layer.name, action: #selector(contextAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = layer.id
      layers.addItem(item)
    }
    let item = NSMenuItem(title: L("选择图层"), action: nil, keyEquivalent: "")
    item.submenu = layers
    menu.addItem(item)
    return menu
  }
  @objc func contextAction(_ sender: NSMenuItem) {
    guard let store else { return }
    if let id = sender.representedObject as? UUID {
      store.selectLayer(id)
      return
    }
    if let action = sender.representedObject as? String, action.hasPrefix("warpGrid:"),
      let n = Int(action.dropFirst(9)) {
      store.updateSelected("调整变形网格") {
        $0.warpNodes = TransformGeometry.resampleWarp($0.warpNodes ?? TransformGeometry.denseWarpGrid,dimension:n)
      }
      store.transformMode = .warp; needsDisplay = true;return
    }
    if let action = sender.representedObject as? String, action.hasPrefix("mode:"), let mode = TransformMode(rawValue:String(action.dropFirst(5))) {
      store.transformMode = mode;needsDisplay = true;return
    }
    if let action = sender.representedObject as? String, action.hasPrefix("maskShape:") {
      store.addMaskSelected(String(action.dropFirst(10)))
      return
    }
    if let action = sender.representedObject as? String, action.hasPrefix("rulerUnit:") {
      store.setRulerUnit(String(action.dropFirst("rulerUnit:".count)))
      needsDisplay = true
      return
    }
    switch sender.representedObject as? String {
    case "deleteRuler": store.deleteSelectedRulerMeasurement();needsDisplay = true
    case "applyTransform": store.finishTransform()
    case "cancelTransform": store.finishTransform(cancel:true)
    case "finishPath": store.createBezierPath(penAnchors,closed:false);resetPenDraft()
    case "closePath": store.createBezierPath(penAnchors,closed:true);resetPenDraft()
    case "transform": store.beginTransform()
    case "copy": store.extractSelection()
    case "flipX": store.flipSelected(horizontal: true)
    case "flipY": store.flipSelected(horizontal: false)
    case "rotate90": store.rotateSelected(90)
    case "rotate-90": store.rotateSelected(-90)
    case "rotate180": store.rotateSelected(180)
    case "mask": store.addMaskSelected()
    case "effects": store.showEffects = true
    case "extractText": store.extractTextFromSelected()
    case "extractImageText": store.extractImageText()
    case "raster": store.rasterizeSelected()
    case "pathSelection":store.pathToSelection()
    case "strokePath":store.strokePath()
    case "retouchPath":store.beginPathRetouch()
    case "fillPath":store.fillPath()
    case "pathMask":store.pathAsMask()
    case "lockRuler": store.toggleRulerLock()
    case "deleteMulti": store.deleteSelectedLayers()
    case "group": store.groupSelected()
    case "merge": if let id = store.selected?.id { store.mergeDownAll(id) }
    case "mergeSelected": store.mergeSelectedLayers()
    case "lock": if let id = store.selected?.id { store.toggleLock(id) }
    case "delete":
      if store.selection != nil {
        store.deleteSelection()
      } else if let id = store.selected?.id {
        store.deleteLayer(id)
      }
    default: break
    }
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard
      let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil)
        as? [URL], let store
    else { return false }
    for url in urls { store.open(url, asLayer: true) }
    return true
  }
}
