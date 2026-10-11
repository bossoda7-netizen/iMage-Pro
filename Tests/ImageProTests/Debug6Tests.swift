import XCTest
import AppKit
import CoreImage
import SwiftUI
@testable import ImagePro

final class Debug6Tests:XCTestCase {
  let renderer = ImageRenderer()
  func pixel(_ image:CGImage,_ x:Int,_ y:Int)->NSColor {NSBitmapImageRep(cgImage:image).colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!}
  func asset(_ w:Int = 40,_ h:Int = 30,color:NSColor = .red) throws -> CGImage {
    let context = try XCTUnwrap(ImageRenderer.bitmap(w,h));context.setFillColor(color.cgColor);context.fill(CGRect(x:0,y:0,width:w,height:h));return try XCTUnwrap(context.makeImage())
  }
  @MainActor func store() -> EditorStore {
    let s = EditorStore(loadRecovery:false);s.newProject(name:"Debug6",width:160,height:120,background:nil);return s
  }
  @MainActor func testExpandedRasterPreservesWorldGeometryAndOriginalAsset() throws {
    let s = store();var layer = ImageLayer(name:"图像",kind:.raster,width:40,height:30)
    layer.x = 50;layer.y = 40;layer.rotation = 25;layer.flippedX = true
    layer.assetID = try s.active.assets.insert(asset());let original = layer
    let assetData = s.active.assets.snapshot();let world = TransformGeometry.displayPoint(CGPoint(x:10,y:12),layer:layer)
    let offset = LayerExpansion.expand(&layer,including:[Point(x:-25,y:-17),Point(x:70,y:50)],radius:8)
    let after = TransformGeometry.displayPoint(CGPoint(x:10+offset.x,y:12+offset.y),layer:layer)
    XCTAssertEqual(world.x,after.x,accuracy:0.001);XCTAssertEqual(world.y,after.y,accuracy:0.001)
    XCTAssertEqual(s.active.assets.snapshot(),assetData)
    XCTAssertEqual(layer.rasterPlacement!.width*layer.width,original.width,accuracy:0.001)
    let rendered = try XCTUnwrap(renderer.renderLayer(layer,assets:s.active.assets))
    XCTAssertGreaterThan(pixel(rendered,Int(offset.x+10),Int(offset.y+12)).redComponent,0.95)
    XCTAssertLessThan(pixel(rendered,0,0).alphaComponent,0.01)
  }
  @MainActor func testSpecialDrawingExpandsWithoutScalingOriginalShape() throws {
    let s = store();var layer = ImageLayer(name:"形状",kind:.shape,width:20,height:20);layer.x = 40;layer.y = 40;layer.color = RGBA(r:1,g:0,b:0)
    s.active.document.layers = [layer];s.active.document.selectedLayerID = layer.id
    s.appendStroke(BrushStroke(points:[Point(x:40,y:10)],color:RGBA(r:0,g:0,b:1),size:4,opacity:1,hardness:1))
    let expanded = try XCTUnwrap(s.selected);XCTAssertGreaterThan(expanded.width,20)
    XCTAssertEqual(expanded.contentPlacement!.width*expanded.width,20,accuracy:0.001)
    let image = try XCTUnwrap(renderer.render(s.document,assets:s.active.assets,maxDimension:nil))
    XCTAssertGreaterThan(pixel(image,50,50).redComponent,0.9)
    XCTAssertLessThan(pixel(image,67,50).alphaComponent,0.01)
    XCTAssertGreaterThan(pixel(image,80,50).blueComponent,0.9)
    s.undo();XCTAssertEqual(s.selected,layer)
  }
  @MainActor func testDrawingOutsideDeformedLayerPreservesMaskEffectsAndUndo() throws {
    for warp in [false,true] {
      let s = store();var layer = ImageLayer(name:"变形图层",kind:.raster,width:40,height:30)
      layer.x = 35;layer.y = 30;layer.assetID = try s.active.assets.insert(asset())
      if warp {var grid = TransformGeometry.denseWarpGrid;grid[24].x += 0.07;layer.warpNodes = grid}
      else {layer.quad = [Point(x:0.1,y:0),Point(x:1,y:0.1),Point(x:0.9,y:1),Point(x:0,y:0.9)]}
      let mask = try XCTUnwrap(ImageRenderer.bitmap(40,30))
      mask.setFillColor(NSColor.white.cgColor);mask.fill(CGRect(x:0,y:0,width:40,height:30))
      mask.setFillColor(NSColor.black.cgColor);mask.fill(CGRect(x:0,y:0,width:14,height:30))
      layer.maskAssetID = try s.active.assets.insert(try XCTUnwrap(mask.makeImage()))
      layer.maskDensity = 0.8;layer.effects = [ImageEffect(.color)]
      s.active.document.layers = [layer];s.active.document.selectedLayerID = layer.id
      let before = try XCTUnwrap(renderer.render(s.document,assets:s.active.assets,maxDimension:nil))
      s.appendStroke(BrushStroke(points:[Point(x:95,y:15)],color:RGBA(r:0,g:0,b:1),size:4,opacity:1,hardness:1))
      let afterLayer = try XCTUnwrap(s.selected)
      XCTAssertNil(afterLayer.quad);XCTAssertNil(afterLayer.warpNodes)
      XCTAssertGreaterThan(afterLayer.width,layer.width)
      XCTAssertEqual(afterLayer.effects,layer.effects);XCTAssertEqual(afterLayer.maskDensity,0.8)
      XCTAssertNotNil(afterLayer.maskAssetID);XCTAssertNotNil(s.active.assets.image(layer.assetID))
      let after = try XCTUnwrap(renderer.render(s.document,assets:s.active.assets,maxDimension:nil))
      for local in [CGPoint(x:6,y:15),CGPoint(x:26,y:15)] {
        let p = TransformGeometry.displayPoint(local,layer:layer),x = Int(p.x),y = Int(p.y)
        XCTAssertEqual(pixel(before,x,y).alphaComponent,pixel(after,x,y).alphaComponent,accuracy:0.04)
      }
      s.undo();XCTAssertEqual(s.selected,layer)
    }
  }
  @MainActor func testPixelBrushExpandsDeformedStorageInWorldCoordinates() throws {
    let s = store();var layer = ImageLayer(name:"图像",kind:.raster,width:40,height:30)
    layer.x = 40;layer.y = 40;layer.quad = TransformGeometry.corners
    layer.assetID = try s.active.assets.insert(asset());s.active.document.layers = [layer];s.active.document.selectedLayerID = layer.id
    XCTAssertTrue(s.expandPixelBounds(including:[CGPoint(x:120,y:50)]))
    let result = try XCTUnwrap(s.selected);XCTAssertNil(result.quad)
    let p = TransformGeometry.contentPoint(CGPoint(x:120,y:50),layer:result)
    XCTAssertGreaterThan(p.x,0);XCTAssertLessThan(p.x,result.width)
    s.undo();XCTAssertEqual(s.selected,layer)
  }
  @MainActor func testClickOutsideNumberEndsNativeEditing() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect:CGRect(x:0,y:0,width:400,height:240),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    let field = ScrubTextField(frame:CGRect(x:20,y:20,width:100,height:24))
    field.isEditable = true;field.stringValue = "12";window.contentView?.addSubview(field)
    window.makeFirstResponder(field)
    FieldFocus.dismiss(in:window,at:CGPoint(x:50,y:25));XCTAssertTrue(window.firstResponder === field)
    field.selectText(nil);XCTAssertNotNil(field.currentEditor())
    FieldFocus.dismiss(in:window,at:CGPoint(x:250,y:120));XCTAssertNil(field.currentEditor())
    XCTAssertFalse(window.firstResponder === field)
    window.close()
  }
  @MainActor func testInsertionIsAboveSelectionAndKeepsFolderParent() throws {
    let s = store();s.addLayer(.paint);let bottom = try XCTUnwrap(s.selected?.id)
    s.addLayer(.paint);let top = try XCTUnwrap(s.selected?.id)
    s.selectLayer(bottom);s.addGradient(from:.zero,to:CGPoint(x:100,y:100))
    XCTAssertEqual(s.document.layers[0].id,top);XCTAssertEqual(s.document.layers[2].id,bottom)
    s.addLayer(.group);let group = try XCTUnwrap(s.selected?.id)
    s.createBezierPath([BezierAnchor(point:Point(x:0,y:0)),BezierAnchor(point:Point(x:50,y:50))],closed:false)
    XCTAssertNil(s.selected?.parentID)
    XCTAssertEqual(s.document.layers.firstIndex(where:{$0.id == s.selected?.id})!+1,s.document.layers.firstIndex(where:{$0.id == group}))
  }
  @MainActor func testRulerHistoryCannotUndoDocumentAndCancelRestoresDeletedMarks() throws {
    let s = store();s.addLayer(.paint);let before = s.document,history = s.active.undo.count
    let mark = RulerMeasurement(start:Point(x:10,y:10),end:Point(x:80,y:70),tool:.compass)
    s.rulerMeasurements = [mark];s.beginRulerMode();s.undo()
    XCTAssertEqual(s.document,before);XCTAssertEqual(s.active.undo.count,history)
    s.selectedRulerID = mark.id;s.deleteSelectedRulerMeasurement();XCTAssertTrue(s.rulerMeasurements.isEmpty)
    s.undo();XCTAssertEqual(s.rulerMeasurements,[mark]);s.redo();XCTAssertTrue(s.rulerMeasurements.isEmpty)
    s.cancelRulerMode();XCTAssertEqual(s.rulerMeasurements,[mark]);XCTAssertEqual(s.document,before)
  }
  @MainActor func testRulerDrawingCommitsWhenEnteredFromCropOrRetouch() throws {
    let s = store(),view = CanvasNSView(frame:CGRect(x:0,y:0,width:1000,height:700));view.store = s
    for tool in [ToolCategory.crop,.retouch,.text] {
      s.chooseTool(tool);s.beginRulerMode()
      let p = CGPoint(x:view.imageRect.midX,y:view.imageRect.midY)
      func event(_ type:NSEvent.EventType,_ point:CGPoint)->NSEvent {NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:1,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0)!}
      view.mouseDown(with:event(.leftMouseDown,p));view.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:p.x+40,y:p.y+20)))
      let before = s.rulerMeasurements.count
      view.mouseUp(with:event(.leftMouseUp,CGPoint(x:p.x+40,y:p.y+20)))
      XCTAssertEqual(s.rulerMeasurements.count,before+1)
      s.cancelRulerMode()
    }
  }
  func testRulerToolsHaveDistinctHitGeometry() {
    let circle = RulerMeasurement(start:Point(x:50,y:50),end:Point(x:90,y:50),tool:.compass)
    XCTAssertEqual(circle.distance(to:CGPoint(x:50,y:90)),0,accuracy:0.001)
    let arc = RulerMeasurement(start:Point(x:50,y:50),end:Point(x:90,y:50),tool:.protractor)
    XCTAssertEqual(arc.distance(to:CGPoint(x:50,y:10)),0,accuracy:0.001)
    let guides = RulerMeasurement(start:Point(x:20,y:20),end:Point(x:90,y:80),tool:.guides)
    XCTAssertEqual(guides.distance(to:CGPoint(x:90,y:400)),0,accuracy:0.001)
  }
  @MainActor func testMultiSelectionMovesWholeFolderAndUndoIsOneGesture() throws {
    let s = store();s.addLayer(.group);let group = try XCTUnwrap(s.selected?.id);s.addLayer(.paint)
    let child = try XCTUnwrap(s.selected?.id);s.moveLayerIntoGroup(child,group:group);s.selectLayer(group);s.toggleLayerSelection(child)
    let ids = s.descendants(of:s.selectedIDs),originals = s.document.layers.filter {ids.contains($0.id)},before = s.document
    s.beginTransaction("移动");s.moveSelection(from:originals,delta:CGPoint(x:17,y:-9));s.endTransaction()
    for layer in s.document.layers where ids.contains(layer.id) {XCTAssertEqual(layer.x,17);XCTAssertEqual(layer.y,-9)}
    s.undo();XCTAssertEqual(s.document,before)
  }
  @MainActor func testFolderEffectsAreAppliedToCombinedPixelsOnce() throws {
    let s = store();s.active.document.width = 100;s.active.document.height = 60
    var group = ImageLayer(name:"组",kind:.group,width:100,height:60)
    var effect = ImageEffect(.color);effect.brightness = 0.2;group.effects = [effect];group.opacity = 0.5
    var a = ImageLayer(name:"A",kind:.raster,width:60,height:60);a.assetID = try s.active.assets.insert(asset(60,60,color:.gray));a.parentID = group.id
    var b = a;b.id = UUID();b.x = 40
    s.active.document.layers = [group,a,b]
    let result = try XCTUnwrap(renderer.render(s.document,assets:s.active.assets,maxDimension:nil))
    let outside = pixel(result,20,30),overlap = pixel(result,50,30)
    XCTAssertEqual(outside.alphaComponent,0.5,accuracy:0.02);XCTAssertEqual(overlap.alphaComponent,0.5,accuracy:0.02)
    XCTAssertEqual(outside.redComponent,overlap.redComponent,accuracy:0.02)
  }
  @MainActor func testMergeDownIncludesFoldersAndPreservesHigherLayer() throws {
    let s = store();s.addLayer(.paint);let bottom = try XCTUnwrap(s.selected?.id);s.addLayer(.group);s.addLayer(.paint)
    let child = try XCTUnwrap(s.selected?.id);let group = try XCTUnwrap(s.document.layers.first(where:{$0.kind == .group})?.id);s.moveLayerIntoGroup(child,group:group)
    s.active.document.selectedLayerID = group;s.addLayer(.paint);let high = try XCTUnwrap(s.selected?.id)
    s.active.document.layers.removeAll {$0.id == high};var highLayer = ImageLayer(name:"上方",kind:.paint,width:160,height:120);highLayer.id = high;s.active.document.layers.insert(highLayer,at:0)
    s.mergeDownAll(group)
    XCTAssertEqual(s.document.layers.count,2);XCTAssertEqual(s.document.layers[0].id,high)
    XCTAssertFalse(s.document.layers.contains {$0.id == child || $0.id == bottom || $0.id == group})
  }
  @MainActor func testClipboardPreservesFolderHierarchyAndSelectedPixels() throws {
    let s = store();s.addLayer(.group);let originalGroup = try XCTUnwrap(s.selected?.id);s.addLayer(.paint)
    let child = try XCTUnwrap(s.selected?.id);s.moveLayerIntoGroup(child,group:originalGroup)
    s.selectLayer(originalGroup);s.copySelectedLayer();s.pasteLayer()
    let groups = s.document.layers.filter {$0.kind == .group};XCTAssertEqual(groups.count,2)
    XCTAssertNotEqual(groups[0].id,groups[1].id)
    for group in groups {XCTAssertEqual(s.document.layers.filter {$0.parentID == group.id}.count,1)}
    s.showInspector = true;s.addEffect(.grain);s.copySelectedLayer();s.selectLayer(originalGroup);s.pasteLayer()
    XCTAssertEqual(s.selected?.effects.last?.kind,.grain)
  }
  @MainActor func testProjectRoundtripAndRepeatedOpenKeepOneTab() throws {
    let s = store();s.addLayer(.paint)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".imgp")
    defer {try? FileManager.default.removeItem(at:url)}
    try s.writeProject(s.active,to:url)
    let document = s.document;s.newStartPage();s.open(url);XCTAssertFalse(s.showWelcome)
    XCTAssertEqual(s.document.layers,document.layers)
    let count = s.sessions.count;s.open(url);XCTAssertEqual(s.sessions.count,count);XCTAssertNil(s.error)
    s.newStartPage();s.open(url);XCTAssertEqual(s.sessions.count,count);XCTAssertFalse(s.showWelcome)
  }
  @MainActor func testLibrarySortingAcrossOpenAndClosedProjects() throws {
    let s = store();s.libraryOrder = [];let id = s.active.id
    s.recentProjects = [RecentProject(path:"/tmp/a.imgp",name:"A",width:20,height:20,lastOpened:Date(),thumbnail:nil)]
    s.reorderStartPageProject(identifier:"path:/tmp/a.imgp",before:id.uuidString)
    XCTAssertEqual(s.libraryOrder.prefix(2),["/tmp/a.imgp",id.uuidString])
    s.reorderStartPageProject(identifier:"path:/tmp/a.imgp",before:id.uuidString,after:true)
    XCTAssertEqual(s.libraryOrder.prefix(2),[id.uuidString,"/tmp/a.imgp"])
    s.createProjectFolder(name:"作品");let folder = try XCTUnwrap(s.projectFolders.first?.id)
    s.moveStartPageProjectToFolder(id.uuidString,folderID:folder);XCTAssertEqual(s.active.libraryFolderID,folder)
  }
  func testBrushTipsAffectEveryMode() throws {
    for mode in ["brush","airbrush","watercolor","oil","pencil","texture","marker"] {
      func draw(_ tip:String) throws -> Data {
        let context = try XCTUnwrap(ImageRenderer.bitmap(64,64));var dynamics = BrushDynamics();dynamics.mode = mode;dynamics.tip = tip
        let stroke = BrushStroke(points:[Point(x:32,y:32)],color:RGBA(r:1,g:0,b:0),size:30,opacity:1,hardness:0.05,dynamics:dynamics)
        BrushEngine.draw(stroke,context:context);return try AssetLibrary.encode(XCTUnwrap(context.makeImage()),type:"public.png")
      }
      XCTAssertNotEqual(try draw("round"),try draw("square"),mode)
    }
  }
  func testTextTraitsAndFallbackSurviveRunImports() throws {
    var layer = ImageLayer(name:"文字",kind:.text,width:300,height:200);layer.fontName = "Menlo-Regular";layer.text = "中文ABC🙂";var style = TextStyle();style.bold = true;style.italic = true;layer.textStyle = style
    let value = TextLayout.attributed(layer)
    XCTAssertEqual(value.string,layer.text)
    let latin = value.attributes(at:2,effectiveRange:nil)
    let font = try XCTUnwrap(latin[.font] as? NSFont)
    XCTAssertTrue(NSFontManager.shared.traits(of:font).contains(.boldFontMask) || (latin[.strokeWidth] as? Double ?? 0)<0)
    XCTAssertTrue(NSFontManager.shared.traits(of:font).contains(.italicFontMask) || (latin[.obliqueness] as? Double ?? 0)>0)
  }
  func testGradientFillSupportsMultipleStopsOpacityAndRadial() throws {
    let image = CIImage(color:.white).cropped(to:CGRect(x:0,y:0,width:100,height:100))
    var effect = ImageEffect(.fillStyle);effect.style = "gradient";effect.intensity = 1
    effect.gradient = GradientDefinition(style:"linear",nodes:[GradientNode(point:Point(x:0,y:0.5),color:RGBA(r:1,g:0,b:0),position:0),GradientNode(point:Point(x:0.5,y:0.5),color:RGBA(r:0,g:1,b:0),position:0.5),GradientNode(point:Point(x:1,y:0.5),color:RGBA(r:0,g:0,b:1),position:1)],axisStart:Point(x:0,y:0.5),axisEnd:Point(x:1,y:0.5),opacityStops:[GradientOpacityStop(position:0,opacity:1),GradientOpacityStop(position:1,opacity:0.5)])
    let linear = renderer.apply(effect,to:image,scale:1),cg = try XCTUnwrap(renderer.context.createCGImage(linear,from:image.extent))
    XCTAssertGreaterThan(pixel(cg,50,50).greenComponent,0.65)
    effect.gradient?.style = "radial";effect.gradient?.axisStart = Point(x:0.5,y:0.5)
    let radial = try XCTUnwrap(renderer.context.createCGImage(renderer.apply(effect,to:image,scale:1),from:image.extent))
    XCTAssertGreaterThan(pixel(radial,50,50).redComponent,0.8)
  }
  func testScopeAvoidanceMovesOnlyRequiredDistanceAndSnaps() {
    let size = CGSize(width:200,height:160),safe = CGRect(x:18,y:74,width:1000,height:700)
    XCTAssertEqual(ScopePlacement.constrain(CGPoint(x:21,y:80),size:size,safe:safe),safe.origin)
    let origin = CGPoint(x:790,y:100),obstacle = CGRect(x:950,y:74,width:68,height:700)
    let next = ScopePlacement.avoid(origin,size:size,safe:safe,obstacles:[obstacle])
    XCTAssertEqual(next.y,100);XCTAssertEqual(next.x,738);XCTAssertFalse(CGRect(origin:next,size:size).intersects(obstacle))
  }
  func testNewEffectsAreOpaqueWithoutGlobalHalfStrength() {
    for kind in EffectKind.allCases {let effect = ImageEffect(kind);XCTAssertEqual(effect.amount,1);XCTAssertNil(effect.intensity)}
  }
  func testImportantSnapAxesHaveGreaterCaptureDistance() {
    let target = [SnapTarget(position:100,strength:2.4),SnapTarget(position:90,strength:0.5)]
    let strong = SnapEngine.weighted(110,sources:[110],targets:target,tolerance:6)
    XCTAssertEqual(strong.0,100)
    let weak = SnapEngine.weighted(94,sources:[94],targets:[target[1]],tolerance:6)
    XCTAssertEqual(weak.0,94)
  }
  @MainActor func testNativeNumberDragUpdatesBindingAndDoubleClickResetsSlider() throws {
    _ = NSApplication.shared
    var number = 50.0,started = 0,ended = 0
    let component = ScrubNumberField(value:Binding(get:{number},set:{number = $0}),range:0...100,digits:0,beginEditing:{started += 1},endEditing:{ended += 1})
    let coordinator = component.makeCoordinator(),field = ScrubTextField();field.coordinator = coordinator;coordinator.field = field
    func event(_ type:NSEvent.EventType,_ x:Double,_ count:Int = 1)->NSEvent {NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:10),modifierFlags:[],timestamp:1,windowNumber:0,context:nil,eventNumber:1,clickCount:count,pressure:0)!}
    field.mouseDown(with:event(.leftMouseDown,10));field.mouseDragged(with:event(.leftMouseDragged,25));field.mouseUp(with:event(.leftMouseUp,25))
    XCTAssertEqual(number,65);XCTAssertEqual(started,1);XCTAssertEqual(ended,1)
    let window = NSWindow(contentRect:CGRect(x:0,y:0,width:200,height:100),styleMask:.borderless,backing:.buffered,defer:false)
    field.frame = CGRect(x:10,y:10,width:100,height:24);field.isEditable = true;field.isSelectable = true
    window.contentView?.addSubview(field)
    field.mouseDown(with:event(.leftMouseDown,10));field.mouseUp(with:event(.leftMouseUp,10))
    XCTAssertTrue(window.firstResponder === field);XCTAssertNil(field.currentEditor())
    field.mouseDown(with:event(.leftMouseDown,10));field.mouseDragged(with:event(.leftMouseDragged,30));field.mouseUp(with:event(.leftMouseUp,30))
    XCTAssertEqual(number,85);XCTAssertEqual(started,2);XCTAssertEqual(ended,2)
    window.makeFirstResponder(nil)
    let slider = ResettableNSSlider();var reset = false;slider.reset = {reset = true};slider.mouseDown(with:event(.leftMouseDown,10,2));XCTAssertTrue(reset)
  }
  @MainActor func testLegLengtheningActuallyMovesAnkleAndKeepsHip() throws {
    let s = store();let c = try XCTUnwrap(ImageRenderer.bitmap(160,240));c.translateBy(x:0,y:240);c.scaleBy(x:1,y:-1);c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:160,height:240))
    c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:58,y:72,width:12,height:130));c.fill(CGRect(x:86,y:72,width:12,height:130))
    let image = try XCTUnwrap(c.makeImage());let ci = CIImage(cgImage:image)
    var effect = ImageEffect(.body);effect.set("deformation",0);effect.set("legs",1)
    effect.bodyJoints = [Point(x:0.3,y:0.15),Point(x:0.7,y:0.15),Point(x:0.4,y:0.3),Point(x:0.6,y:0.3),Point(x:0.4,y:0.55),Point(x:0.6,y:0.55),Point(x:0.4,y:0.84),Point(x:0.6,y:0.84)]
    let output = try XCTUnwrap(s.renderer.context.createCGImage(PortraitEffects.body(effect,image:ci),from:ci.extent,format:.RGBA8,colorSpace:ImageRenderer.colorSpace))
    let reference = try XCTUnwrap(s.renderer.context.createCGImage(ci,from:ci.extent,format:.RGBA8,colorSpace:ImageRenderer.colorSpace))
    // Bitmap drawing uses bottom-left space; compare moved anatomy against original by scan.
    let rep = NSBitmapImageRep(cgImage:output),original = NSBitmapImageRep(cgImage:image)
    var changes = 0
    for y in 0..<240 {let a = rep.colorAt(x:64,y:y)!.usingColorSpace(.sRGB)!,b = original.colorAt(x:64,y:y)!.usingColorSpace(.sRGB)!;if abs(a.greenComponent-b.greenComponent)>0.2 {changes += 1}}
    XCTAssertGreaterThan(changes,8)
    XCTAssertGreaterThan(pixel(image,64,229).greenComponent,0.8)
    XCTAssertLessThan(pixel(output,64,229).greenComponent,0.35)
    XCTAssertEqual(pixel(output,64,75).greenComponent,pixel(reference,64,75).greenComponent,accuracy:0.08)
  }
}
