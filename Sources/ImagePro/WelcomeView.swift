import AppKit
import SwiftUI

struct WelcomeView: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  @State private var category = PresetCategory.featured
  @State private var search = ""
  @State private var draft = CanvasDraft()
  @State private var draftNameEdited = false
  @State private var background = CanvasBackground.transparent
  @State private var backgroundColor = Color.white
  @State private var portraitPreference = false
  @State private var renamingHistory: StartPageHistoryItem?
  @State private var historyName = ""
  @State private var renamingFolder: ProjectFolder?
  @State private var openFolder: UUID?
  @State private var draggingProject: String?
  @State private var dropProject: String?
  @State private var dropAfter = false
  @State private var dropIntoFolder = false
  @State private var selectedLibraryItem:String?

  private var presets: [CanvasPreset] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return CanvasPreset.all.filter {
      if !query.isEmpty {
        return (L($0.name) + " " + $0.name + " " + $0.dimensions + " " + L($0.category.rawValue))
          .localizedCaseInsensitiveContains(query)
      }
      return category == .featured ? $0.featured : $0.category == category
    }
  }
  private var allHistory: [StartPageHistoryItem] {
    let open = store.sessions.filter { !$0.isStartPage && !store.hiddenHistorySessions.contains($0.id) }.map { session in
      StartPageHistoryItem(id: session.id.uuidString, name: session.document.name,
        width: session.document.width, height: session.document.height,
        date: session.lastActivated, sessionID: session.id,
        url: session.url ?? session.sourceURL, image: session.thumbnail,
        detail: session.dirty ? "未保存的更改" : "已打开", folderID: session.libraryFolderID ?? store.recentProjects.first(where: {$0.path == (session.url ?? session.sourceURL)?.standardizedFileURL.path})?.folderID)
    }
    let openedPaths = Set(store.sessions.compactMap { ($0.url ?? $0.sourceURL)?.standardizedFileURL.path })
    let saved = store.recentProjects.filter { !openedPaths.contains($0.path) }.map { entry in
      StartPageHistoryItem(id: entry.path, name: entry.name, width: entry.width,
        height: entry.height, date: entry.lastOpened, url: entry.url,
        image: entry.thumbnail.flatMap { NSImage(data: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) },
        detail: entry.lastOpened.formatted(.dateTime.month().day()), folderID: entry.folderID)
    }
    // Preserve the project library order. Manual drag sorting must not be
    // undone by a date sort every time the start page recomputes.
    let order = store.libraryOrder
    let all = (open + saved).enumerated().sorted {a,b in
      func rank(_ item:StartPageHistoryItem,_ fallback:Int)->Int {order.firstIndex(of:item.url?.standardizedFileURL.path ?? item.id) ?? order.count+fallback}
      return rank(a.element,a.offset)<rank(b.element,b.offset)
    }.map(\.element)
    return all
  }

  private var history: [StartPageHistoryItem] {allHistory.filter {$0.folderID == openFolder}}
  private var libraryItems: [StartPageLibraryItem] {
    let entries = store.projectFolders.filter {$0.parentID == openFolder}.map {StartPageLibraryItem.folder($0)}
      + history.map {StartPageLibraryItem.project($0)}
    return entries.enumerated().sorted {a,b in
      let order = store.libraryOrder
      return (order.firstIndex(of:a.element.orderKey) ?? order.count+a.offset)
        < (order.firstIndex(of:b.element.orderKey) ?? order.count+b.offset)
    }.map(\.element)
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 30) {
          header
          if geometry.size.width >= 1000 {
            HStack(alignment: .top, spacing: 32) {
              library.frame(maxWidth: .infinity)
              customCanvas.frame(width: 330)
            }
          } else {
            library
            customCanvas
          }
        }.frame(maxWidth: 1250, alignment: .leading)
          .padding(.horizontal, geometry.size.width < 1200 ? 32 : 48)
          .padding(.top, 32).padding(.bottom, 40)
          .frame(maxWidth: .infinity)
      }
      .scrollContentBackground(.hidden)
      // Native overlay indicators preserve the page width when scrolling begins.
      .pageScrollStyle(.vertical)
      .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: 0) }
    }
    .onChange(of: store.language) { _, _ in
      if !draftNameEdited { draft.name = L("未命名") }
    }
    .alert(L("重命名项目"), isPresented: Binding(
      get: { renamingHistory != nil }, set: { if !$0 { renamingHistory = nil } })) {
      TextField(L("项目名称"), text: $historyName)
      Button(L("取消"), role: .cancel) { renamingHistory = nil }
      Button(L("重命名")) {
        if let item = renamingHistory {
          store.renameHistoryProject(sessionID: item.sessionID, url: item.url, to: historyName)
        }
        renamingHistory = nil
      }.disabled(historyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } message: {
      if let item = renamingHistory, item.sessionID == nil,
        let url = item.url, url.pathExtension.lowercased() != "imgp" {
        Text(L("原始图像文件也会同步重命名。"))
      }
    }
    .alert(L("重命名文件夹"), isPresented: Binding(
      get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
      TextField(L("文件夹名称"), text: $historyName)
      Button(L("取消"), role: .cancel) { renamingFolder = nil }
      Button(L("重命名")) {
        if let folder = renamingFolder { store.renameProjectFolder(folder.id, to: historyName) }
        renamingFolder = nil
      }.disabled(historyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text(L("开始创作")).font(.system(size: 30, weight: .semibold))
        Text(L("从合适的画布开始，或继续上次的作品。"))
          .font(.system(size: 14)).foregroundStyle(.secondary)
      }
      Spacer()
      Button { store.openPanel() } label: {
        Label(L("打开项目或图像…"), systemImage: "folder")
      }.controlSize(.large).buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .tint(.primary).foregroundStyle(.primary)
        .help(L("打开已有项目或图像（⌘O）"))
    }
  }

  private var library: some View {
    VStack(alignment: .leading, spacing: 28) {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text(L("常用尺寸")).font(.system(size: 18, weight: .semibold))
          Text(L("{0} 种", CanvasPreset.all.count)).font(.system(size: 12)).foregroundStyle(.secondary)
          Spacer()
          TextField(L("搜索尺寸"), text: $search).textFieldStyle(.plain)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 150).accessibilityLabel(L("搜索常用尺寸"))
        }
        Picker(L("尺寸分类"), selection: $category) {
          ForEach(PresetCategory.allCases) { Text(L($0.rawValue)).tag($0) }.id(AppLocalization.language)
        }.id(AppLocalization.language).pickerStyle(.segmented).labelsHidden()
        if presets.isEmpty {
          Text(L("没有匹配的尺寸。可以在右侧设置自定义画布。"))
            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 32)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
            ForEach(presets) { preset in
              CanvasPresetButton(preset: preset) {
                store.newProject(width: preset.width, height: preset.height, dpi: preset.dpi,
                  background: [.print, .photo].contains(preset.category) ? RGBA(r: 1, g: 1, b: 1) : nil)
              }.contextMenu {
                Button(L("载入自定义画布")) { load(preset) }
              }
            }.id(AppLocalization.language)
          }
        }
        Text(L(category == .social
          ? "社交尺寸为常用推荐值，发布前请确认平台的最新要求。"
          : "尺寸以像素表示。右键预设可载入自定义画布。"))
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Divider()
      projectManager
    }
  }

  private var projectManager: some View {
    VStack(alignment:.leading,spacing:18) {
      HStack(spacing:8) {
        ScrollView(.horizontal) {
        HStack(spacing:8) {
        breadcrumb("项目",folderID:nil)
        ForEach(store.projectFolderTrail(openFolder)) {folder in
          Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary)
          breadcrumb(folder.name,folderID:folder.id)
        }.id(AppLocalization.language)
        }
        }.scrollIndicators(.hidden)
        Spacer(minLength:8)
        Button {store.createProjectFolder(parentID:openFolder)} label: {Label(L("新建文件夹"),systemImage:"folder.badge.plus")}
          .buttonStyle(.borderless).font(.system(size:12))
      }
      if libraryItems.isEmpty {
        VStack(spacing:8) {
          Image(systemName:"square.grid.2x2").font(.system(size:24)).foregroundStyle(.secondary)
          Text(L(openFolder == nil ? "还没有项目" : "文件夹为空")).font(.system(size:13,weight:.medium))
          Text(L(openFolder == nil ? "打开或保存作品，也可以新建文件夹整理。" : "拖入项目或文件夹，或在这里新建文件夹。"))
            .font(.system(size:12)).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity).padding(.vertical,28)
          .background(LayerDropSurface(priority:0,drop:{moveDraggedItem(to:openFolder)}))
      } else {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:120,maximum:160),spacing:16)],alignment:.leading,spacing:18) {
          ForEach(libraryItems) {entry in
            libraryTile(entry)
          }.id(AppLocalization.language)
        }
      }
      Text(L("双击打开 · 拖到文件夹中归类 · 拖到项目两侧调整顺序"))
        .font(.system(size:11)).foregroundStyle(.secondary)
    }
  }
  private func breadcrumb(_ title:String,folderID:UUID?) -> some View {
    Button {openFolder = folderID;selectedLibraryItem = nil} label: {
      Text(verbatim: folderID == nil ? L("项目") : title).font(.system(size:folderID == openFolder ? 18 : 13,weight:folderID == openFolder ? .semibold : .medium))
        .foregroundStyle(folderID == openFolder ? .primary : .secondary).lineLimit(1)
        .padding(.vertical,5).contentShape(Rectangle())
    }.buttonStyle(.plain).help(L(folderID == nil ? "返回所有项目；拖到这里移出文件夹" : "打开此文件夹；拖到这里移动"))
      .background(LayerDropSurface(priority:3,drop:{moveDraggedItem(to:folderID)}))
      .onDrop(of:[.text],isTargeted:nil) {providers in receiveLibraryDrop(providers,to:folderID)}
  }
  @ViewBuilder private func libraryTile(_ entry:StartPageLibraryItem) -> some View {
    Group {
      switch entry {
      case .folder(let folder):
        StartPageFolderButton(name:folder.name,count:allHistory.filter {$0.folderID == folder.id}.count + store.projectFolders.filter {$0.parentID == folder.id}.count,
          selected:selectedLibraryItem == entry.id,targeted:dropProject == entry.id && dropIntoFolder && draggingProject != nil) {selectLibraryItem(entry)}
      case .project(let item):
        StartPageHistoryButton(item:item,selected:selectedLibraryItem == entry.id) {selectLibraryItem(entry)}
      }
    }
    .overlay(LayerDragSurface(id:entry.nativeID,name:entry.name,begin:{draggingProject = entry.id;dropProject = nil;dropIntoFolder = false},
      select:{selectLibraryItem(entry)},cancel:{clearLibraryDrag()},preview:entry.preview,
      accessibilityPrefix:"打开或拖动：",exposesAccessibility:false))
    .background(LayerDropSurface(priority:1,hover:{point in
      guard let source = draggingProject,source != entry.id else {return}
      dropProject = entry.id;dropAfter = point.x > 0.5
      dropIntoFolder = entry.folderID != nil && point.x > 0.22 && point.x < 0.78 && point.y > 0.15 && point.y < 0.85
    },drop:{
      guard let source = draggingProject,source != entry.id else {clearLibraryDrag();return}
      if dropIntoFolder,let folderID = entry.folderID { _ = store.moveStartPageLibraryItem(source,to:folderID) }
      else if store.moveStartPageLibraryItem(source,to:openFolder) {
        withAnimation(.easeInOut(duration:0.18)) {store.reorderStartPageProject(identifier:source,before:entry.id,after:dropAfter)}
      }
      clearLibraryDrag()
    }))
    .overlay(alignment:dropAfter ? .trailing : .leading) {
      if draggingProject != nil,dropProject == entry.id,!dropIntoFolder {
        Capsule().fill(.primary.opacity(0.6)).frame(width:2).padding(.vertical,8).allowsHitTesting(false)
      }
    }
    .onDrop(of:[.text],isTargeted:nil) {providers in receiveLibraryDrop(providers,to:entry.folderID ?? openFolder)}
    .contextMenu {
      switch entry {
      case .folder(let folder):
        Button(L("打开")) {openFolder = folder.id}
        Button(L("重命名…")) {historyName = folder.name;renamingFolder = folder}
        moveDestinationMenu(entry.id)
        Divider()
        Button(L("移除文件夹，保留内容"),role:.destructive) {
          store.deleteProjectFolder(folder.id)
          if openFolder == folder.id {openFolder = folder.parentID}
        }
      case .project(let item):
        projectContextMenu(item)
      }
    }
  }
  private func openLibraryItem(_ entry:StartPageLibraryItem) {
    selectedLibraryItem = nil
    switch entry {case .folder(let folder):openFolder = folder.id;case .project(let item):openHistory(item)}
  }
  private func selectLibraryItem(_ entry:StartPageLibraryItem) {
    selectedLibraryItem = entry.id
    if (NSApp.currentEvent?.clickCount ?? 0) >= 2 {openLibraryItem(entry)}
  }
  private func clearLibraryDrag() {draggingProject = nil;dropProject = nil;dropIntoFolder = false}
  private func moveDraggedItem(to folderID:UUID?) {
    if let source = draggingProject {_ = store.moveStartPageLibraryItem(source,to:folderID)}
    clearLibraryDrag()
  }
  private func receiveLibraryDrop(_ providers:[NSItemProvider],to folderID:UUID?) -> Bool {
    guard let provider = providers.first else {return false}
    provider.loadObject(ofClass:NSString.self) {object,_ in
      guard let identifier = object as? String else {return}
      DispatchQueue.main.async {_ = store.moveStartPageLibraryItem(identifier,to:folderID)}
    }
    return true
  }
  private func moveDestinationMenu(_ identifier:String) -> some View {
    Menu(L("移动到")) {
      Button(L("项目")) {_ = store.moveStartPageLibraryItem(identifier,to:nil)}
      ForEach(store.projectFolders.filter {folder in !store.projectFolderTrail(folder.id).contains(where:{$0.libraryIdentifier == identifier})}) {folder in
        Button(store.projectFolderTrail(folder.id).map(\.name).joined(separator:" / ")) {
          _ = store.moveStartPageLibraryItem(identifier,to:folder.id)
        }
      }.id(AppLocalization.language)
    }
  }
  @ViewBuilder private func projectContextMenu(_ item:StartPageHistoryItem) -> some View {
    if item.available {
      Button(L("打开项目")) {openHistory(item)}
      Button(L("重命名…")) {historyName = item.name;renamingHistory = item}
      if let id = item.sessionID {Button(L("复制项目")) {store.duplicateProject(id)}}
      moveDestinationMenu(item.dragIdentifier)
      Divider()
    }
    if let url = item.url {
      if item.available {Button(L("在 Finder 中显示")) {NSWorkspace.shared.activateFileViewerSelecting([url])}}
      Button(L("复制路径")) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(url.path,forType:.string)}
      Divider()
    }
    Button(L("从项目列表移除")) {store.removeHistoryProject(sessionID:item.sessionID,url:item.url)}
    if let id = item.sessionID {Button(L("关闭项目")) {store.closeProject(id)}}
    else if item.available,let url = item.url {Button(L("移到废纸篓"),role:.destructive) {store.trashHistoryProject(url)}}
  }

  private var createProjectButton: some View {
    Button(L("创建项目")) { create() }.buttonStyle(.borderedProminent)
      .disabled(draft.validationMessage != nil).controlSize(.large)
  }

  private var customCanvas: some View {
    VStack(alignment: .leading, spacing: 16) {
      ViewThatFits(in: .horizontal) {
        HStack {
          Text(L("自定义画布")).font(.system(size: 18, weight: .semibold)).fixedSize()
          Spacer()
          createProjectButton.fixedSize()
        }
        VStack(alignment: .leading, spacing: 10) {
          Text(L("自定义画布")).font(.system(size: 18, weight: .semibold))
          HStack { Spacer(); createProjectButton }
        }
      }
      CanvasSizePreview(size: draft.validationMessage == nil ? draft.pixelSize : nil,
        background: chosenBackground)
        .frame(height: 92).accessibilityLabel(L("自定义画布比例预览"))
      VStack(alignment: .leading, spacing: 7) {
        fieldLabel("项目名称")
        TextField(L("未命名"), text: Binding(get: { draft.name }, set: { draftNameEdited = true; draft.name = $0 })).textFieldStyle(.plain)
          .padding(.horizontal, 9).padding(.vertical, 7)
          .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
          .accessibilityLabel(L("项目名称"))
      }
      HStack(alignment: .bottom, spacing: 10) {
        VStack(alignment: .leading, spacing: 7) {
          fieldLabel("宽度")
          TextField(L("宽度"), text: dimensionBinding(width: true)).textFieldStyle(.plain)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .monospacedDigit().accessibilityLabel(L("画布宽度"))
        }
        VStack(alignment: .leading, spacing: 7) {
          fieldLabel("高度")
          TextField(L("高度"), text: dimensionBinding(width: false)).textFieldStyle(.plain)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .monospacedDigit().accessibilityLabel(L("画布高度"))
        }
        Picker(L("尺寸单位"), selection: Binding(get: { draft.unit }, set: { draft.changeUnit(to: $0) })) {
          ForEach(CanvasUnit.allCases) { Text($0.symbol).accessibilityLabel(L($0.rawValue)).tag($0) }.id(AppLocalization.language)
        }.id(AppLocalization.language).labelsHidden().frame(width: 74)
      }
      HStack(spacing: 12) {
        Picker(L("画布方向"), selection: Binding(get: {
          guard let width = Double(draft.width), let height = Double(draft.height),
            width != height else { return portraitPreference }
          return width < height
        }, set: { portrait in
          portraitPreference = portrait
          draft.orient(portrait: portrait)
        })) {
          Text(L("横向")).tag(false)
          Text(L("纵向")).tag(true)
        }.id(AppLocalization.language).pickerStyle(.segmented).labelsHidden().controlSize(.regular)
          .fixedSize().frame(width: 150, alignment: .leading).tint(.primary)
          .help(L("切换画布方向，自动交换宽度与高度"))
        Spacer(minLength: 0)
        Toggle(L("锁定比例"), isOn: Binding(get: { draft.lockAspect }, set: { draft.setAspectLock($0) }))
          .toggleStyle(.checkbox).font(.system(size: 12))
      }.frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        fieldLabel("分辨率")
        Spacer()
        ResolutionInput(value: $draft.resolution).frame(width: 112, height: 30)
        Text(L("DPI")).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      HStack {
        fieldLabel("背景")
        Spacer()
        Picker(L("画布背景"), selection: $background) {
          ForEach(CanvasBackground.allCases) { Text(L($0.rawValue)).tag($0) }.id(AppLocalization.language)
        }.id(AppLocalization.language).labelsHidden().frame(width: 145)
      }
      if background == .custom {
        ModernColorButton(title:"背景颜色",color:Binding(get:{RGBA(NSColor(backgroundColor))},set:{backgroundColor = $0.color}))
          .font(.system(size: 13))
      }
      Divider()
      DisclosureGroup(L("更多画布选项")) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            fieldLabel("作者")
            TextField(L("可选"), text: $draft.author).textFieldStyle(.plain)
              .padding(.horizontal, 9).padding(.vertical, 7)
              .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
              .accessibilityLabel(L("项目作者"))
          }
          Toggle(L("显示网格"), isOn: $draft.showGrid)
          Toggle(L("显示标尺"), isOn: $draft.showRulers)
        }.toggleStyle(.checkbox).padding(.top, 12)
      }.font(.system(size: 13))
      VStack(alignment: .leading, spacing: 6) {
        if let message = draft.validationMessage {
          Label(L(message), systemImage: "exclamationmark.circle").foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        } else if let size = draft.pixelSize {
          Text(L("{0} × {1} px", size.width.formatted(.number.precision(.fractionLength(0))), size.height.formatted(.number.precision(.fractionLength(0)))))
            .monospacedDigit()
        }
        Text(L("sRGB · 8 bit / 通道")).foregroundStyle(.secondary)
      }.font(.system(size: 12))
    }.controlSize(.large).padding(22)
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
  }

  private var chosenBackground: RGBA? {
    switch background {
    case .transparent: return nil
    case .white: return RGBA(r: 1, g: 1, b: 1)
    case .black: return RGBA(r: 0, g: 0, b: 0)
    case .custom: return RGBA(NSColor(backgroundColor))
    }
  }
  private func openHistory(_ item: StartPageHistoryItem) {
    guard item.available else { return }
    if let id = item.sessionID { store.activate(id) }
    else if let url = item.url { store.open(url) }
  }
  private func fieldLabel(_ title: String) -> some View {
    Text(L(title)).font(.system(size: 12)).foregroundStyle(.secondary)
  }
  private func dimensionBinding(width: Bool) -> Binding<String> {
    Binding(get: { width ? draft.width : draft.height }, set: { draft.setDimension($0, width: width) })
  }
  private func load(_ preset: CanvasPreset) {
    draft.unit = .pixels
    draft.width = String(Int(preset.width))
    draft.height = String(Int(preset.height))
    draft.resolution = String(Int(preset.dpi))
    draft.aspectRatio = preset.width / preset.height
    background = [.print, .photo].contains(preset.category) ? .white : .transparent
  }
  private func create() {
    guard draft.validationMessage == nil, let size = draft.pixelSize, let dpi = draft.dpi else { return }
    store.newProject(name: draft.name, width: size.width, height: size.height, dpi: dpi,
      background: chosenBackground, author: draft.author, grid: draft.showGrid, rulers: draft.showRulers)
  }
}

/// An editable native combo box keeps presets with the numeric value. The
/// adjacent DPI label is a unit, rather than a misleading unit-selection menu.
private struct ResolutionInput: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  @Binding var value: String
  private let options = ["72", "144", "150", "300", "600", "1200"]
  func makeCoordinator() -> Coordinator { Coordinator(value: $value) }
  func makeNSView(context: Context) -> NSComboBox {
    let view = NSComboBox()
    view.addItems(withObjectValues: options)
    view.isEditable = true
    view.completes = false
    view.controlSize = .large
    view.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    view.bezelStyle = .roundedBezel
    view.numberOfVisibleItems = 6
    view.setAccessibilityLabel(L("画布分辨率"))
    view.toolTip = L("输入分辨率，或从下拉列表选择常用数值（DPI）")
    view.stringValue = value
    if let index = options.firstIndex(of: value) { view.selectItem(at: index) }
    view.delegate = context.coordinator
    return view
  }
  func updateNSView(_ view: NSComboBox, context: Context) {
    view.setAccessibilityLabel(L("画布分辨率"))
    view.toolTip = L("输入分辨率，或从下拉列表选择常用数值（DPI）")
    context.coordinator.value = $value
    context.coordinator.updating = true
    defer { context.coordinator.updating = false }
    let selection = options.firstIndex(of: value) ?? -1
    if view.indexOfSelectedItem != selection {
      if selection >= 0 { view.selectItem(at: selection) }
      else if view.indexOfSelectedItem >= 0 { view.deselectItem(at: view.indexOfSelectedItem) }
    }
    if view.stringValue != value { view.stringValue = value }
  }
  final class Coordinator: NSObject, NSComboBoxDelegate {
    var value: Binding<String>
    var updating = false
    init(value: Binding<String>) { self.value = value }
    func controlTextDidChange(_ notification: Notification) {
      guard !updating, let view = notification.object as? NSComboBox else { return }
      value.wrappedValue = view.stringValue
    }
    func comboBoxSelectionDidChange(_ notification: Notification) {
      guard !updating, let view = notification.object as? NSComboBox,
        let selected = view.objectValueOfSelectedItem as? String else { return }
      value.wrappedValue = selected
    }
  }
}

private enum CanvasBackground: String, CaseIterable, Identifiable {
  case transparent = "透明", white = "白色", black = "黑色", custom = "自定义颜色"
  var id: Self { self }
}

private struct CanvasPresetButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  var preset: CanvasPreset
  var action: () -> Void
  @State private var hover = false
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        PresetIcon(width: preset.width, height: preset.height).frame(width: 32, height: 32)
        VStack(alignment: .leading, spacing: 5) {
          Text(L(preset.name)).font(.system(size: 13, weight: .medium)).lineLimit(2).fixedSize(horizontal:false,vertical:true)
          Text(L(preset.dimensions)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        Spacer(minLength: 0)
      }.padding(14).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(Color.primary.opacity(hover ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(hover ? 0.16 : 0.07), lineWidth: 0.7))
    }.buttonStyle(.plain).onHover { hover = $0 }
      .help(L("{0} · {1} px · {2} DPI\n点击新建，右键载入自定义画布", L(preset.name), preset.dimensions, Int(preset.dpi)))
      .accessibilityLabel(L("新建{0}，{1}像素，{2} DPI", L(preset.name), preset.dimensions, Int(preset.dpi)))
  }
}

private struct CanvasSizePreview: View {
  @ObservedObject private var localization = LocalizationState.shared
  var size: (width: Double, height: Double)?
  var background: RGBA?
  var body: some View {
    GeometryReader { geometry in
      let ratio = (size?.width ?? 1920) / (size?.height ?? 1080)
      let width = min(geometry.size.width - 36, geometry.size.height * ratio)
      let height = min(geometry.size.height, (geometry.size.width - 36) / ratio)
      Canvas { context, bounds in
        context.fill(Path(CGRect(origin: .zero, size: bounds)), with: .color(.primary.opacity(0.04)))
        let cell: CGFloat = 8
        for row in 0..<Int(ceil(bounds.height / cell)) {
          for column in 0..<Int(ceil(bounds.width / cell)) where (row + column).isMultiple(of: 2) {
            context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
              with: .color(.primary.opacity(0.09)))
          }
        }
        if let background { context.fill(Path(CGRect(origin: .zero, size: bounds)), with: .color(background.color)) }
      }.frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct StartPageHistoryItem: Identifiable {
  var id: String
  var name: String
  var width: Double
  var height: Double
  var date: Date
  var sessionID: UUID?
  var url: URL?
  var image: CGImage?
  var detail: String
  var folderID: UUID? = nil
  var available: Bool { sessionID != nil || url.map { FileManager.default.fileExists(atPath: $0.path) } == true }
  var dragIdentifier: String {
    if let sessionID { return sessionID.uuidString }
    return "path:" + (url?.standardizedFileURL.path ?? id)
  }
}

private struct StartPageHistoryButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  var item: StartPageHistoryItem
  var selected = false
  var action: () -> Void
  @State private var hover = false
  var body: some View {
    Button(action: action) {
      VStack(spacing:6) {
        ZStack {
          RoundedRectangle(cornerRadius:6).fill(Color.primary.opacity(0.045))
          if let image = item.image {
            Image(decorative:image,scale:1).resizable().scaledToFit().padding(4)
          } else {
            Image(systemName:"doc.richtext").font(.system(size:30)).foregroundStyle(.secondary)
          }
        }.frame(width:96,height:80).clipShape(RoundedRectangle(cornerRadius:6))
        Text(item.name).font(.system(size:13,weight:selected ? .semibold : .regular)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.center)
          .padding(.horizontal,6).padding(.vertical,2)
          .background(Color.primary.opacity(selected ? 0.12 : 0),in:RoundedRectangle(cornerRadius:4))
        Text(L(item.available ? "\(Int(item.width)) × \(Int(item.height))" : "文件不可用"))
          .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
      }.padding(8).frame(maxWidth:.infinity,minHeight:140,alignment:.top).contentShape(Rectangle())
        .background(Color.primary.opacity(selected ? 0.07 : hover ? 0.045 : 0),in:RoundedRectangle(cornerRadius:10))
    }.buttonStyle(.plain).onHover { hover = $0 }
      .opacity(item.available ? 1 : 0.6)
      .help(item.url?.path ?? L("{0} · 未保存的项目", item.name))
      .accessibilityLabel(L("打开{0}，{1}", item.name, L(item.available ? item.detail : "文件不可用")))
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private enum StartPageLibraryItem: Identifiable {
  case folder(ProjectFolder),project(StartPageHistoryItem)
  var id:String {switch self {case .folder(let value):return value.libraryIdentifier;case .project(let value):return value.dragIdentifier}}
  var orderKey:String {switch self {case .folder:return id;case .project(let value):return value.url?.standardizedFileURL.path ?? value.id}}
  var nativeID:UUID {switch self {case .folder(let value):return value.id;case .project(let value):return value.sessionID ?? UUID()}}
  var name:String {switch self {case .folder(let value):return value.name;case .project(let value):return value.name}}
  var preview:CGImage? {if case .project(let value) = self {return value.image};return nil}
  var folderID:UUID? {if case .folder(let value) = self {return value.id};return nil}
}
