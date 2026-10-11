import AppKit
import SwiftUI

@main
struct ImageProApp: App {
  @NSApplicationDelegateAdaptor(ImageProDelegate.self) var delegate
  @StateObject private var store = EditorStore()
  var body: some Scene {
    Window("iMage Pro", id: "editor") {
      EditorWindowContent(store: store, delegate: delegate)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
    }
    // The content reaches the titlebar so the native traffic lights and the
    // Liquid Glass command row occupy one visual line, as in the reference
    // design. The traffic-light controls themselves remain AppKit-owned.
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1440, height: 920)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button(L("新建项目…")) { store.newStartPage() }.keyboardShortcut("n")
        Button(L("打开…")) { store.openPanel() }.keyboardShortcut("o")
      }
      CommandGroup(replacing: .saveItem) {
        Button(L("保存项目")) { store.save() }.keyboardShortcut("s")
        Button(L("另存为…")) { store.save(as: true) }.keyboardShortcut(
          "s", modifiers: [.command, .shift])
        Button(L("导出…")) { store.sheet = "export" }.keyboardShortcut(
          "e", modifiers: [.command, .shift])
      }
      CommandGroup(replacing: .undoRedo) {
        Button(L(store.undoLabel)) { store.undo() }.keyboardShortcut("z").disabled(
          !store.canUndo)
        Button(L(store.redoLabel)) { store.redo() }.keyboardShortcut(
          "z", modifiers: [.command, .shift]
        ).disabled(!store.canRedo)
      }
      CommandGroup(replacing: .appSettings) {
        Button(L("设置…")) { store.sheet = "settings" }.keyboardShortcut(",")
      }
      CommandGroup(replacing: .appInfo) { Button(L("关于 iMage Pro")) { store.sheet = "about" } }
      CommandGroup(replacing: .help) { Button(L("iMage Pro 使用指南")) { store.sheet = "help" } }
      CommandGroup(replacing:.pasteboard) {
        Button(L("剪切")) {NSApp.sendAction(#selector(NSText.cut(_:)),to:nil,from:nil)}.keyboardShortcut("x")
        Button(L("复制")) {
          if NSApp.keyWindow?.firstResponder is NSTextView {NSApp.sendAction(#selector(NSText.copy(_:)),to:nil,from:nil)} else {store.copySelectedLayer()}
        }.keyboardShortcut("c")
        Button(L("粘贴")) {
          if NSApp.keyWindow?.firstResponder is NSTextView {NSApp.sendAction(#selector(NSText.paste(_:)),to:nil,from:nil)} else {store.pasteLayer()}
        }.keyboardShortcut("v")
        Divider()
        Button(L("自由变换")) { store.beginTransform() }.keyboardShortcut("t")
        Button(L("选区内容到新图层")) { store.extractSelection() }.keyboardShortcut("j")
        Button(L("剪切选区到新图层")) {store.extractSelection(cut:true)}.keyboardShortcut("j",modifiers:[.command,.shift])
        Button(L("全选")) {store.selectAll()}.keyboardShortcut("a")
        Button(L("编组")) {store.groupSelected()}.keyboardShortcut("g").disabled(store.selectedIDs.count < 2)
        Button(L("取消编组")) {if let id = store.selected?.id {store.ungroup(id)}}.keyboardShortcut("g",modifiers:[.command,.shift]).disabled(store.selected?.kind != .group)
        Button(L("建立 / 释放剪切蒙版")) {if let id = store.selected?.id {store.toggleClippingMask(id)}}.keyboardShortcut("g",modifiers:[.command,.option])
        Button(L("图层上移")) {store.reorderSelected(up:true)}.keyboardShortcut("]")
        Button(L("图层下移")) {store.reorderSelected(up:false)}.keyboardShortcut("[")
        Button(L("图层置顶")) {store.reorderSelected(up:true,edge:true)}.keyboardShortcut("]",modifiers:[.command,.shift])
        Button(L("图层置底")) {store.reorderSelected(up:false,edge:true)}.keyboardShortcut("[",modifiers:[.command,.shift])
        Button(L("路径转选区")) {store.pathToSelection()}.keyboardShortcut(.return,modifiers:[.command,.shift])
        Button(L("画笔描边路径")) {store.strokePath()}
        Button(L("取消选区")) { store.deselect() }.keyboardShortcut("d")
        Button(L("反选")) { store.invertSelection() }.keyboardShortcut(
          "i", modifiers: [.command, .shift])
      }
      CommandMenu(L("工具")) {
        Button(L("液化推移")) {store.chooseTool(.retouch,branch:ToolCategory.retouch.branches.first {$0.id == "liquify"})}.keyboardShortcut("x",modifiers:[.command,.shift])
        Divider()
        ForEach(ShortcutCatalog.tools,id:\.key) {shortcut in
          Button(L(shortcut.title)+"   "+shortcut.key.uppercased()) {store.selectToolShortcut(shortcut.key)}
        }.id(AppLocalization.language)
      }
      CommandMenu(L("效果器")) {
        ForEach(EffectCatalog.groups,id:\.0) {group in
          Menu(L(group.0)) {ForEach(group.1,id:\.self) {kind in Button(L(kind.title)) {store.addEffect(kind)}}.id(AppLocalization.language)}
        }.id(AppLocalization.language)
      }
      CommandGroup(after: .toolbar) {
        Button(L("放大画布")) { store.zoomCanvas(1.2) }.keyboardShortcut("+")
        Button(L("缩小画布")) { store.zoomCanvas(1 / 1.2) }.keyboardShortcut("-")
        Button(L("适合窗口")) { store.fitCanvas() }.keyboardShortcut("0")
        Button(L("实际像素")) {store.actualPixels()}.keyboardShortcut("1")
        Button(L("图层管理器")) { store.showLayers.toggle() }.keyboardShortcut(
          "l", modifiers: [.command, .option])
        Button(L("上下文调节器")) { store.showInspector.toggle() }.keyboardShortcut(
          "i", modifiers: [.command, .option])
      }
    }
  }
}

private struct EditorWindowContent: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  let delegate: ImageProDelegate
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    WorkspaceView(store: store).frame(minWidth: 1100, minHeight: 720)
      .onAppear {
        delegate.reopenEditor = { openWindow(id: "editor") }
        delegate.store = store
        NativeMenuLocalization.shared.install()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
      }
  }
}

final class ImageProDelegate: NSObject, NSApplicationDelegate {
  private var pendingFiles: [String] = []
  var reopenEditor: (() -> Void)?
  weak var store: EditorStore? {
    didSet {
      guard store != nil, !pendingFiles.isEmpty else { return }
      let files = pendingFiles
      pendingFiles.removeAll()
      Task { @MainActor in for file in files { store?.open(URL(fileURLWithPath: file)) } }
    }
  }
  // Keep the process alive while LaunchServices delivers a document-open
  // event. With the SwiftUI Window scene there can be a short interval during
  // launch where no NSWindow has been materialized yet; returning true here
  // lets AppKit terminate the app before `openFiles` reaches the store.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    reopenEditor?()
    return true
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    MainActor.assumeIsolated { (store?.canQuit() ?? true) ? .terminateNow : .terminateCancel }
  }
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    handleOpen(filenames, in: sender)
  }

  // Finder and LaunchServices use different delegate entry points depending
  // on whether the document UTI is treated as a package or a file. Support
  // both paths so double-clicking an `.imgp` package behaves the same as
  // opening it from the in-app panel.
  func application(_ application: NSApplication, open urls: [URL]) {
    handleOpen(urls.map(\.path), in: application)
  }

  func application(_ application: NSApplication, openFile filename: String) -> Bool {
    handleOpen([filename], in: application)
    return true
  }

  private func handleOpen(_ filenames: [String], in sender: NSApplication) {
    sender.activate(ignoringOtherApps: true)
    reopenEditor?()
    if store == nil {
      pendingFiles.append(contentsOf: filenames)
      sender.reply(toOpenOrPrint: .success)
      return
    }
    Task { @MainActor in
      for file in filenames { store?.open(URL(fileURLWithPath: file)) }
      sender.reply(toOpenOrPrint: .success)
    }
  }

}

struct WindowBridge: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  func makeCoordinator() -> Coordinator { Coordinator(store) }
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    configure(view, coordinator: context.coordinator)
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {
    configure(view, coordinator: context.coordinator)
  }
  private func configure(_ view: NSView, coordinator: Coordinator) {
    DispatchQueue.main.async {
      guard let window = view.window else { return }
      coordinator.observeFocus(in:window)
      // Full-size content still overlaps AppKit's native titlebar. Disabling
      // background dragging alone doesn't stop that titlebar claiming a drag.
      WindowTitlebarDragArea.restrictDragging(window)
      // Keep the system-defined NSWindow frame, titlebar, corner radius, and
      // standardWindowButton semantics. No content layer is used to imitate them.
      if window.delegate !== coordinator {
        // Only the explicit empty titlebar drag regions move the window.
        // Background dragging competes with custom tab mouse tracking.
        window.isMovableByWindowBackground = false
        window.delegate = coordinator
        window.minSize = NSSize(width: 1100, height: 720)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .windowBackgroundColor
        // The command row owns the visible traffic lights. Leaving AppKit's
        // buttons in the titlebar while reparenting the content would make
        // macOS 26 draw a blue unified window glyph over the row.
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
          window.standardWindowButton(type)?.isHidden = true
        }
      }
      let title = store.active.isStartPage ? L("启动页") : store.document.name
      if window.title != title { window.title = title }
    }
  }
  final class Coordinator: NSObject, NSWindowDelegate {
    weak var store: EditorStore?
    var closingApproved = false
    private weak var focusWindow: NSWindow?
    private var focusMonitor: Any?
    init(_ store: EditorStore) { self.store = store }
    deinit {if let focusMonitor {NSEvent.removeMonitor(focusMonitor)}}
    func observeFocus(in window:NSWindow) {
      guard focusWindow !== window else {return}
      if let focusMonitor {NSEvent.removeMonitor(focusMonitor)}
      focusWindow = window
      focusMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] event in
        guard let window = self?.focusWindow,event.window === window else {return event}
        FieldFocus.dismiss(in:window,at:event.locationInWindow)
        return event
      }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      MainActor.assumeIsolated {
        guard let store else { return true }
        let allowed = store.canQuit()
        closingApproved = allowed
        return allowed
      }
    }
  }
}

enum FieldFocus {
  static func dismiss(in window:NSWindow,at point:NSPoint) {
    let owner:NSView?
    if let field = window.firstResponder as? ScrubTextField {owner = field}
    else if let editor = window.firstResponder as? NSTextView,editor.isFieldEditor {
      owner = editor.delegate as? NSView
      if editor.bounds.contains(editor.convert(point,from:nil)) {return}
    } else {return}
    if let owner,owner.bounds.contains(owner.convert(point,from:nil)) {return}
    window.makeFirstResponder(nil)
  }
}

/// Embed AppKit's actual window buttons in the command row. The holder shares
/// the row's height, so resizing and appearance changes preserve its centerline.
struct NativeWindowControls: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  func makeNSView(context: Context) -> ControlHolder { ControlHolder() }
  func updateNSView(_ view: ControlHolder, context: Context) { view.installButtons() }

  final class ControlHolder: NSView {
    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var aligning = false
    private var pendingAlignment = false
    private let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      installButtons()
    }

    func installButtons() {
      guard let window else { return }
      if observedWindow !== window {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observedWindow = window
        for name in [NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
                     NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
          observe(name, object: window)
        }
        // AppKit can rewrite the standard buttons' frames while showing sheets,
        // even when the SwiftUI holder itself never receives another layout pass.
        for type in buttonTypes {
          if let button = window.standardWindowButton(type) {
            button.postsFrameChangedNotifications = true
            observe(NSView.frameDidChangeNotification, object: button)
          }
        }
        postsFrameChangedNotifications = true
        observe(NSView.frameDidChangeNotification, object: self)
      }
      alignButtons()
    }

    private func observe(_ name: Notification.Name, object: AnyObject) {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
        [weak self] _ in
        guard let self, !self.aligning else { return }
        self.alignButtons()
        // Reassert after the entire system titlebar/sheet layout transaction.
        guard !self.pendingAlignment else { return }
        self.pendingAlignment = true
        DispatchQueue.main.async { [weak self] in
          self?.pendingAlignment = false
          self?.alignButtons()
        }
      })
    }

    private func alignButtons() {
      guard !aligning, let window else { return }
      aligning = true
      defer { aligning = false }
      for (index, type) in buttonTypes.enumerated() {
        guard let button = window.standardWindowButton(type) else { continue }
        if button.superview !== self { addSubview(button) }
        button.isHidden = window.styleMask.contains(.fullScreen)
        let origin = NSPoint(x: CGFloat(index) * 22,
                             y: (bounds.height - button.frame.height) / 2)
        if button.frame.origin != origin { button.setFrameOrigin(origin) }
      }
    }

    override func layout() {
      super.layout()
      alignButtons()
    }
  }
}

/// Empty space in the attached toolbar drags the real window rather than
/// forwarding mouse events to the editing canvas underneath it.
struct WindowTitlebarDragArea: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  static func restrictDragging(_ window: NSWindow) {
    window.isMovable = false
    window.isMovableByWindowBackground = false
  }
  func makeNSView(context: Context) -> DragView { DragView() }
  func updateNSView(_ view: DragView, context: Context) {}

  final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
      guard let window else { return }
      window.isMovable = true
      defer { WindowTitlebarDragArea.restrictDragging(window) }
      window.performDrag(with: event)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  }
}
