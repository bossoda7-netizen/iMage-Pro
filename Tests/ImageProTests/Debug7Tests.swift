import XCTest
import AppKit
import SwiftUI
import CoreImage
@testable import ImagePro

final class Debug7Tests:XCTestCase {
  let renderer = ImageRenderer()
  @MainActor func store()->EditorStore {
    let s = EditorStore(loadRecovery:false);s.newProject(name:"Debug7",width:200,height:160,background:nil);return s
  }
  func color(_ image:CGImage,_ x:Int,_ y:Int)->NSColor {NSBitmapImageRep(cgImage:image).colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!}
  @MainActor func testFXCreationWithoutSelectionIsOneUndo() throws {
    let s = store();s.addLayer(.paint);s.clearCanvasFocus();let before = s.document
    s.addEffect(.custom)
    XCTAssertEqual(s.selected?.kind,.adjustment);XCTAssertEqual(s.selected?.effects.first?.kind,.custom)
    XCTAssertTrue(s.showInspector);s.undo();XCTAssertEqual(s.document,before)
  }
  @MainActor func testPanelCommandTogglesAndShiftExtendsFromAnchor() throws {
    let s = store();for _ in 0..<6 {s.addLayer(.paint)}
    let ids = s.document.layers.map(\.id)
    s.selectLayerFromPanel(ids[1],modifiers:[]);s.selectLayerFromPanel(ids[4],modifiers:.shift)
    XCTAssertEqual(s.selectedIDs,Set(ids[1...4]))
    s.selectLayerFromPanel(ids[2],modifiers:.command);XCTAssertFalse(s.selectedIDs.contains(ids[2]))
    s.selectLayerFromPanel(ids[0],modifiers:[]);XCTAssertEqual(s.selectedIDs,[ids[0]])
  }
  @MainActor func testGroupOnlyMultipleSelectionKeepsSubtreesAndUndo() throws {
    let s = store();for _ in 0..<4 {s.addLayer(.paint)}
    let ids = s.document.layers.map(\.id),before = s.document
    s.groupSelected();XCTAssertEqual(s.document,before)
    s.selectLayerFromPanel(ids[1],modifiers:[]);s.selectLayerFromPanel(ids[3],modifiers:.command)
    let selected = s.document;s.groupSelected()
    let group = try XCTUnwrap(s.selected);XCTAssertEqual(group.kind,.group)
    XCTAssertEqual(Set(s.document.layers.filter {$0.parentID == group.id}.map(\.id)),[ids[1],ids[3]])
    XCTAssertNil(s.document.layers.first {$0.id == ids[2]}?.parentID)
    s.undo();XCTAssertEqual(s.document,selected)
  }
  @MainActor func testShiftCanvasSelectsOverlappingContentWithoutStartingTransform() throws {
    let s = store();s.chooseTool(.move)
    var a = ImageLayer(name:"A",kind:.shape,width:70,height:70);a.shape = "rectangle";a.cornerRadius = 0;a.x = 10;a.y = 10
    var b = a;b.id = UUID();b.name = "B";b.x = 70;b.y = 60
    s.active.document.layers = [a,b];s.selectLayer(b.id)
    let view = CanvasNSView(frame:CGRect(x:0,y:0,width:800,height:600));view.store = s
    let point = CGPoint(x:view.imageRect.minX+30*view.scale,y:view.imageRect.minY+30*view.scale)
    let event = try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:view.convert(point,to:nil),modifierFlags:.shift,timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0))
    view.mouseDown(with:event);XCTAssertEqual(s.selectedIDs,[a.id,b.id]);XCTAssertNil(view.initialLayer);XCTAssertNil(view.handle)
  }
  @MainActor func testRulerLockBlocksMoveDeleteAndIsUndoable() throws {
    let s = store();s.beginRulerMode();let mark = RulerMeasurement(start:Point(x:10,y:10),end:Point(x:140,y:100),tool:.guides)
    s.addRulerMeasurement(mark);s.selectedRulerID = mark.id;s.toggleRulerLock()
    let locked = try XCTUnwrap(s.rulerMeasurements.first);XCTAssertEqual(locked.locked,true)
    var moved = locked;moved.end.x += 20;s.updateRulerMeasurement(moved);s.deleteSelectedRulerMeasurement()
    XCTAssertEqual(s.rulerMeasurements,[locked]);s.undo();XCTAssertNotEqual(s.rulerMeasurements.first?.locked,true)
    s.redo();XCTAssertEqual(s.rulerMeasurements.first?.locked,true)
  }
  @MainActor func testMultiSelectionMenuDoesNotExposeSinglePathActions() throws {
    let s = store();s.addLayer(.paint);s.addLayer(.paint)
    let ids = s.document.layers.map(\.id)
    s.updateSelected("路径测试") {$0.bezierAnchors = [BezierAnchor(point:Point(x:0,y:0))]}
    s.selectLayerFromPanel(ids[0],modifiers:[]);s.selectLayerFromPanel(ids[1],modifiers:.command)
    let view = CanvasNSView(frame:CGRect(x:0,y:0,width:800,height:600));view.store = s
    let event = try XCTUnwrap(NSEvent.mouseEvent(with:.rightMouseDown,location:CGPoint(x:-100,y:-100),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0))
    let titles = try XCTUnwrap(view.menu(for:event)).items.filter {!$0.isSeparatorItem}.map(\.title)
    XCTAssertEqual(titles,["编组","合并选中图层","删除选中图层"])
  }
  func testOpacityAndStrengthAreIndependentWithoutLegacyMultiplier() throws {
    let image = CIImage(color:CIColor(red:0.2,green:0.3,blue:0.4)).cropped(to:CGRect(x:0,y:0,width:20,height:20))
    var effect = ImageEffect(.custom);effect.filterName = "CIColorInvert";effect.intensity = 0.5;effect.amount = 1
    let full = try XCTUnwrap(renderer.context.createCGImage(renderer.apply(effect,to:image,scale:1),from:image.extent))
    effect.amount = 0.5
    let half = try XCTUnwrap(renderer.context.createCGImage(renderer.apply(effect,to:image,scale:1),from:image.extent))
    XCTAssertGreaterThan(color(full,10,10).redComponent,color(half,10,10).redComponent)
    effect.amount = 0
    let zero = try XCTUnwrap(renderer.context.createCGImage(renderer.apply(effect,to:image,scale:1),from:image.extent))
    XCTAssertEqual(color(zero,10,10).redComponent,0.2,accuracy:0.02)
    XCTAssertEqual(ImageEffect(.grain).value("strength"),0.275,accuracy:0.0001)
    XCTAssertNil(ImageEffect(.custom).intensity)
  }
  func testClippingImageCanCoverUnshieldedOutline() throws {
    var base = ImageLayer(name:"base",kind:.shape,width:80,height:80);base.x = 20;base.y = 20;base.shape = "rectangle";base.cornerRadius = 0;base.color = RGBA(r:0,g:1,b:0)
    var upper = ImageLayer(name:"upper",kind:.shape,width:140,height:140);upper.cornerRadius = 0;upper.color = RGBA(r:0,g:0,b:1);upper.clippingMask = true
    var effect = ImageEffect(.outline);effect.radius = 8;effect.tint = RGBA(r:1,g:0,b:0);effect.set("ignoreClipping",0)
    base.effects = [effect]
    var doc = ImageDocument();doc.width = 140;doc.height = 140;doc.layers = [upper,base]
    let included = try XCTUnwrap(renderer.render(doc,assets:AssetLibrary(),maxDimension:nil))
    doc.layers[1].effects[0].set("ignoreClipping",1)
    let excluded = try XCTUnwrap(renderer.render(doc,assets:AssetLibrary(),maxDimension:nil))
    XCTAssertGreaterThan(color(included,15,50).blueComponent,0.9)
    XCTAssertGreaterThan(color(excluded,15,50).redComponent,0.9)
  }
  func testClippingShieldChangesOutlineAndShadowOnTranslucentBase() throws {
    for kind in [EffectKind.outline,.shadow] {
      var base = ImageLayer(name:"base",kind:.shape,width:70,height:70)
      base.x = 30;base.y = 30;base.shape = "rectangle";base.cornerRadius = 0;base.color = RGBA(r:0,g:1,b:0,a:0.4)
      var upper = base;upper.id = UUID();upper.width = 35;upper.color = RGBA(r:0,g:0,b:1);upper.clippingMask = true
      var style = ImageEffect(kind);style.tint = RGBA(r:1,g:0,b:0);style.radius = 8;style.set("spread",1);style.set("ignoreClipping",0)
      base.effects = [style]
      var doc = ImageDocument();doc.width = 140;doc.height = 140;doc.layers = [upper,base]
      let included = try XCTUnwrap(renderer.render(doc,assets:AssetLibrary(),maxDimension:nil))
      doc.layers[1].effects[0].set("ignoreClipping",1)
      let excluded = try XCTUnwrap(renderer.render(doc,assets:AssetLibrary(),maxDimension:nil))
      XCTAssertNotEqual(included.dataProvider?.data as Data?,excluded.dataProvider?.data as Data?,"\(kind) must respect the clipping shield")
    }
  }
  @MainActor func testDragKeepsWindowWhenLazySourceLeavesHierarchy() throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect:CGRect(x:0,y:0,width:400,height:400),styleMask:.borderless,backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false;defer {window.close()}
    let source = LayerDragNSView(frame:CGRect(x:0,y:300,width:100,height:40)),target = LayerDropNSView(frame:CGRect(x:0,y:20,width:100,height:60))
    window.contentView?.addSubview(source);window.contentView?.addSubview(target)
    var dropped = false;target.drop = {dropped = true}
    func event(_ type:NSEvent.EventType,_ y:Double)->NSEvent {NSEvent.mouseEvent(with:type,location:CGPoint(x:20,y:y),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:0)!}
    source.mouseDown(with:event(.leftMouseDown,320));source.mouseDragged(with:event(.leftMouseDragged,250))
    source.removeFromSuperview();source.mouseDragged(with:event(.leftMouseDragged,40));source.mouseUp(with:event(.leftMouseUp,40))
    XCTAssertTrue(dropped)
  }
  @MainActor func testFloatingDragUsesWindowCoordinatesAfterViewMoves() {
    let view = ScopeDragView(frame:CGRect(x:0,y:0,width:100,height:30));var delta = CGPoint.zero
    view.changed = {delta = $0}
    func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double)->NSEvent {NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:y),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0)!}
    view.mouseDown(with:event(.leftMouseDown,30,150));view.mouseDragged(with:event(.leftMouseDragged,80,100))
    view.frame.origin = CGPoint(x:50,y:50);view.mouseDragged(with:event(.leftMouseDragged,90,90))
    XCTAssertEqual(delta,CGPoint(x:60,y:60));view.mouseUp(with:event(.leftMouseUp,90,90))
  }
  @MainActor func testEdgeAutoscrollContinuesAfterLazyRowDisappears() throws {
    final class FlippedDocument:NSView {override var isFlipped:Bool {true}}
    _ = NSApplication.shared
    let window = NSWindow(contentRect:CGRect(x:0,y:0,width:400,height:400),styleMask:.borderless,backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false;defer {window.close()}
    let scroll = NSScrollView(frame:CGRect(x:0,y:0,width:250,height:350));scroll.hasVerticalScroller = true
    let document = FlippedDocument(frame:CGRect(x:0,y:0,width:230,height:4000));scroll.documentView = document
    window.contentView?.addSubview(scroll)
    let source = LayerDragNSView(frame:CGRect(x:20,y:20,width:180,height:40));document.addSubview(source)
    func event(_ type:NSEvent.EventType,_ location:CGPoint)->NSEvent {NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:0)!}
    let start = source.convert(CGPoint(x:30,y:20),to:nil)
    let edge = scroll.contentView.convert(CGPoint(x:80,y:scroll.contentView.bounds.maxY-2),to:nil)
    source.mouseDown(with:event(.leftMouseDown,start));source.mouseDragged(with:event(.leftMouseDragged,edge))
    RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
    let first = scroll.contentView.bounds.minY;XCTAssertGreaterThan(first,0)
    source.removeFromSuperview();RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
    XCTAssertGreaterThan(scroll.contentView.bounds.minY,first)
    source.mouseUp(with:event(.leftMouseUp,edge))
  }
  func testShadowSpreadStaysWithinConfiguredRadius() throws {
    let image = CIImage(color:.white).cropped(to:CGRect(x:40,y:40,width:40,height:40))
    var effect = ImageEffect(.shadow);effect.radius = 5;effect.set("spread",1);effect.set("distance",0)
    let extent = CGRect(x:0,y:0,width:120,height:120)
    let rendered = try XCTUnwrap(renderer.context.createCGImage(renderer.apply(effect,to:image,scale:1),from:extent))
    XCTAssertLessThan(color(rendered,25,60).alphaComponent,0.01)
    XCTAssertGreaterThan(color(rendered,37,60).alphaComponent,0.9)
  }
  @MainActor func testDragHitRegionDoesNotCoverNeighboringEye() {
    _ = NSApplication.shared
    let parent = NSView(frame:CGRect(x:0,y:0,width:300,height:60)),surface = LayerDragNSView(frame:CGRect(x:50,y:0,width:200,height:60))
    parent.addSubview(surface);XCTAssertNil(surface.hitTest(CGPoint(x:20,y:30)))
    XCTAssertTrue(surface.hitTest(CGPoint(x:100,y:30)) === surface)
  }
}
