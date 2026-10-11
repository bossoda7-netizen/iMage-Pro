import AppKit
import SwiftUI

struct WorkspaceView: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var renamingProject: UUID?
  @State private var projectName = ""
  var body: some View {
    ZStack(alignment: .top) {
      GeometryReader { geometry in
        ZStack {
        if store.showWelcome {
          WelcomeView(store: store)
            .padding(.top, 56)
            .transition(.opacity)
        } else {
          EditorCanvas(store: store)
        }
        VStack(spacing: 0) {
          Spacer()
          if !store.status.isEmpty {
            HStack(spacing: 8) {
              if store.busy {
                ProgressView().controlSize(.small)
              } else {
                Image(systemName: store.statusIsWarning ? "exclamationmark.triangle" : "checkmark.circle")
              }
              Text(L(store.status)).font(.system(size: 12))
              IconButton(symbol: "xmark", label: "关闭提示", size: 24) { store.status = "" }
            }
            .padding(.horizontal, 15).padding(.vertical, 8).background(
              .regularMaterial, in: Capsule()
            ).padding(.bottom, 12)
          }
          if !store.showWelcome {
            bottomBar.id(store.rulerMode).padding(.horizontal, 18).padding(.bottom, 18)
              .transition(.opacity.combined(with: reduceMotion ? .identity : .move(edge: .bottom)))
          }
        }
        if !store.showWelcome && store.showLayers {
          LayerPanel(store: store).frame(width: 260, height: max(300, geometry.size.height - 179))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(
              .leading, 18
            ).padding(.bottom, 105)
            .transition(.opacity.combined(with: reduceMotion ? .identity : .move(edge: .bottom)))
        }
        if !store.showWelcome && store.showEffects {
          EffectsPanel(store: store).frame(width: min(470, max(390, geometry.size.width * 0.34)), height: max(300, geometry.size.height - 179))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(
              .trailing, 18
            ).padding(.bottom, 105)
            .transition(.opacity.combined(with: reduceMotion ? .identity : .move(edge: .bottom)))
        }
        if !store.showWelcome && store.showInspector && !store.showEffects {
          InspectorPanel(store: store).frame(
            width: geometry.size.width < 1200 ? 370 : 414,
            height: max(300, geometry.size.height - 179)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(
            .trailing, 18
          ).padding(.bottom, 105)
          .transition(.opacity.combined(with: reduceMotion ? .identity : .move(edge: .trailing)))
        }
        if let pathID = store.retouchPathID, !store.showWelcome {
          HStack(spacing:12) {
            Label(L("路径修饰"),systemImage:"point.topleft.down.to.point.bottomright.curvepath").font(.system(size:12,weight:.semibold))
            Button {
              if store.interactionTool != .retouch {store.chooseTool(.retouch);store.retouchPathID = pathID}
              store.showTools = true
            } label: {
              Label(L(store.interactionTool == .retouch ? store.branch.title : "选择修饰工具"),systemImage:store.interactionTool == .retouch ? "checkmark.circle.fill" : "1.circle")
            }.buttonStyle(.bordered)
            Image(systemName:"chevron.right").foregroundStyle(.tertiary)
            Label(L("点选目标图层"),systemImage:"2.circle").foregroundStyle(store.interactionTool == .retouch ? .primary : .secondary)
            Spacer()
            Button(L("取消")) {store.retouchPathID = nil;store.showTools = false}
          }.padding(12).glassSurface(14)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).padding(.top,74)
        }
        if !store.showWelcome && store.showScopes {
          ScopePanel(store: store, viewport: geometry.size)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        }
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.showLayers)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.showTools)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.showEffects)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.showInspector)
      .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: store.rulerMode)
      }
    }
    .overlay(alignment: .top) {
      ImageProTopBar(store: store) { id in
        guard let session = store.sessions.first(where: { $0.id == id }), !session.isStartPage else { return }
        projectName = session.document.name
        renamingProject = id
      }.frame(height: 56)
    }
    .ignoresSafeArea(.container, edges: .top)
    .tint(store.accent)
    .environment(\.appAccent, store.accent)
    .preferredColorScheme(
      store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil
    )
    .background(Color(nsColor: .windowBackgroundColor))
    .background(WindowBridge(store: store).frame(width: 0, height: 0))
    .sheet(isPresented: Binding(get: { store.sheet != nil }, set: { if !$0 { store.sheet = nil } }))
    { ManagementSheet(store: store, kind: store.sheet ?? "about") }
    .alert(L("无法完成操作"),
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button(L("好"), role: .cancel) { store.error = nil }
    } message: {
      Text(L(store.error ?? ""))
    }
    .alert(L("重命名项目"),
      isPresented: Binding(
        get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } })
    ) {
      TextField(L("项目名称"), text: $projectName)
      Button(L("取消"), role: .cancel) { renamingProject = nil }
      Button(L("重命名")) {
        if let id = renamingProject {
          store.renameProject(id, to: projectName)
        }
        renamingProject = nil
      }.disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }
  var bottomBar: some View {
    if store.rulerMode { return AnyView(rulerBottomBar) }
    return AnyView(
    HStack(alignment: .center, spacing: 14) {
      TextAction(title: "图层", symbol: "square.3.layers.3d", selected: store.showLayers) {
        store.showLayers.toggle()
        store.showTools = false
      }
      .frame(width: 125, height: 64).glassSurface(22)
      toolBar.frame(maxWidth: .infinity).frame(height: 64).glassSurface(22)
      TextAction(title: "效果器", symbol: "sparkles", selected: store.showEffects) {
        store.showEffects.toggle()
        store.showTools = false
      }
      .frame(width: 136, height: 64).glassSurface(22)
    })
  }
  private var rulerBottomBar: some View {
    HStack(spacing: 8) {
      ForEach(RulerTool.allCases) { tool in
        Button { store.activeRulerTool = tool } label: {
          Label(L(tool.rawValue), systemImage: tool.symbol)
            .labelStyle(.titleAndIcon).frame(minWidth: 74, minHeight: 40)
        }.buttonStyle(.plain).background(store.activeRulerTool == tool ? Color.primary.opacity(0.14) : .clear, in: Capsule())
      }.id(AppLocalization.language)
      Spacer(minLength: 12)
      Button(L("取消")) { store.cancelRulerMode() }.buttonStyle(.bordered)
      Button(L("完成")) { store.finishRulerMode() }.buttonStyle(.borderedProminent)
    }.padding(.horizontal, 14).frame(height: 64).glassSurface(22)
  }
  var toolBar: some View {
    HStack(spacing: 14) {
      Button {
        store.showTools.toggle()
      } label: {
        HStack(spacing: 8) {
          ToolGlyph(category: store.tool).frame(width: 24, height: 24).foregroundStyle(.primary)
          Text(L(store.branch.title)).font(.system(size:12,weight:.medium)).lineLimit(1)
          Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 10).frame(height: 44).background(
          Color.primary.opacity(store.showTools ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius:12))
      }.buttonStyle(.plain).help(L("切换工具 · {0}", L(store.branch.title)))
        .popover(isPresented: $store.showTools, arrowEdge: .bottom) {
          ToolBrowser(store: store).frame(width: 340, height: 510).padding(10)
        }
      ToolQuickControls(store: store).frame(maxWidth: .infinity)

    }.padding(.horizontal, 14)
  }

}

/// macOS 26 command surface. The AppKit traffic lights stay native while the
/// actions use one shared Liquid Glass layer, with a project tab strip in the
/// center so the current project is always visible.
struct ImageProTopBar: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var onRename: (UUID) -> Void
  @State private var hoverPreview: ProjectTabHoverPreview?
  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        TrafficLightControls().frame(width: 66, height: 56)
        leadingCommands.padding(.leading, 16)
        WindowTitlebarDragArea().frame(minWidth: 12, maxWidth: .infinity)
        ProjectTabStrip(store: store, onRename: onRename, hoverPreview: $hoverPreview)
          .frame(width: min(430, max(180, geometry.size.width - 900)))
        WindowTitlebarDragArea().frame(minWidth: 12, maxWidth: .infinity)
        trailingCommands
      }
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .glassSurface(0, attached: true)
    // The hover preview lives after the glass modifier so the titlebar's
    // material clipping never clips the content below its lower edge.
    .overlay(alignment: .topLeading) {
      GeometryReader { geometry in
        if let preview = hoverPreview,
          let session = store.sessions.first(where: { $0.id == preview.id }),
          session.id != store.activeID, store.sheet == nil {
          ProjectTabTooltip(session: session)
            .offset(x: min(max(0, preview.centerX - 130), max(0, geometry.size.width - 260)),
                    y: geometry.size.height + 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
    }
    .coordinateSpace(name: "workspace-titlebar")
    .onChange(of: store.sheet) { _, _ in hoverPreview = nil }
    .onChange(of: store.activeID) { _, _ in hoverPreview = nil }
    .tint(.primary)
    .foregroundStyle(.primary)
    .accessibilityElement(children: .contain)
  }

  private var leadingCommands: some View {
    HStack(spacing: 2) {
      ToolbarIconButton(symbol: "arrow.uturn.backward", label: store.undoLabel,
                        disabled: !store.canUndo) { store.undo() }
      ToolbarIconButton(symbol: "arrow.uturn.forward", label: store.redoLabel,
                        disabled: !store.canRedo) { store.redo() }
      TopBarCommand(title: "设置", label: "打开设置") { store.sheet = "settings" }
      TopBarCommand(title: "项目", label: "项目操作", disabled: store.showWelcome) { store.sheet = "project" }
      TopBarCommand(title: "扩展", label: "管理扩展") { store.sheet = "extensions" }
      TopBarCommand(title: "关于", label: "关于 iMage Pro") { store.sheet = "about" }
      Menu {
        Button(L("新建项目…")) { store.newStartPage() }
        Button(L("打开…")) { store.openPanel() }
        Button(L("添加图像…")) { store.openPanel(asLayer: true) }.disabled(store.showWelcome)
        Divider()
        Button(L("保存")) { store.save() }
        Button(L("另存为…")) { store.save(as: true) }
        Divider()
        Toggle(L("吸附"), isOn: $store.snapping).disabled(store.showWelcome)
        Toggle(L("内容吸附"), isOn: $store.contentSnapping).disabled(store.showWelcome)
        Toggle(L("显示网格"), isOn: $store.showGrid).disabled(store.showWelcome)
        Divider()
        Button(L("使用指南")) { store.sheet = "help" }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .semibold))
          .frame(width: 30, height: 34)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .help(L("更多项目操作"))
      .accessibilityLabel(L("更多项目操作"))
    }
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(.primary)
    .fixedSize(horizontal: true, vertical: false)
  }

  private var trailingCommands: some View {
    HStack(spacing: 8) {
      TopBarMenu(title: "专业", label: "专业工具") {
        Button(L(store.rulerMode ? "标尺模式进行中" : "进入标尺模式")) { store.beginRulerMode() }
          .disabled(store.rulerMode)
        Toggle(L("显示标尺线"), isOn: $store.showRulers)
        Divider()
        Button(L("显示图谱")) { store.showScopes = true }
      }.disabled(store.showWelcome)
      TopBarMenu(title: "智能", label: "智能工具") {
        Button(L("提取主体 / 去除背景")) { store.extractSubject() }
          .disabled(store.busy || store.selected == nil)
        Button(L("智能 HDR")) { store.addEffect(.hdr) }.disabled(store.selected == nil)
      }.disabled(store.showWelcome)
      TopBarCommand(title: "导出", label: "导出项目", prominent: true, disabled: store.showWelcome) { store.sheet = "export" }
      TopBarCommand(title: "调节器", label: store.showInspector ? "隐藏调节器" : "显示调节器",
                    symbol: "slider.horizontal.3", prominent: store.showInspector, disabled: store.showWelcome) {
        store.showInspector.toggle(); store.showEffects = false; store.inspector = store.selected?.defaultInspector ?? .base
      }
    }
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(.primary)
    .fixedSize(horizontal: true, vertical: false)
  }
}

/// The native titlebar buttons are hidden when the command row is embedded in
/// the full-size content view. Reusing those AppKit views outside their
/// titlebar causes macOS 26 to render a single blue window glyph. These three
/// compact controls keep the familiar traffic-light affordance while calling
/// the real NSWindow actions.
private struct TrafficLightControls: View {
  @ObservedObject private var localization = LocalizationState.shared
  @State private var hovering: Int?
  var body: some View {
    HStack(spacing: 8) {
      light(index: 0, color: .systemRed, symbol: "xmark") {
        NSApp.keyWindow?.performClose(nil)
      }
      light(index: 1, color: .systemYellow, symbol: "minus") {
        NSApp.keyWindow?.miniaturize(nil)
      }
      light(index: 2, color: .systemGreen, symbol: "arrow.up.left.and.arrow.down.right") {
        NSApp.keyWindow?.zoom(nil)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .accessibilityElement(children: .contain)
  }
  private func light(index: Int, color: NSColor, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      ZStack {
        Circle().fill(Color(nsColor: color))
        if hovering == index {
          Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(.black.opacity(0.62))
        }
      }.frame(width: 13, height: 13)
    }
    .buttonStyle(.plain)
    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside ? index : nil } }
    .accessibilityLabel(L(index == 0 ? "关闭窗口" : index == 1 ? "最小化窗口" : "缩放窗口"))
  }
}

private struct ToolbarIconButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  let symbol: String
  let label: String
  var disabled = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 30, height: 34)
        .contentShape(Rectangle())
        .background(hovering && !disabled ? Color.primary.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.35 : 1)
    .onHover { hovering = $0 }
    .help(L(label))
    .accessibilityLabel(L(label))
  }
}

private struct TopBarCommand: View {
  @ObservedObject private var localization = LocalizationState.shared
  let title: String
  let label: String
  var symbol: String?
  var prominent = false
  var disabled = false
  let action: () -> Void
  @State private var hovering = false

  init(title: String, label: String, symbol: String? = nil, prominent: Bool = false, disabled: Bool = false,
       action: @escaping () -> Void) {
    self.title = title; self.label = label; self.symbol = symbol
    self.prominent = prominent; self.disabled = disabled; self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: symbol == nil ? 0 : 5) {
        if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
        Text(L(title)).lineLimit(1)
      }
      .padding(.horizontal, 9)
      .frame(minHeight: 34)
      .background(
        hovering && !disabled || prominent ? Color.primary.opacity(prominent ? 0.14 : 0.09) : .clear,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(disabled ? .secondary : .primary)
    .disabled(disabled)
    .opacity(disabled ? 0.55 : 1)
    .onHover { hovering = $0 }
    .help(L(label))
    .accessibilityLabel(L(label))
  }
}

private struct TopBarMenu<Content: View>: View {
  @ObservedObject private var localization = LocalizationState.shared
  let title: String
  let label: String
  @ViewBuilder let content: () -> Content
  @State private var hovering = false

  var body: some View {
    Menu(content: content) {
      HStack(spacing: 4) {
        Text(L(title))
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
      }
      .padding(.horizontal, 9)
      .frame(minHeight: 34)
      .background(hovering ? Color.primary.opacity(0.09) : .clear,
                  in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .tint(.primary)
    .foregroundStyle(.primary)
    .onHover { hovering = $0 }
    .help(L(label))
    .accessibilityLabel(L(label))
  }
}

private struct ProjectTabStrip: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var onRename: (UUID) -> Void
  @Binding var hoverPreview: ProjectTabHoverPreview?
  @State private var draggedID: UUID?
  @State private var tabFrames: [UUID: CGRect] = [:]
  @State private var dragOrder: [UUID] = []
  @State private var dragWidths: [UUID: CGFloat] = [:]
  @State private var dragOrigin: CGFloat = 0
  @State private var dragTranslation: CGFloat = 0
  @State private var hoveredID: UUID?
  @State private var tooltipID: UUID?

  var body: some View {
    GeometryReader { geometry in
      let layout = ProjectTabLayout(sessions: store.sessions, activeID: store.activeID,
                                    availableWidth: geometry.size.width - 36)
      let order = draggedID == nil ? store.sessions.map(\.id) : dragOrder
      let sessionsByID = Dictionary(uniqueKeysWithValues: store.sessions.map { ($0.id, $0) })
      let sessions = order.compactMap { sessionsByID[$0] }
      let origins = ProjectTabReorder.origins(order: order, widths: dragWidths)
      HStack(spacing: 4) {
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
              ForEach(sessions) { session in
                ProjectTab(session: session, selected: session.id == store.activeID,
                           compact: layout.compact && session.id != store.activeID,
                           width: dragWidths[session.id] ?? layout.width(for: session),
                           select: { store.activate(session.id) },
                           rename: { onRename(session.id) },
                           dragBegan: { beginDrag(session.id, layout: layout) },
                           dragChanged: { updateDrag(translation: $0) },
                           dragEnded: { finishDrag(cancelled: $0) },
                           hover: { inside in
                             if inside && draggedID == nil && layout.compact && session.id != store.activeID {
                               hoveredID = session.id
                             } else if hoveredID == session.id { hoveredID = nil }
                           })
                  .id(session.id)
                  .contextMenu {
                    Button(L("新建标签页")) { store.newStartPage() }
                    Button(L(session.isStartPage ? "复制启动页" : "复制项目")) { store.duplicateProject(session.id) }
                    if !session.isStartPage {
                      Button(L("重命名项目…")) { onRename(session.id) }
                    }
                    Divider()
                    Button(L("向左移动标签")) { move(session.id, offset: -1) }
                      .disabled(store.sessions.first?.id == session.id)
                    Button(L("向右移动标签")) { move(session.id, offset: 1) }
                      .disabled(store.sessions.last?.id == session.id)
                    Divider()
                    Button(L("关闭标签页")) { store.closeProject(session.id) }
                    Button(L("关闭其他标签页")) { store.closeOtherProjects(keeping: session.id) }
                      .disabled(store.sessions.count == 1)
                    Button(L("关闭右侧标签页")) { store.closeOtherProjects(keeping: session.id, toRightOnly: true) }
                      .disabled(store.sessions.last?.id == session.id)
                  }
                  .background {
                    GeometryReader { geometry in
                      Color.clear.preference(key: ProjectTabFrames.self,
                        value: [session.id: geometry.frame(in: .named("project-tabs"))])
                    }.allowsHitTesting(false)
                  }
                  .offset(x: draggedID == session.id ?
                    dragOrigin + dragTranslation - (origins[session.id] ?? dragOrigin) : 0)
                  .zIndex(draggedID == session.id ? 1 : 0)
                  .animation(draggedID == session.id || reduceMotion ? nil :
                    .interactiveSpring(response: 0.22, dampingFraction: 0.9), value: order)
              }.id(AppLocalization.language)
            }
            .padding(.horizontal, 2)
          }
          .coordinateSpace(name: "project-tabs")
          .focusEffectDisabled()
          .onPreferenceChange(ProjectTabFrames.self) { tabFrames = $0 }
          .onAppear { if let id = store.activeID { proxy.scrollTo(id, anchor: .center) } }
          .onChange(of: store.activeID) { _, id in
            if draggedID == nil, let id { proxy.scrollTo(id, anchor: .center) }
          }
          .onChange(of: geometry.size.width) { _, _ in
            if let id = store.activeID { proxy.scrollTo(id, anchor: .center) }
          }
          .onChange(of: store.sessions.map(\.id)) { previous, current in
            if draggedID == nil, Set(previous) != Set(current), let id = store.activeID {
              proxy.scrollTo(id, anchor: .center)
            }
          }
        }
        ToolbarIconButton(symbol: "plus", label: "新建标签页") { store.newStartPage() }
          .frame(width: 30)
      }
      .frame(height: geometry.size.height)
      .onChange(of: tooltipID) { _, id in
        if let id, let rect = tabFrames[id], layout.compact, id != store.activeID {
          hoverPreview = ProjectTabHoverPreview(id: id,
            centerX: geometry.frame(in: .named("workspace-titlebar")).minX + rect.midX)
        } else { hoverPreview = nil }
      }
      .task(id: hoveredID) {
        tooltipID = nil
        guard let id = hoveredID else { return }
        do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
        // A menu may keep a mouse button pressed through the initial delay.
        // Keep waiting while the pointer remains here rather than dropping the
        // preview until the next mouse-enter event.
        while NSEvent.pressedMouseButtons != 0 {
          do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
        }
        guard !Task.isCancelled, hoveredID == id, draggedID == nil else { return }
        tooltipID = id
      }
    }
    .frame(height: 56)
    .accessibilityLabel(L("项目标签"))
  }

  private func beginDrag(_ id: UUID, layout: ProjectTabLayout) {
    dragOrder = store.sessions.map(\.id)
    dragWidths = Dictionary(uniqueKeysWithValues: store.sessions.map { ($0.id, layout.width(for: $0)) })
    dragOrigin = ProjectTabReorder.origins(order: dragOrder, widths: dragWidths)[id] ?? 0
    dragTranslation = 0
    draggedID = id
    hoveredID = nil
    tooltipID = nil
    hoverPreview = nil
  }

  private func updateDrag(translation: CGFloat) {
    guard let id = draggedID else { return }
    // Pointer movement is immediate. Only siblings animate when a midpoint is
    // crossed; moving the dragged view itself must never lag behind the mouse.
    withTransaction(Transaction(animation: nil)) { dragTranslation = translation }
    dragOrder = ProjectTabReorder.moving(id, in: dragOrder, widths: dragWidths,
      centerX: dragOrigin + translation + (dragWidths[id] ?? 0) / 2)
  }

  private func finishDrag(cancelled: Bool) {
    guard let id = draggedID else { return }
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
      if !cancelled, let destination = dragOrder.firstIndex(of: id),
        store.sessions.indices.contains(destination) {
        store.moveProject(id, to: store.sessions[destination].id)
      }
      draggedID = nil
      dragOrder = []
      dragWidths = [:]
      dragTranslation = 0
    }
  }

  private func move(_ id: UUID, offset: Int) {
    guard let index = store.sessions.firstIndex(where: { $0.id == id }),
      store.sessions.indices.contains(index + offset) else { return }
    store.moveProject(id, to: store.sessions[index + offset].id)
  }
}

/// Work in stable content coordinates, independent of scroll position and the
/// animated presentation frames. Midpoint crossings leave a natural gap and
/// prevent adjacent tabs from swapping back and forth near their edges.
enum ProjectTabReorder {
  static func origins(order: [UUID], widths: [UUID: CGFloat]) -> [UUID: CGFloat] {
    var x: CGFloat = 0
    var result: [UUID: CGFloat] = [:]
    for id in order { result[id] = x; x += (widths[id] ?? 0) + 3 }
    return result
  }

  static func moving(_ id: UUID, in order: [UUID], widths: [UUID: CGFloat],
                     centerX: CGFloat) -> [UUID] {
    guard var index = order.firstIndex(of: id) else { return order }
    var result = order
    let start = origins(order: result, widths: widths)[id] ?? 0
    let movingRight = centerX > start + (widths[id] ?? 0) / 2
    while movingRight ? index < result.count - 1 : index > 0 {
      let neighborIndex = index + (movingRight ? 1 : -1)
      let neighbor = result[neighborIndex]
      let middle = (origins(order: result, widths: widths)[neighbor] ?? 0) + (widths[neighbor] ?? 0) / 2
      guard movingRight ? centerX > middle : centerX < middle else { break }
      result.swapAt(index, neighborIndex)
      index = neighborIndex
    }
    return result
  }
}

/// Reserve the current tab's title before compressing its siblings to thumbnails.
struct ProjectTabLayout {
  let sessions: [ProjectSession]
  let activeID: UUID?
  let availableWidth: CGFloat
  var compact: Bool {
    sessions.reduce(CGFloat(0)) { $0 + expandedWidth($1) + 3 } > availableWidth
  }
  private func expandedWidth(_ session: ProjectSession) -> CGFloat {
    let title = ((session.isStartPage ? L("启动页") : session.document.name) as NSString).size(withAttributes:
      [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
    return max(104, title + 68)
  }
  func width(for session: ProjectSession) -> CGFloat {
    if compact && session.id != activeID { return 34 }
    return min(expandedWidth(session), max(110, availableWidth - 4))
  }
}

private struct ProjectTabHoverPreview {
  let id: UUID
  let centerX: CGFloat
}

private struct ProjectTabFrames: PreferenceKey {
  static var defaultValue: [UUID: CGRect] = [:]
  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

private struct ProjectTab: View {
  @ObservedObject private var localization = LocalizationState.shared
  let session: ProjectSession
  let selected: Bool
  let compact: Bool
  let width: CGFloat
  let select: () -> Void
  let rename: () -> Void
  let dragBegan: () -> Void
  let dragChanged: (CGFloat) -> Void
  let dragEnded: (Bool) -> Void
  let hover: (Bool) -> Void
  @State private var hovering = false
  @FocusState private var keyboardFocused: Bool

  var body: some View {
    HStack(spacing: 6) {
      ProjectThumbnail(session: session, size: compact ? 22 : 24, width: compact ? 22 : 32)
      if !compact {
        Text(verbatim: session.isStartPage ? L("启动页") : session.document.name).lineLimit(1).truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
        if session.dirty {
          Circle().fill(.primary).frame(width: 5, height: 5)
            .accessibilityLabel(L("有未保存更改"))
        }
      }
    }
    .font(.system(size: 12, weight: selected ? .semibold : .medium))
    .padding(.horizontal, compact ? 5 : 9)
    .frame(width: width, height: 34)
    .background(selected ? Color.primary.opacity(0.12) : hovering || keyboardFocused ? Color.primary.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: selected ? 12 : 8, style: .continuous))
    .overlay(alignment: .trailing) {
      if compact {
        Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 0.5, height: 18)
      }
    }
    .frame(height: 56)
    .contentShape(Rectangle())
    .overlay {
      ProjectTabInteractionArea(select: select,
        rename: { if !session.isStartPage { rename() } },
        dragBegan: dragBegan, dragChanged: dragChanged, dragEnded: dragEnded)
        .accessibilityHidden(true)
    }
    .background {
      ProjectTabHoverArea { inside in
        if hovering != inside { hovering = inside }
        hover(inside)
      }
    }
    .help(session.document.name)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel((session.isStartPage ? L("启动页") : session.document.name) + (session.dirty ? L("，有未保存更改") : ""))
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    .accessibilityAction { select() }
    .accessibilityAction(named: L("重命名项目")) { if !session.isStartPage { rename() } }
    .focusable()
    .focused($keyboardFocused)
    .focusEffectDisabled()
    .onKeyPress(.return) { select(); return .handled }
    .onKeyPress(.space) { select(); return .handled }
  }
}

/// Own the primary mouse sequence before AppKit can interpret it as titlebar
/// dragging. Window coordinates stay stable even while the tab changes slots.
struct ProjectTabInteractionArea: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  var select: () -> Void
  var rename: () -> Void
  var dragBegan: () -> Void
  var dragChanged: (CGFloat) -> Void
  var dragEnded: (Bool) -> Void

  func makeNSView(context: Context) -> MouseView { MouseView(actions: self) }
  func updateNSView(_ view: MouseView, context: Context) { view.actions = self }

  final class MouseView: NSView {
    var actions: ProjectTabInteractionArea
    private var origin: NSPoint?
    private var isDragging = false
    private var clickCount = 0
    private var cancelMonitor: Any?
    init(actions: ProjectTabInteractionArea) {
      self.actions = actions
      super.init(frame: .zero)
      setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) } }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      origin = event.locationInWindow
      clickCount = event.clickCount
      isDragging = false
      if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
      cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, self.origin != nil, event.keyCode == 53 else { return event }
        self.finish(cancelled: true)
        return nil
      }
    }

    override func mouseDragged(with event: NSEvent) {
      guard let origin else { return }
      let delta = event.locationInWindow.x - origin.x
      if !isDragging {
        guard abs(delta) >= 4 else { return }
        isDragging = true
        actions.dragBegan()
        NSCursor.closedHand.set()
      }
      actions.dragChanged(delta)
    }

    override func mouseUp(with event: NSEvent) {
      guard origin != nil else { return }
      if isDragging { finish(cancelled: false) }
      else {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
          if clickCount == 2 { actions.rename() } else { actions.select() }
        }
        reset()
      }
    }

    private func finish(cancelled: Bool) {
      if isDragging { actions.dragEnded(cancelled) }
      reset()
    }

    private func reset() {
      origin = nil
      isDragging = false
      if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
      cancelMonitor = nil
      NSCursor.arrow.set()
    }
  }
}

/// Passive AppKit tracking keeps hover previews working when the window is
/// inactive or has just dismissed a context menu, without consuming clicks.
private struct ProjectTabHoverArea: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  var hover: (Bool) -> Void
  func makeNSView(context: Context) -> TrackingView { TrackingView(hover: hover) }
  func updateNSView(_ view: TrackingView, context: Context) { view.hover = hover }

  final class TrackingView: NSView {
    var hover: (Bool) -> Void
    private var eventMonitor: Any?
    init(hover: @escaping (Bool) -> Void) {
      self.hover = hover
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
      eventMonitor = nil
      guard window != nil else { return }
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching:
        [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
         .leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
        guard let self, event.window === self.window else { return event }
        let point = self.convert(event.locationInWindow, from: nil)
        let isDown = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        self.hover(!isDown && self.bounds.intersection(self.visibleRect).contains(point))
        return event
      }
    }
    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      trackingAreas.forEach(removeTrackingArea)
      // SwiftUI's AppKit bridge can report the whole scroll viewport as a
      // view's visibleRect. Restrict tracking to this particular tab's bounds.
      addTrackingArea(NSTrackingArea(rect: bounds.intersection(visibleRect),
        options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
        owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseMoved(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }
  }
}

private struct ProjectTabTooltip: View {
  @ObservedObject private var localization = LocalizationState.shared
  let session: ProjectSession
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      ProjectThumbnail(session: session, size: 32)
      VStack(alignment: .leading, spacing: 5) {
        Text(verbatim: session.isStartPage ? L("启动页") : session.document.name).font(.system(size: 13, weight: .semibold))
          .fixedSize(horizontal: false, vertical: true)
        Text(L(session.isStartPage ? "选择预设或打开项目" :
          "\(Int(session.document.width)) × \(Int(session.document.height))" + (session.dirty ? " · 未保存" : "")))
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(12).frame(width: 260)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.7))
    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
  }
}

private struct ProjectThumbnail: View {
  @ObservedObject private var localization = LocalizationState.shared
  let session: ProjectSession
  var size: CGFloat = 22
  var width: CGFloat? = nil
  var body: some View {
    ZStack {
      if session.isStartPage {
        Image(systemName: "square.grid.2x2").font(.system(size: size * 0.65, weight: .medium))
      } else {
        ZStack {
          // Preserve the whole canvas, including its aspect ratio and alpha.
          // Empty and transparent projects show their canvas rather than a
          // generic document icon that looks unrelated to the project.
          Canvas { context, bounds in
            context.fill(Path(CGRect(origin: .zero, size: bounds)), with: .color(Color(nsColor: .textBackgroundColor)))
            for row in 0..<Int(ceil(bounds.height / 4)) {
              for column in 0..<Int(ceil(bounds.width / 4)) where (row + column).isMultiple(of: 2) {
                context.fill(Path(CGRect(x: column * 4, y: row * 4, width: 4, height: 4)),
                  with: .color(.primary.opacity(0.16)))
              }
            }
          }
          if let image = session.thumbnail {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
          }
        }
        .aspectRatio(session.document.width / session.document.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
      }
    }
    .frame(width: width ?? size, height: size)
    .accessibilityHidden(true)
  }
}

enum ScopeMode: String, CaseIterable, Identifiable {
  case histogram = "直方图"
  case waveform = "RGB 波形"
  case parade = "RGB Parade"
  case vectorscope = "矢量示波器"
  var id: String { rawValue }
}

struct ScopePanel: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var viewport: CGSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mode: ScopeMode = .histogram
  @State private var origin: CGPoint?
  @State private var dragOrigin: CGPoint?
  @State private var metrics = ScopeMetrics(image: nil)
  private var size: CGSize {
    let left = store.showLayers ? 260.0 : 0
    let right = store.showInspector || store.showEffects ? (store.showEffects ? 470.0 : viewport.width<1200 ? 370.0 : 414.0) : 0
    let corridor = viewport.width-left-right-72
    return CGSize(width:min(360,viewport.width*0.32,max(240,corridor)),height:230)
  }
  private var safe: CGRect {CGRect(x:18,y:74,width:max(size.width,viewport.width-36),height:max(size.height,viewport.height-179))}
  private var position: CGPoint {origin ?? CGPoint(x:safe.minX,y:safe.minY)}
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        HStack {Text(L("专业图谱")).font(.system(size:15,weight:.semibold));Spacer(minLength:0)}
          .frame(maxWidth:.infinity,minHeight:28)
          .overlay(ScopeDragSurface(begin:{dragOrigin = position},changed:{delta in
            guard let start = dragOrigin else {return}
            var transaction = Transaction();transaction.disablesAnimations = true
            withTransaction(transaction) {origin = ScopePlacement.constrain(CGPoint(x:start.x+delta.x,y:start.y+delta.y),size:size,safe:safe,snap:0)}
          },end:{
            dragOrigin = nil
            origin = ScopePlacement.constrain(position,size:size,safe:safe,snap:16)
            avoidPanels()
          }))
        Picker(L("图谱类型"), selection: $mode) {
          ForEach(ScopeMode.allCases) {Text(L($0.rawValue)).tag($0)}.id(AppLocalization.language)
        }.id(AppLocalization.language).pickerStyle(.menu).labelsHidden().controlSize(.small)
        IconButton(symbol:"xmark",label:"关闭专业图谱",size:26) {store.showScopes = false}
      }
      ScopeChart(mode:mode,metrics:metrics).frame(height:140)
        .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
      Text(L("数据来自当前项目预览 · {0} × {1}", Int(store.document.width), Int(store.document.height)))
        .font(.system(size:10)).foregroundStyle(.secondary)
    }.padding(14).frame(width:size.width,height:size.height).glassSurface(18)
      .position(x:position.x+size.width/2,y:position.y+size.height/2)
      .onAppear {refreshMetrics();avoidPanels()}
      .onChange(of:store.previewRevision) {_,_ in refreshMetrics()}
      .onChange(of:store.showLayers) {_,_ in avoidPanels()}
      .onChange(of:store.showInspector) {_,_ in avoidPanels()}
      .onChange(of:store.showEffects) {_,_ in avoidPanels()}
      .onChange(of:viewport) {_,_ in avoidPanels()}
  }
  private func refreshMetrics() {
    guard let image = store.preview else {metrics = ScopeMetrics(image:nil);return}
    let generation = store.previewRevision
    Task.detached(priority:.utility) {
      let value = ScopeMetrics(image:image)
      await MainActor.run {if store.previewRevision == generation {metrics = value}}
    }
  }
  private func avoidPanels() {
    var obstacles: [CGRect] = []
    if store.showLayers {obstacles.append(CGRect(x:18,y:74,width:260,height:max(300,viewport.height-179)))}
    if store.showInspector || store.showEffects {
      let width = store.showEffects ? min(470,max(390,viewport.width*0.34)) : viewport.width<1200 ? 370.0 : 414.0
      obstacles.append(CGRect(x:viewport.width-18-width,y:74,width:width,height:max(300,viewport.height-179)))
    }
    let next = ScopePlacement.avoid(position,size:size,safe:safe,obstacles:obstacles)
    withAnimation(reduceMotion ? nil : .spring(response:0.28,dampingFraction:0.9)) {origin = next}
  }
}

enum ScopePlacement {
  static func constrain(_ origin: CGPoint,size:CGSize,safe:CGRect,snap:CGFloat = 16) -> CGPoint {
    var x = min(safe.maxX-size.width,max(safe.minX,origin.x))
    var y = min(safe.maxY-size.height,max(safe.minY,origin.y))
    if abs(x-safe.minX)<snap {x = safe.minX}
    if abs(x-(safe.maxX-size.width))<snap {x = safe.maxX-size.width}
    if abs(y-safe.minY)<snap {y = safe.minY}
    if abs(y-(safe.maxY-size.height))<snap {y = safe.maxY-size.height}
    return CGPoint(x:x,y:y)
  }
  static func avoid(_ origin:CGPoint,size:CGSize,safe:CGRect,obstacles:[CGRect]) -> CGPoint {
    let current = constrain(origin,size:size,safe:safe)
    let rect = CGRect(origin:current,size:size)
    guard obstacles.contains(where: {$0.intersects(rect)}) else {return current}
    var candidates = [current]
    for obstacle in obstacles {
      candidates += [CGPoint(x:obstacle.minX-size.width-12,y:current.y),CGPoint(x:obstacle.maxX+12,y:current.y),
        CGPoint(x:current.x,y:obstacle.minY-size.height-12),CGPoint(x:current.x,y:obstacle.maxY+12)]
    }
    let valid = candidates.map {constrain($0,size:size,safe:safe,snap:0)}
    func overlap(_ p:CGPoint) -> CGFloat {obstacles.reduce(0) {sum,o in let r = o.intersection(CGRect(origin:p,size:size));return sum+(r.isNull ? 0 : r.width*r.height)}}
    return valid.min {a,b in
      let aa = overlap(a),bb = overlap(b)
      if abs(aa-bb)>1 {return aa<bb}
      return hypot(a.x-current.x,a.y-current.y)<hypot(b.x-current.x,b.y-current.y)
    } ?? current
  }
}

struct ScopeMetrics {
  var histogram: [Double] = Array(repeating: 0, count: 256)
  var redWave: [Double] = []
  var greenWave: [Double] = []
  var blueWave: [Double] = []
  var vectors: [(Double, Double, Double)] = []
  init(image: CGImage?) {
    guard let image else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    let width = max(1, rep.pixelsWide), height = max(1, rep.pixelsHigh)
    var data = [UInt8](repeating: 0, count: width * height * 4)
    guard let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let step = max(1, Int((Double(width * height) / 90_000.0).squareRoot().rounded()))
    for y in stride(from: 0, to: height, by: step) {
      for x in stride(from: 0, to: width, by: step) {
        let i = (y * width + x) * 4
        let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
        histogram[Int(max(0, min(255, ((r + g + b) / 3 * 255).rounded())))] += 1
        let maxv = max(r, g, b), minv = min(r, g, b), d = maxv - minv
        if d > 0.02 {
          var h = 0.0
          if maxv == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
          else if maxv == g { h = (b - r) / d + 2 }
          else { h = (r - g) / d + 4 }
          if h < 0 { h += 6 }
          let saturation = d / max(0.001, maxv)
          let brightness = (r + g + b) / 3
          vectors.append((h / 6, saturation, brightness))
        }
      }
    }
    let maxBin = max(1, histogram.max() ?? 1); histogram = histogram.map { $0 / maxBin }
    func wave(_ channel: Int) -> [Double] {
      (0..<min(180, width)).map { x in
        var total = 0.0, count = 0.0
        for y in stride(from: 0, to: height, by: max(1, height / 120)) {
          total += Double(data[(y * width + x * width / min(180, width)) * 4 + channel]) / 255
          count += 1
        }
        return total / max(1, count)
      }
    }
    redWave = wave(0); greenWave = wave(1); blueWave = wave(2)
  }
}

struct ScopeChart: View {
  @ObservedObject private var localization = LocalizationState.shared
  var mode: ScopeMode
  var metrics: ScopeMetrics
  var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
      context.stroke(Path(rect), with: .color(.secondary.opacity(0.22)), lineWidth: 0.5)
      switch mode {
      case .histogram:
        let bins = metrics.histogram
        var path = Path(); path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (i, v) in bins.enumerated() { path.addLine(to: CGPoint(x: rect.minX + rect.width * CGFloat(i) / 255, y: rect.maxY - rect.height * v)) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.closeSubpath()
        context.fill(path, with: .color(.secondary.opacity(0.32)))
      case .waveform, .parade:
        let channels = [(metrics.redWave, Color.red), (metrics.greenWave, Color.green), (metrics.blueWave, Color.blue)]
        for (index, item) in channels.enumerated() {
          var path = Path(); let x0 = mode == .parade ? rect.minX + rect.width * CGFloat(index) / 3 : rect.minX
          let w = mode == .parade ? rect.width / 3 : rect.width
          for (i, value) in item.0.enumerated() { let x = x0 + w * CGFloat(i) / CGFloat(max(1, item.0.count - 1)); let y = rect.maxY - rect.height * value; if i == 0 { path.move(to: CGPoint(x:x,y:y)) } else { path.addLine(to: CGPoint(x:x,y:y)) } }
          context.stroke(path, with: .color(item.1.opacity(0.9)), lineWidth: 1.2)
        }
      case .vectorscope:
        let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) * 0.42
        context.stroke(Path(ellipseIn: CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)), with: .color(.secondary.opacity(0.35)), lineWidth: 0.7)
        for (h, s, _) in metrics.vectors.prefix(20_000) { let angle = h * 2 * .pi; let p = CGPoint(x:center.x + cos(angle) * radius * s, y:center.y + sin(angle) * radius * s); context.fill(Path(ellipseIn: CGRect(x:p.x-1,y:p.y-1,width:2,height:2)), with: .color(Color(hue:h,saturation:max(0.35,s),brightness:0.9).opacity(0.72))) }
      }
    }
  }
}

struct PresetIcon: View {
  @ObservedObject private var localization = LocalizationState.shared
  var width: Double
  var height: Double
  var body: some View {
    GeometryReader { proxy in
      let ratio = width / max(1, height)
      let w = min(proxy.size.width, proxy.size.height * ratio)
      let h = min(proxy.size.height, proxy.size.width / max(0.1, ratio))
      RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.8), lineWidth: 1.4)
        .frame(width: w, height: h).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

struct ToolGlyph: View {
  @ObservedObject private var localization = LocalizationState.shared
  var category: ToolCategory
  var body: some View {
    Group {
      if category == .text {
        Text(L("T")).font(.system(size: 20, weight: .semibold, design: .serif))
      } else {
        Image(systemName: category.symbol).font(.system(size: 17))
      }
    }
  }
}
struct ToolBrowser: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  @State private var hovered: ToolCategory?
  var current: ToolCategory { hovered ?? store.tool }
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ScrollView {
        VStack(spacing: 4) {
          ForEach(ToolCategory.displayed) { category in
            Button {
              store.chooseTool(category)
              store.showTools = false
            } label: {
              ToolGlyph(category: category).frame(width: 42, height: 38).foregroundStyle(
                current == category ? store.accent : .primary
              ).background(
                store.accent.opacity(current == category ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).help(L(category.rawValue)).onHover { inside in
              if inside { withAnimation(.smooth(duration: 0.18)) { hovered = category } }
            }
          }.id(AppLocalization.language)
        }
      }.frame(width: 52).pageScrollStyle(.vertical)
      VStack(alignment: .leading, spacing: 12) {
        Text(L(current.rawValue)).font(.system(size: 15, weight: .semibold))
        Divider()
        if current.branches.count > 1 {
        ScrollView {
          VStack(spacing: 5) {
            ForEach(current.branches) { branch in
              HoverToolRow(
                title: branch.title, symbol: branch.symbol,
                checked: (store.toolDefaults[current.rawValue] ?? current.branches[0].id)
                  == branch.id
              ) {
                store.chooseTool(current, branch: branch)
                store.showTools = false
              }
            }.id(AppLocalization.language)
          }.id(current.id).transition(.opacity.combined(with: .move(edge: .leading)))
        }.pageScrollStyle(.vertical)
        } else {
          Text(L("点击工具即可使用")).font(.system(size: 12)).foregroundStyle(.secondary)
          Spacer()
        }
        Text(L("点击分类使用上次分支；悬停选择其他工具。")).font(.system(size: 11)).foregroundStyle(.secondary)
          .lineSpacing(4)
      }.frame(maxWidth: .infinity).padding(8)
    }
  }
}
struct HoverToolRow: View {
  @ObservedObject private var localization = LocalizationState.shared
  var title: String
  var symbol: String
  var checked = false
  var action: () -> Void
  @State private var hover = false
  @Environment(\.appAccent) private var appAccent
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol).frame(width: 22)
        Text(L(title))
        Spacer()
        if checked { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
      }.font(.system(size: 13)).padding(11).contentShape(Rectangle()).background(
        appAccent.opacity(hover ? 0.12 : checked ? 0.06 : 0),
        in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain).onHover { inside in
      withAnimation(.easeOut(duration: 0.15)) { hover = inside }
    }
  }
}
