import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import Vision

final class ProjectSession: Identifiable {
  var id: UUID { document.id }
  var document: ImageDocument
  var assets: AssetLibrary
  var undo: [HistoryEntry] = []
  var redo: [HistoryEntry] = []
  var url: URL?
  var sourceURL: URL?
  var lastActivated = Date()
  var savedDocument: ImageDocument?
  var libraryFolderID: UUID?
  var isStartPage = false
  var thumbnail: CGImage?
  init(_ document: ImageDocument, assets: AssetLibrary = AssetLibrary()) {
    self.document = document
    self.assets = assets
  }
  var dirty: Bool {
    guard !isStartPage else { return false }
    guard var saved = savedDocument else { return true }
    saved.selectedLayerID = document.selectedLayerID
    return document != saved
  }
}

@MainActor
final class EditorStore: ObservableObject {
  @Published var language = AppLanguage.saved() {
    didSet {
      language.save()
      AppLocalization.language = language
      status = ""
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NativeMenuLocalization.shared.refresh() }
    }
  }
  @Published var sessions: [ProjectSession] = []
  @Published var activeID: UUID?
  @Published var revision = 0
  @Published var preview: CGImage?
  @Published var layerPreviews: [UUID: LayerPreview] = [:]
  @Published var previewRevision = 0
  @Published var tool: ToolCategory = .brush
  @Published var toolDefaults: [String: String] =
    UserDefaults.standard.dictionary(forKey: "toolDefaults") as? [String: String] ?? [:]
  @Published var inspector: InspectorContext = .base
  @Published var showLayers = false
  @Published var showEffects = false
  @Published var showInspector = false
  @Published var showTools = false
  @Published var textEditingLayerID: UUID?
  @Published var canvasCanUndo = false
  @Published var canvasCanRedo = false
  var canvasViewport = CGSize(width:1000,height:700)
  var canvasUndo: (() -> Bool)?
  var canvasRedo: (() -> Bool)?
  var canUndo: Bool { rulerMode ? !rulerUndo.isEmpty : canvasCanUndo || !active.undo.isEmpty }
  var canRedo: Bool { rulerMode ? !rulerRedo.isEmpty : canvasCanRedo || !active.redo.isEmpty }
  /// A start page is a real tab, not a global mode independent of selection.
  var showWelcome: Bool { active.isStartPage }
  @Published var sheet: String?
  @Published var multiSelectedLayers: Set<UUID> = []
  @Published var retouchPathID: UUID?
  @Published var selection: SelectionRegion?
  @Published var zoom: Double = 1
  @Published var pan = CGSize.zero
  @Published var brushSize: Double = 48
  @Published var brushHardness: Double = 0.8
  @Published var brushOpacity: Double = 1
  @Published var brushFlow: Double = 1
  @Published var brushDynamics = BrushDynamics()
  @Published var brushPopover = false
  @Published var moreToolPopover = false
  @Published var shapePopover = false
  @Published var gradientPoint: UUID?
  @Published var customShape = "heart"
  @Published var shapeSides = 6
  @Published var selectionTolerance: Double = 0.15
  @Published var selectionFeather: Double = 0
  @Published var selectionMode = "new"
  @Published var editingMask = false
  @Published var maskReveal = false
  @Published var maskOverlay = false
  @Published var refiningSelection = false
  @Published var refineRoundness: Double = 0
  @Published var refineSoftness: Double = 0
  @Published var refineExpand: Double = 0
  @Published var refineOverlay = "red"
  @Published var refineOutput = "selection"
  @Published var refineBrush = "basic"
  @Published var refineMode = "add"
  @Published var refineBrushSize: Double = 40
  @Published var refineBrushSoftness: Double = 0.3
  var refineOriginal: SelectionRegion?
  var refineInput: SelectionRegion?
  var refinePreviousInspector: InspectorContext = .base
  var refinePreviousVisibility = false
  var refineGeneration = 0
  @Published var colorRangeSample: CGPoint?
  @Published var transformActive = false
  @Published var transformMode: TransformMode = .free
  @Published var layerPanelPinned = false
  @Published var cropRatio = "free"
  @Published var cloneSource: CGPoint?
  @Published var secondaryColor = RGBA(r: 1, g: 1, b: 1)
  @Published var foreground = RGBA(r: 0.05, g: 0.07, b: 0.12)
  @Published var busy = false
  @Published var status = ""
  @Published var statusIsWarning = false
  @Published var error: String?
  @Published var extensions: [ExtensionManifest] = []
  @Published var recentProjects: [RecentProject] = []
  @Published var projectFolders: [ProjectFolder] = []
  @Published var libraryOrder: [String] = UserDefaults.standard.stringArray(forKey:"projectLibraryOrder") ?? []
  @Published var hiddenHistorySessions: Set<UUID> = []
  @Published var showGrid = false
  @Published var roundedCanvas = UserDefaults.standard.bool(forKey: "roundedCanvas")
  @Published var showRulers = false
  /// Ruler mode captures measurements on the canvas; showRulers controls their visibility after leaving the mode.
  @Published var rulerMode = false
  @Published var rulerMeasurements: [RulerMeasurement] = []
  var layerSelectionAnchor: UUID?
  @Published var activeRulerTool: RulerTool = .ruler
  @Published var rulerUnit = UserDefaults.standard.string(forKey: "rulerUnit") ?? "px"
  @Published var selectedRulerID: UUID?
  private var rulerSessionStart = 0
  private var rulerSessionSnapshot: [RulerMeasurement] = []
  private var rulerUndo: [[RulerMeasurement]] = []
  private var rulerRedo: [[RulerMeasurement]] = []
  @Published var showScopes = false
  @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
  @Published var snapping = true
  @Published var snapGuides: [SnapGuide] = []
  var contentAnchors: [String: ContentAnchors] = [:]
  @Published var contentSnapping = true
  @Published var themeColor = UserDefaults.standard.string(forKey: "themeColor") ?? "system"
  var accent: Color {
    switch themeColor {
    case "blue": return .blue
    case "purple": return .purple
    case "pink": return .pink
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green": return .green
    case "graphite": return .gray
    default: return Color(nsColor: .controlAccentColor)
    }
  }
  var transformSnapshot: ImageDocument?
  private var transformGestureTransaction = false
  private var transaction: (name: String, before: ImageDocument)?
  private var renderWork: DispatchWorkItem?
  private var statusWork: DispatchWorkItem?
  private var autosaveTimer: Timer?
  private var autosaving = false
  private var recoverySnapshots: [UUID:ImageDocument] = [:]
  private let recoveryQueue = DispatchQueue(label:"com.imagepro.recovery",qos:.utility)
  private let recoveryEnabled: Bool
  private var terminationApproved = false
  let selectionQueue = DispatchQueue(label: "com.imagepro.selection", qos: .userInitiated)
  var selectionToken = 0
  @Published var selectingRegion = false
  var pendingColorSamples: [(CGPoint, String)] = []
  private let renderQueue = DispatchQueue(label: "com.imagepro.render", qos: .userInteractive)
  private var rendering = false
  private var renderAgain = false
  private var renderGeneration = 0
  var adjustmentInputCache: (ImageDocument,ImageLayer,CGImage?)?
  var effectInputCache: (ImageLayer,CGImage?)?
  let renderer = ImageRenderer()
  var active: ProjectSession { sessions.first { $0.id == activeID } ?? sessions[0] }
  var document: ImageDocument { active.document }
  var selected: ImageLayer? { document.selectedLayer }
  var branch: ToolBranch {
    tool.branches.first { $0.id == toolDefaults[tool.rawValue] } ?? tool.branches[0]
  }
  var interactionTool: ToolCategory {
    if tool == .canvas {return ["move":.move,"crop":.crop,"hand":.hand,"zoom":.zoom,"eyedropper":.eyedropper][branch.id] ?? .move}
    if tool == .brush,branch.id == "eraser" {return .eraser}
    return tool
  }
  var compositorToolID: String? {
    switch interactionTool {
    case .crop: return "crop"
    case .text: return "horizontalText"
    case .retouch where branch.id == "heal": return "miganHeal"
    case .retouch, .detail:
      return ["smudge","liquify"].contains(branch.id) ? branch.id : nil
    default: return nil
    }
  }
  var undoLabel: String { if rulerMode {return "撤销标尺操作"}; if canvasCanUndo {return textEditingLayerID != nil ? "撤销文字编辑" : "撤销路径节点"}; return active.undo.last.map { "撤回「\(L($0.name))」" } ?? "没有可撤回的操作" }
  var redoLabel: String { if rulerMode {return "恢复标尺操作"}; if canvasCanRedo {return textEditingLayerID != nil ? "恢复文字编辑" : "恢复路径节点"}; return active.redo.last.map { "恢复「\(L($0.name))」" } ?? "没有可恢复的操作" }
  var supportURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ImagePro", isDirectory: true)
  }
  init(loadRecovery: Bool = true) {
    recoveryEnabled = loadRecovery && !CommandLine.arguments.contains("--self-test")
    if recoveryEnabled, let data = UserDefaults.standard.data(forKey: "recentProjects"),
      let entries = try? JSONDecoder().decode([RecentProject].self, from: data) {
      recentProjects = entries
    }
    if recoveryEnabled, let data = UserDefaults.standard.data(forKey: "projectFolders"),
      let folders = try? JSONDecoder().decode([ProjectFolder].self, from: data) {
      projectFolders = folders
    }
    FontCatalog.registerBundledAndPersonalFonts()
    if let data = UserDefaults.standard.data(forKey: "extensions"),
      let values = try? JSONDecoder().decode([ExtensionManifest].self, from: data)
    {
      extensions = values
    }
    newStartPage()
    renderNow()
    if recoveryEnabled {
      restoreAutosaves()
      autosaveTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.autosave() }
      }
    }
  }
  func newStartPage() {
    var doc = ImageDocument()
    doc.name = "启动页"
    let session = ProjectSession(doc)
    session.isStartPage = true
    session.savedDocument = doc
    if sessions.isEmpty {
      sessions = [session]
      activeID = session.id
    } else {
      let index = sessions.firstIndex { $0.id == activeID }.map { $0 + 1 } ?? sessions.count
      sessions.insert(session, at: index)
      activate(session.id)
    }
    sheet = nil
  }

  func beginRulerMode() {
    guard !showWelcome else { return }
    if transformActive {finishTransform()}
    textEditingLayerID = nil;endTransaction();selection = nil
    rulerSessionStart = rulerMeasurements.count
    rulerSessionSnapshot = rulerMeasurements
    selectedRulerID = nil
    rulerMode = true
    rulerUndo.removeAll(); rulerRedo.removeAll()
    showRulers = true
    showLayers = false; showEffects = false; showInspector = false; showTools = false
  }
  func finishRulerMode() {
    rulerMode = false
    showRulers = true
    rulerSessionStart = rulerMeasurements.count
    rulerUndo.removeAll(); rulerRedo.removeAll()
  }
  func cancelRulerMode() {
    rulerMeasurements = rulerSessionSnapshot
    selectedRulerID = nil
    rulerMode = false
    showRulers = !rulerMeasurements.isEmpty
    rulerUndo.removeAll(); rulerRedo.removeAll()
  }

  func rulerUndoSnapshot() {rulerUndo.append(rulerMeasurements); rulerRedo.removeAll()}

  func addRulerMeasurement(_ measurement: RulerMeasurement) {
    rulerUndo.append(rulerMeasurements)
    rulerMeasurements.append(measurement)
    rulerRedo.removeAll()
  }

  func deleteLastRulerMeasurement() {
    guard let i = rulerMeasurements.lastIndex(where: {$0.locked != true}) else { return }
    rulerUndo.append(rulerMeasurements)
    rulerMeasurements.remove(at:i)
    rulerRedo.removeAll()
    showRulers = rulerMode || !rulerMeasurements.isEmpty
  }

  func undoRulerMeasurement() -> Bool {
    guard rulerMode, let previous = rulerUndo.popLast() else { return false }
    rulerRedo.append(rulerMeasurements); rulerMeasurements = previous
    showRulers = rulerMode || !rulerMeasurements.isEmpty
    selectedRulerID = nil
    return true
  }

  func redoRulerMeasurement() -> Bool {
    guard rulerMode, let next = rulerRedo.popLast() else { return false }
    rulerUndo.append(rulerMeasurements); rulerMeasurements = next
    showRulers = rulerMode || !rulerMeasurements.isEmpty
    selectedRulerID = nil
    return true
  }

  func rulerValue(_ pixels: Double) -> Double {
    switch rulerUnit {
    case "mm": return pixels * 25.4 / max(1, document.dpi)
    case "cm": return pixels * 2.54 / max(1, document.dpi)
    case "in": return pixels / max(1, document.dpi)
    default: return pixels
    }
  }

  func setRulerUnit(_ unit: String) {
    guard ["px", "mm", "cm", "in"].contains(unit) else { return }
    rulerUnit = unit
    UserDefaults.standard.set(unit, forKey: "rulerUnit")
    revision += 1
  }

  /// Only the selected start page is consumed, and only after a successful open.
  private func installProject(_ session: ProjectSession) {
    // Every opened project needs its own thumbnail immediately, including
    // background tabs when several files open before the canvas can render.
    if session.thumbnail == nil {
      session.thumbnail = Self.tabThumbnail(renderer.render(
        session.document, assets: session.assets, maxDimension: 96))
    }
    if let index = sessions.firstIndex(where: { $0.id == activeID && $0.isStartPage }) {
      // Finish operations on the old session before replacing its slot.
      endTransaction()
      sessions[index] = session
    } else {
      let index = sessions.firstIndex { $0.id == activeID }.map { $0 + 1 } ?? sessions.count
      sessions.insert(session, at: index)
    }
    activate(session.id)
  }

  func moveProject(_ id: UUID, to target: UUID) {
    guard id != target,
      let source = sessions.firstIndex(where: { $0.id == id }),
      let destination = sessions.firstIndex(where: { $0.id == target }) else { return }
    sessions.move(fromOffsets: IndexSet(integer: source),
                  toOffset: destination > source ? destination + 1 : destination)
  }

  func renameProject(_ id: UUID, to name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, let session = sessions.first(where: { $0.id == id }),
      !session.isStartPage, session.document.name != name else { return }
    if id == activeID { endTransaction() }
    let before = session.document
    session.document.name = name
    session.undo.append(HistoryEntry(name: "重命名项目", before: before, after: session.document))
    session.redo.removeAll()
    terminationApproved = false
    revision += 1
  }

  func duplicateProject(_ id: UUID) {
    guard let source = sessions.first(where: { $0.id == id }) else { return }
    if source.isStartPage { newStartPage(); return }
    var doc = source.document
    doc.id = UUID()
    doc.name += L(" 副本")
    let session = ProjectSession(doc, assets: source.assets)
    session.thumbnail = source.thumbnail ?? Self.tabThumbnail(renderer.render(
      session.document, assets: session.assets, maxDimension: 96))
    let index = sessions.firstIndex { $0.id == id }!
    sessions.insert(session, at: index + 1)
    activate(session.id)
  }

  func notify(_ message: String, warning: Bool = false) {
    statusWork?.cancel()
    statusIsWarning = warning
    status = message
    let work = DispatchWorkItem { [weak self] in self?.status = "" }
    statusWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
  }
  func fail(_ failure: Error) { error = failure.localizedDescription }
  func edit(_ name: String, _ operation: (inout ImageDocument) -> Void) {
    guard !rulerMode else {return}
    let before = document
    var doc = before
    operation(&doc)
    guard doc != before else { return }
    active.isStartPage = false
    active.document = doc
    if transaction == nil { appendHistory(name, before: before, after: doc) }
    revision += 1
    requestRender()
  }
  private func appendHistory(_ name: String, before: ImageDocument, after: ImageDocument) {
    terminationApproved = false
    if var previous = active.undo.last, previous.name == name,
      name == "编辑文字" || name.hasPrefix("重命名") || name == "修改作者",
      Date().timeIntervalSince(previous.date) < 0.7
    {
      previous.after = after
      previous.date = Date()
      active.undo[active.undo.count - 1] = previous
      active.redo.removeAll()
      return
    }
    active.undo.append(HistoryEntry(name: name, before: before, after: after))
    active.redo.removeAll()
    let limit = max(
      20,
      min(
        1000,
        UserDefaults.standard.integer(forKey: "historyLimit") == 0
          ? 200 : UserDefaults.standard.integer(forKey: "historyLimit")))
    if active.undo.count > limit { active.undo.removeFirst(active.undo.count - limit) }
  }
  func cancelTransaction(_ snapshot: ImageDocument) {
    transaction = nil
    active.document = snapshot
    revision += 1
    requestRender()
  }
  func beginTransaction(_ name: String) { if transaction == nil { transaction = (name, document) } }
  /// A canvas pointer gesture inside an active free-transform session is an
  /// independent undo step. Programmatic edits still retain the session-level
  /// transaction used by the document API.
  func beginTransformGesture(_ name: String) {
    transformGestureTransaction = transformActive
    beginTransaction(name)
  }
  func endTransaction() {
    if transformActive && transformSnapshot != nil && !transformGestureTransaction { return }
    if let transaction, transaction.before != document {
      appendHistory(transaction.name, before: transaction.before, after: document)
      revision += 1
    }
    transaction = nil
    transformGestureTransaction = false
    requestRender()
  }
  func updateSelected(_ name: String, _ operation: (inout ImageLayer) -> Void) {
    guard let id = document.selectedLayerID else { return }
    edit(name) { doc in
      if let i = doc.layers.firstIndex(where: { $0.id == id }) {
        operation(&doc.layers[i])
        if doc.layers[i].kind == .text, doc.layers[i].text != document.layers.first(where:{$0.id == id})?.text {
          let text = doc.layers[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
          doc.layers[i].name = text.isEmpty ? L("文字") : String(text.prefix(32)).replacingOccurrences(of: "\n", with: " ")
        }
        TextLayout.resizePointText(&doc.layers[i])
      }
    }
  }
  func selectLayer(_ id: UUID, revealInspector: Bool = true) {
    multiSelectedLayers = []
    if refiningSelection { finishRefinement(cancel:true) }
    if transformActive { finishTransform() }
    endTransaction()
    active.document.selectedLayerID = id
    editingMask = false
    inspector = selected?.defaultInspector ?? .base
    if revealInspector {showInspector = true}
    revision += 1
  }
  func chooseTool(_ category: ToolCategory, branch: ToolBranch? = nil) {
    let legacyCanvas: [ToolCategory:String] = [.move:"move",.crop:"crop",.hand:"hand",.zoom:"zoom",.eyedropper:"eyedropper"]
    if let id = legacyCanvas[category] {chooseTool(.canvas,branch:ToolCategory.canvas.branches.first {$0.id == id});return}
    if category == .eraser {chooseTool(.brush,branch:ToolCategory.brush.branches.first {$0.id == "eraser"});return}
    if [.clone,.dodge,.detail].contains(category) {chooseTool(.retouch,branch:branch ?? category.branches.first);return}
    if category != .text {textEditingLayerID = nil}
    if refiningSelection, category != .selection { finishRefinement(cancel:true) }
    if transformActive { finishTransform() }
    endTransaction()
    cancelColorSelection()
    tool = category
    if let branch {
      toolDefaults[category.rawValue] = branch.id
      UserDefaults.standard.set(toolDefaults, forKey: "toolDefaults")
    }
    if !editingMask { inspector = selected?.defaultInspector ?? .base }
    transformActive = false
    if category == .shape && self.branch.id == "star" { shapeSides = 5 }
    brushDynamics.mode = self.branch.id
    if interactionTool == .crop {
      let canvas = CGRect(x:0,y:0,width:document.width,height:document.height)
      let r = selection?.type == "crop" ? selection!.bounds : (selection?.bounds.intersection(canvas) ?? canvas)
      selection = SelectionRegion(type: "crop", points: [Point(r.origin), Point(x: r.maxX, y: r.maxY)])
      constrainCropRatio()
    }
    if category == .brush {
      if self.branch.id == "pencil" {
        brushHardness = 1
        brushSize = 4
      }
      if self.branch.id == "marker" {
        brushHardness = 1
        brushSize = 32
        brushOpacity = 0.6
      }
      if self.branch.id == "airbrush" {
        brushHardness = 0.05
        brushOpacity = 0.2
      }
    }
    if category == .fill, self.branch.id == "mesh", selected?.gradient?.style != "mesh" {
      addGradient(from: .zero, to: CGPoint(x:document.width,y:document.height))
    }
    revision += 1
  }
  func undo() {
    // Ruler mode is a self-contained editing session. A command-Z with no
    // ruler history must never reach the document history from before entry.
    if rulerMode { _ = undoRulerMeasurement(); return }
    if canvasUndo?() == true { return }
    if transformActive { finishTransform() }
    endTransaction()
    guard let entry = active.undo.popLast() else { return }
    active.redo.append(entry)
    active.document = entry.before
    repairContext()
    revision += 1
    requestRender()
    notify("已撤回：\(L(entry.name))")
  }
  func redo() {
    if rulerMode { _ = redoRulerMeasurement(); return }
    if canvasRedo?() == true { return }
    if transformActive { finishTransform() }
    endTransaction()
    guard let entry = active.redo.popLast() else { return }
    active.undo.append(entry)
    active.document = entry.after
    repairContext()
    revision += 1
    requestRender()
    notify("已恢复：\(L(entry.name))")
  }
  func repairContext() {
    deselect()
    if inspector == .mask,selected?.maskAssetID == nil {editingMask = false;inspector = selected?.defaultInspector ?? .base}
    if inspector == .special,selected?.specialInspectorTitle == nil {inspector = .base}
    if case .effect(let id) = inspector,
      !(selected?.effects.contains(where: { $0.id == id }) ?? false)
    {
      inspector = .base
    }
  }
  func requestRender() {
    renderGeneration += 1
    if rendering {
      renderAgain = true
      return
    }
    if renderWork != nil { return }
    let work = DispatchWorkItem { [weak self] in
      self?.renderWork = nil
      self?.renderAsync()
    }
    renderWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.012, execute: work)
  }
  private func renderAsync() {
    rendering = true
    renderAgain = false
    let doc = document
    let assets = active.assets
    let generation = renderGeneration
    let renderer = renderer
    let maxDimension = transaction != nil ? 1100.0 : 1800.0
    let oldAnchors = contentAnchors
    renderQueue.async { [weak self] in
      let scale = min(1, maxDimension / max(doc.width, doc.height))
      var layers: [UUID: LayerPreview] = [:]
      for layer in doc.layers where layer.kind != .group && layer.kind != .adjustment {
        layers[layer.id] = renderer.previewLayer(layer, assets: assets, scale: scale)
      }
      var anchors = oldAnchors
      for layer in doc.layers {
        if let key = layer.assetID, anchors[key] == nil, let image = assets.image(key) { anchors[key] = SnapEngine.content(image) }
      }
      let result = renderer.render(doc, assets: assets, maxDimension: maxDimension)
      DispatchQueue.main.async {
        guard let self else { return }
        self.rendering = false
        if let session = self.sessions.first(where: { $0.id == doc.id }), session.document == doc {
          session.thumbnail = Self.tabThumbnail(result)
          self.objectWillChange.send()
        }
        if self.activeID == doc.id,generation == self.renderGeneration {
          self.layerPreviews = layers
          self.previewRevision += 1
          self.contentAnchors = anchors
          if generation == self.renderGeneration { self.preview = result }
        }
        if self.renderAgain || generation != self.renderGeneration { self.renderAsync() }
      }
    }
  }
  func renderNow() {
    let scale = min(1, 1800 / max(document.width, document.height))
    layerPreviews = Dictionary(
      uniqueKeysWithValues: document.layers.filter { $0.kind != .group }.compactMap { l in
        renderer.previewLayer(l, assets: active.assets, scale: scale).map { (l.id, $0) }
      })
    preview = renderer.render(document, assets: active.assets)
    active.thumbnail = Self.tabThumbnail(preview)
    previewRevision += 1
  }
  private static func tabThumbnail(_ image: CGImage?) -> CGImage? {
    guard let image else { return nil }
    let scale = min(1, 96 / Double(max(image.width, image.height)))
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))
    guard let context = ImageRenderer.bitmap(width, height) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
  func activate(_ id: UUID) {
    guard sessions.contains(where: { $0.id == id }) else { return }
    if refiningSelection { finishRefinement(cancel:true) }
    editingMask = false
    if transformActive { finishTransform() }
    cancelColorSelection()
    endTransaction()
    multiSelectedLayers = []; retouchPathID = nil
    activeID = id
    inspector = selected?.defaultInspector ?? .base
    active.lastActivated = Date()
    repairContext()
    zoom = 1
    pan = .zero
    layerPreviews = [:]
    revision += 1
    requestRender()
  }
  func newProject(name: String = L("未命名"), width: Double = 1920, height: Double = 1080,
    dpi: Double = 300, background: RGBA? = nil, author: String = "",
    grid: Bool = false, rulers: Bool = false) {
    var doc = ImageDocument()
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    doc.name = trimmedName.isEmpty ? L("未命名") : trimmedName
    doc.author = author
    doc.width = width.rounded()
    doc.height = height.rounded()
    doc.dpi = dpi
    var layer = ImageLayer(name: L("画布"), kind: .paint, width: doc.width, height: doc.height)
    layer.color = foreground
    doc.layers = [layer]
    if let background {
      var paper = ImageLayer(name: L("背景"), kind: .shape, width: doc.width, height: doc.height)
      paper.color = background
      paper.cornerRadius = 0
      paper.locked = true
      doc.layers.append(paper)
    }
    doc.selectedLayerID = layer.id
    do { try doc.validate() } catch { fail(error); return }
    endTransaction()
    installProject(ProjectSession(doc))
    rulerMode = false
    showGrid = grid
    showRulers = rulers
    rulerMeasurements = []
    sheet = nil
  }
  func addLayer(_ kind: LayerKind, at point: CGPoint? = nil, rect: CGRect? = nil) {
    let size =
      rect?.size
      ?? CGSize(
        width: kind == .text
          ? min(900, document.width * 0.7) : kind == .shape ? 320 : document.width,
        height: kind == .text ? 240 : kind == .shape ? 240 : document.height)
    let defaultName = kind == .text ? "文字" : kind == .shape ? "形状" : kind == .group ? "文件夹" : "空白图层"
    var layer = ImageLayer(
      name: L(defaultName), kind: kind, width: size.width, height: size.height)
    layer.x =
      (rect.map { Double($0.minX) } ?? point.map { Double($0.x) })
      ?? (kind == .paint || kind == .group ? 0 : document.width * 0.2)
    layer.y =
      (rect.map { Double($0.minY) } ?? point.map { Double($0.y) })
      ?? (kind == .paint || kind == .group ? 0 : document.height * 0.3)
    if kind == .shape && branch.id == "line" { layer.cornerRadius = 4 }
    layer.parentID = selected?.parentID
    layer.color = foreground
    layer.shape = branch.id == "custom" ? customShape : branch.id
    layer.shapeSides = shapeSides
    if kind == .text {
      var style = TextStyle()
      style.vertical = branch.id == "verticalText"
      layer.textStyle = style
    }
    edit("新建\(defaultName)") { doc in
      doc.layers.insert(layer,at:doc.insertionIndex)
      doc.selectedLayerID = layer.id
    }
    inspector = selected?.defaultInspector ?? .base
    if kind == .text || kind == .shape {showInspector = true}
  }
  func duplicateLayer(_ id: UUID) {
    edit("复制图层") { doc in
      guard let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
      var copy = doc.layers[i]
      copy.id = UUID()
      copy.name += L(" 副本")
      copy.x += 24
      copy.y += 24
      if copy.kind == .group {
        copy.kind = .paint
        copy.name = L("空白图层")
      }  // Folder actions use ungroup instead.
      doc.layers.insert(copy, at: i)
      doc.selectedLayerID = copy.id
    }
  }
  func deleteLayer(_ id: UUID) {
    edit("删除图层") { doc in
      doc.layers.removeAll { $0.id == id }
      for i in doc.layers.indices where doc.layers[i].parentID == id {
        doc.layers[i].parentID = nil
      }
      if doc.selectedLayerID == id { doc.selectedLayerID = doc.layers.first?.id }
    }
    repairContext()
  }
  func toggleVisibility(_ id: UUID) {
    edit("切换图层可见性") { doc in
      if let i = doc.layers.firstIndex(where: { $0.id == id }) { doc.layers[i].visible.toggle() }
    }
  }
  func toggleLock(_ id: UUID) {
    edit("切换图层锁定") { doc in
      if let i = doc.layers.firstIndex(where: { $0.id == id }) { doc.layers[i].locked.toggle() }
    }
  }
  func toggleClippingMask(_ id: UUID) {
    guard let index = document.layers.firstIndex(where: { $0.id == id }), index + 1 < document.layers.count,
      document.layers[index + 1].kind != .group else {
      notify("剪切蒙版需要一个下方的内容图层")
      return
    }
    edit("切换剪切蒙版") { doc in
      if let i = doc.layers.firstIndex(where: { $0.id == id }) { doc.layers[i].clippingMask.toggle() }
    }
  }
  func removeMask(_ id: UUID) {
    guard document.layers.contains(where: { $0.id == id && $0.maskAssetID != nil }) else { return }
    edit("解除蒙版") { doc in
      guard let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
      doc.layers[i].maskAssetID = nil
      doc.layers[i].maskStrokes = nil
      doc.layers[i].maskDensity = nil
      doc.layers[i].maskOpacity = nil
      doc.layers[i].maskFeather = nil
      doc.layers[i].maskInverted = nil
      doc.layers[i].maskEnabled = true
    }
    if selected?.id == id {
      editingMask = false
      inspector = .base
    }
  }
  func renameLayer(_ id: UUID, name: String) {
    edit("重命名图层") { doc in
      if let i = doc.layers.firstIndex(where: { $0.id == id }) { doc.layers[i].name = name }
    }
  }
  func extractTextFromSelected() {
    guard let layer = selected, layer.kind == .text, !layer.text.isEmpty else {
      notify("当前图层没有可提取的文字")
      return
    }
    let style = layer.textStyle ?? TextStyle()
    let font = NSFont(name: layer.fontName, size: layer.fontSize) ?? NSFont.systemFont(ofSize: layer.fontSize)
    let color = layer.color.ns
    let alignment: NSTextAlignment = style.alignment == 1 ? .center : style.alignment == 2 ? .right : style.alignment == 3 ? .justified : .left
    let attributed = NSAttributedString(string: layer.text, attributes: [
      .font: font, .foregroundColor: color,
      .kern: style.tracking,
      .paragraphStyle: {
        let p = NSMutableParagraphStyle(); p.alignment = alignment; p.lineSpacing = max(0, layer.fontSize * (style.lineHeight - 1)); return p
      }()
    ])
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([layer.text as NSString])
    if let rtf = try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
      pasteboard.setData(rtf, forType: .rtf)
    }
    notify("已提取文字并复制到剪贴板（包含格式）")
  }

  func reorderLayer(_ id: UUID, delta: Int) {
    edit("调整图层顺序") { doc in
      guard let i = doc.layers.firstIndex(where: { $0.id == id }), doc.layers[i].kind != .group
      else { return }
      let target = max(0, min(doc.layers.count - 1, i + delta))
      guard i != target else { return }
      let layer = doc.layers.remove(at: i)
      doc.layers.insert(layer, at: target)
    }
  }
  func groupSelected() {
    let ids = selectedIDs
    guard ids.count > 1 else {return}
    let chosen = document.layers.filter {ids.contains($0.id)}
    guard !chosen.contains(where: {$0.locked}) else {return}
    let roots = chosen.filter {layer in
      var parent = layer.parentID
      while let id = parent {
        if ids.contains(id) {return false}
        parent = document.layers.first {$0.id == id}?.parentID
      }
      return true
    }
    guard let first = roots.first else {return}
    var group = ImageLayer(name:L("文件夹"),kind:.group,width:document.width,height:document.height)
    group.parentID = roots.allSatisfy {$0.parentID == first.parentID} ? first.parentID : nil
    let moving = descendants(of:Set(roots.map(\.id)))
    edit("编组图层") {doc in
      let index = doc.layers.firstIndex {moving.contains($0.id)} ?? 0
      var block = doc.layers.filter {moving.contains($0.id)}
      for i in block.indices where roots.contains(where: {$0.id == block[i].id}) {block[i].parentID = group.id}
      doc.layers.removeAll {moving.contains($0.id)}
      doc.layers.insert(contentsOf:[group]+block,at:min(index,doc.layers.count))
      doc.selectedLayerID = group.id
    }
    multiSelectedLayers = [];layerSelectionAnchor = group.id
  }
  func ungroup(_ id: UUID) {
    edit("取消编组") { doc in
      let parent = doc.layers.first { $0.id == id }?.parentID
      for i in doc.layers.indices where doc.layers[i].parentID == id {
        doc.layers[i].parentID = parent
      }
      doc.layers.removeAll { $0.id == id }
      doc.selectedLayerID = doc.layers.first?.id
    }
  }
  func mergeDown(_ id: UUID) {
    guard let index = document.layers.firstIndex(where: { $0.id == id }),
      index + 1 < document.layers.count,
      document.layers[index].kind != .group, document.layers[index + 1].kind != .group
    else { return }
    do {
      var temp = document
      temp.layers = Array(document.layers[index...index + 1])
      guard let image = renderer.render(temp, assets: active.assets, maxDimension: nil) else {
        throw ImageProError.message("合并失败。")
      }
      var layer = ImageLayer(
        name: selected?.name ?? L("合并图层"), kind: .raster, width: document.width,
        height: document.height)
      layer.assetID = try active.assets.insert(image)
      edit("合并图层") { doc in
        doc.layers.replaceSubrange(index...index + 1, with: [layer])
        doc.selectedLayerID = layer.id
      }
    } catch { fail(error) }
  }
  func mergeDownAll(_ id: UUID) {
    guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
    let parent = document.layers[index].parentID
    let siblings = Set(document.layers.dropFirst(index).filter {$0.parentID == parent}.map(\.id))
    let ids = descendants(of:siblings)
    guard siblings.count>1 else {return}
    let oldPrimary = document.selectedLayerID
    multiSelectedLayers = ids;active.document.selectedLayerID = id
    mergeSelectedLayers()
    if document.layers.contains(where:{$0.id == oldPrimary}) {active.document.selectedLayerID = oldPrimary}
  }
  func addEffect(_ kind: EffectKind, extension plugin: ExtensionManifest? = nil) {
    let creatingFX = selected == nil
    if creatingFX {
      beginTransaction("添加 FX 效果")
      let layer = ImageLayer(name:L("FX · 调整图层"),kind:.adjustment,width:document.width,height:document.height)
      edit("添加 FX 效果") {doc in doc.layers.insert(layer,at:0);doc.selectedLayerID = layer.id}
    }
    var effect = ImageEffect(kind, name: plugin?.name)
    effect.filterName = plugin?.coreImageFilter
    if kind == .beauty { effect.style = "face" }
    updateSelected("添加\(effect.name)") { $0.effects.append(effect) }
    if creatingFX {endTransaction()}
    inspector = .effect(effect.id)
    showInspector = true
    showEffects = false
    if kind == .beauty || kind == .body { detectPortrait(for:effect.id,body:kind == .body) }
  }
  func updateEffect(_ id: UUID, _ name: String, _ operation: (inout ImageEffect) -> Void) {
    updateSelected(name) { layer in
      if let i = layer.effects.firstIndex(where: { $0.id == id }) { operation(&layer.effects[i]) }
    }
  }
  func removeEffect(_ id: UUID) {
    updateSelected("删除效果") { $0.effects.removeAll { $0.id == id } }
    inspector = selected?.defaultInspector ?? .base
  }
  func reorderEffect(_ id: UUID, delta: Int) {
    updateSelected("调整效果顺序") { layer in
      guard let i = layer.effects.firstIndex(where: { $0.id == id }) else { return }
      let target = max(0, min(layer.effects.count - 1, i + delta))
      let effect = layer.effects.remove(at: i)
      layer.effects.insert(effect, at: target)
    }
  }
  func appendStroke(_ stroke: BrushStroke) {
    if selected == nil || selected?.kind == .group { addLayer(.paint) }
    guard selected?.locked != true else {
      notify("当前图层已锁定")
      return
    }
    updateSelected(stroke.erasing ? "橡皮擦除" : "画笔描边") { layer in
      var stroke = stroke
      let outside = stroke.points.contains {$0.x-stroke.size<0 || $0.y-stroke.size<0 || $0.x+stroke.size>layer.width || $0.y+stroke.size>layer.height}
      if outside,layer.quad != nil || layer.warpNodes != nil {
        let original = layer
        guard self.bakeDrawingGeometry(&layer) else {return}
        func map(_ p:Point) -> Point {Point(TransformGeometry.contentPoint(TransformGeometry.displayPoint(p.cg,layer:original),layer:layer))}
        stroke.points = stroke.points.map(map)
        if var clip = stroke.clip {
          let r = clip.bounds
          if ["rectangle","crop"].contains(clip.type) {
            clip.type = "lasso";clip.points = [Point(x:r.minX,y:r.minY),Point(x:r.maxX,y:r.minY),Point(x:r.maxX,y:r.maxY),Point(x:r.minX,y:r.maxY)]
          } else if clip.type == "ellipse" {
            clip.type = "lasso";clip.points = (0..<96).map {i in let a = Double(i)*2 * .pi/96;return Point(x:r.midX+cos(a)*r.width/2,y:r.midY+sin(a)*r.height/2)}
          }
          if let spans = clip.spans {
            clip.contours = spans.map {r in [Point(x:r.x,y:r.y),Point(x:r.x+r.width,y:r.y),Point(x:r.x+r.width,y:r.y+r.height),Point(x:r.x,y:r.y+r.height)]};clip.spans = nil
          }
          clip.points = clip.points.map(map);clip.contours = clip.contours?.map {$0.map(map)}
          stroke.clip = clip
        }
      }
      let shift = LayerExpansion.expand(&layer, including: stroke.points, radius: stroke.size)
      stroke.points = stroke.points.map {Point(x:$0.x+shift.x,y:$0.y+shift.y)}
      if var clip = stroke.clip {clip.points = clip.points.map {Point(x:$0.x+shift.x,y:$0.y+shift.y)};stroke.clip = clip}
      layer.strokes.append(stroke)
    }
  }
  func constrainCropRatio() {
    guard interactionTool == .crop, let selection, cropRatio != "free" else { return }
    let parts = cropRatio.split(separator:":").compactMap { Double($0) }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return }
    let r = selection.bounds
    guard !r.isNull else { return }
    let ratio = parts[0]/parts[1]
    let w = min(r.width,r.height*ratio),h = min(r.height,r.width/ratio)
    self.selection = SelectionRegion(type:"crop",points:[Point(x:r.midX-w/2,y:r.midY-h/2),Point(x:r.midX+w/2,y:r.midY+h/2)])
  }
  func cropToSelection() {
    guard let selection else {
      notify("先在画布拖出裁剪范围")
      return
    }
    let rect = interactionTool == .crop ? CTCropGeometry.snapped(selection.bounds) : selection.bounds.intersection(
      CGRect(x: 0, y: 0, width: document.width, height: document.height)
    ).integral
    guard rect.width >= 1, rect.height >= 1 else { return }
    guard rect.width <= 16384,rect.height <= 16384,rect.width*rect.height <= 100_000_000 else {notify("裁切范围超过画布尺寸上限");return}
    edit("裁剪画布") { doc in
      doc.width = rect.width
      doc.height = rect.height
      for i in doc.layers.indices {
        doc.layers[i].x -= rect.minX
        doc.layers[i].y -= rect.minY
      }
    }
    self.selection = nil
    fitCanvas()
  }
  func fitCanvas() {
    zoom = 1
    pan = .zero
  }
  func openPanel(asLayer: Bool = false) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.title = L(asLayer ? "添加图像图层" : "打开图像或 iMage Pro 项目")
    panel.prompt = L("打开")
    panel.allowedContentTypes = [.image, .pdf,
      UTType(filenameExtension: "psd") ?? .data,
      UTType(filenameExtension: "psb") ?? .data,
      UTType(filenameExtension: "imgp") ?? .package]
    if panel.runModal() == .OK { for url in panel.urls { open(url, asLayer: asLayer) } }
  }
  func open(_ url: URL, asLayer: Bool = false) {
    do {
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw ImageProError.message("文件不存在或已被移动。")
      }
      if url.pathExtension.lowercased() == "imgp" {
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("document.json").path) else {
          throw ImageProError.message("这不是有效的 iMage Pro 项目文件。")
        }
        let session = try loadProject(url)
        if let existing = sessions.first(where: { $0.url?.standardizedFileURL.path == url.standardizedFileURL.path }) {
          let startID = showWelcome ? active.id : nil
          activate(existing.id)
          if let startID { sessions.removeAll { $0.id == startID } }
          rememberRecentProject(at: url, session: existing)
          return
        }
        if sessions.contains(where: { $0.id == session.id }) { session.document.id = UUID() }
        installProject(session)
        rememberRecentProject(at: url, session: session)
        notify("项目已打开")
        return
      }
      if ["psd", "psb"].contains(url.pathExtension.lowercased()) {
        let (imported, library, warning, embedded) = try PSDCodec.read(Data(contentsOf: url))
        if asLayer {
          var layers = imported.layers
          let ids = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, UUID()) })
          for i in layers.indices {
            let old = layers[i].id
            layers[i].id = ids[old]!
            layers[i].parentID = layers[i].parentID.flatMap { ids[$0] }
          }
          for (id, data) in library.data { active.assets.insert(data, id: id) }
          edit("导入 PSD 图层") {
            $0.layers.insert(contentsOf: layers, at: $0.insertionIndex)
            $0.selectedLayerID = layers.first(where: { $0.kind != .group })?.id
          }
          showLayers = true
        } else {
          var doc = imported
          doc.name = url.deletingPathExtension().lastPathComponent
          if sessions.contains(where: { $0.id == doc.id }) { doc.id = UUID() }
          let session = ProjectSession(doc, assets: library)
          session.undo = embedded?.archive.undo ?? []
          session.redo = embedded?.archive.redo ?? []
          installProject(session)
          rememberRecentProject(at: url, session: session)
          showLayers = true
        }
        notify(warning ?? "已恢复 PSD 的图层、分组、名称、混合与透明度")
        return
      }
      let bytes = try Data(contentsOf: url)
      let library = asLayer ? active.assets : AssetLibrary()
      var asset = library.insert(bytes)
      // ImageIO handles common raster/RAW formats and the flattened PSD preview. PDF is rasterized at import.
      if library.image(asset) == nil, let native = NSImage(contentsOf: url),
        let image = native.cgImage(forProposedRect: nil, context: nil, hints: nil)
      {
        asset = try library.insert(image)
      }
      guard let image = library.image(asset) else {
        throw ImageProError.message("无法解码这个文件。请检查文件格式或文件是否损坏。")
      }
      var layer = ImageLayer(
        name: url.deletingPathExtension().lastPathComponent, kind: .raster,
        width: Double(image.width), height: Double(image.height))
      layer.assetID = asset
      if asLayer {
        let scale = min(1, document.width / layer.width, document.height / layer.height)
        layer.width *= scale
        layer.height *= scale
        layer.x = (document.width - layer.width) / 2
        layer.y = (document.height - layer.height) / 2
        edit("导入图像图层") {
          layer.parentID = $0.insertionParent;$0.layers.insert(layer,at:$0.insertionIndex)
          $0.selectedLayerID = layer.id
        }
        showLayers = true
      } else {
        var doc = ImageDocument()
        doc.name = layer.name
        doc.width = layer.width
        doc.height = layer.height
        doc.layers = [layer]
        doc.selectedLayerID = layer.id
        try doc.validate()
        let session = ProjectSession(doc, assets: library)
        installProject(session)
        rememberRecentProject(at: url, session: session)
      }
      if ["psd", "psb", "pdf", "svg"].contains(url.pathExtension.lowercased()) {
        notify("已导入合成图像；原有分层或矢量结构未保留")
      } else {
        notify("图像已打开，原始文件保持完整")
      }
    } catch { fail(error) }
  }
  @discardableResult func save(as saveAs: Bool = false) -> Bool {
    guard !showWelcome else { sheet = "new"; return false }
    if transformActive { finishTransform() }
    endTransaction()
    var url = active.url
    if saveAs || url == nil {
      let panel = NSSavePanel()
      panel.title = L("保存 iMage Pro 项目")
      panel.prompt = L("保存")
      panel.nameFieldStringValue = document.name + ".imgp"
      panel.allowedContentTypes = [UTType(filenameExtension: "imgp") ?? .package]
      panel.canCreateDirectories = true
      guard panel.runModal() == .OK, let chosen = panel.url else { return false }
      // A package must always carry its type extension. NSSavePanel can return
      // a path without it when the user edits the name field manually.
      url = chosen.pathExtension.lowercased() == "imgp"
        ? chosen
        : chosen.appendingPathExtension("imgp")
    }
    do {
      let destination = url!.standardizedFileURL
      let proposed = destination.deletingPathExtension().lastPathComponent
      let unnamed = AppLanguage.allCases.contains { document.name == AppLocalization.string("未命名", language: $0) }
      if !proposed.isEmpty, (unnamed || saveAs) {
        active.document.name = proposed
      }
      try writeProject(active, to: destination)
      url = destination
      active.url = destination
      active.savedDocument = document
      // The name entered in Save is the project name when saving an unnamed
      // document. Keep the document and the start-page entry in sync.
      active.savedDocument = active.document
      rememberRecentProject(at: destination, session: active)
      revision += 1
      notify("已保存：\(destination.lastPathComponent)")
      return true
    } catch {
      fail(error)
      return false
    }
  }
  private func rememberRecentProject(at url: URL, session: ProjectSession) {
    session.sourceURL = url
    let thumbnail = session.thumbnail.flatMap { try? AssetLibrary.encode($0, type: "public.png") }
    let entry = RecentProject(path: url.standardizedFileURL.path,
      name: session.document.name, width: session.document.width, height: session.document.height,
      lastOpened: Date(), thumbnail: thumbnail,folderID:session.libraryFolderID ?? recentProjects.first(where:{$0.path == url.standardizedFileURL.path})?.folderID)
    recentProjects = RecentProject.recordingUnlimited(entry, in: recentProjects)
    if let i = libraryOrder.firstIndex(of:session.id.uuidString) {libraryOrder[i] = url.standardizedFileURL.path;if recoveryEnabled {UserDefaults.standard.set(libraryOrder,forKey:"projectLibraryOrder")}}
    persistRecentProjects()
  }
  func removeRecentProject(_ path: String) {
    recentProjects.removeAll { $0.path == path }
    persistRecentProjects()
  }
  func removeHistoryProject(sessionID: UUID?, url: URL?) {
    if let sessionID { hiddenHistorySessions.insert(sessionID) }
    if let url { removeRecentProject(url.standardizedFileURL.path) }
  }

  /// Rename a closed native project without activating it or losing its assets
  /// and undo history. Imported images retain their format and rename on disk.
  func renameHistoryProject(sessionID: UUID?, url: URL?, to proposedName: String) {
    let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    if let sessionID {
      renameProject(sessionID, to: name)
      return
    }
    guard let url else { return }
    do {
      var destination = url
      if url.pathExtension.lowercased() == "imgp" {
        let session = try loadProject(url)
        let before = session.document
        session.document.name = name
        session.undo.append(HistoryEntry(name: "重命名项目", before: before, after: session.document))
        session.redo.removeAll()
        try writeProject(session, to: url)
      } else {
        guard !name.contains("/"), !name.contains(":"), name != ".", name != ".." else {
          throw ImageProError.message("名称不能包含 / 或 :。")
        }
        destination = url.deletingLastPathComponent().appendingPathComponent(name)
          .appendingPathExtension(url.pathExtension)
        if destination.standardizedFileURL != url.standardizedFileURL {
          try FileManager.default.moveItem(at: url, to: destination)
        }
      }
      if let index = recentProjects.firstIndex(where: { $0.path == url.standardizedFileURL.path }) {
        recentProjects[index].name = name
        recentProjects[index].path = destination.standardizedFileURL.path
        persistRecentProjects()
      }
      notify("项目已重命名")
    } catch { fail(error) }
  }

  func trashHistoryProject(_ url: URL) {
    // Open projects must go through the existing close/save flow first.
    guard !sessions.contains(where: {
      ($0.url ?? $0.sourceURL)?.standardizedFileURL == url.standardizedFileURL
    }) else { return }
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
      removeRecentProject(url.standardizedFileURL.path)
      notify("已移到废纸篓")
    } catch { fail(error) }
  }
  private func persistRecentProjects() {
    guard recoveryEnabled, let data = try? JSONEncoder().encode(recentProjects) else { return }
    UserDefaults.standard.set(data, forKey: "recentProjects")
  }
  private func persistProjectFolders() {
    guard recoveryEnabled, let data = try? JSONEncoder().encode(projectFolders) else { return }
    UserDefaults.standard.set(data, forKey: "projectFolders")
  }
  func createProjectFolder(name: String = L("新建文件夹"), parentID: UUID? = nil) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,parentID == nil || projectFolders.contains(where:{$0.id == parentID}) else { return }
    var unique = trimmed,index = 2
    while projectFolders.contains(where:{$0.parentID == parentID && $0.name == unique}) {unique = trimmed+" \(index)";index += 1}
    projectFolders.append(ProjectFolder(name: unique,parentID:parentID))
    persistProjectFolders()
  }
  func renameProjectFolder(_ id: UUID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let index = projectFolders.firstIndex(where: { $0.id == id }) else { return }
    projectFolders[index].name = trimmed; persistProjectFolders()
  }
  func deleteProjectFolder(_ id: UUID) {
    guard let folder = projectFolders.first(where:{$0.id == id}) else {return}
    for index in projectFolders.indices where projectFolders[index].parentID == id {projectFolders[index].parentID = folder.parentID}
    projectFolders.removeAll { $0.id == id }
    for session in sessions where session.libraryFolderID == id {session.libraryFolderID = folder.parentID}
    for index in recentProjects.indices where recentProjects[index].folderID == id { recentProjects[index].folderID = folder.parentID }
    libraryOrder.removeAll {$0 == folder.libraryIdentifier}
    if recoveryEnabled {UserDefaults.standard.set(libraryOrder,forKey:"projectLibraryOrder")}
    persistProjectFolders(); persistRecentProjects()
  }
  func projectFolderTrail(_ id: UUID?) -> [ProjectFolder] {
    var result:[ProjectFolder] = [],current = id,seen = Set<UUID>()
    while let value = current,seen.insert(value).inserted,let folder = projectFolders.first(where:{$0.id == value}) {
      result.insert(folder,at:0);current = folder.parentID
    }
    return result
  }
  @discardableResult func moveStartPageLibraryItem(_ identifier:String,to parentID:UUID?) -> Bool {
    guard parentID == nil || projectFolders.contains(where:{$0.id == parentID}) else {return false}
    if identifier.hasPrefix("folder:") {
      guard let id = UUID(uuidString:String(identifier.dropFirst(7))),let index = projectFolders.firstIndex(where:{$0.id == id}),
        !projectFolderTrail(parentID).contains(where:{$0.id == id}) else {return false}
      projectFolders[index].parentID = parentID;persistProjectFolders();return true
    }
    let path = identifier.hasPrefix("path:") ? String(identifier.dropFirst(5)) : identifier
    guard sessions.contains(where:{$0.id.uuidString == identifier && !$0.isStartPage}) || recentProjects.contains(where:{$0.path == path}) else {return false}
    moveStartPageProjectToFolder(identifier,folderID:parentID);return true
  }
  func moveStartPageProjectToFolder(_ identifier: String, folderID: UUID?) {
    if let id = UUID(uuidString: identifier), let session = sessions.first(where: {$0.id == id}) {
      if let path = (session.url ?? session.sourceURL)?.standardizedFileURL.path { moveProjectToFolder(path, folderID: folderID) }
      session.libraryFolderID = folderID
    } else {moveProjectToFolder(identifier.hasPrefix("path:") ? String(identifier.dropFirst(5)) : identifier, folderID: folderID)}
  }
  func moveProjectToFolder(_ path: String, folderID: UUID?) {
    for session in sessions where (session.url ?? session.sourceURL)?.standardizedFileURL.path == path {session.libraryFolderID = folderID}
    guard let index = recentProjects.firstIndex(where: { $0.path == path }) else { return }
    recentProjects[index].folderID = folderID; persistRecentProjects()
  }
  func reorderProject(path: String, before targetPath: String) {
    guard path != targetPath,
      let source = recentProjects.firstIndex(where: { $0.path == path }),
      let target = recentProjects.firstIndex(where: { $0.path == targetPath }) else { return }
    let item = recentProjects.remove(at: source)
    let adjusted = target > source ? target - 1 : target
    recentProjects.insert(item, at: max(0, min(adjusted, recentProjects.count)))
    persistRecentProjects()
  }

  /// Reorders a project from the start-page library. Open tabs use their UUID
  /// as the drag identifier; saved projects use their canonical package path.
  /// Keeping this in the store makes the operation independent of the grid
  /// layout and prevents a drop on a compact card from being interpreted as a
  /// window drag.
  func reorderStartPageProject(identifier: String, before targetIdentifier: String, after: Bool = false) {
    guard identifier != targetIdentifier else { return }
    func key(_ value:String) -> String {
      if let id = UUID(uuidString:value),let session = sessions.first(where:{$0.id == id}) {
        return (session.url ?? session.sourceURL)?.standardizedFileURL.path ?? value
      }
      return value.hasPrefix("path:") ? String(value.dropFirst(5)) : value
    }
    let source = key(identifier),target = key(targetIdentifier)
    var order = libraryOrder
    for session in sessions where !session.isStartPage {
      let value = (session.url ?? session.sourceURL)?.standardizedFileURL.path ?? session.id.uuidString
      if !order.contains(value) {order.append(value)}
    }
    for item in recentProjects where !order.contains(item.path) {order.append(item.path)}
    for folder in projectFolders where !order.contains(folder.libraryIdentifier) {order.append(folder.libraryIdentifier)}
    order.removeAll {$0 == source}
    let insertion = order.firstIndex(of:target).map {$0 + (after ? 1 : 0)} ?? order.count
    order.insert(source,at:insertion)
    libraryOrder = order
    if recoveryEnabled {UserDefaults.standard.set(order,forKey:"projectLibraryOrder")}
    // Keep legacy order in sync for projects that are not currently opened.
    recentProjects.sort {(order.firstIndex(of:$0.path) ?? order.count)<(order.firstIndex(of:$1.path) ?? order.count)}
    persistRecentProjects()
  }

  func writeProject(_ session: ProjectSession, to url: URL) throws {
    try session.document.validate()
    let archive = ProjectArchive(document: session.document, undo: session.undo, redo: session.redo)
    try Self.writeSnapshot(archive,assets:session.assets.snapshot(),to:url)
  }
  nonisolated static func writeSnapshot(_ archive:ProjectArchive,assets:[String:Data],to url:URL) throws {
    let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    let json = try encoder.encode(archive)
    var files: [String: FileWrapper] = [:]
    for (id, data) in assets {
      files[id + ".asset"] = FileWrapper(regularFileWithContents: data)
    }
    let root = FileWrapper(directoryWithFileWrappers: [
      "document.json": FileWrapper(regularFileWithContents: json),
      "Assets": FileWrapper(directoryWithFileWrappers: files),
    ])
    try root.write(to: url, options: .atomic, originalContentsURL: nil)
  }
  func loadProject(_ url: URL) throws -> ProjectSession {
    let decoder = JSONDecoder()
    let data = try Data(contentsOf: url.appendingPathComponent("document.json"))
    guard data.count < 200_000_000 else { throw ImageProError.message("项目描述文件过大。") }
    let archive = try decoder.decode(ProjectArchive.self, from: data)
    guard archive.formatVersion == 1 else {
      throw ImageProError.message("此项目由较新版本创建，请升级 iMage Pro。")
    }
    try archive.document.validate()
    for step in archive.undo + archive.redo {
      try step.before.validate()
      try step.after.validate()
    }
    let library = AssetLibrary()
    let folder = url.appendingPathComponent("Assets")
    for asset in try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
    where asset.pathExtension == "asset" {
      guard UUID(uuidString: asset.deletingPathExtension().lastPathComponent) != nil,
        (try asset.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true
      else { throw ImageProError.message("项目资源路径无效。") }
      library.insert(
        try Data(contentsOf: asset), id: asset.deletingPathExtension().lastPathComponent)
    }
    let allDocuments =
      [archive.document] + (archive.undo + archive.redo).flatMap { [$0.before, $0.after] }
    for doc in allDocuments {
      for layer in doc.layers {
        for id in [layer.assetID, layer.maskAssetID].compactMap({ $0 }) {
          guard library.image(id) != nil else { throw ImageProError.message("项目缺少图像资源，或资源无法解码。") }
        }
      }
    }
    let session = ProjectSession(archive.document, assets: library)
    session.undo = Array(archive.undo.suffix(1000))
    session.redo = Array(archive.redo.suffix(1000))
    session.url = url
    session.savedDocument = session.document
    return session
  }
  func autosave() {
    guard recoveryEnabled, transaction == nil, !autosaving else { return }
    let folder = supportURL.appendingPathComponent("Recovery", isDirectory:true)
    let dirty = sessions.filter(\.dirty)
    let snapshots = dirty.filter {recoverySnapshots[$0.id] != $0.document}.map {session in
      (session.id,ProjectArchive(document:session.document,undo:session.undo,redo:session.redo),session.assets.snapshot())
    }
    let ids = dirty.map { $0.id.uuidString }
    guard !snapshots.isEmpty else {UserDefaults.standard.set(ids,forKey:"recoveryProjects");return}
    autosaving = true
    recoveryQueue.async { [weak self] in
      do {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for (id,archive,assets) in snapshots {try Self.writeSnapshot(archive,assets:assets,to:folder.appendingPathComponent(id.uuidString+".imgp"))}
        Task {@MainActor in
          guard let self else {return}
          for (id,archive,_) in snapshots {self.recoverySnapshots[id] = archive.document}
          if !self.terminationApproved {UserDefaults.standard.set(ids,forKey:"recoveryProjects")};self.autosaving = false
        }
      } catch {
        Task {@MainActor in self?.autosaving = false;self?.notify(Self.recoveryFailureMessage(error),warning:true)}
      }
    }
  }
  static func recoveryFailureMessage(_ error: Error) -> String {
    let failure = error as NSError
    if (failure.domain == NSCocoaErrorDomain && failure.code == NSFileWriteOutOfSpaceError)
      || (failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOSPC)) {
      return "空间不足，自动恢复未保存。"
    }
    if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? Error {
      return recoveryFailureMessage(underlying)
    }
    return "自动恢复未保存，请手动保存项目。"
  }
  func restoreAutosaves() {
    let ids = UserDefaults.standard.stringArray(forKey: "recoveryProjects") ?? []
    var recovered = 0
    for id in ids {
      let url = supportURL.appendingPathComponent("Recovery/\(id).imgp")
      if let session = try? loadProject(url) {
        session.url = nil
        session.savedDocument = nil
        sessions.append(session)
        session.thumbnail = Self.tabThumbnail(renderer.render(session.document, assets: session.assets, maxDimension: 96))
        recovered += 1
      }
    }
    if recovered > 0 {
      renderNow()
      notify("已恢复 \(recovered) 个未保存的项目")
    }
  }
  @discardableResult
  func closeProject(_ id: UUID) -> Bool {
    guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
    let previous = activeID
    let session = sessions[index]
    if session.dirty {
      activate(id)
      guard confirmDiscard() else {
        if let previous { activate(previous) }
        return false
      }
    }
    if sessions.count == 1 {
      // Keep the model valid while replacing the last closed tab.
      newStartPage()
    }
    sessions.removeAll { $0.id == id }
    if let previous, previous != id, sessions.contains(where: { $0.id == previous }) {
      activate(previous)
    } else {
      activate(sessions[min(index, sessions.count - 1)].id)
    }
    autosave()
    return true
  }

  func closeOtherProjects(keeping id: UUID, toRightOnly: Bool = false) {
    guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
    let targets = toRightOnly ? Array(sessions.dropFirst(index + 1)) : sessions.filter { $0.id != id }
    for session in targets {
      if !closeProject(session.id) { break }
    }
  }
  func confirmDiscard() -> Bool {
    let alert = NSAlert()
    alert.messageText = L("保存“{0}”的更改？", document.name)
    alert.informativeText = L("保存后可以继续修改图层、效果和历史记录。")
    alert.addButton(withTitle: "保存")
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "不保存")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return save()
    case .alertThirdButtonReturn: return true
    default: return false
    }
  }
  func canQuit() -> Bool {
    if terminationApproved { return true }
    endTransaction()
    for session in sessions where session.dirty {
      activate(session.id)
      if !confirmDiscard() { return false }
    }
    if recoveryEnabled { UserDefaults.standard.removeObject(forKey: "recoveryProjects") }
    terminationApproved = true
    return true
  }
  func export(format: ExportFormat, width: Double, quality: Double, transparency: Bool) {
    if transformActive { finishTransform() }
    let aspect = document.height / document.width
    let outputWidth = max(1, min(16384, width.rounded()))
    let outputHeight = (outputWidth * aspect).rounded()
    guard outputWidth * outputHeight <= 100_000_000, outputHeight <= 16384 else {
      fail(ImageProError.message("导出尺寸过大，请缩小尺寸。"))
      return
    }
    let panel = NSSavePanel()
    panel.title = L("导出")
    panel.prompt = L("导出")
    panel.nameFieldStringValue = document.name + "." + format.ext
    panel.allowedContentTypes = [UTType(filenameExtension: format.ext) ?? .data]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      if format.ext == "psd" {
        let archive = ProjectArchive(document: document, undo: active.undo, redo: active.redo)
        try PSDCodec.write(
          document: document, assets: active.assets, renderer: renderer, archive: archive
        ).write(to: url, options: .atomic)
        sheet = nil
        notify("已导出分层 PSD：" + url.lastPathComponent)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return
      }
      guard
        let original = renderer.render(
          document, assets: active.assets, maxDimension: nil,
          whiteBackground: !transparency || format.ext == "jpg")
      else { throw ImageProError.message("无法分配导出所需的图像内存。") }
      let input = CIImage(cgImage: original)
      let scaled = input.applyingFilter(
        "CILanczosScaleTransform",
        parameters: [
          kCIInputScaleKey: outputWidth / Double(original.width), kCIInputAspectRatioKey: 1,
        ])
      guard
        let image = renderer.context.createCGImage(
          scaled, from: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight),
          format: .RGBA8, colorSpace: ImageRenderer.colorSpace)
      else { throw ImageProError.message("导出渲染失败。") }
      if format.ext == "pdf" {
        let data = NSMutableData()
        var media = CGRect(
          x: 0, y: 0, width: outputWidth * 72 / document.dpi,
          height: outputHeight * 72 / document.dpi)
        guard let consumer = CGDataConsumer(data: data),
          let pdf = CGContext(consumer: consumer, mediaBox: &media, nil)
        else { throw ImageProError.message("PDF 编码失败。") }
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: media)
        pdf.endPDFPage()
        pdf.closePDF()
        try (data as Data).write(to: url, options: .atomic)
      } else if format.ext == "svg" {
        let png = try AssetLibrary.encode(image, type: UTType.png.identifier).base64EncodedString()
        let svg =
          "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(outputWidth))\" height=\"\(Int(outputHeight))\" viewBox=\"0 0 \(Int(outputWidth)) \(Int(outputHeight))\"><image width=\"100%\" height=\"100%\" href=\"data:image/png;base64,\(png)\"/></svg>"
        try svg.write(to: url, atomically: true, encoding: .utf8)
      } else {
        try AssetLibrary.encode(image, type: format.identifier, quality: quality, dpi: document.dpi)
          .write(to: url, options: .atomic)
      }
      sheet = nil
      notify("已导出：\(url.lastPathComponent)")
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch { fail(error) }
  }
  func maskFromSelection() {
    guard let selection, let layer = selected, !layer.locked else {
      notify("先创建选区，再为未锁定的图层添加蒙版")
      return
    }
    do {
      let local = localSelection(selection, layer: layer)
      guard
        let image = SelectionEngine.mask(
          local, size: CGSize(width: layer.width, height: layer.height), maxSize: 4096)
      else { return }
      let id = try active.assets.insert(image)
      updateSelected("添加选区蒙版") {
        $0.maskAssetID = id
        $0.maskEnabled = true
        $0.resetMaskParameters()
      }
      self.selection = nil
    } catch { fail(error) }
  }
  func extractSubject() {
    guard !busy, let layer = selected, layer.kind != .group,
      let image = renderer.renderLayer(
        layer, assets: active.assets, scale: min(1, 2048 / max(layer.width, layer.height)))
    else {
      notify("请先选择一个图像图层")
      return
    }
    let projectID = active.id
    let layerID = layer.id
    busy = true
    notify("正在本机识别主体…")
    Task.detached(priority: .userInitiated) {
      do {
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
          throw ImageProError.message("没有检测到清晰的前景主体。可以用套索或选框创建蒙版。")
        }
        let buffer = try observation.generateScaledMaskForImage(
          forInstances: observation.allInstances, from: handler)
        let ci = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let mask = context.createCGImage(ci, from: ci.extent) else {
          throw ImageProError.message("主体蒙版生成失败。")
        }
        let bytes = try AssetLibrary.encode(mask, type: UTType.png.identifier)
        await MainActor.run {
          self.busy = false
          guard self.activeID == projectID, self.selected?.id == layerID, self.selected == layer
          else {
            self.notify("当前对象已改变，请重新执行主体识别")
            return
          }
          let id = self.active.assets.insert(bytes)
          self.updateSelected("智能提取主体") {
            $0.maskAssetID = id
            $0.maskEnabled = true
          }
          self.sheet = nil
          self.showLayers = true
          self.notify("主体已提取。原图保留，可随时停用蒙版。")
        }
      } catch {
        await MainActor.run {
          self.busy = false
          self.fail(error)
        }
      }
    }
  }
  func installExtension() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.title = L("添加效果扩展")
    panel.prompt = L("添加")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf: url)
      guard data.count < 100_000 else { throw ImageProError.message("扩展描述文件过大。") }
      let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
      guard manifest.capability == "effect",
        ExtensionManifest.allowedFilters.contains(manifest.coreImageFilter), !manifest.name.isEmpty
      else {
        throw ImageProError.message("首版扩展支持声明受支持的 Core Image 效果；这个扩展的能力尚不支持。")
      }
      extensions.removeAll { $0.id == manifest.id }
      extensions.append(manifest)
      persistExtensions()
      notify("\(manifest.name) 已加入效果器")
    } catch { fail(error) }
  }
  func removeExtension(_ id: String) {
    extensions.removeAll { $0.id == id }
    persistExtensions()
  }
  func persistExtensions() {
    if let bytes = try? JSONEncoder().encode(extensions) {
      UserDefaults.standard.set(bytes, forKey: "extensions")
    }
  }
}
