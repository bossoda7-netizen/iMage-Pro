import AppKit
import XCTest
@testable import ImagePro

final class ProjectTabTests: XCTestCase {
  func testStartPageReplacementAndIndependentSelection() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      XCTAssertEqual(store.sessions.count, 1)
      XCTAssertTrue(store.showWelcome)
      XCTAssertFalse(store.active.dirty)
      let firstStart = store.active.id
      store.newProject(name: "A", width: 32, height: 32)
      XCTAssertNotNil(store.active.thumbnail)
      XCTAssertEqual(store.sessions.count, 1)
      XCTAssertFalse(store.sessions.contains { $0.id == firstStart })
      let project = store.active.id
      store.newStartPage()
      let start = store.active.id
      store.newStartPage()
      let otherStart = store.active.id
      store.activate(start)
      store.newProject(name: "B", width: 32, height: 32)
      XCTAssertEqual(store.sessions.map(\.document.name), ["A", "B", "启动页"])
      XCTAssertTrue(store.sessions.last!.isStartPage)
      store.activate(project)
      XCTAssertFalse(store.showWelcome)
      store.activate(otherStart)
      XCTAssertTrue(store.showWelcome)
    }
  }

  func testFailedOpenPreservesSelectedStartPage() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      let start = store.activeID
      store.open(URL(fileURLWithPath: "/nonexistent/image-pro-tab-regression.png"))
      XCTAssertEqual(store.activeID, start)
      XCTAssertTrue(store.showWelcome)
      XCTAssertEqual(store.sessions.count, 1)
      XCTAssertNotNil(store.error)
    }
  }

  func testSuccessfulImageOpenConsumesOnlySelectedStartPage() async throws {
    try await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newStartPage()
      let unusedStart = store.sessions[0].id
      let context = try XCTUnwrap(ImageRenderer.bitmap(24, 16))
      context.setFillColor(NSColor.red.cgColor)
      context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
      let image = try XCTUnwrap(context.makeImage())
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
      defer { try? FileManager.default.removeItem(at: url) }
      try AssetLibrary.encode(image, type: "public.png").write(to: url)
      store.open(url)
      XCTAssertEqual(store.sessions.count, 2)
      XCTAssertEqual(store.sessions[0].id, unusedStart)
      XCTAssertTrue(store.sessions[0].isStartPage)
      XCTAssertFalse(store.showWelcome)
      XCTAssertNotNil(store.active.thumbnail)
      store.renderNow()
      let thumbnail = try XCTUnwrap(store.active.thumbnail)
      XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), 96)
      XCTAssertGreaterThan(try XCTUnwrap(NSBitmapImageRep(cgImage: thumbnail).colorAt(x: 2, y: 2)).redComponent, 0.9)
      var overlay = ImageLayer(name: "合成预览", kind: .shape, width: 8, height: 8)
      overlay.color = RGBA(r: 0, g: 1, b: 0)
      overlay.cornerRadius = 0
      store.edit("添加预览图层") { $0.layers.insert(overlay, at: 0) }
      store.renderNow()
      let composite = NSBitmapImageRep(cgImage: try XCTUnwrap(store.active.thumbnail))
      XCTAssertGreaterThan(try XCTUnwrap(composite.colorAt(x: 2, y: 2)).greenComponent, 0.9)
      XCTAssertGreaterThan(try XCTUnwrap(composite.colorAt(x: 20, y: 12)).redComponent, 0.9)
    }
  }

  func testBatchOpenHasDistinctThumbnailsBeforeActiveCanvasRenders() async throws {
    try await MainActor.run {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = EditorStore(loadRecovery: false)
      for (name, color) in [("红色", NSColor.red), ("绿色", NSColor.green)] {
        let context = try XCTUnwrap(ImageRenderer.bitmap(24, 16))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        let image = try XCTUnwrap(context.makeImage())
        let url = directory.appendingPathComponent(name + ".png")
        try AssetLibrary.encode(image, type: "public.png").write(to: url)
        store.open(url)
      }
      // No renderNow() or main-loop yield: background tabs must not depend on
      // being activated to obtain their own composite preview.
      XCTAssertEqual(store.sessions.count, 2)
      let first = NSBitmapImageRep(cgImage: try XCTUnwrap(store.sessions[0].thumbnail))
      let second = NSBitmapImageRep(cgImage: try XCTUnwrap(store.sessions[1].thumbnail))
      XCTAssertGreaterThan(try XCTUnwrap(first.colorAt(x: 2, y: 2)).redComponent, 0.9)
      XCTAssertLessThan(try XCTUnwrap(first.colorAt(x: 2, y: 2)).greenComponent, 0.1)
      XCTAssertGreaterThan(try XCTUnwrap(second.colorAt(x: 2, y: 2)).greenComponent, 0.9)
      XCTAssertLessThan(try XCTUnwrap(second.colorAt(x: 2, y: 2)).redComponent, 0.1)
    }
  }

  func testProjectFileOpenReplacesStartPageInPlace() async throws {
    try await MainActor.run {
      let source = EditorStore(loadRecovery: false)
      source.newProject(name: "已保存项目", width: 16, height: 16)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".imgp")
      defer { try? FileManager.default.removeItem(at: url) }
      try source.writeProject(source.active, to: url)
      let store = EditorStore(loadRecovery: false)
      store.newStartPage()
      store.activate(store.sessions[0].id)
      store.open(url)
      XCTAssertEqual(store.sessions.map(\.document.name), ["已保存项目", "启动页"])
      XCTAssertFalse(store.showWelcome)
      XCTAssertFalse(store.active.dirty)
      let openedID = store.activeID
      store.activate(store.sessions[1].id)
      store.open(url)
      XCTAssertEqual(store.sessions.count, 1)
      XCTAssertEqual(store.activeID, openedID)
      XCTAssertFalse(store.showWelcome)
    }
  }

  func testDuplicateKeepsSourceDocumentAndAssets() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(name: "原项目", width: 16, height: 16)
      let source = store.active
      store.duplicateProject(source.id)
      XCTAssertEqual(store.sessions.count, 2)
      XCTAssertNotEqual(store.active.id, source.id)
      XCTAssertEqual(store.active.document.name, "原项目 副本")
      store.renameProject(store.active.id, to: "独立副本")
      XCTAssertEqual(source.document.name, "原项目")
      XCTAssertTrue(store.active.dirty)
    }
  }

  func testMoveKeepsSelectionAndCloseChoosesNeighbor() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newStartPage()
      store.newStartPage()
      let ids = store.sessions.map(\.id)
      store.activate(ids[1])
      store.moveProject(ids[2], to: ids[0])
      XCTAssertEqual(store.sessions.map(\.id), [ids[2], ids[0], ids[1]])
      XCTAssertEqual(store.activeID, ids[1])
      store.moveProject(ids[2], to: ids[1])
      XCTAssertEqual(store.sessions.map(\.id), ids)
      XCTAssertTrue(store.closeProject(ids[0]))
      XCTAssertEqual(store.activeID, ids[1])
      XCTAssertTrue(store.closeProject(ids[1]))
      XCTAssertEqual(store.activeID, ids[2])
      XCTAssertTrue(store.closeProject(ids[2]))
      XCTAssertEqual(store.sessions.count, 1)
      XCTAssertTrue(store.showWelcome)
    }
  }

  func testRenameBackgroundTabAndUndoWithoutChangingSelection() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(name: "原名", width: 16, height: 16)
      let id = store.active.id
      store.newStartPage()
      let start = store.activeID
      store.renameProject(id, to: "  新名称  ")
      XCTAssertEqual(store.sessions[0].document.name, "新名称")
      XCTAssertEqual(store.activeID, start)
      store.renameProject(id, to: " \n ")
      XCTAssertEqual(store.sessions[0].document.name, "新名称")
      store.activate(id)
      store.undo()
      XCTAssertEqual(store.document.name, "原名")
      store.redo()
      XCTAssertEqual(store.document.name, "新名称")
    }
  }

  func testOverflowRetainsActiveTitleAndCompressesSiblings() async {
    await MainActor.run {
      let store = EditorStore(loadRecovery: false)
      store.newProject(name: "湖畔摄影", width: 16, height: 16)
      let id = store.active.id
      for _ in 0..<8 { store.newStartPage() }
      let layout = ProjectTabLayout(sessions: store.sessions, activeID: id, availableWidth: 320)
      XCTAssertTrue(layout.compact)
      XCTAssertGreaterThan(layout.width(for: store.sessions[0]), 100)
      for session in store.sessions.dropFirst() { XCTAssertEqual(layout.width(for: session), 34) }
    }
  }

  func testNativeControlsRepairSystemFrameResetDuringSheetLayout() async throws {
    try await MainActor.run {
      let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 720),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable],
                            backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      let holder = NativeWindowControls.ControlHolder(frame: CGRect(x: 20, y: 660, width: 66, height: 56))
      window.contentView!.addSubview(holder)
      holder.installButtons()
      let button = try XCTUnwrap(window.standardWindowButton(.closeButton))
      button.setFrameOrigin(NSPoint(x: 7, y: 3))
      XCTAssertTrue(button.superview === holder)
      XCTAssertEqual(button.frame.midY, holder.bounds.midY, accuracy: 0.01)
      XCTAssertEqual(button.frame.minX, 0)
      NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)
      for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
        let control = try XCTUnwrap(window.standardWindowButton(type))
        control.setFrameOrigin(NSPoint(x: 8, y: 4))
        XCTAssertEqual(control.frame.midY, holder.bounds.midY, accuracy: 0.01)
        XCTAssertEqual(control.frame.minX, CGFloat(index) * 22)
      }
    }
  }

  func testReorderCrossesMidpointsAndKeepsStableMixedWidthSlots() {
    let ids = (0..<4).map { _ in UUID() }
    let widths: [UUID: CGFloat] = [ids[0]: 120, ids[1]: 34, ids[2]: 34, ids[3]: 34]
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: ids, widths: widths, centerX: 139), ids)
    let moved = ProjectTabReorder.moving(ids[0], in: ids, widths: widths, centerX: 141)
    XCTAssertEqual(moved, [ids[1], ids[0], ids[2], ids[3]])
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: moved, widths: widths, centerX: 141), moved)
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: moved, widths: widths, centerX: 100), moved)
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: moved, widths: widths, centerX: 16), ids)
    let last = ProjectTabReorder.moving(ids[0], in: ids, widths: widths, centerX: 230)
    XCTAssertEqual(last, [ids[1], ids[2], ids[3], ids[0]])
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: last, widths: widths, centerX: -30), ids)
  }

  func testNarrowTabDoesNotBounceBackAfterCrossingWideTab() {
    let ids = (0..<3).map { _ in UUID() }
    let widths: [UUID: CGFloat] = [ids[0]: 34, ids[1]: 120, ids[2]: 34]
    let moved = ProjectTabReorder.moving(ids[0], in: ids, widths: widths, centerX: 98)
    XCTAssertEqual(moved, [ids[1], ids[0], ids[2]])
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: moved, widths: widths, centerX: 98), moved)
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: moved, widths: widths, centerX: 62), moved)
    XCTAssertEqual(ProjectTabReorder.moving(ids[0], in: moved, widths: widths, centerX: 59), ids)
  }

  func testNativeTabDragOwnsMouseAndUsesStableWindowCoordinates() async throws {
    try await MainActor.run {
      let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      var clicks = 0
      var renames = 0
      var starts = 0
      var translations: [CGFloat] = []
      var completions: [Bool] = []
      let area = ProjectTabInteractionArea(select: { clicks += 1 }, rename: { renames += 1 },
        dragBegan: { starts += 1 }, dragChanged: { translations.append($0) },
        dragEnded: { completions.append($0) })
      let view = ProjectTabInteractionArea.MouseView(actions: area)
      view.frame = CGRect(x: 10, y: 200, width: 120, height: 56)
      window.contentView!.addSubview(view)
      window.isMovableByWindowBackground = true
      WindowTitlebarDragArea.restrictDragging(window)
      XCTAssertFalse(window.isMovable)
      XCTAssertFalse(window.isMovableByWindowBackground)
      let originalWindowFrame = window.frame
      let windowNumber = window.windowNumber
      func event(_ type: NSEvent.EventType, x: CGFloat, clicks: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 217),
          modifierFlags: [], timestamp: 0, windowNumber: windowNumber, context: nil,
          eventNumber: 0, clickCount: clicks, pressure: 1))
      }
      XCTAssertFalse(view.mouseDownCanMoveWindow)
      view.mouseDown(with: try event(.leftMouseDown, x: 30))
      view.mouseDragged(with: try event(.leftMouseDragged, x: 32))
      XCTAssertEqual(starts, 0)
      view.mouseDragged(with: try event(.leftMouseDragged, x: 50))
      // Reordering moves the view beneath the pointer; its delta must remain
      // relative to the original window point, not its new local coordinates.
      view.setFrameOrigin(NSPoint(x: 160, y: 200))
      view.mouseDragged(with: try event(.leftMouseDragged, x: 80))
      view.mouseUp(with: try event(.leftMouseUp, x: 80))
      XCTAssertEqual(starts, 1)
      XCTAssertEqual(translations, [20, 50])
      XCTAssertEqual(completions, [false])
      XCTAssertEqual(clicks, 0)
      view.mouseDown(with: try event(.leftMouseDown, x: 180))
      view.mouseUp(with: try event(.leftMouseUp, x: 180))
      XCTAssertEqual(clicks, 1)
      view.mouseDown(with: try event(.leftMouseDown, x: 180, clicks: 2))
      view.mouseUp(with: try event(.leftMouseUp, x: 180, clicks: 2))
      XCTAssertEqual(renames, 1)
      XCTAssertEqual(clicks, 1)
      XCTAssertEqual(window.frame, originalWindowFrame)
      XCTAssertFalse(window.isMovable)
    }
  }
}
