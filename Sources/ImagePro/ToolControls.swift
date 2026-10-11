import AppKit
import SwiftUI

struct ToolQuickControls: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var brushLike: Bool { [.brush, .eraser, .clone, .retouch, .dodge, .detail].contains(store.interactionTool) }
  var body: some View {
    HStack(spacing: 16) {
      if store.compositorToolID != nil {
        CompositorToolControls(store:store)
      } else if brushLike {
        Button {
          store.brushPopover.toggle()
        } label: {
          Label(L("笔头"), systemImage: "circle.dotted").font(.system(size: 12))
        }.buttonStyle(.plain)
          .popover(isPresented: $store.brushPopover, arrowEdge: .bottom) {
            BrushTipPicker(store: store).frame(width: 370).padding(20)
          }
        ParameterSlider(
          store: store, title: "大小", value: store.brushSize, range: 1...1000, unit: " px"
        ) { store.brushSize = $0 }
        ParameterSlider(
          store: store, title: "硬度", value: store.brushHardness, range: 0...1, unit: "%",
          percentage: true
        ) { store.brushHardness = $0 }
        ParameterSlider(
          store: store, title: "不透明度", value: store.brushOpacity, range: 0...1, unit: "%",
          percentage: true
        ) { store.brushOpacity = $0 }
        ParameterSlider(
          store: store, title: "流量", value: store.brushFlow, range: 0.01...1, unit: "%",
          percentage: true
        ) { store.brushFlow = $0 }
        if store.editingMask {
          Picker(L("蒙版"), selection: $store.maskReveal) { Text(L("隐藏")).tag(false); Text(L("显示")).tag(true) }.id(AppLocalization.language)
            .labelsHidden().frame(width: 80)
        } else if store.interactionTool == .brush { ColorWell(store: store) }
      } else if store.interactionTool == .text {
        Text(L(store.branch.title)).font(.system(size:13,weight:.medium))
        Text(L("点击建立文字 · 选中后在调节器编辑内容与排版")).font(.system(size:12)).foregroundStyle(.secondary)
        ColorWell(store:store,layer:store.selected?.kind == .text)
        Spacer()
      } else if store.interactionTool == .selection {
        Picker(L("模式"), selection: $store.selectionMode) {
          Text(L("新建")).tag("new")
          Text(L("添加")).tag("add")
          Text(L("减去")).tag("subtract")
          Text(L("相交")).tag("intersect")
        }.id(AppLocalization.language).labelsHidden().frame(width: 130)
        if store.branch.id == "smart" {
          ParameterSlider(store: store, title: "大小", value: store.brushSize, range: 1...500, unit: " px") { store.brushSize = $0 }
          Button(L("选择主体")) { store.selectSubject() }.disabled(store.busy)
        }
        ParameterSlider(
          store: store, title: store.branch.id == "colorRange" ? "颜色范围" : "容差", value: store.selectionTolerance, range: 0.005...0.6, unit: "%",
          percentage: true
        ) {
          store.selectionTolerance = $0
          if store.branch.id == "colorRange", let p = store.colorRangeSample {
            store.selectColor(at: p, contiguous: false, mode: "new")
          }
        }
        ParameterSlider(
          store: store, title: "羽化", value: store.selectionFeather, range: 0...100, unit: " px"
        ) { store.selectionFeather = $0 }
        Button(L("调整选择")) { withAnimation(.smooth) { store.beginRefiningSelection() } }.disabled(store.selection == nil)
        Button(L("反选")) { store.invertSelection() }.disabled(store.selection == nil)
        IconButton(symbol: "xmark", label: "取消选区") { store.deselect() }.disabled(
          store.selection == nil)
      } else if store.interactionTool == .crop {
        Text(L("裁剪")).font(.system(size: 13, weight: .medium))
        Picker(L("比例"), selection: $store.cropRatio) {
          ForEach(["free", "1:1", "4:3", "3:2", "16:9", "9:16"], id: \.self) {
            Text(L($0 == "free" ? "自由比例" : $0)).tag($0)
          }.id(AppLocalization.language)
        }.id(AppLocalization.language).labelsHidden().frame(width: 130).onChange(of: store.cropRatio) { _, _ in store.constrainCropRatio() }
        Text(L("拖动角点 · 回车应用")).font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer()
        Button(L("应用")) { store.cropToSelection() }.disabled(store.selection == nil)
        Button(L("取消")) { store.deselect() }
      } else if store.interactionTool == .shape {
        Text(L(store.branch.title)).font(.system(size: 13, weight: .medium))
        if store.branch.id == "custom" {
          Button(L("选择形状")) { store.shapePopover.toggle() }.popover(
            isPresented: $store.shapePopover, arrowEdge: .bottom
          ) { ShapeGallery(store: store).frame(width: 420, height: 400).padding(18) }
        }
        if ["polygon", "star"].contains(store.branch.id) {
          Stepper("边数 \(store.shapeSides)", value: $store.shapeSides, in: 3...24).font(
            .system(size: 12)
          ).frame(width: 120)
        }
        ColorWell(store: store)
        Text(L("⇧ 约束比例 · ⌥ 从中心 · 空格重新摆放")).font(.system(size: 11)).foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
      } else {
        VStack(alignment: .leading, spacing: 4) {
          Text(L(store.branch.title)).font(.system(size: 13, weight: .medium))
          Text(L(hint)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if [.fill, .gradient, .eyedropper].contains(store.interactionTool) { ColorWell(store: store) }
        if store.interactionTool == .move {
          if store.transformActive {
            Button(L("取消")) { store.finishTransform(cancel: true) }
            Button(L("应用")) { store.finishTransform() }
          }
          Text(L("{0}%", Int(store.zoom*100))).font(.system(size: 12)).monospacedDigit()
          Button(L("适合窗口")) { store.fitCanvas() }
        }
      }
    }
  }
  var hint: String {
    switch store.interactionTool {
    case .move: return "拖动移动 · 八个控制点缩放 · 顶部控制点旋转 · ⌘T"
    case .clone: return "⌥ 点击设置来源，再涂抹"
    case .text: return "点击添加或选择文字 · 在调节器编辑内容与排版"
    case .gradient: return "拖动定义方向与距离"
    case .path: return store.branch.id == "pen" ? "拖动创建曲线 · ⌥ 独立方向柄 · 双击切换节点 · 回车完成" : "拖动画自由路径"
    case .hand: return "拖动画布 · 空格临时抓手"
    case .zoom: return "滚轮缩放 · ⌘ + / −"
    default: return "在画布上操作"
    }
  }
}
struct BrushTipPicker: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(L("笔头")).font(.system(size: 18, weight: .semibold))
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
          ForEach(BrushTip.all) { tip in
            Button {
              store.brushDynamics.tip = tip.id
            } label: {
              VStack(spacing: 8) {
                Image(systemName: tip.symbol).font(.system(size: 22))
                Text(L(tip.name)).font(.system(size: 11))
              }.frame(maxWidth: .infinity).frame(height: 64).background(
                store.accent.opacity(store.brushDynamics.tip == tip.id ? 0.15 : 0.04),
                in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
          }.id(AppLocalization.language)
        }
      }.frame(maxHeight: 350).pageScrollStyle(.vertical)
      DisclosureGroup(L("笔刷动态")) {
        ScrollView {
          VStack(spacing: 14) {
            ForEach(ToolMoreControls(store: store).brushFields, id: \.0) { f in
              ParameterSlider(store: store, title: f.0, value: store.brushDynamics[keyPath: f.1], range: f.2, digits: 2) {
                store.brushDynamics[keyPath: f.1] = $0
              }
            }.id(AppLocalization.language)
            Toggle(L("数位笔压力"), isOn: $store.brushDynamics.pressure)
          }.padding(.top, 12)
        }.frame(height: 220).pageScrollStyle(.vertical)
      }
      Text(L("笔头与水彩、油画、喷枪等笔触模式组合使用。")).font(.system(size: 12)).foregroundStyle(.secondary)
    }
  }
}
struct ShapeGallery: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L("自定义形状")).font(.system(size: 18, weight: .semibold))
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
          ForEach(ShapePreset.all) { shape in
            Button {
              store.customShape = shape.id
              if shape.id == "star" { store.shapeSides = 5 }
              store.shapePopover = false
            } label: {
              VStack(spacing: 8) {
                ShapeThumbnail(name: shape.id, sides: shape.id == "star" ? 5 : 6)
                  .frame(width: 40, height: 30)
                Text(L(shape.name)).font(.system(size: 11))
              }.frame(maxWidth: .infinity).frame(height: 70).background(
                store.accent.opacity(store.customShape == shape.id ? 0.14 : 0.035),
                in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
          }.id(AppLocalization.language)
        }
      }.pageScrollStyle(.vertical)
    }
  }
}
struct ToolMoreControls: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  func dynamics(_ key: WritableKeyPath<BrushDynamics, Double>) -> Binding<Double> {
    Binding(
      get: { store.brushDynamics[keyPath: key] }, set: { store.brushDynamics[keyPath: key] = $0 })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(L(store.branch.title + " · 更多设置")).font(.system(size: 17, weight: .semibold))
        Spacer()
        IconButton(symbol: "xmark", label: "关闭", size: 24) { store.moreToolPopover = false }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 19) {
          if store.compositorToolID != nil {
            CompositorToolOptions(store:store)
          } else if [.brush, .eraser, .clone, .retouch, .dodge, .detail].contains(store.interactionTool) {
            BrushTipPicker(store: store)
            ForEach(brushFields, id: \.0) { field in
              ParameterSlider(
                store: store, title: field.0, value: store.brushDynamics[keyPath: field.1],
                range: field.2, digits: 2
              ) { store.brushDynamics[keyPath: field.1] = $0 }
            }.id(AppLocalization.language)
            Toggle(L("使用数位笔压力"), isOn: $store.brushDynamics.pressure)
            Text(L("水彩使用透明叠色和湿边；油画使用鬃毛条纹；喷枪使用柔软雾化；马克笔使用扁头叠色。")).font(.system(size: 12))
              .foregroundStyle(.secondary).lineSpacing(4)
          } else if store.interactionTool == .text, let layer = store.selected, layer.kind == .text {
            TextProperties(store: store, layer: layer)
          } else if store.interactionTool == .selection {
            Text(L("⇧ 添加 · ⌥ 减去 · ⇧⌥ 相交\n拖动选区内部移动内容，⌘J 提取到新图层，Delete 删除选区内容。")).font(.system(size: 13))
              .lineSpacing(6)
            Button(L("选区 → 图层蒙版")) { store.maskFromSelection() }.disabled(store.selection == nil)
            Button(L("提取到新图层  ⌘J")) { store.extractSelection() }.disabled(store.selection == nil)
            Button(L("删除选区内容")) { store.deleteSelection() }.disabled(store.selection == nil)
            Button(L("反选")) { store.invertSelection() }.disabled(store.selection == nil)
          } else if store.interactionTool == .shape {
            ShapeGallery(store: store)
            if let layer = store.selected, layer.kind == .shape {
              ParameterSlider(
                store: store, title: "圆角 / 线宽", value: layer.cornerRadius, range: 0...200,
                unit: " px"
              ) { v in store.updateSelected("调整形状") { $0.cornerRadius = v } }
            }
          } else if store.interactionTool == .gradient {
            ModernColorButton(title:"终点颜色",color:$store.secondaryColor)
          } else if store.interactionTool == .crop {
            Text(L("角点调整边界，⇧ 保持比例；比例在底部选择。回车确认，Esc 取消。原始图像始终保留。")).font(.system(size: 13)).lineSpacing(
              5)
          } else {
            Button(L("适合窗口")) { store.fitCanvas() }
            Toggle(L("显示网格"), isOn: $store.showGrid)
            Text(L("滚轮缩放画布，⇧ 滚轮平移；空格拖动抓手。")).font(.system(size: 13)).foregroundStyle(.secondary)
          }
        }.padding(.bottom, 12)
      }.pageScrollStyle(.vertical)
    }.padding(22)
  }
  var brushFields: [(String, WritableKeyPath<BrushDynamics, Double>, ClosedRange<Double>)] {
    [
      ("间距", \.spacing, 0.01...1), ("角度", \.angle, -180...180), ("圆度", \.roundness, 0.05...1),
      ("散布", \.scatter, 0...2), ("大小抖动", \.sizeJitter, 0...1), ("不透明度抖动", \.opacityJitter, 0...1),
      ("湿度", \.wetness, 0...1), ("纹理", \.texture, 0...1), ("平滑", \.smoothing, 0...0.9),
    ]
  }
}
struct FontFamilyButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var layer: ImageLayer
  @ObservedObject var catalog = FontCatalog.shared
  @State private var showing = false
  @State private var search = ""
  var body: some View {
    Button {
      catalog.reload()
      showing.toggle()
    } label: {
      Text(NSFont(name: layer.fontName, size: 13)?.familyName ?? layer.fontName).font(
        .system(size: 12)
      ).lineLimit(1).frame(maxWidth: 150)
    }.buttonStyle(.plain).popover(isPresented: $showing, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 14) {
        TextField(L("搜索所有已安装字体"), text: $search).textFieldStyle(.roundedBorder)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(
              catalog.families.filter {
                search.isEmpty || $0.localizedCaseInsensitiveContains(search)
              }, id: \.self
            ) { family in
              Button {
                if let font = catalog.members(family).first {
                  store.updateSelected("调整字体") { $0.fontName = font.name }
                }
                showing = false
              } label: {
                HStack {
                  Text(family).font(
                    .custom(catalog.members(family).first?.name ?? "Helvetica", size: 15))
                  Spacer()
                }.padding(9).contentShape(Rectangle())
              }.buttonStyle(.plain)
            }.id(AppLocalization.language)
          }
        }.pageScrollStyle(.vertical)
        HStack {
          Text(L("{0} 个字体家族", catalog.families.count)).font(.system(size: 11)).foregroundStyle(
            .secondary)
          Spacer()
          Button(L("加载字体…")) { do { try catalog.importFonts() } catch { store.fail(error) } }
        }
      }.padding(16).frame(width: 350, height: 440)
    }
  }
}
struct TextProperties: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var layer: ImageLayer
  @FocusState private var textFocused: Bool
  var style: TextStyle { layer.textStyle ?? TextStyle() }
  func flag(_ key: WritableKeyPath<TextStyle, Bool>) -> Binding<Bool> {
    Binding(get: { style[keyPath: key] }, set: { v in update { $0[keyPath: key] = v } })
  }
  func update(_ operation: @escaping (inout TextStyle) -> Void) {
    store.updateSelected("调整文字排版") { l in
      var s = l.textStyle ?? TextStyle()
      operation(&s)
      l.textStyle = s
    }
  }
  func typographyButton(_ title: String, symbol: String, key: WritableKeyPath<TextStyle,Bool>) -> some View {
    Button {update {$0[keyPath:key].toggle()}} label: {
      Image(systemName:symbol).frame(maxWidth:.infinity).frame(height:32)
        .background(Color.primary.opacity(style[keyPath:key] ? 0.15 : 0.04),in:RoundedRectangle(cornerRadius:8))
    }.buttonStyle(.plain).help(L(title)).accessibilityLabel(L(title)).accessibilityAddTraits(style[keyPath:key] ? .isSelected : [])
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        SectionCaption(title:"文本内容")
        TextEditor(text: Binding(get: {layer.text},set: {v in store.updateSelected("编辑文字") {$0.text = v;$0.textRuns = nil;$0.importedTextAppearance = nil}}))
          .font(.system(size:14)).scrollContentBackground(.hidden).padding(8).frame(height:86)
          .background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:10))
          .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.primary.opacity(0.08)))
          .focused($textFocused)
      }
      Divider()
      HStack {
        Text(L("type.font"))
        Spacer()
        FontFamilyButton(store: store, layer: layer)
      }
      let family = NSFont(name: layer.fontName, size: 12)?.familyName ?? "Helvetica"
      Picker(
        L("字重 / 字体样式"),
        selection: Binding(
          get: { layer.fontName }, set: { v in store.updateSelected("调整字体") { $0.fontName = v } })
      ) {
        ForEach(FontCatalog.shared.members(family), id: \.name) { member in
          Text(member.face).tag(member.name)
        }.id(AppLocalization.language)
      }.id(AppLocalization.language)
      NumericField(store: store, title: "字号", value: layer.fontSize, suffix: "pt", range: 1...1024)
      { v in store.updateSelected("调整字号") { $0.fontSize = v } }
      HStack(spacing: 8) {
        typographyButton("粗体",symbol:"bold",key: \.bold)
        typographyButton("斜体",symbol:"italic",key: \.italic)
        typographyButton("下划线",symbol:"underline",key: \.underline)
        typographyButton("删除线",symbol:"strikethrough",key: \.strikethrough)
      }
      Divider()
      SectionCaption(title:"段落")
      HStack {
        Text(L("文字颜色"))
        Spacer()
        ColorWell(store: store, layer: true)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(L("对齐")).font(.system(size: 12)).foregroundStyle(.secondary)
        Picker(
          L("对齐"),
          selection: Binding(get: { style.alignment }, set: { v in update { $0.alignment = v } })
        ) {
          Text(L("左")).tag(0)
          Text(L("中")).tag(1)
          Text(L("右")).tag(2)
          Text(L("两端")).tag(3)
        }.id(AppLocalization.language).labelsHidden().pickerStyle(.segmented)
      }
      Picker(
        L("垂直对齐"),
        selection: Binding(
          get: { style.verticalAlignment }, set: { v in update { $0.verticalAlignment = v } })
      ) {
        Text(L("顶部")).tag(0)
        Text(L("居中")).tag(1)
        Text(L("底部")).tag(2)
      }.id(AppLocalization.language)
      Toggle(L("竖排文字"), isOn: flag(\.vertical))
      NumericField(
        store: store, title: "字距", value: style.tracking, suffix: "pt", range: -100...300
      ) { v in update { $0.tracking = v } }
      NumericField(store: store, title: "行高", value: style.lineHeight, suffix: "倍", range: 0.5...5)
      { v in update { $0.lineHeight = v } }
      NumericField(
        store: store, title: "段前", value: style.paragraphBefore, suffix: "pt", range: 0...1000
      ) { v in update { $0.paragraphBefore = v } }
      NumericField(
        store: store, title: "段后", value: style.paragraphAfter, suffix: "pt", range: 0...1000
      ) { v in update { $0.paragraphAfter = v } }

    }.font(.system(size: 13))
  }
}
