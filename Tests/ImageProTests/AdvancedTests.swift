import AppKit
import Combine
import CoreImage
import UniformTypeIdentifiers
import XCTest

@testable import ImagePro

final class AdvancedTests: XCTestCase {
  func testPSDIndependentFixtureCompressionAndGroups() throws {
    for compression in ["RAW", "RLE", "ZIP", "ZIP_WITH_PREDICTION"] {
      let url = try XCTUnwrap(
        Bundle.module.url(
          forResource: "fixture-" + compression, withExtension: "psd", subdirectory: "Fixtures"))
      let (doc, assets, _, _) = try PSDCodec.read(Data(contentsOf: url))
      XCTAssertEqual(doc.width, 32)
      XCTAssertEqual(doc.height, 24)
      XCTAssertEqual(doc.layers.map(\.name), ["绿色", "设计分组", "半透明红", "底图"])
      let red = try XCTUnwrap(doc.layers.first { $0.name == "半透明红" })
      XCTAssertEqual(red.parentID, doc.layers[1].id)
      XCTAssertEqual(red.x, 4)
      XCTAssertEqual(red.y, 3)
      XCTAssertEqual(red.opacity, 192.0 / 255, accuracy: 0.001)
      let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(assets.image(red.assetID)))
      let c = try XCTUnwrap(bitmap.colorAt(x: 3, y: 3))
      XCTAssertEqual(c.redComponent, 1, accuracy: 0.02)
      XCTAssertEqual(c.alphaComponent, 128.0 / 255, accuracy: 0.02)
    }
  }
  func testPSDWriterRetainsIndependentLayersAndFolderRelations() throws {
    var doc = ImageDocument()
    doc.width = 32
    doc.height = 24
    let group = ImageLayer(name: "分组", kind: .group, width: 32, height: 24)
    var red = ImageLayer(name: "标题色块", kind: .shape, width: 8, height: 6)
    red.parentID = group.id
    red.x = 4
    red.y = 3
    red.color = .init(r: 1, g: 0, b: 0)
    red.opacity = 0.5
    red.cornerRadius = 0
    var blue = ImageLayer(name: "底图", kind: .shape, width: 32, height: 24)
    blue.color = .init(r: 0, g: 0, b: 1)
    blue.cornerRadius = 0
    doc.layers = [group, red, blue]
    doc.selectedLayerID = red.id
    let bytes = try PSDCodec.write(document: doc, assets: AssetLibrary(), renderer: ImageRenderer())
    try FileManager.default.createDirectory(
      atPath: "/tmp/image-pro-qa-fixtures", withIntermediateDirectories: true)
    try bytes.write(to: URL(fileURLWithPath: "/tmp/image-pro-qa-fixtures/native-export.psd"))
    let (restored, library, _, _) = try PSDCodec.read(bytes)
    XCTAssertEqual(restored.layers.map(\.name), doc.layers.map(\.name))
    XCTAssertEqual(restored.layers[1].parentID, restored.layers[0].id)
    XCTAssertEqual(restored.layers[1].opacity, 128.0 / 255, accuracy: 0.01)
    let bitmap = NSBitmapImageRep(
      cgImage: try XCTUnwrap(ImageRenderer().render(restored, assets: library, maxDimension: nil)))
    let c = try XCTUnwrap(bitmap.colorAt(x: 6, y: 5))
    XCTAssertEqual(c.redComponent, 0.5, accuracy: 0.02)
    XCTAssertEqual(c.blueComponent, 0.5, accuracy: 0.02)
  }
  func testPSDEmbeddedProjectRetainsTextEffectsAndHistory() throws {
    var doc = ImageDocument()
    doc.width = 32
    doc.height = 32
    var text = ImageLayer(name: "可编辑文字", kind: .text, width: 32, height: 32)
    text.fontSize = 9
    text.textStyle = TextStyle()
    text.textStyle?.vertical = true
    text.effects = [ImageEffect(.hue)]
    doc.layers = [text]
    let archive = ProjectArchive(
      document: doc, undo: [HistoryEntry(name: "创建文字", before: ImageDocument(), after: doc)],
      redo: [])
    let bytes = try PSDCodec.write(
      document: doc, assets: AssetLibrary(), renderer: ImageRenderer(), archive: archive)
    let (restored, _, _, embedded) = try PSDCodec.read(bytes)
    XCTAssertEqual(restored, doc)
    XCTAssertEqual(embedded?.archive.undo.first?.name, "创建文字")
  }
  func testPSDTruncatedFilesFailWithoutReadingPastBounds() throws {
    let fixture = try XCTUnwrap(
      Bundle.module.url(forResource: "fixture-RLE", withExtension: "psd", subdirectory: "Fixtures"))
    let bytes = try Data(contentsOf: fixture)
    for length in [0, 10, 25, 100, 200] {
      XCTAssertThrowsError(try PSDCodec.read(bytes.prefix(length)))
    }
  }
  func testTransformEveryHandleKeepsOppositeCornerAndAspect() {
    var l = ImageLayer(name: "", kind: .raster, width: 120, height: 80)
    l.x = 15
    l.y = 25
    l.rotation = 35
    for handle in [0, 2, 4, 6] {
      let result = TransformGeometry.resize(
        l, handle: handle, delta: CGPoint(x: 20, y: -13), keepAspect: true)
      XCTAssertEqual(result.width / result.height, 1.5, accuracy: 0.0001)
      let (x, y) = TransformGeometry.handles[handle]
      func opposite(_ l: ImageLayer) -> CGPoint {
        let a = l.rotation * .pi / 180
        let dx = (0.5 - x) * l.width
        let dy = (0.5 - y) * l.height
        return CGPoint(
          x: l.x + l.width / 2 + dx * cos(a) - dy * sin(a),
          y: l.y + l.height / 2 + dx * sin(a) + dy * cos(a))
      }
      XCTAssertEqual(opposite(l).x, opposite(result).x, accuracy: 0.0001)
      XCTAssertEqual(opposite(l).y, opposite(result).y, accuracy: 0.0001)
    }
  }
  func testQuickSelectionAndGlobalColorRangeAreDistinctAndOriented() throws {
    let cg = try XCTUnwrap(ImageRenderer.bitmap(20, 10))
    cg.setFillColor(NSColor.blue.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
    cg.setFillColor(NSColor.red.cgColor)
    cg.fill(CGRect(x: 0, y: 6, width: 4, height: 4))
    cg.fill(CGRect(x: 16, y: 0, width: 4, height: 4))
    let image = try XCTUnwrap(cg.makeImage())
    let size = CGSize(width: 20, height: 10)
    let contiguous = try XCTUnwrap(
      SelectionEngine.region(
        image: image, point: CGPoint(x: 1, y: 1), canvasSize: size, tolerance: 0.01,
        contiguous: true))
    let global = try XCTUnwrap(
      SelectionEngine.region(
        image: image, point: CGPoint(x: 1, y: 1), canvasSize: size, tolerance: 0.01,
        contiguous: false))
    XCTAssertTrue(contiguous.path.contains(CGPoint(x: 2, y: 2)))
    XCTAssertFalse(contiguous.path.contains(CGPoint(x: 18, y: 8)))
    XCTAssertTrue(global.path.contains(CGPoint(x: 18, y: 8)))
  }
  func testSelectionCombineAndFeatherMask() throws {
    let a = SelectionRegion(type: "rectangle", points: [.init(x: 0, y: 0), .init(x: 10, y: 20)])
    let b = SelectionRegion(type: "rectangle", points: [.init(x: 5, y: 0), .init(x: 20, y: 20)])
    let size = CGSize(width: 20, height: 20)
    let add = SelectionEngine.combine(a, b, mode: "add", size: size)
    XCTAssertTrue(add.path.contains(CGPoint(x: 18, y: 10)))
    let sub = SelectionEngine.combine(a, b, mode: "subtract", size: size)
    XCTAssertTrue(sub.path.contains(CGPoint(x: 2, y: 10)))
    XCTAssertFalse(sub.path.contains(CGPoint(x: 7, y: 10)))
    var soft = a
    soft.feather = 3
    let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(SelectionEngine.mask(soft, size: size)))
    let v = try XCTUnwrap(bitmap.colorAt(x: 10, y: 10)).redComponent
    XCTAssertGreaterThan(v, 0.1)
    XCTAssertLessThan(v, 0.9)
  }
  func testSelectionExtractDeleteAndUndoPreserveOriginal() async throws {
    try await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 20, height: 20)
      let cg = try XCTUnwrap(ImageRenderer.bitmap(20, 20))
      cg.setFillColor(NSColor.red.cgColor)
      cg.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
      let id = try store.active.assets.insert(try XCTUnwrap(cg.makeImage()))
      store.updateSelected("导入") {
        $0.kind = .raster
        $0.assetID = id
      }
      let original = store.active.assets.data[id]
      store.selection = SelectionRegion(
        type: "rectangle", points: [.init(x: 4, y: 3), .init(x: 12, y: 11)])
      store.extractSelection()
      XCTAssertEqual(store.selected?.width, 8)
      XCTAssertEqual(store.selected?.x, 4)
      XCTAssertEqual(store.selected?.y, 3)
      store.undo()
      store.selection = SelectionRegion(
        type: "rectangle", points: [.init(x: 4, y: 3), .init(x: 12, y: 11)])
      store.deleteSelection()
      store.renderNow()
      let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(store.preview))
      XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 6, y: 5)).alphaComponent, 0.02)
      XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 17, y: 17)).alphaComponent, 0.98)
      XCTAssertEqual(original, store.active.assets.data[id])
      store.undo()
      XCTAssertNil(store.selected?.maskAssetID)
    }
  }
  func testEveryEffectAndGroupedStylesRender() throws {
    let renderer = ImageRenderer()
    let assets = AssetLibrary()
    var layer = ImageLayer(name: "test", kind: .shape, width: 32, height: 32)
    layer.shape = "ellipse"
    layer.color = .init(r: 0.6, g: 0.4, b: 0.2)
    for kind in EffectKind.allCases where kind != .custom {
      var e = ImageEffect(kind)
      e.radius = 3
      layer.effects = [e]
      XCTAssertNotNil(renderer.renderLayer(layer, assets: assets), kind.title)
      if kind == .blur || kind == .distort {
        for style in (kind == .blur ? EffectStyles.blur : EffectStyles.distort) {
          e.style = style.0
          layer.effects = [e]
          XCTAssertNotNil(renderer.renderLayer(layer, assets: assets), style.1)
        }
      }
    }
  }
  func testOuterShadowExtendsPastObjectBounds() throws {
    var doc = ImageDocument()
    doc.width = 64
    doc.height = 64
    var l = ImageLayer(name: "", kind: .shape, width: 12, height: 12)
    l.x = 20
    l.y = 20
    l.color = .init(r: 1, g: 0, b: 0)
    var e = ImageEffect(.shadow)
    e.radius = 2
    e.amount = 1
    e.set("distance", 8)
    e.set("angle", 0)
    l.effects = [e]
    doc.layers = [l]
    let bitmap = NSBitmapImageRep(
      cgImage: try XCTUnwrap(ImageRenderer().render(doc, assets: AssetLibrary(), maxDimension: nil))
    )
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 36, y: 26)).alphaComponent, 0.2)
  }
  func testDifferentBrushModesProduceDifferentPixelsAndUsePressure() throws {
    var encoded = Set<Data>()
    for mode in ["brush", "watercolor", "oil", "airbrush", "pencil", "marker", "texture"] {
      var l = ImageLayer(name: mode, kind: .paint, width: 64, height: 64)
      var dynamics = BrushDynamics()
      dynamics.mode = mode
      l.strokes = [
        BrushStroke(
          points: [.init(x: 8, y: 32), .init(x: 56, y: 32)], color: .init(r: 1, g: 0, b: 0),
          size: 14, opacity: 1, hardness: 1, dynamics: dynamics, pressures: [0.2, 1])
      ]
      let image = try XCTUnwrap(ImageRenderer().renderLayer(l, assets: AssetLibrary()))
      encoded.insert(try AssetLibrary.encode(image, type: UTType.png.identifier))
    }
    XCTAssertEqual(encoded.count, 7)
  }
  func testTransformUsesCachedPixels() throws {
    let renderer = ImageRenderer()
    let assets = AssetLibrary()
    var l = ImageLayer(name: "", kind: .shape, width: 40, height: 40)
    let a = try XCTUnwrap(renderer.cachedLayer(l, assets: assets, scale: 1))
    l.x = 100
    l.rotation = 40
    l.opacity = 0.5
    let b = try XCTUnwrap(renderer.cachedLayer(l, assets: assets, scale: 1))
    XCTAssertTrue(a === b)
  }
  func testLUTParsingRejectsInvalidDataAndPreservesDimensions() throws {
    XCTAssertThrowsError(try AdvancedEffects.parseLUT("LUT_3D_SIZE 2\n0 0 0"))
    let rows = (0..<8).map { "\($0&1) \(($0>>1)&1) \(($0>>2)&1)" }.joined(separator: "\n")
    let (dimension, data) = try AdvancedEffects.parseLUT("LUT_3D_SIZE 2\n" + rows)
    XCTAssertEqual(dimension, 2)
    XCTAssertEqual(data.count, 128)
  }
  func testFontCatalogScansInstalledFamilies() async {
    await MainActor.run {
      FontCatalog.shared.reload()
      XCTAssertGreaterThan(FontCatalog.shared.families.count, 20)
      XCTAssertFalse(FontCatalog.shared.members("Helvetica").isEmpty)
    }
  }
  func testFreeTransformCancelAndCommitAreSingleHistorySteps() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 64, height: 64)
      let before = store.document
      store.beginTransform()
      store.updateSelected("移动") { $0.x = 10 }
      store.updateSelected("缩放") { $0.width = 32 }
      store.endTransaction()
      XCTAssertTrue(store.active.undo.isEmpty)
      store.finishTransform(cancel: true)
      XCTAssertEqual(store.document, before)
      XCTAssertTrue(store.active.undo.isEmpty)
      store.beginTransform()
      store.updateSelected("移动") { $0.x = 12 }
      store.updateSelected("旋转") { $0.rotation = 15 }
      store.finishTransform()
      XCTAssertEqual(store.active.undo.count, 1)
      store.undo()
      XCTAssertEqual(store.document, before)
    }
  }
  func testTextToVectorRetainsGlyphContoursAndUndoRestoresText() async throws {
    try await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 200, height: 100)
      store.addLayer(.text)
      store.updateSelected("文字") {
        $0.width = 180
        $0.height = 80
        $0.fontSize = 36
        $0.fontName = "Helvetica"
        $0.text = "Pro"
        $0.color = RGBA(r: 1, g: 1, b: 1)
      }
      store.textToShape()
      XCTAssertEqual(store.selected?.kind, .shape)
      XCTAssertGreaterThan(store.selected?.vectorOutline?.count ?? 0, 10)
      let image = try XCTUnwrap(
        store.renderer.renderLayer(try XCTUnwrap(store.selected), assets: store.active.assets))
      let bitmap = NSBitmapImageRep(cgImage: image)
      var visible = 0
      for y in 0..<image.height {
        for x in 0..<image.width {
          if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { visible += 1 }
        }
      }
      XCTAssertGreaterThan(visible, 100)
      store.undo()
      XCTAssertEqual(store.selected?.kind, .text)
      XCTAssertEqual(store.selected?.text, "Pro")
    }
  }
  func testFeatheredDeletionAndRotatedSelectionMask() async throws {
    try await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 40, height: 40)
      store.addLayer(.shape)
      store.updateSelected("对象") {
        $0.x = 10
        $0.y = 10
        $0.width = 20
        $0.height = 20
        $0.rotation = 90
        $0.shape = "rectangle"
        $0.color = RGBA(r: 1, g: 0, b: 0)
      }
      store.selection = .init(
        type: "rectangle", points: [.init(x: 10, y: 10), .init(x: 20, y: 30)], feather: 2)
      store.deleteSelection()
      store.renderNow()
      let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(store.preview))
      XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 12, y: 20)).alphaComponent, 0.1)
      XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 28, y: 20)).alphaComponent, 0.9)
      let edge = try XCTUnwrap(bitmap.colorAt(x: 20, y: 20)).alphaComponent
      XCTAssertGreaterThan(edge, 0.1)
      XCTAssertLessThan(edge, 0.9)
    }
  }
  func testAdvancedMetadataRejectsNonfiniteValues() {
    var doc = ImageDocument()
    var l = ImageLayer(name: "", kind: .shape, width: 10, height: 10)
    var e = ImageEffect(.hue)
    e.set("hue", .nan)
    l.effects = [e]
    doc.layers = [l]
    XCTAssertThrowsError(try doc.validate())
  }

  func testSwitchingProjectsCommitsTransformToOriginalProjectOnly() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 64, height: 64)
      let original = store.active
      store.beginTransform()
      store.updateSelected("移动") { $0.x = 12 }
      store.newProject(width: 80, height: 80)
      XCTAssertFalse(store.transformActive)
      XCTAssertNil(store.transformSnapshot)
      XCTAssertEqual(original.undo.count, 1)
      XCTAssertEqual(original.document.selectedLayer?.x, 12)
      XCTAssertEqual(store.document.width, 80)
      XCTAssertEqual(store.selected?.x, 0)
    }
  }
  func testAsyncSelectionCancellationDoesNotRestoreDismissedSelection() async throws {
    let done = expectation(description: "background selection completed")
    let pair = await MainActor.run { () -> (EditorStore, AnyCancellable) in
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 64, height: 64)
      store.addLayer(.shape)
      store.updateSelected("图形") {
        $0.x = 0
        $0.y = 0
        $0.width = 64
        $0.height = 64
        $0.shape = "rectangle"
      }
      store.renderNow()
      store.chooseTool(.selection)
      let token = store.$selectingRegion.dropFirst().filter { !$0 }.prefix(1).sink { _ in
        done.fulfill()
      }
      store.selectColor(at: CGPoint(x: 10, y: 10), contiguous: true)
      store.deselect()
      return (store, token)
    }
    await fulfillment(of: [done], timeout: 3)
    await MainActor.run {
      XCTAssertNil(pair.0.selection)
      pair.1.cancel()
    }
  }
  func testAllBrushTipsProduceVisiblePixels() throws {
    var variants = Set<Data>()
    for tip in BrushTip.all {
      var l = ImageLayer(name: tip.name, kind: .paint, width: 64, height: 64)
      var d = BrushDynamics()
      d.tip = tip.id
      l.strokes = [
        BrushStroke(
          points: [.init(x: 16, y: 32), .init(x: 48, y: 32)], color: .init(r: 1, g: 0, b: 0),
          size: 22, opacity: 1, hardness: 1, dynamics: d)
      ]
      let image = try XCTUnwrap(ImageRenderer().renderLayer(l, assets: AssetLibrary()))
      variants.insert(try AssetLibrary.encode(image, type: UTType.png.identifier))
    }
    XCTAssertGreaterThan(variants.count, 20)
  }

}
