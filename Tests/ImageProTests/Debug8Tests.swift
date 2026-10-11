import XCTest
import AppKit
import SwiftUI
import CoreImage
@testable import ImagePro

final class Debug8Tests:XCTestCase {
  @MainActor func store()->EditorStore {
    let s = EditorStore(loadRecovery:false);s.newProject(name:"Debug8",width:300,height:220,background:nil);return s
  }
  func event(_ type:NSEvent.EventType,_ point:CGPoint,flags:NSEvent.ModifierFlags = [])->NSEvent {
    NSEvent.mouseEvent(with:type,location:point,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0)!
  }
  func image(_ width:Int = 300,_ height:Int = 220)->CGImage {
    let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.blue.cgColor);context.fill(CGRect(x:0,y:0,width:width,height:height));return context.makeImage()!
  }
  @MainActor func testEveryRulerToolCanStartOnLockedMeasurement() throws {
    for tool in RulerTool.allCases {
      let s = store();s.beginRulerMode();s.activeRulerTool = tool
      var locked = RulerMeasurement(start:Point(x:40,y:40),end:Point(x:100,y:90),tool:tool);locked.locked = true
      s.addRulerMeasurement(locked)
      let view = CanvasNSView(frame:CGRect(x:0,y:0,width:900,height:700));view.store = s
      func screen(_ p:CGPoint)->CGPoint {view.convert(CGPoint(x:view.imageRect.minX+p.x*view.scale,y:view.imageRect.minY+p.y*view.scale),to:nil)}
      view.mouseDown(with:event(.leftMouseDown,screen(locked.end.cg)))
      XCTAssertNil(view.rulerEditingBefore)
      view.mouseDragged(with:event(.leftMouseDragged,screen(CGPoint(x:160,y:150))))
      view.mouseUp(with:event(.leftMouseUp,screen(CGPoint(x:160,y:150))))
      XCTAssertEqual(s.rulerMeasurements.count,2,"\(tool)");XCTAssertEqual(s.rulerMeasurements[0],locked)
      XCTAssertEqual(s.rulerMeasurements[1].drawingTool,tool);s.undo();XCTAssertEqual(s.rulerMeasurements,[locked])
    }
  }
  @MainActor func testInspectorResizesAboutCenterAndKeepsSource() throws {
    let s = store();s.addLayer(.raster)
    s.updateSelected("测试") {$0.x = 30;$0.y = 40;$0.width = 80;$0.height = 60;$0.rotation = 37;$0.aspectLocked = true;$0.assetID = "source"}
    let before = s.document
    s.beginTransaction("尺寸");s.resizeSelectedFromCenter(width:160);s.resizeSelectedFromCenter(height:90);s.endTransaction()
    let layer = try XCTUnwrap(s.selected)
    XCTAssertEqual(layer.width,120,accuracy:0.001);XCTAssertEqual(layer.height,90)
    XCTAssertEqual(layer.x+layer.width/2,70);XCTAssertEqual(layer.y+layer.height/2,70)
    XCTAssertEqual(layer.rotation,37);XCTAssertEqual(layer.assetID,"source")
    s.undo();XCTAssertEqual(s.document,before)
  }
  @MainActor func testSelectionFrameIncludesAllSelectedContentAndFolderChildren() throws {
    let s = store();var folder = ImageLayer(name:"folder",kind:.group,width:300,height:220)
    folder.x = -100
    var a = ImageLayer(name:"A",kind:.shape,width:40,height:30);a.x = 20;a.y = 30;a.rotation = 45;a.parentID = folder.id
    var b = ImageLayer(name:"B",kind:.raster,width:50,height:60);b.x = 180;b.y = 140
    s.active.document.layers = [folder,a,b];s.selectLayer(folder.id);s.toggleLayerSelection(b.id)
    let bounds = try XCTUnwrap(s.selectedContentBounds)
    XCTAssertEqual(bounds,SnapEngine.bounds(a).union(SnapEngine.bounds(b)))
    XCTAssertGreaterThan(bounds.width,b.width);XCTAssertGreaterThan(bounds.height,b.height)
  }
  @MainActor func testRelativeScrubAccumulatesWithoutDisplayCoordinates() {
    var value = 1000.0,beginCount = 0,endCount = 0
    let field = ScrubNumberField(value:Binding(get:{value},set:{value = $0}),range:0...100000,digits:1,beginEditing:{beginCount += 1},endEditing:{endCount += 1})
    let coordinator = ScrubNumberField.Coordinator(field)
    coordinator.start(at:value)
    var motion = ScrubMotion()
    for _ in 0..<2000 {motion.append(delta:12)}
    coordinator.update(translation:motion.translation)
    XCTAssertEqual(value,25000)
    for _ in 0..<4000 {motion.append(delta:-12)}
    coordinator.update(translation:motion.translation);XCTAssertEqual(value,0)
    coordinator.finish();XCTAssertEqual(beginCount,1);XCTAssertEqual(endCount,1)
  }
  @MainActor func testDraggingEarlierSelectedObjectKeepsMultiSelection() throws {
    let s = store();s.chooseTool(.move);s.snapping = false
    var a = ImageLayer(name:"A",kind:.shape,width:50,height:50);a.x = 10;a.y = 10;a.cornerRadius = 0
    var b = a;b.id = UUID();b.x = 180;b.y = 100
    s.active.document.layers = [a,b];s.selectLayer(a.id);s.toggleLayerSelection(b.id)
    let view = CanvasNSView(frame:CGRect(x:0,y:0,width:900,height:700));view.store = s
    func screen(_ p:CGPoint)->CGPoint {view.convert(CGPoint(x:view.imageRect.minX+p.x*view.scale,y:view.imageRect.minY+p.y*view.scale),to:nil)}
    view.mouseDown(with:event(.leftMouseDown,screen(CGPoint(x:30,y:30))))
    XCTAssertEqual(s.selectedIDs,[a.id,b.id]);XCTAssertNil(view.handle)
    view.mouseDragged(with:event(.leftMouseDragged,screen(CGPoint(x:60,y:60))))
    view.mouseUp(with:event(.leftMouseUp,screen(CGPoint(x:60,y:60))))
    XCTAssertEqual(s.document.layers[0].x,40,accuracy:0.01);XCTAssertEqual(s.document.layers[1].x,210,accuracy:0.01)
  }
  @MainActor func testNativeImportedThumbnailCannotStealEyeHit() throws {
    _ = NSApplication.shared
    for size in [(1600,40),(40,1600)] {
      let s = store();s.addLayer(.raster)
      let asset = try s.active.assets.insert(image(size.0,size.1))
      s.updateSelected("导入") {$0.assetID = asset;$0.name = "LOGO6_thumbnail";$0.effects = [ImageEffect(.outline),ImageEffect(.shadow)]}
      let host = NSHostingView(rootView:LayerPanel(store:s).row(s.selected!).frame(width:240,height:60))
      let window = NSWindow(contentRect:CGRect(x:0,y:0,width:240,height:60),styleMask:.borderless,backing:.buffered,defer:false)
      window.isReleasedWhenClosed = false;window.contentView = host;host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until:Date(timeIntervalSinceNow:0.03));host.layoutSubtreeIfNeeded()
      func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
      let eye = try XCTUnwrap(descendants(host).compactMap {$0 as? VisibilityButton}.first)
      let thumbnail = try XCTUnwrap(descendants(host).compactMap {$0 as? ThumbnailView}.first)
      let center = eye.convert(CGPoint(x:eye.bounds.midX,y:eye.bounds.midY),to:host)
      let hit = try XCTUnwrap(host.hitTest(center))
      XCTAssertTrue(hit === eye || hit.isDescendant(of:eye),"The drawn eye must own its center for \(size)")
      XCTAssertNil(thumbnail.hitTest(CGPoint(x:-10,y:18)))
      eye.performClick(nil);XCTAssertEqual(s.selected?.visible,false)
      eye.performClick(nil);XCTAssertEqual(s.selected?.visible,true)
      window.close()
    }
  }
  func testPixelSampleMatchesMarkedPixelAtEdges() throws {
    let cg = image(11,7)
    let sample = try XCTUnwrap(CanvasPixelSample.read(cg,point:CGPoint(x:299.9,y:219.9),canvas:CGSize(width:300,height:220)))
    XCTAssertEqual(sample.x,10);XCTAssertEqual(sample.y,6);XCTAssertEqual(sample.hex,"#0000FF")
    XCTAssertNil(CanvasPixelSample.read(cg,point:CGPoint(x:-0.1,y:1),canvas:CGSize(width:300,height:220)))
  }
  @MainActor func testTextOutlineDefaultShieldAndImageFilledStroke() throws {
    let s = store()
    var text = ImageLayer(name:"文字",kind:.text,width:120,height:190);text.x = 70;text.y = 10;text.text = "I";text.fontName = "HelveticaNeue-Bold";text.fontSize = 150;text.color = RGBA(r:1,g:1,b:1)
    var stroke = ImageEffect(.outline);stroke.radius = 10;stroke.tint = RGBA(r:1,g:0,b:0)
    XCTAssertEqual(stroke.value("ignoreClipping"),1)
    text.effects = [stroke]
    var photo = ImageLayer(name:"图片",kind:.raster,width:300,height:220);photo.assetID = try s.active.assets.insert(image());photo.clippingMask = true
    var doc = s.document;doc.layers = [photo,text]
    let shielded = try XCTUnwrap(s.renderer.render(doc,assets:s.active.assets,maxDimension:nil))
    doc.layers[1].effects[0].set("ignoreClipping",0)
    let unshielded = try XCTUnwrap(s.renderer.render(doc,assets:s.active.assets,maxDimension:nil))
    let a = NSBitmapImageRep(cgImage:shielded),b = NSBitmapImageRep(cgImage:unshielded)
    var imageStrokePixels = 0
    for y in 0..<220 {for x in 0..<300 {
      let old = a.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!,new = b.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
      if old.alphaComponent > 0.95,old.redComponent > 0.9,old.blueComponent < 0.1,new.blueComponent > 0.9,new.redComponent < 0.1 {imageStrokePixels += 1}
    }}
    XCTAssertGreaterThan(imageStrokePixels,100,"Unshielded stroke must contain the upper image rather than the fixed stroke tint")
  }
  @MainActor func testEffectReorderingIsStableAndOneUndo() throws {
    let s = store();s.addLayer(.raster)
    s.addEffect(.grain);s.addEffect(.outline);s.addEffect(.shadow)
    let before = s.document,effects = s.selected!.effects
    s.beginTransaction("排序")
    for _ in 0..<10 {s.moveInspectorEffect(effects[0].id,relativeTo:effects[2].id,after:true)}
    s.endTransaction()
    XCTAssertEqual(s.selected?.effects.map(\.id),[effects[1].id,effects[2].id,effects[0].id])
    s.undo();XCTAssertEqual(s.document,before)
  }
}
