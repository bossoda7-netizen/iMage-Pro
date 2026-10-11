import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LayerPanel: View {
  @ObservedObject private var localization = LocalizationState.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var store: EditorStore
  @State private var query = ""
  @State private var dragging: UUID?
  @State private var dropTarget: UUID?
  @State private var dropAfter = false
  @State private var dropIntoGroup = false
  @State private var dropAsMask = false
  @State private var draggingMask: UUID?
  @State private var dragSnapshot: ImageDocument?
  @State private var dragProjectID:UUID?
  @State private var renameID: UUID?
  @State private var rename = ""
  var layers: [ImageLayer] {
    store.document.layers.filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    VStack(spacing: 14) {
      HStack {
        Text(L("图层")).font(.system(size: 17, weight: .semibold))
        Spacer()
        IconButton(
          symbol: store.layerPanelPinned ? "pin.fill" : "pin", label: "固定图层面板",
          selected: store.layerPanelPinned, size: 28
        ) { store.layerPanelPinned.toggle() }
        IconButton(symbol: "xmark", label: "关闭图层", size: 28) { store.showLayers = false }
      }
      HStack(spacing: 7) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField(L("查找图层"), text: $query).textFieldStyle(.plain)
      }
      .font(.system(size: 12)).padding(9).background(
        Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
      Picker(
        L("混合模式"),
        selection: Binding(
          get: { store.selected?.blend ?? .normal },
          set: { mode in store.updateSelected("调整混合模式") { $0.blend = mode } })
      ) {
        ForEach(BlendMode.groups,id:\.0) {group in
          Section(L(group.0)) {ForEach(group.1,id:\.self) {Text(L($0 == .luminosity ? "blend.luminosity" : $0.rawValue)).tag($0)}.id(AppLocalization.language)}
        }.id(AppLocalization.language)
      }.id(AppLocalization.language).controlSize(.regular).disabled(store.selected == nil)
      ParameterSlider(
        store: store, title: "不透明度", value: store.selected?.opacity ?? 1, range: 0...1, unit: "%",
        percentage: true
      ) { v in store.updateSelected("调整不透明度") { $0.opacity = v } }.disabled(store.selected == nil)
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
            row(layer)
            if index < layers.count-1 {
              ClippingGapSurface(clipped:layer.clippingMask,action:{store.toggleClippingMask(layer.id)})
                .frame(height:6).accessibilityLabel(L("切换{0}的剪切蒙版", layer.name))
                .accessibilityAction {store.toggleClippingMask(layer.id)}

            }
          }.id(AppLocalization.language)
        }.frame(maxWidth:.infinity,minHeight:170,alignment:.top)
      }
      .pageScrollStyle(.vertical)
      .background(LayerDropSurface(priority:1,hover:{_ in dropTarget = nil;dropAsMask = false;dropIntoGroup = false},drop:{
        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18)) {
          if let source = draggingMask {_ = store.detachMask(source)}
        }
        finishLayerDrag()
      }))

      HStack(spacing: 5) {
        Menu {
          Button(L("空白图层")) { store.addLayer(.paint) }
          Button(L("图像图层…")) { store.openPanel(asLayer: true) }
          Button(L("文件夹")) { store.addLayer(.group) }
        } label: {
          Image(systemName: "plus").foregroundStyle(.primary).frame(width: 28, height: 28)
        }.menuStyle(.borderlessButton).fixedSize().help(L("新建图层"))
        IconButton(symbol: "folder.badge.plus", label: "将选中图层编组", size: 28) {
          store.groupSelected()
        }.disabled(store.selectedIDs.count < 2)
        IconButton(symbol: "rectangle.badge.checkmark", label: "从选区添加蒙版", size: 28) {
          store.maskFromSelection()
        }.disabled(store.selection == nil)
        Button { store.addAdjustmentLayer() } label: {
          Image(systemName: "fx").font(.system(size:15,weight:.semibold)).foregroundStyle(.primary).frame(width: 28, height: 28)
        }.buttonStyle(.plain).fixedSize().help(L("添加调整图层"))
        Spacer(minLength: 0)
        IconButton(symbol: "trash", label: "删除当前图层", size: 28) {
          if let id = store.selected?.id { store.deleteLayer(id) }
        }.disabled(store.selected == nil || store.selected?.locked == true)
      }
    }.padding(16).glassSurface(20)
      .alert(L("重命名图层"), isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })
      ) {
        TextField(L("图层名称"), text: $rename)
        Button(L("取消"), role: .cancel) { renameID = nil }
        Button(L("重命名")) {
          if let id = renameID { store.renameLayer(id, name: rename.isEmpty ? L("未命名图层") : rename) }
          renameID = nil
        }
      }
  }
  func row(_ layer: ImageLayer) -> some View {
    HStack(spacing: 8) {
      LayerVisibilityButton(visible:layer.visible,name:layer.name) {store.toggleVisibility(layer.id)}
        .frame(width:28,height:32).fixedSize()
      if layer.parentID != nil {
        Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(.tertiary)
      }
      Group {
        if let image = store.active.assets.image(layer.assetID) {
          LayerThumbnail(image:image)
        } else {
          Image(systemName: layer.symbol).foregroundStyle(.secondary).frame(
            maxWidth: .infinity, maxHeight: .infinity
          ).background(.quaternary)
        }
      }.frame(width: 34, height: 37).clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .padding(.leading,layer.clippingMask ? 12 : 0)
        .overlay(LayerDragSurface(id:layer.id,name:layer.name,begin:{beginLayerDrag(layer.id)},select:{store.selectLayerFromPanel(layer.id)},cancel:{cancelLayerDrag()},preview:store.active.assets.image(layer.assetID)))
        .onTapGesture {store.selectLayerFromPanel(layer.id);store.showEffects = false}
        .background(LayerDropSurface(priority:3,hover:{_ in if dragging != layer.id || draggingMask != nil {dropTarget = layer.id;dropAsMask = layer.kind != .group;dropIntoGroup = layer.kind == .group}},drop:{commitLayerDrop(on:layer.id)}))
      if let mask = store.active.assets.image(layer.maskAssetID) {
        Button { store.selectMask(layer.id) } label: {
          Image(decorative: mask, scale: 1).resizable().scaledToFit()
            .frame(width: 30, height: 34).background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
              store.editingMask && store.selected?.id == layer.id ? store.accent : .clear, lineWidth: 2))
        }.buttonStyle(.plain).help(L("编辑蒙版；拖到列表空白处可分离，拖到另一个缩略图可移动"))
          .accessibilityLabel(L("编辑{0}的蒙版", layer.name))
          .overlay(LayerDragSurface(id:layer.id,name:layer.name+L(" · 蒙版"),begin:{dragProjectID = store.activeID;dragSnapshot = store.document;dragging = nil;draggingMask = layer.id;store.beginTransaction("移动蒙版")},select:{store.selectMask(layer.id)},cancel:{cancelLayerDrag()},preview:mask))
          .background(LayerDropSurface(priority:3,hover:{_ in if dragging != layer.id || draggingMask != nil {dropTarget = layer.id;dropAsMask = layer.kind != .group;dropIntoGroup = layer.kind == .group}},drop:{commitLayerDrop(on:layer.id)}))
          .opacity(draggingMask == layer.id ? 0.45 : 1)
            .contextMenu {
            Button(L("分离蒙版为图层")) { store.detachMask(layer.id) }
            Button(L(layer.maskEnabled ? "停用蒙版" : "启用蒙版")) {
              store.selectLayerFromPanel(layer.id);store.updateSelected("切换蒙版") { $0.maskEnabled.toggle() }
            }
            Button(L("删除蒙版"),role:.destructive) { store.removeMask(layer.id) }
          }
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(layer.name).font(
          .system(size: 12, weight: store.selectedIDs.contains(layer.id) ? .medium : .regular)
        ).lineLimit(1)
        if !layer.effects.isEmpty || layer.maskAssetID != nil {
          Text(
            (layer.maskAssetID != nil ? L("蒙版") : "")
              + (!layer.effects.isEmpty ? L("  {0} 个效果", layer.effects.count) : "")
          ).font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }.frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:37)
        .overlay(LayerDragSurface(id:layer.id,name:layer.name,begin:{beginLayerDrag(layer.id)},select:{store.selectLayerFromPanel(layer.id);store.showEffects = false},cancel:{cancelLayerDrag()}))
      if layer.clippingMask {
        Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(.secondary).help(L("剪切蒙版"))
      }
      if layer.locked {
        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
      }
    }.padding(.horizontal, 6).padding(.vertical, 5)
      .overlay(RoundedRectangle(cornerRadius:11).strokeBorder(Color.primary.opacity(store.retouchPathID != nil && store.interactionTool == .retouch && ![.group,.adjustment].contains(layer.kind) && !layer.isPath && !layer.locked ? 0.25 : 0),lineWidth:1).allowsHitTesting(false))
      .background(
        store.accent.opacity(store.selectedIDs.contains(layer.id) ? 0.13 : 0),
        in: RoundedRectangle(cornerRadius: 11)
      )
      .contentShape(Rectangle())
      .background(LayerDropSurface(priority:2,hover:{point in hoverLayerDrag(over:layer,point:point)},drop:{commitLayerDrop(on:layer.id)}))
      .contextMenu {
        if store.selectedIDs.count > 1,store.selectedIDs.contains(layer.id) {
          Button(L("编组")) {store.groupSelected()}
          Button(L("合并选中图层")) {store.mergeSelectedLayers()}
          Divider()
          Button(L("删除选中图层"),role:.destructive) {store.deleteSelectedLayers()}
        } else {
        Button(L("重命名")) {
          renameID = layer.id
          rename = layer.name
        }
        if layer.kind == .group {
          Button(L("添加整体效果")) {store.selectLayer(layer.id); store.showEffects = true}
          Button(L("取消编组")) { store.ungroup(layer.id) }
        } else {
          Button(L("复制")) { store.duplicateLayer(layer.id) }
          if [.text, .shape, .gradient, .adjustment].contains(layer.kind) {
            Button(L("转换为普通图层")) { store.selectLayerFromPanel(layer.id); store.rasterizeSelected() }
          }
          Button(L("上移")) { store.reorderLayer(layer.id, delta: -1) }
          Button(L("下移")) { store.reorderLayer(layer.id, delta: 1) }
          Button(L("合并下方所有图层")) { store.mergeDownAll(layer.id) }
        Button(L("添加蒙版")) {
          store.selectLayerFromPanel(layer.id)
          store.addMaskSelected()
        }
          if layer.maskAssetID != nil {
            Button(L("分离蒙版为图层")) { store.detachMask(layer.id) }
            Button(L("删除蒙版"),role:.destructive) { store.removeMask(layer.id) }
          }
          Button(L(layer.kind == .text ? "复制文字" : "提取图片文字")) {
            store.selectLayerFromPanel(layer.id)
            if layer.kind == .text { store.extractTextFromSelected() } else { store.extractImageText() }
          }
          Menu(L("形状蒙版")) {
            ForEach(ShapePreset.all) { shape in
              Button(L(shape.name)) {
                store.selectLayerFromPanel(layer.id)
                store.addMaskSelected(shape.id)
              }
            }.id(AppLocalization.language)
          }
          Button(L("添加效果")) {
            store.selectLayerFromPanel(layer.id)
            store.showEffects = true
          }
        }
        Divider()
        Button(L(layer.locked ? "解锁" : "锁定")) { store.toggleLock(layer.id) }
        Button(L(layer.visible ? "隐藏" : "显示")) { store.toggleVisibility(layer.id) }
        Button(L(layer.clippingMask ? "取消剪切蒙版" : "建立剪切蒙版")) { store.toggleClippingMask(layer.id) }
        Button(L("删除"), role: .destructive) { store.deleteLayer(layer.id) }.disabled(layer.locked)
        }
      }
      .overlay {
        if dropTarget == layer.id,dropIntoGroup || dropAsMask {
          RoundedRectangle(cornerRadius:11).strokeBorder(Color.primary.opacity(0.6),lineWidth:1.5)
            .overlay(alignment:.bottomTrailing) {
              Text(L(dropIntoGroup ? "放入文件夹" : "用作蒙版")).font(.system(size:10,weight:.medium))
                .padding(.horizontal,5).padding(.vertical,2).background(.regularMaterial,in:Capsule())
            }.allowsHitTesting(false)
        }
      }
      .overlay(alignment:dropAfter ? .bottom : .top) {
        if dropTarget == layer.id,!dropIntoGroup,!dropAsMask,dragging != layer.id {
          Capsule().fill(Color.primary.opacity(0.65)).frame(height:2).padding(.horizontal,5).allowsHitTesting(false)
        }
      }
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.document.layers.map(\.id))
      .opacity(dragging == layer.id ? 0.5 : 1)
      .accessibilityElement(children: .contain)
      .accessibilityAction { store.selectLayerFromPanel(layer.id) }
  }
  private func hoverLayerDrag(over layer:ImageLayer,point:CGPoint) {
    guard dragProjectID == store.activeID,dragging != layer.id else {return}
    dropTarget = layer.id;dropAfter = point.y>0.5
    dropIntoGroup = layer.kind == .group && (0.2...0.8).contains(point.y)
    dropAsMask = false
  }
  private func commitLayerDrop(on target:UUID) {
    guard dragProjectID == store.activeID else {finishLayerDrag();return}
    withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18)) {
      if dropAsMask { _ = acceptMaskDrop(on:target) }
      else if let source = dragging {
        if dropIntoGroup {store.moveLayerIntoGroup(source,group:target)}
        else {store.moveLayer(source,before:target,after:dropAfter)}
      } else if let source = draggingMask,let id = store.detachMask(source) {store.moveLayer(id,before:target,after:dropAfter)}
    }
    finishLayerDrag()
  }
  private func finishLayerDrag() {
    if dragProjectID == store.activeID {store.endTransaction()}
    dragging = nil;draggingMask = nil;dragSnapshot = nil;dropTarget = nil;dropAsMask = false;dropIntoGroup = false;dragProjectID = nil
  }
  private func cancelLayerDrag() {
    if dragProjectID == store.activeID,let snapshot = dragSnapshot {store.cancelTransaction(snapshot)}
    finishLayerDrag()
  }
  private func beginLayerDrag(_ id:UUID) {
    dragProjectID = store.activeID;dragSnapshot = store.document;draggingMask = nil;dragging = id;dropTarget = nil
    store.beginTransaction("调整图层顺序")
  }
  private func acceptMaskDrop(on target:UUID) -> Bool {
    guard dragProjectID == store.activeID else {finishLayerDrag();return false}
    if let source = draggingMask,source != target {
      store.transferMask(from:source,to:target);return true
    }
    if let source = dragging,source != target {
      store.attachLayerAsMask(source,to:target);return true
    }
    return false
  }
  @ViewBuilder private func rowDragPreview(_ layer: ImageLayer) -> some View {
    HStack(spacing: 7) {
      Image(systemName: layer.symbol)
      Text(layer.name).font(.system(size: 12, weight: .medium))
    }.padding(.horizontal, 12).padding(.vertical, 8)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

struct EffectsPanel: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  @State private var search = ""
  @State private var selectedGroup = "色彩调整"
  var effectGroups: [(String, [EffectKind])] {
    EffectCatalog.groups
  }

  var currentEffects: [EffectKind] {
    effectGroups.first(where: { $0.0 == selectedGroup })?.1 ?? []
  }
  var body: some View {
    VStack(spacing: 13) {
      PanelHeader(title: "效果器", subtitle: store.selected?.name ?? L("添加效果将新建 FX 图层")) {
        store.showEffects = false
      }
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField(L("查找效果"), text: $search).textFieldStyle(.plain)
      }
      .font(.system(size: 12)).padding(9).background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
      HStack(alignment: .top, spacing: 12) {
        ScrollView(.vertical) {
          VStack(spacing: 4) {
            ForEach(effectGroups.map { $0.0 }, id: \.self) { group in
              Button {
                withAnimation(.smooth(duration: 0.18)) { selectedGroup = group }
              } label: {
                Text(L(group)).font(.system(size: 11, weight: selectedGroup == group ? .semibold : .regular))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 10).frame(minHeight:36).contentShape(Rectangle())
                  .foregroundStyle(selectedGroup == group ? store.accent : .secondary)
                  .background(selectedGroup == group ? store.accent.opacity(0.13) : .clear,
                              in: RoundedRectangle(cornerRadius: 9))
              }.buttonStyle(.plain).contentShape(Rectangle())
            }.id(AppLocalization.language)
            if !store.extensions.isEmpty {
              Button {
                withAnimation(.smooth(duration: 0.18)) { selectedGroup = "扩展" }
              } label: {
                Text(L("扩展")).font(.system(size: 11, weight: selectedGroup == "扩展" ? .semibold : .regular))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 10).frame(minHeight:36).contentShape(Rectangle())
                  .foregroundStyle(selectedGroup == "扩展" ? store.accent : .secondary)
                  .background(selectedGroup == "扩展" ? store.accent.opacity(0.13) : .clear,
                              in: RoundedRectangle(cornerRadius: 9))
              }.buttonStyle(.plain).contentShape(Rectangle())
            }
          }
        }.frame(width: 116).pageScrollStyle(.vertical)
        Divider()
        ScrollView {
          VStack(spacing: 4) {
            Text(L(selectedGroup)).font(.system(size: 12, weight: .semibold))
              .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            if selectedGroup == "扩展" {
              ForEach(store.extensions.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { plugin in
                effectRow(plugin.name, subtitle: "已安装效果", symbol: "puzzlepiece.extension") {
                  store.addEffect(.custom, extension: plugin)
                }
              }.id(AppLocalization.language)
            } else {
              ForEach(currentEffects.filter { search.isEmpty || L($0.title).localizedCaseInsensitiveContains(search) }, id: \.self) { kind in
                effectRow(kind.title, subtitle: kind.subtitle, symbol: kind.symbol) { store.addEffect(kind) }
              }.id(AppLocalization.language)
            }
          }
        }.pageScrollStyle(.vertical)
      }
      Text(L("效果独立保存，随时修改或停用。"))
        .font(.system(size: 10)).foregroundStyle(.secondary).frame(
          maxWidth: .infinity, alignment: .leading)
    }.padding(16).glassSurface(20)
  }
  func effectRow(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.secondary).frame(
          width: 23)
        VStack(alignment: .leading, spacing: 3) {
          Text(L(title)).font(.system(size: 12, weight: .medium))
          Text(L(subtitle)).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(.secondary)
      }.padding(.vertical, 9).padding(.horizontal, 7).contentShape(Rectangle())
    }.buttonStyle(.plain).contentShape(Rectangle())
  }
}

struct InspectorPanel: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @State private var draggingEffect: UUID?
  @State private var dropTargetEffect: UUID?
  @State private var effectDragBefore:[ImageEffect]?
  @State private var effectDragLayer:UUID?
  @State private var effectDragProject:UUID?
  @State private var centerPicker = false
  @State private var centerReferences: Set<UUID> = []
  var activeEffect: ImageEffect? {
    if case .effect(let id) = store.inspector {
      return store.selected?.effects.first { $0.id == id }
    }
    return nil
  }
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if !store.refiningSelection {
      ScrollView {
        VStack(spacing: 9) {
          if let title = store.selected?.specialInspectorTitle {
            contextButton(title, symbol: store.selected?.symbol ?? "slider.horizontal.3", selected: store.inspector == .special) {
              store.inspector = .special;store.editingMask = false
            }
          }
          contextButton("基础", symbol: "gearshape", selected: store.inspector == .base) {
            store.inspector = .base
            store.editingMask = false
          }
          if let layer = store.selected {
            if layer.maskAssetID != nil {
              contextButton("蒙版", symbol: "rectangle.lefthalf.inset.filled", selected: store.inspector == .mask) {
                store.selectMask(layer.id)
              }
            }
            ForEach(layer.effects) { effect in
              contextButton(
                effect.name, symbol: effect.kind.symbol,
                selected: store.inspector == .effect(effect.id), dim: !effect.enabled
              ) { store.inspector = .effect(effect.id) }
              .overlay(LayerDragSurface(id:effect.id,name:L(effect.name),begin:{
                effectDragBefore = store.selected?.effects;effectDragLayer = store.selected?.id;effectDragProject = store.document.id
                draggingEffect = effect.id;dropTargetEffect = nil
                store.beginTransaction("调整效果顺序")
              },select:{store.inspector = .effect(effect.id)},cancel:{finishEffectDrag(cancel:true)},accessibilityPrefix:"调整或拖动效果："))
              .background(LayerDropSurface(priority:4,hover:{point in
                guard let source = draggingEffect,source != effect.id else {return}
                dropTargetEffect = effect.id
                withAnimation(reduceMotion ? nil : .smooth(duration:0.2)) {store.moveInspectorEffect(source,relativeTo:effect.id,after:point.y >= 0.5)}
              },drop:{finishEffectDrag(cancel:false)}))
              .overlay(alignment: .top) {
                if dropTargetEffect == effect.id, draggingEffect != effect.id {
                  Capsule().fill(store.accent).frame(height: 2).padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
              }
              .opacity(draggingEffect == effect.id ? 0.62 : 1)
              .animation(.smooth(duration: 0.32), value: store.selected?.effects.map(\.id))
              .animation(.smooth(duration: 0.2), value: dropTargetEffect)
              .contextMenu {
                Button(L(effect.enabled ? "停用" : "启用")) {
                  store.updateEffect(effect.id, "切换效果") { $0.enabled.toggle() }
                }
                Button(L("复制")) {
                  store.updateSelected("复制效果") { l in
                    var copy = effect
                    copy.id = UUID()
                    l.effects.append(copy)
                  }
                }
                Button(L("上移")) { store.reorderEffect(effect.id, delta: -1) }
                Button(L("下移")) { store.reorderEffect(effect.id, delta: 1) }
                Button(L("重置")) {
                  store.updateEffect(effect.id, "重置效果") { e in
                    var reset = ImageEffect(e.kind)
                    reset.id = e.id
                    reset.filterName = e.filterName
                    e = reset
                  }
                }
                Divider()
                Button(L("删除"), role: .destructive) { store.removeEffect(effect.id) }
              }
            }.id(AppLocalization.language)
          }
          IconButton(symbol: "plus", label: "添加效果") { store.showEffects = true }.padding(.top, 4)
        }.padding(.top,18).padding(.bottom,14)
      }.frame(width: 76, height: min(700, CGFloat((store.selected?.effects.count ?? 0) + (store.selected?.specialInspectorTitle == nil ? 0 : 1) + (store.selected?.maskAssetID == nil ? 0 : 1))*83 + 135)).pageScrollStyle(.vertical)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
      }
      VStack(spacing: 18) {
        PanelHeader(title: store.refiningSelection ? "调整选择" : store.inspector == .mask ? "蒙版" : activeEffect?.name ?? (store.inspector == .special ? store.selected?.specialInspectorTitle ?? "基础" : "基础"), subtitle: store.selected?.name) {
          store.showInspector = false
        }
        ScrollView {
          VStack(spacing: 21) {
            if store.refiningSelection {
              RefineSelectionInspector(store: store)
            } else if store.inspector == .mask, let layer = store.selected {
              MaskInspector(store: store, layer: layer)
            } else if let effect = activeEffect {
              effectControls(effect)
            } else if let layer = store.selected {
              if store.inspector == .special {specialControls(layer)} else {baseControls(layer)}
            } else {
              ContentUnavailableView(
                L("选择内容"), systemImage: "cursorarrow", description: Text(L("选择图层后，调整它的位置、尺寸与外观。")))
            }
          }.padding(.bottom, 8)
        }.pageScrollStyle(.vertical)
      }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).glassSurface(22)
    }.animation(reduceMotion ? nil : .smooth(duration: 0.24), value: store.refiningSelection)
  }
  func contextButton(
    _ title: String, symbol: String, selected: Bool, dim: Bool = false, action: @escaping () -> Void
  ) -> some View {
    InspectorSwitcherButton(title:title,symbol:symbol,selected:selected,dim:dim,action:action)
  }
  func finishEffectDrag(cancel:Bool) {
    guard draggingEffect != nil else {return}
    if cancel,effectDragProject == store.document.id,effectDragLayer == store.selected?.id,let before = effectDragBefore {
      store.updateSelected("取消效果排序") {$0.effects = before}
    }
    store.endTransaction();draggingEffect = nil;dropTargetEffect = nil;effectDragBefore = nil;effectDragLayer = nil;effectDragProject = nil
  }
  @ViewBuilder func baseControls(_ layer: ImageLayer) -> some View {
    if layer.locked {
      HStack {
        Label(L("对象已锁定"), systemImage: "lock").font(.system(size: 12))
        Spacer()
        Button(L("解锁")) { store.toggleLock(layer.id) }
      }
    }
    if layer.kind != .group {
      HStack(alignment: .top, spacing: 12) {
        VStack(spacing: 8) {
          SectionCaption(title: "位置").frame(height:24)
          NumericField(store: store, title: "X", value: layer.x) { v in
            store.updateSelected("调整位置") { $0.x = v }
          }
          NumericField(store: store, title: "Y", value: layer.y) { v in
            store.updateSelected("调整位置") { $0.y = v }
          }
        }
        VStack(spacing: 8) {
          HStack {
            SectionCaption(title: "尺寸")
            IconButton(
              symbol: layer.aspectLocked == true ? "lock.fill" : "lock.open", label: "固定宽高比",
              selected: layer.aspectLocked == true, size: 24
            ) { store.updateSelected("固定比例") { $0.aspectLocked = !($0.aspectLocked ?? false) } }
          }.frame(height:24)
          NumericField(store: store, title: "W", value: layer.width, range: 1...16384) { v in
            store.resizeSelectedFromCenter(width:v)
          }
          NumericField(store: store, title: "H", value: layer.height, range: 1...16384) { v in
            store.resizeSelectedFromCenter(height:v)
          }
        }
      }.disabled(layer.locked)
      HStack(spacing: 8) {
        Button(L("居中画布")) {store.centerSelected()}.buttonStyle(.bordered)
        Button(L("对照居中")) {centerReferences = [];centerPicker = true}.buttonStyle(.bordered)
          .popover(isPresented:$centerPicker) {
            VStack(alignment:.leading,spacing:14) {
              Text(L("选择对照图层")).font(.headline)
              ScrollView {
                VStack(alignment:.leading,spacing:10) {
                  ForEach(store.document.layers.filter {!store.descendants(of:store.selectedIDs).contains($0.id) && $0.kind != .adjustment}) {other in
                    Toggle(other.name,isOn:Binding(get:{centerReferences.contains(other.id)},set:{v in if v {centerReferences.insert(other.id)} else {centerReferences.remove(other.id)}}))
                  }.id(AppLocalization.language)
                }
              }.frame(maxHeight:260).pageScrollStyle(.vertical)
              HStack {Button(L("取消")) {centerPicker = false};Spacer();Button(L("居中")) {store.centerSelected(relativeTo:store.descendants(of:centerReferences));centerPicker = false}.buttonStyle(.borderedProminent).disabled(centerReferences.isEmpty)}
            }.padding(18).frame(width:270)
          }
      }.font(.system(size: 12)).disabled(layer.locked)
      ParameterSlider(
        store: store, title: "旋转", value: layer.rotation, range: -180...180, unit: "°", digits: 1
      ) { v in store.updateSelected("旋转对象") { $0.rotation = v } }.disabled(layer.locked)
    }
    ParameterSlider(
      store: store, title: "不透明度", value: layer.opacity, range: 0...1, unit: "%", percentage: true
    ) { v in store.updateSelected("调整不透明度") { $0.opacity = v } }
    if layer.kind != .group {
      Picker(
        L("混合模式"),
        selection: Binding(
          get: { layer.blend }, set: { v in store.updateSelected("调整混合模式") { $0.blend = v } })
      ) {
        ForEach(BlendMode.groups,id:\.0) {group in
          Section(L(group.0)) {ForEach(group.1,id:\.self) {Text(L($0 == .luminosity ? "blend.luminosity" : $0.rawValue)).tag($0)}.id(AppLocalization.language)}
        }.id(AppLocalization.language)
      }.id(AppLocalization.language).font(.system(size: 12))
    }
    if layer.maskAssetID != nil {
      Divider()
      Toggle(
        L("启用蒙版"),
        isOn: Binding(
          get: { layer.maskEnabled },
          set: { v in store.updateSelected("切换蒙版") { $0.maskEnabled = v } })
      ).font(.system(size: 12))
      Button(L("移除蒙版")) { store.removeMask(layer.id) }.font(
        .system(size: 12))
    }
    if layer.kind == .paint || layer.kind == .raster {
      Text(L("原始内容保留 · {0} 次描边", layer.strokes.count)).font(.system(size: 10)).foregroundStyle(
        .secondary
      ).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  @ViewBuilder func specialControls(_ layer:ImageLayer) -> some View {
    if layer.isPath {
      Text(L("路径保留锚点与曲线，可用于选区、描边、填充和蒙版。")).font(.system(size:12)).foregroundStyle(.secondary)
      Button(L("路径转选区")) {store.pathToSelection()}
      Button(L("画笔描边路径")) {store.strokePath()}
      Button(L("修饰工具沿路径")) {store.beginPathRetouch(layer.id)}
      Button(L("填充为形状")) {store.fillPath()}
      Button(L("用于下方图层蒙版")) {store.pathAsMask()}
    } else {
    if layer.kind == .gradient, layer.gradient != nil {
      GradientInspector(store: store, layer: layer)
    }
    if layer.kind == .text {
      TextProperties(store: store, layer: layer)
    }
    if layer.kind == .shape {
      HStack {
        SectionCaption(title: "填充颜色")
        ColorWell(store: store, layer: true)
      }
      if ["line", "freePath", "pen", "roundedRectangle"].contains(layer.shape) {
        ParameterSlider(
          store: store, title: layer.shape == "roundedRectangle" ? "圆角" : "线宽",
          value: layer.cornerRadius, range: 0...200, unit: " px"
        ) { v in store.updateSelected("调整形状") { $0.cornerRadius = v } }
      }
      if ["star", "polygon"].contains(layer.shape) {
        Stepper("边数 \(layer.shapeSides ?? 6)", value: Binding(
          get: { layer.shapeSides ?? 6 }, set: { v in store.updateSelected("调整边数") { $0.shapeSides = v } }), in: 3...24)
      }
    }
    }
  }
  @ViewBuilder func effectControls(_ effect: ImageEffect) -> some View {
    Toggle(
      L("启用效果"),
      isOn: Binding(
        get: { effect.enabled },
        set: { v in store.updateEffect(effect.id, "切换效果") { $0.enabled = v } })
    ).font(.system(size: 12))
    AdvancedEffectControls(store: store, effect: effect)
    Text(L("处理顺序沿左侧从上到下执行。\n右键效果按钮可复制、重置或停用。"))
      .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).frame(
        maxWidth: .infinity, alignment: .leading)
  }
  func effectSlider(
    _ effect: ImageEffect, title: String, value: Double, range: ClosedRange<Double>,
    unit: String = "", digits: Int = 0, percentage: Bool = false,
    set: @escaping (inout ImageEffect, Double) -> Void
  ) -> some View {
    ParameterSlider(
      store: store, title: title, value: value, range: range, unit: unit, digits: digits,
      percentage: percentage
    ) { v in store.updateEffect(effect.id, "调整\(title)") { set(&$0, v) } }
  }
}

struct LayerReorderDelegate: DropDelegate {
  var store: EditorStore
  var target: UUID
  @Binding var dragging: UUID?
  @Binding var dropTarget: UUID?
  @Binding var draggingMask: UUID?
  func dropEntered(info: DropInfo) {
    guard let source = dragging, source != target else { return }
    dropTarget = target
    let ids = store.document.layers.map(\.id)
    let after = (ids.firstIndex(of:source) ?? 0)<(ids.firstIndex(of:target) ?? 0)
    withAnimation(.smooth(duration: 0.22)) { store.moveLayer(source, before: target,after:after) }
  }
  func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
  func performDrop(info: DropInfo) -> Bool {
    if let source = draggingMask {
      if let id = store.detachMask(source) { store.moveLayer(id,before:target) }
      draggingMask = nil
    }
    dragging = nil
    withAnimation(.smooth(duration: 0.22)) { dropTarget = nil }
    store.endTransaction()
    return true
  }
  func dropExited(info: DropInfo) { if dropTarget == target { dropTarget = nil } }
}

struct EffectReorderDelegate: DropDelegate {
  var store: EditorStore
  var target: UUID
  @Binding var dragging: UUID?
  @Binding var dropTarget: UUID?
  func dropEntered(info: DropInfo) {
    guard let source = dragging, source != target, let effects = store.selected?.effects,
      let a = effects.firstIndex(where: { $0.id == source }), let b = effects.firstIndex(where: { $0.id == target }) else { return }
    dropTarget = target
    withAnimation(.smooth(duration: 0.28)) { store.reorderEffect(source, delta: b - a) }
  }
  func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
  func performDrop(info: DropInfo) -> Bool {
    dragging = nil
    withAnimation(.smooth(duration: 0.24)) { dropTarget = nil }
    store.endTransaction()
    return true
  }
  func dropExited(info: DropInfo) { if dropTarget == target { dropTarget = nil } }
}
