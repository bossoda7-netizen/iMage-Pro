import XCTest
import AppKit
import Metal
@testable import ImagePro

final class CompositorToolTests:XCTestCase {
  func image(_ w:Int = 128,_ h:Int = 96,draw:(CGContext)->Void) throws -> CGImage {
    let c = try XCTUnwrap(ImageRenderer.bitmap(w,h));draw(c);return try XCTUnwrap(c.makeImage())
  }
  func bytes(_ image:CGImage) throws -> [UInt8] {
    let c = try XCTUnwrap(CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
      space:ImageRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
    c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    return Array(UnsafeBufferPointer(start:try XCTUnwrap(c.data).assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
  }
  @MainActor func setup(_ source:CGImage,id:String) throws -> EditorStore {
    let store = EditorStore(loadRecovery:false);store.active.document.layers = [];store.active.document.width = Double(source.width);store.active.document.height = Double(source.height)
    var layer = ImageLayer(name:"Migration fixture",kind:.raster,width:Double(source.width),height:Double(source.height))
    layer.assetID = try store.active.assets.insert(source)
    store.active.document.layers = [layer];store.active.document.selectedLayerID = layer.id
    choose(store,id:id);return store
  }
  @MainActor func choose(_ store:EditorStore,id:String) {
    switch id {
    case "crop":store.chooseTool(.crop)
    case "horizontalText":store.chooseTool(.text,branch:ToolCategory.text.branches.first {$0.id == id})
    case "miganHeal":store.chooseTool(.retouch,branch:ToolCategory.retouch.branches.first {$0.id == "heal"})
    case "smudge","liquify":store.chooseTool(.retouch,branch:ToolCategory.retouch.branches.first {$0.id == id})
    default:store.chooseTool(.move)
    }
  }
  @MainActor func testPromotedToolsUseExistingCategoriesAndKeepOriginalMoveAndClone() {
    let s = EditorStore(loadRecovery:false)
    XCTAssertFalse(ToolCategory.displayed.contains {$0.rawValue == "测试"})
    XCTAssertEqual(ToolCategory.retouch.branches.first {$0.id == "heal"}?.title, "智能修复")
    for (key,category,id) in [("c",ToolCategory.canvas,"crop"),("j",.retouch,"heal"),("r",.retouch,"smudge"),("t",.text,"horizontalText")] {
      s.selectToolShortcut(key);XCTAssertEqual(s.tool,category)
      s.chooseTool(category,branch:category.branches.first {$0.id == id});XCTAssertNotNil(s.compositorToolID)
    }
    choose(s,id:"liquify");XCTAssertEqual(s.tool,.retouch);XCTAssertEqual(s.compositorToolID,"liquify")
    s.chooseTool(.move);XCTAssertNil(s.compositorToolID)
    s.chooseTool(.clone);XCTAssertNil(s.compositorToolID)
  }
  @MainActor func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double,_ flags:NSEvent.ModifierFlags = []) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:y),modifierFlags:flags,timestamp:1,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1))
  }
  func testCropSymmetryRatioAndRotatedResizeAnchor() {
    let r = CTCropGeometry.create(from:CGPoint(x:50,y:50),to:CGPoint(x:80,y:70),ratio:1.5,symmetric:true)
    XCTAssertEqual(r,CGRect(x:20,y:30,width:60,height:40))
    let p = CTPlacement(origin:CGPoint(x:20,y:30),size:CGSize(width:80,height:40),rotation:37)
    let start = p.point(.zero),anchor = p.point(CGPoint(x:1,y:1))
    let drag = CTTransformDrag(original:p,start:start,mode:.resize(0))
    let result = drag.updated(to:CGPoint(x:start.x-12,y:start.y-5),lockRatio:false,shift:false)
    XCTAssertEqual(result.point(CGPoint(x:1,y:1)).x,anchor.x,accuracy:0.00001)
    XCTAssertEqual(result.point(CGPoint(x:1,y:1)).y,anchor.y,accuracy:0.00001)
    let move = CTTransformDrag(original:p,start:.zero,mode:.move).updated(to:CGPoint(x:40,y:9),lockRatio:false,shift:true)
    XCTAssertEqual(move.origin.y,p.origin.y);XCTAssertEqual(move.origin.x,p.origin.x+40)
  }
  @MainActor func testCropCanExpandCanvasAndUndo() throws {
    let s = try setup(image {c in c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:0,y:0,width:128,height:96))},id:"crop")
    let before = s.document
    s.selection = SelectionRegion(type:"crop",points:[Point(x:-20,y:-10),Point(x:148,y:106)])
    s.cropToSelection();XCTAssertEqual(s.document.width,168);XCTAssertEqual(s.document.height,116)
    XCTAssertEqual(s.selected?.x,20);XCTAssertEqual(s.selected?.y,10)
    s.undo();XCTAssertEqual(s.document,before)
  }
  func testHealingModesRemoveBlemishAndKeepOutside() throws {
    let source = try image {c in
      c.setFillColor(NSColor(calibratedWhite:0.5,alpha:1).cgColor);c.fill(CGRect(x:0,y:0,width:128,height:96))
      c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:58,y:42,width:12,height:12))
    }
    let original = try bytes(source)
    var coverage = [UInt8](repeating:0,count:128*96)
    for y in 38..<58 {for x in 54..<74 {coverage[y*128+x] = 255}}
    do {
      let result = try XCTUnwrap(CTHealingJob(original:original,coverage:coverage,width:128,height:96,opacity:1).run())
      let pixels = try bytes(result),center = (48*128+64)*4
      XCTAssertLessThan(abs(Int(pixels[center])-Int(pixels[center+1])),15)
      XCTAssertEqual(Array(pixels[0..<40]),Array(original[0..<40]))
    }
  }
  @MainActor func testSmudgeCPUAndMetalTransportColorAndRespectSelection() throws {
    let source = try image {c in
      c.setFillColor(NSColor.blue.cgColor);c.fill(CGRect(x:0,y:0,width:128,height:96))
      c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:0,y:0,width:40,height:96))
    }
    for gpu in [false,true] {
      let s = try setup(source,id:"smudge");s.brushSize = 18;s.brushHardness = 1;s.brushOpacity = 1;s.brushFlow = 1
      s.selection = SelectionRegion(type:"rectangle",points:[Point(x:0,y:20),Point(x:65,y:60)])
      let count = s.active.assets.data.count
      let stroke = try XCTUnwrap(CompositorPixelStroke(store:s,useGPU:gpu))
      if gpu,MTLCreateSystemDefaultDevice() != nil {XCTAssertNotNil(stroke.gpu,"Metal kernels must compile")}
      stroke.appendDocument(CGPoint(x:35,y:40),store:s);stroke.appendDocument(CGPoint(x:90,y:40),store:s)
      _ = stroke.preview(store:s);XCTAssertEqual(s.active.assets.data.count,count)
      let result = try XCTUnwrap(stroke.result()),pixels = try bytes(result)
      XCTAssertGreaterThan(pixels[(40*128+55)*4],80)
      XCTAssertEqual(pixels[(40*128+85)*4+2],255,"Outside the selection stays blue")
      XCTAssertEqual(pixels[(5*128+55)*4+2],255)
      XCTAssertEqual(try bytes(try XCTUnwrap(stroke.result())),pixels,"Reading preview repeatedly must not reapply clip")
    }
  }
  @MainActor func testLiquifyMovesPixelsAndKeepsFarPixels() throws {
    let source = try image {c in
      c.setFillColor(NSColor.blue.cgColor);c.fill(CGRect(x:0,y:0,width:128,height:96))
      c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:50,y:36,width:8,height:24))
    }
    for gpu in [false,true] {
      let s = try setup(source,id:"liquify");s.brushSize = 42;s.brushHardness = 0.9;s.brushOpacity = 1;s.brushFlow = 1
      let stroke = try XCTUnwrap(CompositorPixelStroke(store:s,useGPU:gpu))
      stroke.appendDocument(CGPoint(x:54,y:48),store:s);stroke.appendDocument(CGPoint(x:70,y:48),store:s)
      let pixels = try bytes(try XCTUnwrap(stroke.result()))
      XCTAssertGreaterThan(pixels[(48*128+69)*4],60)
      XCTAssertEqual(Array(pixels[0..<40]),Array(try bytes(source)[0..<40]))
    }
  }
  @MainActor func testCommitPreservesEffectsMaskAndUndoAndArchive() throws {
    let source = try image {c in c.setFillColor(NSColor.blue.cgColor);c.fill(CGRect(x:0,y:0,width:128,height:96))}
    let s = try setup(source,id:"smudge")
    let mask = try image {c in c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:128,height:96))}
    s.active.document.layers[0].maskAssetID = try s.active.assets.insert(mask)
    s.active.document.layers[0].effects = [ImageEffect(.grain)]
    let before = s.document,layer = try XCTUnwrap(s.selected)
    s.commitCompositorPixels(mask,project:s.document.id,original:layer,title:"Test stroke")
    XCTAssertEqual(s.selected?.effects,layer.effects);XCTAssertEqual(s.selected?.maskAssetID,layer.maskAssetID)
    XCTAssertEqual(s.active.undo.count,1)
    let archive = ProjectArchive(document:s.document,undo:s.active.undo,redo:s.active.redo)
    XCTAssertEqual(try JSONDecoder().decode(ProjectArchive.self,from:JSONEncoder().encode(archive)).document,s.document)
    s.undo();XCTAssertEqual(s.document,before);s.redo();XCTAssertEqual(s.selected?.maskAssetID,layer.maskAssetID)
    let current = s.document
    s.commitCompositorPixels(source,project:UUID(),original:layer,title:"Stale")
    XCTAssertEqual(s.document,current)
  }
  @MainActor func testTextDragCreatesParagraphAndPointTextGrowsAndCancels() throws {
    let s = EditorStore(loadRecovery:false);s.active.document.layers = [];s.active.document.width = 400;s.active.document.height = 300
    s.chooseTool(.text,branch:ToolCategory.text.branches.first {$0.id == "horizontalText"})
    let v = CanvasNSView(frame:CGRect(x:0,y:0,width:400,height:300));v.store = s
    v.mouseDown(with:try event(.leftMouseDown,30,40));v.mouseUp(with:try event(.leftMouseUp,220,160))
    XCTAssertEqual(s.selected?.width,190);XCTAssertEqual(s.selected?.height,120);XCTAssertEqual(s.selected?.textStyle?.pointText,false)
    XCTAssertNotNil(v.textEditor);v.finishTextEditing(cancel:true);XCTAssertTrue(s.document.layers.isEmpty)
    v.mouseDown(with:try event(.leftMouseDown,30,40));v.mouseUp(with:try event(.leftMouseUp,30,40))
    XCTAssertEqual(s.selected?.textStyle?.pointText,true)
    let editor = try XCTUnwrap(v.textEditor);editor.string = "A long native text line"
    v.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
    XCTAssertGreaterThan(try XCTUnwrap(s.selected?.width),120)
    XCTAssertEqual(s.selected?.x,30);XCTAssertEqual(s.selected?.y,260)
    v.finishTextEditing();XCTAssertEqual(s.active.undo.count,1)
    s.undo();XCTAssertTrue(s.document.layers.isEmpty)
  }

  @MainActor func testHealingGestureCompletesOneUndoStep() async throws {
    let source = try image {c in
      c.setFillColor(NSColor(calibratedWhite:0.6,alpha:1).cgColor);c.fill(CGRect(x:0,y:0,width:128,height:96))
      c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:60,y:44,width:8,height:8))
    }
    let s = try setup(source,id:"miganHeal");s.brushSize = 20;s.brushOpacity = 1;s.brushFlow = 1;s.brushHardness = 1
    let before = s.document
    let v = CanvasNSView(frame:CGRect(x:0,y:0,width:128,height:96));v.store = s
    v.mouseDown(with:try event(.leftMouseDown,64,48));v.mouseUp(with:try event(.leftMouseUp,64,48))
    XCTAssertTrue(s.busy)
    for _ in 0..<1500 {if !s.busy {break};try await Task.sleep(nanoseconds:10_000_000)}
    XCTAssertFalse(s.busy);XCTAssertEqual(s.active.undo.count,1)
    let layer = try XCTUnwrap(s.selected),img = try XCTUnwrap(s.active.assets.image(layer.assetID)),output = try bytes(img)
    let index = (48*128+64)*4;XCTAssertLessThan(abs(Int(output[index])-Int(output[index+1])),20)
    s.undo();XCTAssertEqual(s.document,before)
  }
  @MainActor func testMigrationFixtureRoundTrip() throws {
    let source = try image(640,480) {c in
      c.setFillColor(NSColor(calibratedWhite:0.88,alpha:1).cgColor);c.fill(CGRect(x:0,y:0,width:640,height:480))
      for x in stride(from:0,to:640,by:40) {c.setFillColor(NSColor(calibratedWhite:Double(x%80 == 0 ? 0.72 : 0.8),alpha:1).cgColor);c.fill(CGRect(x:x,y:0,width:20,height:480))}
      c.setFillColor(NSColor.systemRed.cgColor);c.fillEllipse(in:CGRect(x:220,y:160,width:16,height:16))
      c.setFillColor(NSColor.systemTeal.cgColor);c.fill(CGRect(x:50,y:300,width:160,height:90))
      c.setFillColor(NSColor.systemOrange.cgColor);c.fillEllipse(in:CGRect(x:380,y:280,width:120,height:120))
    }
    let s = try setup(source,id:"move");s.active.document.name = "Compositor 工具测试"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("compositor-migration-\(UUID().uuidString).imgp")
    defer { try? FileManager.default.removeItem(at: url) }
    try s.writeProject(s.active,to:url)
    let reopened = try s.loadProject(url);XCTAssertEqual(reopened.document,s.document)
    XCTAssertNotNil(reopened.assets.image(reopened.document.selectedLayer?.assetID))
  }
}
