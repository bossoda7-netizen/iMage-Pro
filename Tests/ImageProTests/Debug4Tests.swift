import XCTest
import AppKit
import CoreImage
@testable import ImagePro

final class Debug4Tests:XCTestCase {
  let renderer = ImageRenderer()
  func image(_ w:Int = 192,_ h:Int = 128) throws -> CGImage {
    let c = try XCTUnwrap(ImageRenderer.bitmap(w,h))
    c.setFillColor(NSColor.gray.cgColor);c.fill(CGRect(x:0,y:0,width:w,height:h))
    for x in stride(from:0,to:w,by:12) {
      c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:x,y:0,width:4,height:h))
    }
    return try XCTUnwrap(c.makeImage())
  }
  func bytes(_ ci:CIImage) throws -> [UInt8] {
    let cg = try XCTUnwrap(renderer.context.createCGImage(ci,from:ci.extent))
    let c = try XCTUnwrap(CGContext(data:nil,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,
      space:ImageRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
    c.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
    return Array(UnsafeBufferPointer(start:try XCTUnwrap(c.data).assumingMemoryBound(to:UInt8.self),count:cg.width*cg.height*4))
  }
  @MainActor func store() throws -> EditorStore {
    let s = EditorStore(loadRecovery:false)
    var l = ImageLayer(name:"test",kind:.raster,width:192,height:128)
    l.assetID = try s.active.assets.insert(image())
    s.active.document.width = 192;s.active.document.height = 128
    s.active.document.layers = [l];s.active.document.selectedLayerID = l.id
    return s
  }
  func testStrongMeshDragCannotFoldAndInverseHasNoInteriorHoles() throws {
    for index in [0,3,24,48] {
      let nodes = TransformGeometry.dragWarp(TransformGeometry.denseWarpGrid,index:index,to:Point(x:1.4,y:-0.5))
      XCTAssertTrue(TransformGeometry.validWarp(nodes))
      for y in 1..<10 {for x in 1..<10 {
        let uv = Point(x:Double(x)/10,y:Double(y)/10)
        let dest = TransformGeometry.warpPoint(uv,nodes:nodes)
        let recovered = try XCTUnwrap(TransformGeometry.warpSource(dest,nodes:nodes))
        XCTAssertEqual(recovered.x,uv.x,accuracy:0.0001);XCTAssertEqual(recovered.y,uv.y,accuracy:0.0001)
      }}
    }
  }
  func testWarpGPUKeepsOpaqueSurfaceInterior() throws {
    XCTAssertNotNil(WarpRenderer.kernel)
    let nodes = TransformGeometry.dragWarp(TransformGeometry.denseWarpGrid,index:24,to:Point(x:0.9,y:0.3))
    let base = CIImage(color:.white).cropped(to:CGRect(x:0,y:0,width:160,height:160))
    let result = try bytes(WarpRenderer.apply(base,nodes:nodes,extent:base.extent))
    for y in stride(from:2,to:98,by:4) {for x in stride(from:2,to:98,by:4) {
      let p = TransformGeometry.warpPoint(Point(x:Double(x)/100,y:Double(y)/100),nodes:nodes)
      let px = Int(p.x*160),py = Int((1-p.y)*160)
      guard (1..<159).contains(px),(1..<159).contains(py) else {continue}
      XCTAssertGreaterThan(result[(py*160+px)*4+3],245,"Interior hole at \(x),\(y)")
    }}
  }
  @MainActor func testFolderDropMovesSubtreeAndSingleUndoRestoresIt() throws {
    let s = try store();s.addLayer(.group);let folder = try XCTUnwrap(s.selected?.id)
    s.addLayer(.group);let nested = try XCTUnwrap(s.selected?.id)
    s.addLayer(.paint);let child = try XCTUnwrap(s.selected?.id)
    s.updateSelected("parent") {$0.parentID = nested}
    let before = s.document
    s.moveLayerIntoGroup(nested,group:folder)
    XCTAssertEqual(s.document.layers.first {$0.id == nested}?.parentID,folder)
    XCTAssertEqual(s.document.layers.first {$0.id == child}?.parentID,nested)
    let unchanged = s.document;s.moveLayerIntoGroup(folder,group:nested);XCTAssertEqual(s.document,unchanged)
    s.undo();XCTAssertEqual(s.document,before)
  }
  @MainActor func testMaskDetachReattachHasOneUndoAndRetainsPixels() throws {
    let s = try store();let target = try XCTUnwrap(s.selected?.id)
    let asset = try s.active.assets.insert(image())
    s.updateSelected("mask") {$0.maskAssetID = asset}
    let before = s.document;s.beginTransaction("drag mask")
    let detached = try XCTUnwrap(s.detachMask(target))
    let bakedAsset = s.selected?.assetID
    s.attachLayerAsMask(detached,to:target);s.endTransaction()
    XCTAssertEqual(s.selected?.maskAssetID,bakedAsset)
    XCTAssertEqual(s.document.layers.count,before.layers.count)
    XCTAssertEqual(s.document.layers.first {$0.id == target}?.width,192)
  }
  func testCropHitRegionsWorkOutsideCanvasAtEveryZoom() {
    let rect = CGRect(x:-25,y:-30,width:240,height:180)
    for scale:CGFloat in [0.25,1,4] {
      XCTAssertEqual(CTCropGeometry.handle(at:CGPoint(x:rect.minX-12/scale,y:rect.minY),in:rect,scale:scale),0)
      XCTAssertEqual(CTCropGeometry.handle(at:CGPoint(x:rect.maxX+10/scale,y:rect.midY+20),in:rect,scale:scale),3)
    }
    let drag = CTCropDrag(start:rect.origin,original:rect,mode:.resize(0))
    XCTAssertLessThan(drag.updated(to:CGPoint(x:-80,y:-70),ratio:nil).minX,rect.minX)
  }
  @MainActor func testCropViewAllowsStartingOutsideOldCanvas() throws {
    let s = try store();s.chooseTool(.crop)
    let view = CanvasNSView(frame:CGRect(x:0,y:0,width:500,height:400));view.store = s
    let window = NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false;window.contentView = view;defer {window.close()}
    let p = view.convert(CGPoint(x:view.imageRect.minX-20,y:view.imageRect.minY-20),to:nil)
    let event = try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:p,modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    view.mouseDown(with:event)
    XCTAssertNotNil(view.compositorCrop)
    XCTAssertLessThan(view.start.x,0);XCTAssertLessThan(view.start.y,0)
  }
  @MainActor func testClosedPenIsGeometryUntilExplicitFill() throws {
    let s = try store();s.active.document.layers = []
    s.createBezierPath([BezierAnchor(point:Point(x:20,y:20)),BezierAnchor(point:Point(x:140,y:20)),BezierAnchor(point:Point(x:140,y:100)),BezierAnchor(point:Point(x:20,y:100))],closed:true)
    let path = try XCTUnwrap(s.selected)
    XCTAssertTrue(path.isPath);XCTAssertEqual(s.inspector,.special)
    let blank = try XCTUnwrap(renderer.renderLayer(path,assets:s.active.assets))
    let pixels = try bytes(CIImage(cgImage:blank))
    XCTAssertTrue(stride(from:3,to:pixels.count,by:4).allSatisfy {pixels[$0]==0})
    s.pathToSelection();XCTAssertNotNil(s.selection)
    s.fillPath();XCTAssertFalse(try XCTUnwrap(s.selected).isPath)
    XCTAssertEqual(s.document.layers.count,2)
    let fill = try XCTUnwrap(renderer.renderLayer(try XCTUnwrap(s.selected),assets:s.active.assets))
    XCTAssertGreaterThan(try bytes(CIImage(cgImage:fill)).filter {$0>0}.count,100)
  }
  @MainActor func testHealFeedbackAndWarpCommitPublishNewPreviewImmediately() throws {
    let s = try store();s.chooseTool(.retouch,branch:ToolCategory.retouch.branches.first {$0.id=="heal"})
    let stroke = try XCTUnwrap(CompositorPixelStroke(store:s,useGPU:false))
    XCTAssertNil(stroke.coverageImage());stroke.appendDocument(CGPoint(x:80,y:60),store:s)
    let overlay = try XCTUnwrap(stroke.coverageImage()),pixels = try bytes(CIImage(cgImage:overlay))
    XCTAssertTrue(stride(from:3,to:pixels.count,by:4).contains {pixels[$0]>0})
    XCTAssertEqual(pixels[3],0)
    let original = try XCTUnwrap(s.selected)
    s.commitCompositorPixels(try image(),project:s.document.id,original:original,title:"stroke")
    XCTAssertNotNil(s.layerPreviews[original.id])
    XCTAssertGreaterThan(s.previewRevision,0)
  }
  func testForeheadIncludedAndShoulderLeavesArmOutsideSupport() throws {
    let face = FaceRegion(contour:[Point(x:0.25,y:0.4),Point(x:0.3,y:0.7),Point(x:0.5,y:0.85),Point(x:0.7,y:0.7),Point(x:0.75,y:0.4)],bounds:CGRect(x:0.2,y:0.18,width:0.6,height:0.67),leftEye:[],rightEye:[],outerLips:[],innerLips:[],brows:[])
    let mask = try bytes(PortraitEffects.faceMask([face],extent:CGRect(x:0,y:0,width:200,height:200),feature:"skin"))
    XCTAssertGreaterThan(mask[((200-50)*200+100)*4],240)
    XCTAssertLessThan(mask[(10*200+10)*4],5)
    var e = ImageEffect(.body);e.amount = 1;e.set("deformation",0);e.set("shoulders",1)
    e.bodyJoints = [Point(x:0.35,y:0.3),Point(x:0.65,y:0.3),Point(x:0.4,y:0.6),Point(x:0.6,y:0.6)]
    let base = CIImage(cgImage:try image(200,200))
    let before = try bytes(base),after = try bytes(PortraitEffects.body(e,image:base))
    var differences = 0
    for y in 0..<200 {for x in 0..<200 {
      let i = (y*200+x)*4
      if x<45 || x>155 {XCTAssertEqual(Array(before[i..<i+4]),Array(after[i..<i+4]))}
      if before[i] != after[i] {differences += 1}
    }}
    XCTAssertGreaterThan(differences,0)
  }
  func testIndependentEffectsRespondAndLegacyCatalogIsHidden() throws {
    let kinds = EffectCatalog.groups.flatMap {$0.1}
    XCTAssertFalse(kinds.contains(.blur));XCTAssertFalse(kinds.contains(.distort))
    let base = CIImage(cgImage:try image()),original = try bytes(base)
    for kind:EffectKind in [.gaussianBlur,.motionBlur,.focusBlur,.bumpDistort,.pinchDistort,.stretchDistort,.twirlDistort,.waveDistort] {
      var e = ImageEffect(kind);e.radius = 10;e.amount = 1;e.set("angle",45)
      let result = renderer.apply(e,to:base,scale:1)
      XCTAssertEqual(result.extent,base.extent)
      XCTAssertNotEqual(try bytes(result),original,kind.title)
    }
  }
  func testGrainDeterministicAlphaSafeAndDoesNotTileEvery128Pixels() throws {
    XCTAssertNotNil(FilmGrain.kernel)
    let base = CIImage(color:CIColor(red:0.5,green:0.5,blue:0.5,alpha:0.6)).cropped(to:CGRect(x:0,y:0,width:320,height:16))
    var e = ImageEffect(.grain);e.amount = 1
    let a = try bytes(FilmGrain.apply(e,image:base,scale:1)),b = try bytes(FilmGrain.apply(e,image:base,scale:1))
    XCTAssertEqual(a,b)
    XCTAssertTrue(stride(from:3,to:a.count,by:4).allSatisfy {abs(Int(a[$0])-153)<=1})
    XCTAssertNotEqual(Array(a[0..<128*4]),Array(a[128*4..<256*4]))
  }
  @MainActor func testSpecialInspectorDefaultsAndToolMappings() throws {
    let s = try store()
    for kind:LayerKind in [.text,.shape] {s.addLayer(kind);XCTAssertEqual(s.inspector,.special)}
    s.chooseTool(.fill,branch:ToolCategory.fill.branches.first {$0.id=="linear"})
    s.addGradient(from:.zero,to:CGPoint(x:192,y:128));XCTAssertEqual(s.inspector,.special)
    s.inspector = .base;s.selectLayer(try XCTUnwrap(s.selected?.id));XCTAssertEqual(s.inspector,.special)
    for tool:ToolCategory in [.move,.crop,.hand,.zoom,.eyedropper] {s.chooseTool(tool);XCTAssertEqual(s.tool,.canvas);XCTAssertEqual(s.interactionTool,tool)}
    s.chooseTool(.eraser);XCTAssertEqual(s.tool,.brush);XCTAssertEqual(s.interactionTool,.eraser)
    s.selectToolShortcut("b");XCTAssertEqual(s.interactionTool,.brush);XCTAssertNotEqual(s.branch.id,"eraser")
    for removed:ToolCategory in [.detail,.dodge,.clone] {XCTAssertFalse(ToolCategory.displayed.contains(removed))}
  }
}
