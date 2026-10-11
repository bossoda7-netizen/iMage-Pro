import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import ImagePro

final class ImageProTests: XCTestCase {
  func testDocumentRejectsInvalidDimensionsAndFolderCycles() throws {
    var document = ImageDocument()
    document.width = .infinity
    XCTAssertThrowsError(try document.validate())
    document.width = 100
    var group = ImageLayer(name: "cycle", kind: .group, width: 100, height: 100)
    group.parentID = group.id
    document.layers = [group]
    XCTAssertThrowsError(try document.validate())
  }
  func testAssetOrientationAndLayerPosition() throws {
    let assets = AssetLibrary()
    let renderer = ImageRenderer()
    var document = ImageDocument()
    document.width = 32
    document.height = 32
    var layer = ImageLayer(name: "red", kind: .shape, width: 8, height: 8)
    layer.x = 2
    layer.y = 3
    layer.cornerRadius = 0
    layer.color = RGBA(r: 1, g: 0, b: 0)
    document.layers = [layer]
    let image = try XCTUnwrap(renderer.render(document, assets: assets, maxDimension: nil))
    let bitmap = NSBitmapImageRep(cgImage: image)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 4, y: 5)).redComponent, 0.9)
    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 4, y: 28)).alphaComponent, 0.01)
  }
  func testHistoryCoalescesDragAndClearsRedoOnNewEdit() async throws {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 32, height: 32)
      store.beginTransaction("移动对象")
      for position in 1...10 { store.updateSelected("移动") { $0.x = Double(position) } }
      store.endTransaction()
      XCTAssertEqual(store.active.undo.count, 1)
      XCTAssertEqual(store.selected?.x, 10)
      store.undo()
      XCTAssertEqual(store.selected?.x, 0)
      XCTAssertEqual(store.active.redo.count, 1)
      store.redo()
      XCTAssertEqual(store.selected?.x, 10)
      store.undo()
      store.updateSelected("更改位置") { $0.y = 4 }
      XCTAssertTrue(store.active.redo.isEmpty)
    }
  }
  func testCropPreservesLayerAndUndoRestoresCanvas() async throws {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 32, height: 32)
      let id = store.selected?.id
      store.selection = SelectionRegion(
        type: "crop", points: [.init(x: 8, y: 4), .init(x: 24, y: 20)])
      store.cropToSelection()
      XCTAssertEqual(store.document.width, 16)
      XCTAssertEqual(store.document.height, 16)
      XCTAssertEqual(store.selected?.width, 32)
      XCTAssertEqual(store.selected?.x, -8)
      XCTAssertEqual(store.selected?.y, -4)
      store.undo()
      XCTAssertEqual(store.document.width, 32)
      XCTAssertEqual(store.selected?.id, id)
    }
  }
  func testProjectRoundTripRetainsOriginalAssetsEffectsAndRedo() async throws {
    try await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 32, height: 32)
      let cg = try XCTUnwrap(ImageRenderer.bitmap(32, 32))
      cg.setFillColor(NSColor.red.cgColor)
      cg.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
      let image = try XCTUnwrap(cg.makeImage())
      let assetID = try store.active.assets.insert(image)
      store.updateSelected("导入") {
        $0.kind = .raster
        $0.assetID = assetID
      }
      store.addEffect(.blur)
      store.addEffect(.color)
      store.undo()
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".imgp")
      defer { try? FileManager.default.removeItem(at: folder) }
      try store.writeProject(store.active, to: folder)
      let loaded = try store.loadProject(folder)
      XCTAssertEqual(loaded.document, store.document)
      XCTAssertEqual(loaded.undo.count, store.active.undo.count)
      XCTAssertEqual(loaded.redo.count, 1)
      XCTAssertEqual(loaded.assets.data[assetID], store.active.assets.data[assetID])
      XCTAssertEqual(loaded.document.selectedLayer?.effects.first?.kind, .blur)
    }
  }
  func testSelectionMaskCanBeDisabledWithoutChangingOriginal() async throws {
    try await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 32, height: 32)
      let cg = try XCTUnwrap(ImageRenderer.bitmap(32, 32))
      cg.setFillColor(NSColor.red.cgColor)
      cg.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
      let image = try XCTUnwrap(cg.makeImage())
      let id = try store.active.assets.insert(image)
      let original = store.active.assets.data[id]
      store.updateSelected("导入") {
        $0.kind = .raster
        $0.assetID = id
      }
      store.selection = .init(type: "rectangle", points: [.init(x: 0, y: 0), .init(x: 16, y: 32)])
      store.maskFromSelection()
      store.renderNow()
      let masked = NSBitmapImageRep(cgImage: try XCTUnwrap(store.preview))
      XCTAssertGreaterThan(try XCTUnwrap(masked.colorAt(x: 4, y: 16)).alphaComponent, 0.95)
      XCTAssertLessThan(try XCTUnwrap(masked.colorAt(x: 28, y: 16)).alphaComponent, 0.01)
      store.updateSelected("停用蒙版") { $0.maskEnabled = false }
      store.renderNow()
      let restored = NSBitmapImageRep(cgImage: try XCTUnwrap(store.preview))
      XCTAssertGreaterThan(try XCTUnwrap(restored.colorAt(x: 28, y: 16)).alphaComponent, 0.95)
      XCTAssertEqual(original, store.active.assets.data[id])
    }
  }
  func testEffectsDisabledRestorePixelsAndPNGDecodes() throws {
    let renderer = ImageRenderer()
    let assets = AssetLibrary()
    var doc = ImageDocument()
    doc.width = 20
    doc.height = 20
    var layer = ImageLayer(name: "shape", kind: .shape, width: 20, height: 20)
    layer.color = .init(r: 1, g: 0, b: 0)
    layer.cornerRadius = 0
    var effect = ImageEffect(.custom)
    effect.filterName = "CIColorInvert"
    effect.amount = 1
    effect.intensity = 1 // Exercise full inversion independently of the new restrained default.
    layer.effects = [effect]
    doc.layers = [layer]
    let inverted = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.render(doc, assets: assets)))
    XCTAssertLessThan(try XCTUnwrap(inverted.colorAt(x: 10, y: 10)).redComponent, 0.05)
    doc.layers[0].effects[0].amount = 0
    let noIntensity = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.render(doc, assets: assets)))
    XCTAssertGreaterThan(try XCTUnwrap(noIntensity.colorAt(x: 10, y: 10)).redComponent, 0.95)
    doc.layers[0].effects[0].enabled = false
    let restored = try XCTUnwrap(renderer.render(doc, assets: assets))
    let bytes = try AssetLibrary.encode(restored, type: UTType.png.identifier)
    let id = assets.insert(bytes)
    XCTAssertNotNil(assets.image(id))
    XCTAssertEqual(assets.image(id)?.width, 20)
    XCTAssertGreaterThan(
      try XCTUnwrap(NSBitmapImageRep(cgImage: restored).colorAt(x: 10, y: 10)).redComponent, 0.95)
  }
  func testGroupVisibilityAndOpacityApplyToChildren() throws {
    let renderer = ImageRenderer()
    let assets = AssetLibrary()
    var doc = ImageDocument()
    doc.width = 10
    doc.height = 10
    var group = ImageLayer(name: "group", kind: .group, width: 10, height: 10)
    group.opacity = 0.5
    var layer = ImageLayer(name: "child", kind: .shape, width: 10, height: 10)
    layer.parentID = group.id
    layer.cornerRadius = 0
    doc.layers = [group, layer]
    var bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.render(doc, assets: assets)))
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 5, y: 5)).alphaComponent, 0.5, accuracy: 0.01)
    doc.layers[0].visible = false
    bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.render(doc, assets: assets)))
    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 5, y: 5)).alphaComponent, 0.01)
  }
  func testToolDefaultsRememberBranchAndSelectionDoesNotDirtySavedProject() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.chooseTool(.brush, branch: ToolCategory.brush.branches[1])
      store.chooseTool(.move)
      store.chooseTool(.brush)
      XCTAssertEqual(store.branch.id, "pencil")
      store.newProject(width: 10, height: 10)
      store.addLayer(.shape)
      store.active.savedDocument = store.document
      let other = store.document.layers.last!.id
      store.selectLayer(other)
      XCTAssertFalse(store.active.dirty)
      UserDefaults.standard.removeObject(forKey: "toolDefaults")
    }
  }
  func testGrainIsDeterministicAndPreservesTransparentPixels() throws {
    var doc = ImageDocument()
    doc.width = 32
    doc.height = 32
    var layer = ImageLayer(name: "rounded", kind: .shape, width: 32, height: 32)
    layer.shape = "roundedRectangle"
    layer.cornerRadius = 15
    layer.effects = [ImageEffect(.grain)]
    doc.layers = [layer]
    let renderer = ImageRenderer()
    let assets = AssetLibrary()
    let first = try XCTUnwrap(renderer.render(doc, assets: assets))
    let second = try XCTUnwrap(renderer.render(doc, assets: assets))
    XCTAssertEqual(
      try AssetLibrary.encode(first, type: UTType.png.identifier),
      try AssetLibrary.encode(second, type: UTType.png.identifier))
    XCTAssertLessThan(
      try XCTUnwrap(NSBitmapImageRep(cgImage: first).colorAt(x: 0, y: 0)).alphaComponent, 0.01)
  }
  func testBrushAndEraserRemainIndependentRecords() throws {
    var doc = ImageDocument()
    doc.width = 32
    doc.height = 32
    var layer = ImageLayer(name: "paint", kind: .paint, width: 32, height: 32)
    let red = RGBA(r: 1, g: 0, b: 0)
    layer.strokes = [
      .init(
        points: [.init(x: 5, y: 16), .init(x: 27, y: 16)], color: red, size: 8, opacity: 1,
        hardness: 1),
      .init(
        points: [.init(x: 16, y: 16)], color: red, size: 6, opacity: 1, hardness: 1, erasing: true),
    ]
    doc.layers = [layer]
    let bitmap = NSBitmapImageRep(
      cgImage: try XCTUnwrap(ImageRenderer().render(doc, assets: AssetLibrary())))
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 8, y: 16)).redComponent, 0.95)
    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 16, y: 16)).alphaComponent, 0.01)
    XCTAssertEqual(doc.layers[0].strokes.count, 2)
  }
}
