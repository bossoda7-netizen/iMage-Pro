import AppKit
import CoreImage
import XCTest
@testable import ImagePro

final class Debug3Tests:XCTestCase {
  let renderer = ImageRenderer()
  func image(_ width:Int = 96,_ height:Int = 64,_ draw:(CGContext)->Void) throws -> CGImage {
    let c = try XCTUnwrap(ImageRenderer.bitmap(width,height));draw(c);return try XCTUnwrap(c.makeImage())
  }
  func color(_ ci:CIImage,_ x:Int,_ y:Int) throws -> NSColor {
    let cg = try XCTUnwrap(renderer.context.createCGImage(ci,from:ci.extent))
    return try XCTUnwrap(NSBitmapImageRep(cgImage:cg).colorAt(x:x,y:y))
  }
  func testDenseWarpUsesIntermediateNodesAndIsContinuouslyDifferentiable() throws {
    var nodes = TransformGeometry.warpGrid(7)
    let source = Point(x:1.0/6,y:1.0/6)
    nodes[8].x += 0.15
    XCTAssertEqual(TransformGeometry.warpPoint(source,nodes:nodes).x,source.x+0.15,accuracy:1e-8)
    let forward = TransformGeometry.warpPoint(Point(x:0.2,y:0.3),nodes:nodes)
    let backward = try XCTUnwrap(TransformGeometry.warpSource(forward,nodes:nodes))
    XCTAssertEqual(backward.x,0.2,accuracy:1e-6);XCTAssertEqual(backward.y,0.3,accuracy:1e-6)
    let h = 0.00001,x = 1.0/6,y = 0.22
    let left = (TransformGeometry.warpPoint(Point(x:x,y:y),nodes:nodes).x-TransformGeometry.warpPoint(Point(x:x-h,y:y),nodes:nodes).x)/h
    let right = (TransformGeometry.warpPoint(Point(x:x+h,y:y),nodes:nodes).x-TransformGeometry.warpPoint(Point(x:x,y:y),nodes:nodes).x)/h
    XCTAssertEqual(left,right,accuracy:0.002)
    let base = try image {c in c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:96,height:64));c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:10,y:40,width:16,height:16))}
    let identity = WarpRenderer.apply(CIImage(cgImage:base),nodes:TransformGeometry.warpGrid(7),extent:CGRect(x:0,y:0,width:96,height:64))
    let changed = WarpRenderer.apply(CIImage(cgImage:base),nodes:nodes,extent:CGRect(x:0,y:0,width:96,height:64))
    let a = renderer.context.createCGImage(identity,from:identity.extent),b = renderer.context.createCGImage(changed,from:changed.extent)
    XCTAssertNotEqual(a?.dataProvider?.data as Data?,b?.dataProvider?.data as Data?)
  }
  func testGradientMultipleColorsSeparateOpacityAndAxisRoundTrip() throws {
    var g = GradientDefinition(style:"linear",nodes:[.init(point:.init(x:0,y:0),color:.init(r:1,g:0,b:0),position:0),
      .init(point:.init(x:0.5,y:0),color:.init(r:0,g:1,b:0),position:0.5),.init(point:.init(x:1,y:0),color:.init(r:0,g:0,b:1),position:1)],
      axisStart:.init(x:0,y:0.5),axisEnd:.init(x:1,y:0.5),opacityStops:[.init(position:0,opacity:0),.init(position:1,opacity:1)])
    XCTAssertEqual(g.color(at:0.5).g,1);XCTAssertEqual(g.color(at:0.5).a,0.5)
    g.axisEnd = Point(x:0,y:1)
    XCTAssertEqual(g.location(g.nodes[1]),0.5);XCTAssertEqual(g.canvasNodes.count,2)
    let copy = try JSONDecoder().decode(GradientDefinition.self,from:JSONEncoder().encode(g));XCTAssertEqual(copy,g)
    g.opacityStops = [];XCTAssertEqual(g.color(at:0.5).a,1)
    let cg = GradientRenderer.render(copy,width:96,height:64);XCTAssertEqual(cg.width,96)
  }
  @MainActor func testSolidFillValidationAndMeshSelectionCreatesOnlyOneLayer() throws {
    let store = EditorStore(loadRecovery:false);store.documentForTests(width:96,height:64)
    store.chooseTool(.fill,branch:ToolCategory.fill.branches.first {$0.id == "solid"});store.fill(at:CGPoint(x:20,y:20))
    XCTAssertEqual(store.selected?.kind,.gradient);XCTAssertEqual(store.selected?.gradient?.style,"solid")
    try store.document.validate()
    store.chooseTool(.fill,branch:ToolCategory.fill.branches.first {$0.id == "mesh"})
    let count = store.document.layers.count
    store.chooseTool(.fill,branch:ToolCategory.fill.branches.first {$0.id == "mesh"})
    XCTAssertEqual(store.document.layers.count,count)
    let view = CanvasNSView(frame:CGRect(x:0,y:0,width:96,height:64));view.store = store
    let down = try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:CGPoint(x:40,y:30),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1))
    view.mouseDown(with:down);view.mouseUp(with:down);XCTAssertEqual(store.document.layers.count,count)
  }
  func testSmudgeTransportsColorAlongStrokeInsteadOfBlurringEverything() throws {
    let base = try image {c in c.setFillColor(NSColor.blue.cgColor);c.fill(CGRect(x:0,y:0,width:96,height:64));c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:0,y:0,width:32,height:64))}
    let result = try XCTUnwrap(PixelRetouch.smudge(base,points:[CGPoint(x:28,y:32),CGPoint(x:65,y:32)],radius:10,hardness:1,strength:1))
    let a = NSBitmapImageRep(cgImage:result)
    XCTAssertGreaterThan(try XCTUnwrap(a.colorAt(x:45,y:32)).redComponent,0.4)
    XCTAssertGreaterThan(try XCTUnwrap(a.colorAt(x:45,y:5)).blueComponent,0.95)
  }
  func testHealingRemovesBlemishAndLeavesOutsideStrokeUnchanged() throws {
    let base = try image {c in c.setFillColor(NSColor(calibratedWhite:0.6,alpha:1).cgColor);c.fill(CGRect(x:0,y:0,width:96,height:64));c.setFillColor(NSColor.black.cgColor);c.fillEllipse(in:CGRect(x:45,y:29,width:6,height:6))}
    let healed = try XCTUnwrap(PixelRetouch.heal(base,points:[CGPoint(x:48,y:32)],radius:8,source:nil))
    let result = NSBitmapImageRep(cgImage:healed)
    XCTAssertEqual(try XCTUnwrap(result.colorAt(x:48,y:32)).redComponent,0.6,accuracy:0.06)
    XCTAssertEqual(try XCTUnwrap(result.colorAt(x:5,y:5)).redComponent,try XCTUnwrap(NSBitmapImageRep(cgImage:base).colorAt(x:5,y:5)).redComponent,accuracy:0.001)
  }
  @MainActor func testPenDraftUndoAndRedoDoNotUndoDocumentEdits() {
    let store = EditorStore(loadRecovery:false)
    let view = CanvasNSView();view.store = store;view.installDraftUndo()
    let layers = store.document.layers
    view.savePenUndo();view.penAnchors.append(BezierAnchor(point:.init(x:20,y:20)));view.publishPenHistory()
    view.savePenUndo();view.penAnchors.append(BezierAnchor(point:.init(x:40,y:40)));view.publishPenHistory()
    store.undo();XCTAssertEqual(view.penAnchors.count,1);XCTAssertEqual(store.document.layers,layers)
    store.redo();XCTAssertEqual(view.penAnchors.count,2)
    view.resetPenDraft();XCTAssertFalse(store.canvasCanUndo);XCTAssertFalse(store.canvasCanRedo)
  }
  func testFreehandIsCurvedAndWorldPathCoordinatesMatchTransformedLayer() throws {
    let anchors = BezierGeometry.freehand([.init(x:0,y:0),.init(x:10,y:20),.init(x:20,y:22),.init(x:35,y:5)])
    XCTAssertNotNil(anchors[1].incoming);XCTAssertNotNil(anchors[1].outgoing)
    var layer = ImageLayer(name:"path",kind:.shape,width:100,height:80);layer.rotation = 28;layer.flippedX = true
    layer.quad = [.init(x:0.05,y:0),.init(x:1,y:0.05),.init(x:0.95,y:1),.init(x:0,y:0.9)]
    let p = CGPoint(x:20,y:30),world = TransformGeometry.displayPoint(p,layer:layer),local = TransformGeometry.contentPoint(world,layer:layer)
    XCTAssertEqual(local.x,p.x,accuracy:1e-6);XCTAssertEqual(local.y,p.y,accuracy:1e-6)
  }
  func testCurvesStackChannelsAndChannelSelectionDoesNotChangeRender() throws {
    var e = ImageEffect(.curves);e.set("curve2",0.7);e.set("redCurve2",0.8);e.set("blueCurve2",0.2)
    let base = CIImage(color:CIColor(red:0.5,green:0.5,blue:0.5)).cropped(to:CGRect(x:0,y:0,width:8,height:8))
    let a = try color(renderer.apply(e,to:base,scale:1),3,3)
    XCTAssertGreaterThan(a.redComponent,a.greenComponent);XCTAssertLessThan(a.blueComponent,a.greenComponent)
    e.set("activeChannel",3)
    let b = try color(renderer.apply(e,to:base,scale:1),3,3)
    XCTAssertEqual(a.redComponent,b.redComponent,accuracy:0.001)
    XCTAssertEqual(a.blueComponent,b.blueComponent,accuracy:0.001)
    e.tonalCurves = ["curve":[.init(x:0,y:0),.init(x:0.32,y:0.6),.init(x:1,y:1)]]
    XCTAssertEqual(AdvancedEffects.curveValue(e,prefix:"curve",0.32),0.6,accuracy:1e-8)
  }
  func testAllEffectsProduceFiniteRenderAndNeutralToneDefaults() throws {
    let base = try image {c in c.setFillColor(NSColor.gray.cgColor);c.fill(CGRect(x:10,y:10,width:76,height:44))}
    let ci = CIImage(cgImage:base)
    for kind in EffectKind.allCases {
      let e = ImageEffect(kind),result = renderer.apply(e,to:ci,scale:1)
      XCTAssertFalse(result.extent.isInfinite,kind.rawValue)
      XCTAssertNotNil(renderer.context.createCGImage(result,from:ci.extent),kind.rawValue)
    }
    for kind:EffectKind in [.color,.hue,.selective,.wheels,.levels,.curves,.channels] {
      let value = try color(renderer.apply(ImageEffect(kind),to:ci,scale:1),30,30)
      XCTAssertEqual(value.redComponent,0.5,accuracy:0.03,kind.rawValue)
    }
  }
  func testBeautyLightingStaysInsideFaceAndProtectsEyeArea() throws {
    let base = CIImage(color:CIColor(red:0.4,green:0.3,blue:0.25)).cropped(to:CGRect(x:0,y:0,width:100,height:100))
    let eye = [Point(x:0.4,y:0.42),.init(x:0.48,y:0.42),.init(x:0.48,y:0.47),.init(x:0.4,y:0.47)]
    let f = FaceRegion(contour:[.init(x:0.3,y:0.35),.init(x:0.3,y:0.65),.init(x:0.5,y:0.8),.init(x:0.7,y:0.65),.init(x:0.7,y:0.35)],bounds:CGRect(x:0.25,y:0.2,width:0.5,height:0.6),leftEye:eye,rightEye:[],outerLips:[],innerLips:[],brows:[])
    var e = ImageEffect(.beauty);e.style = "face";e.faces = [f];e.amount = 1;e.set("lighting",1);e.set("brightness",0.15)
    let result = PortraitEffects.beauty(e,image:base)
    XCTAssertEqual(try color(result,5,5).redComponent,0.4,accuracy:0.01)
    XCTAssertGreaterThan(try color(result,50,58).redComponent,0.4)
  }
  func testOCRRecognizesRasterAndCreatesRichText() throws {
    let base = try image(500,160) {c in
      c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:500,height:160))
      c.translateBy(x:0,y:160);c.scaleBy(x:1,y:-1)
      let text = NSAttributedString(string:"Image Pro 2026",attributes:[.font:NSFont.systemFont(ofSize:44),.foregroundColor:NSColor.black])
      NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:true)
      text.draw(at:CGPoint(x:25,y:40));NSGraphicsContext.restoreGraphicsState()
    }
    let result = try ImageTextRecognition.recognize(base,logicalWidth:500)
    XCTAssertTrue(result.string.contains("2026"),result.string)
    XCTAssertNotNil(result.attribute(.font,at:0,effectiveRange:nil))
    let rtf = try result.data(from:NSRange(location:0,length:result.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.rtf])
    XCTAssertGreaterThan(rtf.count,50)
  }
  @MainActor func testMaskDetachReattachAndLayerOrderingAreUndoable() throws {
    let store = EditorStore(loadRecovery:false);store.documentForTests(width:96,height:64)
    store.addLayer(.shape);let target = try XCTUnwrap(store.selected?.id)
    let mask = try image {c in c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:48,height:64))}
    let asset = try store.active.assets.insert(mask)
    store.updateSelected("mask") {$0.maskAssetID = asset}
    let detached = try XCTUnwrap(store.detachMask(target))
    XCTAssertNil(store.document.layers.first {$0.id == target}?.maskAssetID)
    let detachedAsset = store.selected?.assetID
    store.attachLayerAsMask(detached,to:target)
    XCTAssertEqual(store.selected?.maskAssetID,detachedAsset)
    XCTAssertFalse(store.document.layers.contains {$0.id == detached})
    store.undo();XCTAssertTrue(store.document.layers.contains {$0.id == detached})
    XCTAssertEqual(store.inspector,.base)
    store.addLayer(.paint);let first = try XCTUnwrap(store.selected?.id)
    store.moveLayer(first,before:detached,after:true)
    let ids = store.document.layers.map(\.id)
    XCTAssertGreaterThan(try XCTUnwrap(ids.firstIndex(of:first)),try XCTUnwrap(ids.firstIndex(of:detached)))
  }
  func testMaskConversionFollowsWarpPerspectiveAndTransparentPixels() throws {
    let source = try image(96,64) {c in
      c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:48,height:64))
    }
    var target = ImageLayer(name:"Warp",kind:.shape,width:96,height:64)
    target.quad = [Point(x:0.1,y:0),Point(x:0.9,y:0.1),Point(x:1,y:1),Point(x:0,y:0.9)]
    target.warpNodes = TransformGeometry.warpGrid(7);target.warpNodes?[24].x += 0.12
    let mask = try XCTUnwrap(ImageRenderer.alignedMask(source,canvasSize:CGSize(width:96,height:64),target:target,width:96,height:64))
    let bitmap = NSBitmapImageRep(cgImage:mask)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x:10,y:32)).redComponent,0.9)
    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x:45,y:32)).redComponent,0.1)
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x:80,y:32)).alphaComponent,1)
    let grayscale = NSBitmapImageRep(cgImage:try XCTUnwrap(ImageRenderer.opaqueGrayscale(source)))
    XCTAssertEqual(try XCTUnwrap(grayscale.colorAt(x:80,y:32)).redComponent,0)
    XCTAssertEqual(try XCTUnwrap(grayscale.colorAt(x:80,y:32)).alphaComponent,1)
  }
  @MainActor func testLayerReorderAfterGroupKeepsChildrenTogether() throws {
    let store = EditorStore(loadRecovery:false);store.documentForTests(width:96,height:64)
    let group = ImageLayer(name:"Group",kind:.group,width:96,height:64)
    var child = ImageLayer(name:"Child",kind:.paint,width:96,height:64);child.parentID = group.id
    let moving = ImageLayer(name:"Moving",kind:.paint,width:96,height:64)
    store.active.document.layers = [moving,group,child]
    store.moveLayer(moving.id,before:group.id,after:true)
    XCTAssertEqual(store.document.layers.map(\.id),[group.id,child.id,moving.id])
    XCTAssertNil(store.document.layers.last?.parentID)
    store.undo();XCTAssertEqual(store.document.layers.map(\.id),[moving.id,group.id,child.id])
  }
  @MainActor func testNativeLayerRowOwnsMouseAndSupportsSelection() throws {
    let view = LayerDragNSView(frame:CGRect(x:0,y:0,width:220,height:40))
    var count = 0;view.select = {count += 1}
    let event = try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:CGPoint(x:20,y:20),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1))
    XCTAssertFalse(view.mouseDownCanMoveWindow);XCTAssertTrue(view.acceptsFirstMouse(for:event))
    view.mouseDown(with:event);view.mouseUp(with:event);XCTAssertEqual(count,1)
    XCTAssertTrue(view.accessibilityPerformPress());XCTAssertEqual(count,2)
  }
  @MainActor func testNativeLayerDragRoutesHoverDropAndCancelWithoutSystemSession() throws {
    let window = NSWindow(contentRect:CGRect(x:0,y:0,width:300,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false;defer {window.close()}
    let root = NSView(frame:CGRect(x:0,y:0,width:300,height:300));window.contentView = root
    let source = LayerDragNSView(frame:CGRect(x:0,y:200,width:100,height:40)),target = LayerDropNSView(frame:CGRect(x:0,y:80,width:100,height:60))
    root.addSubview(source);root.addSubview(target)
    var began = 0,hovered = 0,dropped = 0,cancelled = 0
    source.begin = {began += 1};source.cancel = {cancelled += 1}
    target.hover = {_ in hovered += 1};target.drop = {dropped += 1};target.priority = 2
    func event(_ type:NSEvent.EventType,_ point:CGPoint)throws->NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    }
    source.mouseDown(with:try event(.leftMouseDown,CGPoint(x:20,y:220)))
    source.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:20,y:100)))
    source.mouseUp(with:try event(.leftMouseUp,CGPoint(x:20,y:100)))
    XCTAssertEqual(began,1);XCTAssertEqual(hovered,1);XCTAssertEqual(dropped,1);XCTAssertEqual(cancelled,0)
    source.mouseDown(with:try event(.leftMouseDown,CGPoint(x:20,y:220)))
    source.mouseDragged(with:try event(.leftMouseDragged,CGPoint(x:280,y:100)))
    source.mouseUp(with:try event(.leftMouseUp,CGPoint(x:280,y:100)))
    XCTAssertEqual(cancelled,1)
  }
  @MainActor func testInlineTextEditingPublishesTextAndCanCancel() throws {
    let store = EditorStore(loadRecovery:false);store.documentForTests(width:400,height:300)
    store.addLayer(.text,at:CGPoint(x:40,y:40))
    let before = try XCTUnwrap(store.selected),view = CanvasNSView(frame:CGRect(x:0,y:0,width:800,height:600))
    let window = NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false;window.contentView = view
    defer {window.close()}
    view.store = store;view.installDraftUndo();store.textEditingLayerID = before.id;view.syncTextEditor()
    let editor = try XCTUnwrap(view.textEditor)
    editor.insertText("Debug3 画布文字",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    XCTAssertEqual(store.selected?.text,"Debug3 画布文字")
    XCTAssertGreaterThan(editor.frame.width,0)
    XCTAssertNotNil(view.textEditor);XCTAssertEqual(view.textBefore?.text,before.text);XCTAssertEqual(view.textProjectID,store.document.id)
    view.finishTextEditing(cancel:true);XCTAssertEqual(store.selected?.text,before.text)
    XCTAssertNil(view.textEditor)
  }
  func testClippingChainUsesBaseAlphaInsteadOfMaskRGB() throws {
    let assets = AssetLibrary()
    var base = ImageLayer(name:"base",kind:.shape,width:48,height:64);base.shape = "rectangle";base.cornerRadius = 0;base.color = .init(r:0,g:1,b:0)
    var first = ImageLayer(name:"clip 1",kind:.shape,width:24,height:64);first.shape = "rectangle";first.cornerRadius = 0;first.color = .init(r:1,g:0,b:0);first.clippingMask = true
    var second = ImageLayer(name:"clip 2",kind:.shape,width:96,height:32);second.shape = "rectangle";second.cornerRadius = 0;second.color = .init(r:0,g:0,b:1);second.clippingMask = true
    var doc = ImageDocument();doc.width = 96;doc.height = 64;doc.layers = [second,first,base]
    let image = try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil)),bitmap = NSBitmapImageRep(cgImage:image)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x:35,y:10)).blueComponent,0.95)
    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x:80,y:10)).alphaComponent,0.01)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x:10,y:50)).redComponent,0.95)
  }
  @MainActor func testSpaceMovesCurrentPenAnchorAndHandlesWithoutPanning() throws {
    let store = EditorStore(loadRecovery:false);store.documentForTests(width:400,height:300);store.chooseTool(.path)
    let view = CanvasNSView(frame:CGRect(x:0,y:0,width:400,height:300));view.store = store
    func mouse(_ type:NSEvent.EventType,_ p:CGPoint)->NSEvent {NSEvent.mouseEvent(with:type,location:p,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
    view.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:100,y:100)))
    view.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:125,y:100)))
    let before = try XCTUnwrap(view.penAnchors.first)
    view.spaceHeld = true
    view.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:140,y:115)))
    let after = try XCTUnwrap(view.penAnchors.first)
    XCTAssertEqual(after.point.x-before.point.x,15,accuracy:0.001)
    XCTAssertEqual(after.point.y-before.point.y,-15,accuracy:0.001)
    XCTAssertEqual(try XCTUnwrap(after.outgoing).x-(try XCTUnwrap(before.outgoing).x),15,accuracy:0.001)
    XCTAssertEqual(store.pan,.zero)
  }
  @MainActor func testFillCursorColorAndPenHotspotAreToolSpecific() {
    XCTAssertEqual(ToolCursors.pen.hotSpot,NSPoint(x:2,y:23))
    let red = ToolCursors.drop(.init(r:1,g:0,b:0)),blue = ToolCursors.drop(.init(r:0,g:0,b:1))
    XCTAssertEqual(red.hotSpot,NSPoint(x:12,y:2));XCTAssertNotEqual(red.image.tiffRepresentation,blue.image.tiffRepresentation)
  }

  @MainActor func testDebug3ProjectRoundTripAndCreateVisualFixture() throws {
    let store = EditorStore(loadRecovery:false);store.documentForTests(width:800,height:600)
    store.active.document.name = "Debug3 验证"
    var background = ImageLayer(name:"背景",kind:.gradient,width:800,height:600)
    background.gradient = GradientDefinition(style:"linear",nodes:[.init(point:.init(x:0,y:0),color:.init(r:0.12,g:0.18,b:0.3),position:0),.init(point:.init(x:1,y:1),color:.init(r:0.5,g:0.65,b:0.8),position:1)],axisStart:.init(x:0,y:0),axisEnd:.init(x:1,y:1))
    var text = ImageLayer(name:"双击编辑文字",kind:.text,width:600,height:110);text.x = 90;text.y = 65;text.text = "双击编辑文字";text.fontSize = 60;text.color = .init(r:1,g:1,b:1)
    var circle = ImageLayer(name:"圆形",kind:.shape,width:180,height:180);circle.x = 130;circle.y = 260;circle.shape = "ellipse";circle.color = .init(r:0.95,g:0.6,b:0.25)
    var square = ImageLayer(name:"方形",kind:.shape,width:180,height:180);square.x = 470;square.y = 260;square.shape = "rectangle";square.color = .init(r:0.45,g:0.9,b:0.75)
    store.active.document.layers = [text,circle,square,background];store.active.document.selectedLayerID = text.id
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("Debug3-UI-\(UUID().uuidString).imgp")
    defer { try? FileManager.default.removeItem(at: file) }
    try store.writeProject(store.active,to:file)
    let restored = try store.loadProject(file)
    XCTAssertEqual(restored.document,store.document)
    XCTAssertNotNil(renderer.render(restored.document,assets:restored.assets,maxDimension:800))
  }

}
private extension EditorStore {
  func documentForTests(width:Double,height:Double) {active.document.layers = [];active.document.width = width;active.document.height = height}
}
