import AppKit
import CoreImage
import XCTest
@testable import ImagePro

final class Debug2RegressionTests: XCTestCase {
  let renderer = ImageRenderer()
  func bitmap(_ ci:CIImage, extent:CGRect? = nil) throws -> NSBitmapImageRep {
    NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.context.createCGImage(ci,from:extent ?? ci.extent)))
  }
  func testProjectiveAndWarpTransformsActuallyRenderAndBakeOnce() throws {
    XCTAssertNotNil(WarpRenderer.kernel,"Warp kernel must compile on the running OS")
    let assets = AssetLibrary()
    var layer = ImageLayer(name:"object",kind:.shape,width:64,height:48)
    layer.shape = "rectangle";layer.cornerRadius = 0;layer.color = .init(r:0.7,g:0.3,b:0.2)
    let plain = try XCTUnwrap(renderer.renderLayer(layer,assets:assets))
    layer.warpNodes = TransformGeometry.warpGrid
    let identity = try XCTUnwrap(renderer.renderLayer(layer,assets:assets))
    let center = try XCTUnwrap(NSBitmapImageRep(cgImage:identity).colorAt(x:32,y:24))
    XCTAssertGreaterThan(center.alphaComponent,0.95)
    layer.warpNodes?[4].x = 0.7
    layer.quad = [.init(x:0.2,y:0),.init(x:1.2,y:0.2),.init(x:0.9,y:1),.init(x:0,y:0.8)]
    layer.rotation = 25;layer.x = 20;layer.y = 35
    let baked = try XCTUnwrap(renderer.bakeLayer(layer,assets:assets))
    XCTAssertGreaterThan(baked.bounds.width,64)
    XCTAssertNotEqual(baked.image.dataProvider?.data as Data?,plain.dataProvider?.data as Data?)
    var doc = ImageDocument();doc.width = 180;doc.height = 150;doc.layers = [layer]
    let before = try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil))
    var pixels = ImageLayer(name:"baked",kind:.raster,width:baked.bounds.width,height:baked.bounds.height)
    pixels.assetID = try assets.insert(baked.image);pixels.x = baked.bounds.minX;pixels.y = baked.bounds.minY
    doc.layers = [pixels]
    let after = try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil))
    let a = NSBitmapImageRep(cgImage:before),b = NSBitmapImageRep(cgImage:after)
    for p in [(50,60),(65,75),(20,20)] {
      let x = try XCTUnwrap(a.colorAt(x:p.0,y:p.1)),y = try XCTUnwrap(b.colorAt(x:p.0,y:p.1))
      XCTAssertEqual(x.alphaComponent,y.alphaComponent,accuracy:0.05)
      XCTAssertEqual(x.redComponent,y.redComponent,accuracy:0.05)
    }
  }
  func testRealPSDVisibilityAndHiddenAncestorCanBeChanged() throws {
    for name in ["hidden-layer","hidden-groups"] {
      let url = try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"psd",subdirectory:"Fixtures"))
      var (doc,assets,_,_) = try PSDCodec.read(Data(contentsOf:url))
      let index = try XCTUnwrap(doc.layers.firstIndex{ !$0.visible })
      XCTAssertFalse(doc.isVisible(doc.layers[index]))
      let hidden = try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil))
      doc.layers[index].visible = true
      let shown = try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil))
      XCTAssertNotEqual(hidden.dataProvider?.data as Data?,shown.dataProvider?.data as Data?,name)
      XCTAssertTrue(doc.isVisible(doc.layers[index]))
      for i in doc.layers.indices { doc.layers[i].visible = false }
      let clear = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil)))
      XCTAssertEqual(try XCTUnwrap(clear.colorAt(x:clear.pixelsWide/2,y:clear.pixelsHigh/2)).alphaComponent,0,accuracy:0.01)
    }
  }
  func testDarkerLighterColorCompareSumOfChannels() throws {
    let extent = CGRect(x:0,y:0,width:4,height:4)
    let red = CIImage(color:CIColor(red:1,green:0,blue:0)).cropped(to:extent)
    let green = CIImage(color:CIColor(red:0,green:0.6,blue:0)).cropped(to:extent)
    let darker = try bitmap(LayerBlending.apply(.darkerColor,source:red,background:green,extent:extent))
    let lighter = try bitmap(LayerBlending.apply(.lighterColor,source:red,background:green,extent:extent))
    XCTAssertLessThan(try XCTUnwrap(darker.colorAt(x:1,y:1)).redComponent,0.02)
    XCTAssertGreaterThan(try XCTUnwrap(lighter.colorAt(x:1,y:1)).redComponent,0.95)
  }
  func testStrokePositionsUseDifferentAlphaRingsAndBevelPreservesInterior() throws {
    let assets = AssetLibrary()
    var layer = ImageLayer(name:"shape",kind:.shape,width:60,height:60)
    layer.shape = "rectangle";layer.cornerRadius = 0;layer.color = .init(r:0.4,g:0.4,b:0.4)
    let base = try XCTUnwrap(renderer.renderLayer(layer,assets:assets))
    let ci = CIImage(cgImage:base).transformed(by:CGAffineTransform(translationX:20,y:20))
    let extent = CGRect(x:0,y:0,width:100,height:100)
    var e = ImageEffect(.outline);e.radius = 10;e.amount = 1;e.tint = .init(r:1,g:0,b:0)
    e.style = "outside"
    let outside = try bitmap(AdvancedEffects.apply(e,image:ci,scale:1)!,extent:extent)
    e.style = "inside"
    let inside = try bitmap(AdvancedEffects.apply(e,image:ci,scale:1)!,extent:extent)
    e.style = "center"
    let center = try bitmap(AdvancedEffects.apply(e,image:ci,scale:1)!,extent:extent)
    XCTAssertGreaterThan(try XCTUnwrap(outside.colorAt(x:14,y:50)).alphaComponent,0.9)
    XCTAssertLessThan(try XCTUnwrap(inside.colorAt(x:14,y:50)).alphaComponent,0.1)
    XCTAssertLessThan(try XCTUnwrap(center.colorAt(x:14,y:50)).alphaComponent,0.1)
    XCTAssertGreaterThan(try XCTUnwrap(center.colorAt(x:17,y:50)).alphaComponent,0.9)
    XCTAssertGreaterThan(try XCTUnwrap(inside.colorAt(x:24,y:50)).redComponent,0.9)
    XCTAssertNotNil(AdvancedEffects.bevelKernel)
    e = ImageEffect(.bevel);e.amount = 1
    let bevel = try bitmap(AdvancedEffects.apply(e,image:ci,scale:1)!,extent:extent)
    XCTAssertEqual(try XCTUnwrap(bevel.colorAt(x:50,y:50)).redComponent,0.4,accuracy:0.04)
    XCTAssertLessThan(try XCTUnwrap(bevel.colorAt(x:10,y:10)).alphaComponent,0.01)
  }
  func testPortraitWarpIdentityAndFeatureMasksStayLocalized() throws {
    XCTAssertNotNil(PortraitEffects.bodyKernel)
    let base = GradientRenderer.render(GradientDefinition.mesh([.init(r:1,g:0,b:0),.init(r:0,g:0,b:1)]),width:64,height:64)
    let ci = CIImage(cgImage:base)
    var e = ImageEffect(.body);e.bodyJoints = [.init(x:0.3,y:0.2),.init(x:0.7,y:0.2),.init(x:0.4,y:0.65),.init(x:0.6,y:0.65)];e.set("deformation",0)
    let identity = try bitmap(PortraitEffects.body(e,image:ci))
    let before = try XCTUnwrap(NSBitmapImageRep(cgImage:base).colorAt(x:32,y:32))
    XCTAssertEqual(try XCTUnwrap(identity.colorAt(x:32,y:32)).redComponent,before.redComponent,accuracy:0.02)
    e.set("deformation",0.8);e.set("waist",0.8)
    let changed = try bitmap(PortraitEffects.body(e,image:ci))
    XCTAssertNotEqual(identity.bitmapData.map { Data(bytes:$0,count:identity.bytesPerRow*64) },changed.bitmapData.map { Data(bytes:$0,count:changed.bytesPerRow*64) })
    let f = FaceRegion(bounds:CGRect(x:0.2,y:0.2,width:0.6,height:0.6),leftEye:[.init(x:0.3,y:0.35),.init(x:0.4,y:0.35),.init(x:0.4,y:0.4),.init(x:0.3,y:0.4)],rightEye:[],outerLips:[],innerLips:[],brows:[])
    let skin = try bitmap(PortraitEffects.faceMask([f],extent:ci.extent,feature:"skin"))
    XCTAssertLessThan(try XCTUnwrap(skin.colorAt(x:22,y:24)).redComponent,0.1)
    XCTAssertGreaterThan(try XCTUnwrap(skin.colorAt(x:32,y:35)).redComponent,0.9)
    XCTAssertLessThan(try XCTUnwrap(skin.colorAt(x:2,y:2)).redComponent,0.01)
  }
  func testRefinementBrushesDoNotShareTheSameBehavior() throws {
    let size = CGSize(width:100,height:100)
    let original = SelectionRegion(type:"rectangle",points:[.init(x:30,y:30),.init(x:70,y:70)])
    let basic = SelectionRefinement.paint(original,image:nil,size:size,points:[CGPoint(x:10,y:10)],diameter:12,brush:"basic",mode:"add",tolerance:0.1)
    let edge = SelectionRefinement.paint(original,image:nil,size:size,points:[CGPoint(x:10,y:10)],diameter:12,brush:"edge",mode:"add",tolerance:0.1)
    XCTAssertTrue(SelectionEngine.contains(basic,point:CGPoint(x:10,y:10),canvas:size))
    XCTAssertFalse(SelectionEngine.contains(edge,point:CGPoint(x:10,y:10),canvas:size))
    let cg = try XCTUnwrap(ImageRenderer.bitmap(100,100));cg.setFillColor(NSColor.red.cgColor);cg.fill(CGRect(origin:.zero,size:size))
    let quick = SelectionRefinement.paint(original,image:cg.makeImage(),size:size,points:[CGPoint(x:10,y:10)],diameter:12,brush:"quick",mode:"add",tolerance:0.1)
    XCTAssertTrue(SelectionEngine.contains(quick,point:CGPoint(x:90,y:90),canvas:size))
    XCTAssertFalse(SelectionEngine.contains(basic,point:CGPoint(x:90,y:90),canvas:size))
  }
  func testBezierCurveAndSnappingGeometry() {
    let anchors = [BezierAnchor(point:.init(x:0,y:0),outgoing:.init(x:0.5,y:0)),BezierAnchor(point:.init(x:1,y:1),incoming:.init(x:0.5,y:1))]
    var types:[CGPathElementType] = []
    BezierGeometry.path(anchors,closed:false).applyWithBlock { types.append($0.pointee.type) }
    XCTAssertTrue(types.contains(.addCurveToPoint))
    let near = SnapEngine.snap(24,sources:[24,74],targets:[20,50,100],tolerance:6)
    XCTAssertEqual(near.0,20);XCTAssertEqual(near.1,20)
    let far = SnapEngine.snap(24,sources:[24],targets:[40],tolerance:6)
    XCTAssertEqual(far.0,24);XCTAssertNil(far.1)
  }
  func testInverseProjectiveAndWarpCoordinatesForContentEditing() throws {
    let q = [Point(x:0.12,y:0.04),Point(x:1.1,y:0.16),Point(x:0.85,y:1.2),Point(x:-0.05,y:0.9)]
    let map = try XCTUnwrap(ProjectiveMap(q)),v = map.values
    let source = Point(x:0.32,y:0.67),den = v[6]*source.x+v[7]*source.y+1
    let destination = Point(x:(v[0]*source.x+v[1]*source.y+v[2])/den,y:(v[3]*source.x+v[4]*source.y+v[5])/den)
    let recovered = try XCTUnwrap(map.source(destination))
    XCTAssertEqual(recovered.x,source.x,accuracy:1e-8);XCTAssertEqual(recovered.y,source.y,accuracy:1e-8)
    var layer = ImageLayer(name:"projected",kind:.shape,width:200,height:100)
    layer.x = 35;layer.y = 22;layer.rotation = 33;layer.flippedX = true;layer.quad = q
    let a = layer.rotation * .pi/180,dx = -(destination.x-0.5)*layer.width,dy = (destination.y-0.5)*layer.height
    let world = CGPoint(x:layer.x+layer.width/2+dx*cos(a)-dy*sin(a),y:layer.y+layer.height/2+dx*sin(a)+dy*cos(a))
    let local = TransformGeometry.contentPoint(world,layer:layer)
    XCTAssertEqual(local.x,source.x*layer.width,accuracy:1e-7);XCTAssertEqual(local.y,source.y*layer.height,accuracy:1e-7)
    var nodes = TransformGeometry.warpGrid;nodes[4] = Point(x:0.7,y:0.4)
    let warped = TransformGeometry.warpPoint(Point(x:0.3,y:0.7),nodes:nodes)
    let original = try XCTUnwrap(TransformGeometry.warpSource(warped,nodes:nodes))
    XCTAssertEqual(original.x,0.3,accuracy:1e-6);XCTAssertEqual(original.y,0.7,accuracy:1e-6)
    XCTAssertNil(TransformGeometry.warpSource(Point(x:4,y:4),nodes:nodes))
  }
  func testShiftLineConstraintIncludesHorizontalVerticalAndVisiblePixels() throws {
    let origin = CGPoint(x:10,y:20)
    let horizontal = TransformGeometry.constrained(CGPoint(x:90,y:24),around:origin)
    let vertical = TransformGeometry.constrained(CGPoint(x:12,y:100),around:origin)
    XCTAssertEqual(horizontal.y,20,accuracy:1e-8);XCTAssertEqual(vertical.x,10,accuracy:1e-8)
    var line = ImageLayer(name:"line",kind:.shape,width:84,height:4)
    line.shape = "line";line.cornerRadius = 4
    line.vectorPoints = [Point(x:2/84,y:0.5),Point(x:82/84,y:0.5)]
    let rep = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.renderLayer(line,assets:AssetLibrary())))
    XCTAssertGreaterThan(try XCTUnwrap(rep.colorAt(x:40,y:2)).alphaComponent,0.9)
  }
  func testPenHandlesCanLinkDisconnectAndToggleSmooth() {
    var a = BezierAnchor(point:Point(x:50,y:50))
    a.moveHandle(to:CGPoint(x:80,y:52),incoming:false,independent:false,constrained:true)
    XCTAssertEqual(a.outgoing?.y,50);XCTAssertEqual(a.incoming?.y,50)
    XCTAssertEqual((a.outgoing?.x ?? 0)+(a.incoming?.x ?? 0),100,accuracy:1e-8)
    let fixed = a.incoming
    a.moveHandle(to:CGPoint(x:90,y:70),incoming:false,independent:true,constrained:false)
    XCTAssertEqual(a.incoming,fixed)
    a.moveHandle(to:CGPoint(x:85,y:72),incoming:false,independent:false,constrained:false)
    XCTAssertEqual(a.incoming,fixed,"Disconnected handles remain independent")
    var anchors = [BezierAnchor(point:.init(x:0,y:0)),a,BezierAnchor(point:.init(x:100,y:70))]
    BezierGeometry.toggleSmooth(&anchors,index:1,closed:false)
    XCTAssertNil(anchors[1].outgoing);XCTAssertNil(anchors[1].incoming)
    BezierGeometry.toggleSmooth(&anchors,index:1,closed:false)
    XCTAssertNotNil(anchors[1].outgoing);XCTAssertNotNil(anchors[1].incoming);XCTAssertNil(anchors[1].independentHandles)
  }
  @MainActor func testCropRatioImmediatelyConstrainsExistingSelectionWithoutEditingDocument() {
    let store = EditorStore(loadRecovery:false)
    store.selection = SelectionRegion(type:"rectangle",points:[Point(x:100,y:100),Point(x:700,y:400)])
    store.cropRatio = "free";store.chooseTool(.crop)
    let before = store.document
    store.cropRatio = "1:1";store.constrainCropRatio()
    XCTAssertEqual(store.selection?.bounds.width,300);XCTAssertEqual(store.selection?.bounds.height,300)
    XCTAssertEqual(store.selection?.bounds.midX,400);XCTAssertEqual(store.selection?.bounds.midY,250)
    XCTAssertEqual(store.document,before)
  }
  func testQuickSelectionUsesBrushFootprintToSampleMoreThanOneRegion() throws {
    let cg = try XCTUnwrap(ImageRenderer.bitmap(64,64)),size = CGSize(width:64,height:64)
    cg.setFillColor(NSColor.red.cgColor);cg.fill(CGRect(x:0,y:0,width:32,height:64))
    cg.setFillColor(NSColor.blue.cgColor);cg.fill(CGRect(x:32,y:0,width:32,height:64))
    let image = try XCTUnwrap(cg.makeImage()),point = CGPoint(x:28,y:32)
    let small = try XCTUnwrap(SelectionEngine.region(image:image,point:point,canvasSize:size,tolerance:0.02,contiguous:true,brushDiameter:2))
    let large = try XCTUnwrap(SelectionEngine.region(image:image,point:point,canvasSize:size,tolerance:0.02,contiguous:true,brushDiameter:40))
    XCTAssertFalse(SelectionEngine.contains(small,point:CGPoint(x:50,y:32),canvas:size))
    XCTAssertTrue(SelectionEngine.contains(large,point:CGPoint(x:50,y:32),canvas:size))
  }
  func testPSDAdjustmentExportPreservesAppearanceInExternalReaders() throws {
    let assets = AssetLibrary()
    var doc = ImageDocument();doc.width = 16;doc.height = 16
    var base = ImageLayer(name:"base",kind:.shape,width:16,height:16)
    base.shape = "rectangle";base.cornerRadius = 0;base.color = .init(r:0.2,g:0.3,b:0.4)
    var fx = ImageLayer(name:"FX",kind:.adjustment,width:16,height:16)
    var e = ImageEffect(.color);e.exposure = 1;fx.effects = [e]
    doc.layers = [fx,base]
    let expected = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil)))
    let data = try PSDCodec.write(document:doc,assets:assets,renderer:renderer)
    let (external,loaded,_,_) = try PSDCodec.read(data)
    XCTAssertNotNil(external.layers.first{$0.name == "原始图层 · 含 image Pro FX" && !$0.visible})
    XCTAssertNotNil(external.layers.first{$0.name == "base"})
    let actual = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.render(external,assets:loaded,maxDimension:nil)))
    let a = try XCTUnwrap(expected.colorAt(x:8,y:8)),b = try XCTUnwrap(actual.colorAt(x:8,y:8))
    XCTAssertEqual(a.redComponent,b.redComponent,accuracy:0.02)
    XCTAssertEqual(a.alphaComponent,b.alphaComponent,accuracy:0.02)
  }
  @MainActor func testReplacingMaskClearsOldEditsAndRasterizeClearsTransforms() throws {
    let store = EditorStore(loadRecovery:false)
    store.addLayer(.shape,rect:CGRect(x:20,y:20,width:64,height:48))
    store.addMaskSelected()
    store.updateSelected("dirty mask") { $0.maskInverted = true;$0.maskDensity = 0.2;$0.maskStrokes = [BrushStroke(points:[.init(x:5,y:5)],color:.init(),size:10,opacity:1,hardness:1)] }
    store.addMaskSelected()
    XCTAssertNil(store.selected?.maskInverted);XCTAssertNil(store.selected?.maskDensity);XCTAssertNil(store.selected?.maskStrokes)
    store.updateSelected("transform") { $0.quad = [.init(x:0,y:0),.init(x:1.2,y:0),.init(x:1,y:1),.init(x:0,y:1)];$0.warpNodes = TransformGeometry.warpGrid;$0.rotation = 15 }
    store.rasterizeSelected()
    XCTAssertEqual(store.selected?.kind,.raster);XCTAssertNil(store.selected?.quad);XCTAssertNil(store.selected?.warpNodes)
    XCTAssertEqual(store.selected?.rotation,0)
  }
}
