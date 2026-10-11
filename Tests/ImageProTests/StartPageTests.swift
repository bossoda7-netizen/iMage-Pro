import AppKit
import XCTest
@testable import ImagePro

final class StartPageTests: XCTestCase {
  func testRecoveryErrorsAreShortAndRecognizeWrappedDiskFull() async {
    await MainActor.run {
      let diskFull = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
      let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
        userInfo: [NSUnderlyingErrorKey: diskFull])
      XCTAssertEqual(EditorStore.recoveryFailureMessage(wrapped), "空间不足，自动恢复未保存。")
      XCTAssertEqual(EditorStore.recoveryFailureMessage(NSError(domain: NSCocoaErrorDomain,
        code: NSFileWriteNoPermissionError)), "自动恢复未保存，请手动保存项目。")
      let store = EditorStore(loadRecovery: false)
      store.notify(EditorStore.recoveryFailureMessage(wrapped), warning: true)
      XCTAssertTrue(store.statusIsWarning)
      store.notify("已保存")
      XCTAssertFalse(store.statusIsWarning)
    }
  }

  func testClosedHistoryRenamePreservesLayersAssetsAndUndo() async throws {
    try await MainActor.run {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let store = EditorStore(loadRecovery: false)
      store.newProject(name: "原名", width: 32, height: 24, background: RGBA(r: 1, g: 0, b: 0))
      store.renameProject(store.active.id, to: "作品")
      let original = store.document
      let oldUndo = store.active.undo.count
      let url = folder.appendingPathComponent("作品.imgp")
      try store.writeProject(store.active, to: url)
      store.recentProjects = [RecentProject(path: url.path, name: "作品", width: 32, height: 24,
        lastOpened: Date(), thumbnail: nil)]
      store.newStartPage()
      let active = store.active.id
      store.renameHistoryProject(sessionID: nil, url: url, to: " 新名字 ")
      let renamed = try store.loadProject(url)
      XCTAssertEqual(renamed.document.name, "新名字")
      XCTAssertEqual(renamed.document.layers, original.layers)
      XCTAssertEqual(renamed.undo.count, oldUndo + 1)
      XCTAssertEqual(renamed.undo.last?.before.name, "作品")
      XCTAssertEqual(store.recentProjects.first?.name, "新名字")
      XCTAssertEqual(store.active.id, active)
      XCTAssertEqual(renamed.assets.data, store.sessions.first?.assets.data)
      store.removeHistoryProject(sessionID: store.sessions.first?.id, url: url)
      XCTAssertTrue(store.recentProjects.isEmpty)
      XCTAssertTrue(store.hiddenHistorySessions.contains(store.sessions.first!.id))
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
  }

  func testImportedImageHistoryRenameRetainsBytesAndRejectsCollisions() async throws {
    try await MainActor.run {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let original = folder.appendingPathComponent("原名.png")
      let bytes = Data([1, 2, 3, 4])
      try bytes.write(to: original)
      let store = EditorStore(loadRecovery: false)
      store.recentProjects = [RecentProject(path: original.path, name: "原名", width: 32, height: 24,
        lastOpened: Date(), thumbnail: nil)]
      store.renameHistoryProject(sessionID: nil, url: original, to: "新名字")
      let renamed = folder.appendingPathComponent("新名字.png")
      XCTAssertEqual(try Data(contentsOf: renamed), bytes)
      XCTAssertEqual(store.recentProjects.first?.path, renamed.path)
      let collision = folder.appendingPathComponent("已存在.png")
      try Data([9]).write(to: collision)
      store.renameHistoryProject(sessionID: nil, url: renamed, to: "已存在")
      XCTAssertNotNil(store.error)
      XCTAssertEqual(try Data(contentsOf: renamed), bytes)
      XCTAssertEqual(try Data(contentsOf: collision), Data([9]))
      store.renameHistoryProject(sessionID: nil, url: renamed, to: "../其他")
      XCTAssertEqual(store.recentProjects.first?.path, renamed.path)
    }
  }

  func testAllPresetsAreDistinctAndSupported() throws {
    XCTAssertGreaterThanOrEqual(CanvasPreset.all.count, 50)
    XCTAssertEqual(Set(CanvasPreset.all.map(\.id)).count, CanvasPreset.all.count)
    for category in PresetCategory.allCases where category != .featured {
      XCTAssertFalse(CanvasPreset.all.filter { $0.category == category }.isEmpty)
    }
    for preset in CanvasPreset.all {
      var document = ImageDocument()
      document.width = preset.width
      document.height = preset.height
      document.dpi = preset.dpi
      XCTAssertNoThrow(try document.validate(), preset.name)
    }
  }

  func testPhysicalUnitsAndDPIProduceRealPixelDimensions() throws {
    var draft = CanvasDraft()
    draft.unit = .millimeters
    draft.width = "210"
    draft.height = "297"
    XCTAssertEqual(try XCTUnwrap(draft.pixelSize).width, 2480)
    XCTAssertEqual(try XCTUnwrap(draft.pixelSize).height, 3508)
    draft.resolution = "150"
    XCTAssertEqual(try XCTUnwrap(draft.pixelSize).width, 1240)
    XCTAssertEqual(try XCTUnwrap(draft.pixelSize).height, 1754)
    draft.changeUnit(to: .inches)
    XCTAssertEqual(try XCTUnwrap(draft.pixelSize).width, 1240)
    draft.changeUnit(to: .pixels)
    XCTAssertEqual(draft.width, "1240")
    XCTAssertNil(draft.validationMessage)
  }

  func testAspectLockAndOrientationKeepDimensionsConsistent() {
    var draft = CanvasDraft()
    draft.setAspectLock(true)
    draft.setDimension("3840", width: true)
    XCTAssertEqual(draft.height, "2160")
    draft.orient(portrait: true)
    XCTAssertEqual(draft.width, "2160")
    XCTAssertEqual(draft.height, "3840")
    draft.setDimension("1920", width: false)
    XCTAssertEqual(draft.width, "1080")
    draft.setAspectLock(false)
    draft.setDimension("500", width: true)
    XCTAssertEqual(draft.height, "1920")
  }

  func testInvalidAndOversizedDimensionsCannotCreateCanvas() {
    for value in ["", "0", "-1", "nan", "inf", "1e300", "17000"] {
      var draft = CanvasDraft()
      draft.width = value
      XCTAssertNotNil(draft.validationMessage, value)
      draft.setAspectLock(true)
      draft.setDimension(value, width: true)
      draft.changeUnit(to: .inches)
      XCTAssertNotNil(draft.validationMessage, value)
    }
    var draft = CanvasDraft()
    draft.width = "12000"
    draft.height = "12000"
    XCTAssertNotNil(draft.validationMessage)
    draft = CanvasDraft()
    draft.resolution = "2401"
    XCTAssertNotNil(draft.validationMessage)
  }

  func testHistoryCapsEntriesAndMovesExistingFileToFront() throws {
    var entries: [RecentProject] = []
    for i in 0..<12 {
      let entry = RecentProject(path: "/tmp/start-page-\(i).imgp", name: "\(i)",
        width: 32, height: 32, lastOpened: Date(), thumbnail: nil)
      entries = RecentProject.recording(entry, in: entries)
    }
    XCTAssertEqual(entries.count, 8)
    XCTAssertEqual(entries.first?.name, "11")
    let again = RecentProject(path: "/tmp/./start-page-8.imgp", name: "重新打开",
      width: 64, height: 32, lastOpened: Date(), thumbnail: nil)
    entries = RecentProject.recording(again, in: entries)
    XCTAssertEqual(entries.count, 8)
    XCTAssertEqual(entries.first?.name, "重新打开")
    XCTAssertEqual(entries.filter { $0.url.standardizedFileURL.path == "/tmp/start-page-8.imgp" }.count, 1)
    let recovered = try JSONDecoder().decode([RecentProject].self, from: JSONEncoder().encode(entries))
    XCTAssertEqual(recovered.map(\.id), entries.map(\.id))
  }

  func testCustomProjectAppliesMetadataAndRendersChosenBackground() async throws {
    try await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      let start = store.active.id
      store.newProject(name: "  印刷作品  ", width: 64, height: 32, dpi: 600,
        background: RGBA(r: 1, g: 1, b: 1), author: "作者", grid: true, rulers: true)
      XCTAssertEqual(store.sessions.count, 1)
      XCTAssertFalse(store.sessions.contains { $0.id == start })
      XCTAssertEqual(store.document.name, "印刷作品")
      XCTAssertEqual(store.document.dpi, 600)
      XCTAssertEqual(store.document.author, "作者")
      XCTAssertTrue(store.showGrid)
      XCTAssertTrue(store.showRulers)
      XCTAssertTrue(try XCTUnwrap(store.document.layers.last).locked)
      XCTAssertEqual(store.document.selectedLayer?.kind, .paint)
      let image = try XCTUnwrap(store.renderer.render(store.document, assets: store.active.assets, maxDimension: 64))
      let color = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 2, y: 2))
      XCTAssertGreaterThan(color.redComponent, 0.99)
      XCTAssertGreaterThan(color.alphaComponent, 0.99)
      let project = store.active.id
      store.newProject(width: 17000, height: 100)
      XCTAssertEqual(store.active.id, project)
      XCTAssertNotNil(store.error)
    }
  }

  func testHistoryRecordsOnlySuccessfulOpensAndRetainsPreview() async throws {
    try await MainActor.run {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 32, height: 24, background: RGBA(r: 1, g: 0, b: 0))
      let file = folder.appendingPathComponent("作品.imgp")
      try store.writeProject(store.active, to: file)
      store.newStartPage()
      store.open(file)
      XCTAssertEqual(store.recentProjects.count, 1)
      XCTAssertEqual(store.recentProjects.first?.url.path, file.path)
      XCTAssertNotNil(store.recentProjects.first?.thumbnail)
      let count = store.sessions.count
      store.newStartPage()
      store.open(try XCTUnwrap(store.recentProjects.first?.url))
      XCTAssertEqual(store.sessions.count, count)
      XCTAssertEqual(store.recentProjects.count, 1)
      store.open(folder.appendingPathComponent("不存在.imgp"))
      XCTAssertEqual(store.recentProjects.count, 1)
      store.removeRecentProject(file.path)
      XCTAssertTrue(store.recentProjects.isEmpty)
      XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
  }
}
