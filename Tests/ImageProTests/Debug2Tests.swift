import AppKit
import CoreImage
import XCTest
@testable import ImagePro

final class Debug2Tests: XCTestCase {
  func testPreviewRetainsGeometryWhileEffectsChange() throws {
    let renderer = ImageRenderer()
    var layer = ImageLayer(name: "shape", kind: .shape, width: 100, height: 80)
    layer.cornerRadius = 0
    let cached = try XCTUnwrap(renderer.previewLayer(layer, assets: AssetLibrary(), scale: 1))
    layer.effects = [ImageEffect(.shadow)]
    let shadow = try XCTUnwrap(renderer.previewLayer(layer, assets: AssetLibrary(), scale: 1))
    XCTAssertEqual(cached.extent, CGRect(x: 0, y: 0, width: 100, height: 80))
    XCTAssertLessThan(shadow.extent.minX, 0)
    XCTAssertEqual(cached.contentSize, shadow.contentSize)
  }
  func testMaskPaintingIsIndependentOfLayerContent() throws {
    let renderer = ImageRenderer(), assets = AssetLibrary()
    var layer = ImageLayer(name: "masked", kind: .shape, width: 32, height: 32)
    layer.shape = "rectangle"; layer.cornerRadius = 0
    let mask = try XCTUnwrap(SelectionEngine.mask(SelectionRegion(type: "rectangle", points: [.init(x:0,y:0),.init(x:32,y:32)]), size: CGSize(width:32,height:32)))
    layer.maskAssetID = try assets.insert(mask)
    layer.maskStrokes = [BrushStroke(points:[.init(x:16,y:16)],color:.init(r:0,g:0,b:0),size:16,opacity:1,hardness:1)]
    let hidden = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.renderLayer(layer,assets:assets)))
    XCTAssertLessThan(try XCTUnwrap(hidden.colorAt(x:16,y:16)).alphaComponent,0.1)
    layer.maskInverted = true
    let visible = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.renderLayer(layer,assets:assets)))
    XCTAssertGreaterThan(try XCTUnwrap(visible.colorAt(x:16,y:16)).alphaComponent,0.9)
    XCTAssertTrue(layer.strokes.isEmpty)
  }
  func testHighlightsIncreaseToTheRight() throws {
    let ci = CIImage(color: CIColor(red:0.8,green:0.8,blue:0.8)).cropped(to:CGRect(x:0,y:0,width:4,height:4))
    var effect = ImageEffect(.color)
    effect.set("highlights",-0.7)
    let dark = AdvancedEffects.apply(effect,image:ci,scale:1)!
    effect.set("highlights",0.7)
    let light = AdvancedEffects.apply(effect,image:ci,scale:1)!
    let context = CIContext()
    func red(_ input: CIImage) throws -> Double {
      let image = try XCTUnwrap(context.createCGImage(input,from:ci.extent))
      return try XCTUnwrap(NSBitmapImageRep(cgImage:image).colorAt(x:1,y:1)).redComponent
    }
    XCTAssertGreaterThan(try red(light),try red(dark)+0.02)
  }
  func testEveryBlendModeProducesFinitePixels() throws {
    let source = CIImage(color:CIColor(red:0.8,green:0.3,blue:0.1,alpha:0.7)).cropped(to:CGRect(x:0,y:0,width:8,height:8))
    let back = CIImage(color:CIColor(red:0.2,green:0.6,blue:0.7)).cropped(to:source.extent)
    let context = CIContext()
    XCTAssertNotNil(LayerBlending.special); XCTAssertNotNil(LayerBlending.dissolve)
    for mode in BlendMode.allCases {
      let output = LayerBlending.apply(mode,source:source,background:back,extent:source.extent)
      XCTAssertNotNil(context.createCGImage(output,from:source.extent),mode.rawValue)
    }
  }
  func testMeshGradientChangesAfterMovingAColorNode() throws {
    XCTAssertNotNil(GradientRenderer.meshKernel)
    var gradient = GradientDefinition.mesh([RGBA(r:1,g:0,b:0),RGBA(r:0,g:0,b:1)])
    let first = GradientRenderer.render(gradient,width:64,height:64)
    gradient.nodes[0].point = .init(x:0.8,y:0.8)
    let second = GradientRenderer.render(gradient,width:64,height:64)
    XCTAssertNotEqual(first.dataProvider?.data as Data?,second.dataProvider?.data as Data?)
    let roundtrip = try JSONDecoder().decode(GradientDefinition.self,from:JSONEncoder().encode(gradient))
    XCTAssertEqual(roundtrip,gradient)
  }
  func testAdjustmentLayerAffectsOnlyLayersBelowIt() throws {
    var doc = ImageDocument(); doc.width = 8; doc.height = 8
    var shape = ImageLayer(name:"base",kind:.shape,width:8,height:8)
    shape.color = .init(r:0.3,g:0.3,b:0.3); shape.cornerRadius = 0
    var adjustment = ImageLayer(name:"FX",kind:.adjustment,width:8,height:8)
    var e = ImageEffect(.color); e.exposure = 1; adjustment.effects = [e]
    let renderer = ImageRenderer(), assets = AssetLibrary()
    doc.layers = [adjustment,shape]
    let light = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil)))
    doc.layers = [shape,adjustment]
    let dark = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.render(doc,assets:assets,maxDimension:nil)))
    XCTAssertGreaterThan(try XCTUnwrap(light.colorAt(x:4,y:4)).redComponent,try XCTUnwrap(dark.colorAt(x:4,y:4)).redComponent+0.1)
  }
  @MainActor func testCropStartsWithExistingSelectionAndRefineCancelRestoresContext() {
    let store = EditorStore(loadRecovery:false)
    store.selection = SelectionRegion(type:"rectangle",points:[.init(x:10,y:10),.init(x:50,y:40)])
    store.chooseTool(.crop)
    XCTAssertEqual(store.selection?.type,"crop")
    XCTAssertEqual(store.selection?.bounds,CGRect(x:10,y:10,width:40,height:30))
    let before = store.selection
    store.beginRefiningSelection(); store.refineExpand = 20
    store.finishRefinement(cancel:true)
    XCTAssertEqual(store.selection,before); XCTAssertFalse(store.refiningSelection)
  }
}
