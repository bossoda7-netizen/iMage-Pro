import AppKit
import SwiftUI

struct ManagementSheet: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var kind: String
  @State private var category = ""
  @State private var newName = L("未命名")
  @State private var newWidth = 1920.0
  @State private var newHeight = 1080.0
  @State private var exportID = "png"
  @State private var quality = 0.92
  @State private var transparent = true
  @State private var licenseDocuments: [LicenseDocument]?
  @State private var licenseIndex = 0
  @State private var licensePage = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var fonts = FontCatalog.shared
  var title: String {
    [
      "settings": "设置", "project": "项目", "extensions": "扩展", "export": "导出", "new": "新建项目",
      "help": "使用指南", "licenses": "第三方许可",
    ][kind] ?? "关于 iMage Pro"
  }
  var sections: [(String, String)] {
    switch kind {
    case "settings":
      return [
        ("语言", "globe"), ("外观", "circle.lefthalf.filled"), ("画布", "rectangle"),
        ("性能", "speedometer"), ("字体", "a.square"), ("快捷键", "keyboard"),
      ]
    case "project":
      return [
        ("基本信息", "doc.text"), ("画布", "rectangle"), ("历史记录", "clock.arrow.circlepath"),
        ("资源", "photo.on.rectangle"),
      ]
    case "extensions": return [("我的扩展", "puzzlepiece.extension"), ("能力接口", "square.stack.3d.up")]
    default: return []
    }
  }
  var selectedCategory: String { category.isEmpty ? sections.first?.0 ?? "" : category }
  var body: some View {
    HStack(spacing: 0) {
      if !sections.isEmpty {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 10) {
            Image(
              systemName: kind == "project"
                ? "doc.richtext"
                : kind == "extensions" ? "puzzlepiece.extension.fill" : "gearshape.fill"
            ).font(.system(size: 26)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
              Text(L(title)).font(.system(size: 18, weight: .semibold))
              Text(kind == "project" ? store.document.name : "iMage Pro").font(.system(size: 11))
                .foregroundStyle(.secondary).lineLimit(1)
            }
          }.padding(.top, 14)
          VStack(spacing: 5) {
            ForEach(sections, id: \.0) { section in
              Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { category = section.0 }
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: section.1).frame(width: 20)
                  Text(L(section.0))
                  Spacer()
                }.font(.system(size: 13)).padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 40)
                  .foregroundStyle(.primary)
                  .background(
                    selectedCategory == section.0 ? Color.primary.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
                  .contentShape(Rectangle())
              }.buttonStyle(.plain)
            }.id(AppLocalization.language)
          }
          Spacer()
        }.padding(18).frame(width: 205).background(Color.primary.opacity(0.025))
        Divider()
      }
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(L(sections.isEmpty ? title : selectedCategory)).font(
              .system(size: 22, weight: .semibold))
            if kind == "export" {
              Text(store.document.name).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          Spacer()
          if kind != "export" {
            IconButton(symbol: "xmark", label: "关闭" + title) { store.sheet = nil }
          }
        }.padding(.horizontal, 26).padding(.vertical, 20)
          .glassSurface(0, attached: true)
        Group {
          switch kind {
          case "settings": settings
          case "project": project
          case "extensions": extensions
          case "export": export
          case "new": newProject
          case "help": help
          case "licenses": licenses
          default: about
          }
        }.scrollContentBackground(.hidden)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }.tint(store.accent)
      .frame(width: kind == "export" ? 850 : sections.isEmpty ? 710 : 850, height: 625)
      .background(ManagementWindowMaterial())
      .presentationBackground(.clear)
      .onExitCommand { store.sheet = nil }
      .onAppear { if kind == "settings" { fonts.reload() } }
  }
  var settings: some View {
    Form {
      switch selectedCategory {
      case "语言":
        Section {
          Picker(L("应用语言"), selection: $store.language) {
            ForEach(AppLanguage.allCases) { language in
              Text(verbatim: language.nativeName).tag(language)
            }.id(AppLocalization.language)
          }.id(AppLocalization.language).pickerStyle(.menu)
        } header: { Text(L("语言")) }
        footer: { Text(L("立即应用，无需重新启动。项目名称和文字内容保持原样。")) }
      case "外观":
        Section {
          AppearanceChoices(store: store)
          ThemeColorChoices(store: store)
        } header: {
          Text(L("外观"))
        } footer: {
          Text(L("遵循 macOS 的减少透明度和减少动态效果设置。"))
        }
      case "画布":
        Section(L("显示")) {
          Toggle(L("显示网格"), isOn: $store.showGrid)
          Toggle(L("圆角画布"), isOn: Binding(get: { store.roundedCanvas }, set: { store.roundedCanvas = $0; UserDefaults.standard.set($0, forKey: "roundedCanvas") }))
          Button(L("适合窗口")) { store.fitCanvas() }
        }
        Section {
          LabeledContent(L("滚轮"), value: L("缩放画布"))
          LabeledContent(L("⇧ 滚轮"), value: L("平移画布"))
          LabeledContent(L("空格拖动"), value: L("临时抓手"))
        }
      case "性能":
        Section(L("渲染")) {
          LabeledContent(L("引擎"), value: L("Core Image · GPU"))
          LabeledContent(L("交互"), value: L("缓存图层 · 后台效果合成"))
          Button(L("清理渲染缓存")) {
            store.renderer.clearLayerCache()
            store.requestRender()
          }
        }
        Section(L("历史与恢复")) {
          Picker(
            L("历史容量"),
            selection: Binding(
              get: {
                UserDefaults.standard.integer(forKey: "historyLimit") == 0
                  ? 200 : UserDefaults.standard.integer(forKey: "historyLimit")
              }, set: { UserDefaults.standard.set($0, forKey: "historyLimit") })
          ) {
            Text(L("50 步")).tag(50)
            Text(L("200 步")).tag(200)
            Text(L("1000 步")).tag(1000)
          }.id(AppLocalization.language)
          LabeledContent(L("自动恢复副本"), value: L("每 25 秒"))
        }
      case "字体":
        Section(L("本机字体")) {
          LabeledContent(L("已安装字体家族"), value: L("{0}", fonts.families.count))
          Button(L("重新扫描字体")) { fonts.reload() }
          Button(L("加载 OTF / TTF / TTC 字体…")) {
            do { try fonts.importFonts() } catch { store.fail(error) }
          }
        }
        Section {
          Text(
            L("应用已内置思源黑体常规体（Source Han Sans SC）。也可以加载阿里巴巴普惠体等官方字体文件。字体加载后自动出现在文字工具的字体列表。分享项目时，接收方需要安装相同字体。")
          )
          .font(.system(size: 12)).foregroundStyle(.secondary)
        }
      default:
        Section(L("常用快捷键")) {
          ForEach(shortcuts, id: \.0) { item in LabeledContent(L(item.0), value: L(item.1)) }.id(AppLocalization.language)
        }
      }
    }.formStyle(.grouped).pageScrollStyle(.vertical)
  }
  var project: some View {
    Form {
      switch selectedCategory {
      case "基本信息":
        Section {
          TextField(
            L("名称"),
            text: Binding(
              get: { store.document.name }, set: { v in store.edit("重命名项目") { $0.name = v } }))
          TextField(
            L("作者"),
            text: Binding(
              get: { store.document.author }, set: { v in store.edit("修改作者") { $0.author = v } }))
          LabeledContent(L("格式"), value: L(".imgp · 原生可编辑项目"))
          Button(L("保存项目…")) { store.save() }
        }
      case "画布":
        Section(L("画布尺寸")) {
          NumericField(store: store, title: "宽度", value: store.document.width, range: 1...16384) {
            v in
            if v * store.document.height <= 100_000_000 {
              store.edit("画布宽度") { $0.width = v.rounded() }
            }
          }
          NumericField(store: store, title: "高度", value: store.document.height, range: 1...16384) {
            v in
            if v * store.document.width <= 100_000_000 {
              store.edit("画布高度") { $0.height = v.rounded() }
            }
          }
          NumericField(
            store: store, title: "分辨率", value: store.document.dpi, suffix: "DPI", range: 1...2400
          ) { v in store.edit("调整分辨率") { $0.dpi = v } }
        }
        Section(L("颜色与显示")) {
          LabeledContent(L("工作空间"), value: L("sRGB"))
          LabeledContent(L("输出位深"), value: L("8 bit / 通道"))
          Toggle(L("网格"), isOn: $store.showGrid)
        }
      case "历史记录":
        Section {
          HStack {
            Text(L("{0} 个可撤回操作", store.active.undo.count))
            Spacer()
            Button(L("撤回")) { store.undo() }.disabled(store.active.undo.isEmpty)
            Button(L("恢复")) { store.redo() }.disabled(store.active.redo.isEmpty)
          }
        }
        Section(L("当前历史")) {
          ForEach(Array(store.active.undo.enumerated().reversed()), id: \.element.id) {
            index, entry in
            Button {
              while store.active.undo.count > index + 1 { store.undo() }
            } label: {
              HStack {
                Text(L(entry.name))
                Spacer()
                Text(entry.date, style: .time).foregroundStyle(.secondary)
              }
            }.buttonStyle(.plain)
          }.id(AppLocalization.language)
          Button(L("回到初始状态")) { while !store.active.undo.isEmpty { store.undo() } }
        }
      default:
        Section(L("嵌入资源")) {
          LabeledContent(L("图像资源"), value: L("{0} 个", store.active.assets.data.count))
          LabeledContent(
            L("资源体积"),
            value: L(ByteCountFormatter.string(
              fromByteCount: Int64(store.active.assets.data.values.reduce(0) { $0 + $1.count }),
              countStyle: .file)))
          LabeledContent(
            L("文字字体"),
            value: L(Set(store.document.layers.filter { $0.kind == .text }.map(\.fontName)).sorted()
              .joined(separator: "、")))
        }
        Section {
          Text(L("原始图像、蒙版与效果参数保存在项目里；移动、裁剪与调整效果可以撤回。")).font(.system(size: 12)).foregroundStyle(
            .secondary)
        }
      }
    }.formStyle(.grouped).pageScrollStyle(.vertical)
  }
  var extensions: some View {
    Form {
      if selectedCategory == "我的扩展" {
        Section {
          Button {
            store.installExtension()
          } label: {
            Label(L("添加扩展…"), systemImage: "plus")
          }
        }
        Section(L("已安装")) {
          if store.extensions.isEmpty {
            Text(L("尚未安装扩展。添加后，它的效果会自动出现在效果器中。")).foregroundStyle(.secondary)
          }
          ForEach(store.extensions) { plugin in
            HStack(spacing: 14) {
              Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 22))
                .foregroundStyle(store.accent)
              VStack(alignment: .leading, spacing: 5) {
                Text(plugin.name)
                Text(L("Effect · {0}", plugin.version)).font(.system(size: 11)).foregroundStyle(
                  .secondary)
              }
              Spacer()
              Button(L("移除")) { store.removeExtension(plugin.id) }
            }
          }.id(AppLocalization.language)
        }
      } else {
        Section(L("当前接口")) {
          LabeledContent(L("能力"), value: L("声明式 Core Image 效果"))
          LabeledContent(L("清单"), value: L("JSON 扩展文件"))
          LabeledContent(L("展示位置"), value: L("效果器 → 扩展能力"))
        }
        Section {
          Text(L("目前支持白名单中的 Core Image 效果。工具、模型服务和导出格式的插件运行接口仍需开发。")).font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
    }.formStyle(.grouped).pageScrollStyle(.vertical)
  }
  private var layeredExport: Bool { ["psd", "pxd"].contains(exportID) }
  private var supportsQuality: Bool { ["jpg", "webp", "avif"].contains(exportID) }
  private var supportsTransparency: Bool { !["jpg", "psd", "pxd"].contains(exportID) }
  private var exportDescription: String {
    switch exportID {
    case "jpg": return "适合照片与分享。透明区域将使用白色背景。"
    case "tiff": return "无损图像，适合印刷和后续处理。"
    case "psd": return "保留独立图层与分组，便于在其他图像编辑软件中继续编辑。"
    case "pxd": return "先导出分层 PSD，再用支持 PXD 的软件转换。本应用不直接写入 PXD。"
    case "pdf": return "根据画布尺寸与分辨率生成 PDF。"
    case "svg": return "将合成图像嵌入 SVG 文件。"
    case "webp", "avif": return "高效压缩图像，适合网络发布。"
    default: return "无损图像，适合图形、截图和透明背景。"
    }
  }

  var export: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 28) {
        VStack(alignment: .leading, spacing: 14) {
          Text(L("作品预览")).font(.system(size: 13, weight: .semibold))
          ExportArtworkPreview(image: store.preview ?? store.active.thumbnail,
            aspectRatio: store.document.width / store.document.height,
            transparent: layeredExport || (supportsTransparency && transparent))
            .frame(height: 306)
            .padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
          Text(L("{0} × {1} px", Int(store.document.width), Int(store.document.height)))
            .font(.system(size: 13, weight: .medium)).monospacedDigit()
          Text(L("sRGB · {0} DPI", Int(store.document.dpi)))
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(width: 304)
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
              Text(L("文件格式")).font(.system(size: 13, weight: .semibold))
              Picker(L("导出格式"), selection: $exportID) {
                ForEach(ExportFormat.available) { Text(L($0.name)).tag($0.id) }.id(AppLocalization.language)
                Text(L("PXD · 需外部转换")).tag("pxd")
              }.id(AppLocalization.language).labelsHidden().pickerStyle(.menu).controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
              Text(L(exportDescription)).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
              Text(L("图像选项")).font(.system(size: 13, weight: .semibold))
              ExportOptionRow(title: "尺寸", value: "原始尺寸")
              if supportsQuality {
                VStack(spacing: 8) {
                  ExportOptionRow(title: "质量", value: "\(Int((quality * 100).rounded()))%")
                  Slider(value: $quality, in: 0.1...1).accessibilityLabel(L("导出质量"))
                }
              }
              if supportsTransparency {
                HStack {
                  Text(L("保留透明度")).foregroundStyle(.secondary)
                  Spacer()
                  Toggle(L("保留透明度"), isOn: $transparent).labelsHidden().toggleStyle(.switch)
                }
              } else {
                ExportOptionRow(title: layeredExport ? "透明度" : "背景",
                  value: layeredExport ? "保留各图层透明度" : "白色")
              }
              if layeredExport {
                ExportOptionRow(title: "图层", value: "保留图层与分组")
              }
            }.font(.system(size: 13))
            if layeredExport || exportID == "svg" {
              Divider()
              VStack(alignment: .leading, spacing: 10) {
                Text(L("兼容性")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                if layeredExport {
                  Text(L("文字与效果在其他软件中显示为像素图层。用 iMage Pro 重新打开 PSD，可恢复内嵌的原生对象与历史。"))
                  if store.document.layers.contains(where: { $0.kind == .adjustment }) {
                    Text(L("FX 调整图层会生成兼容合成，原始图层保存在隐藏分组中。用 iMage Pro 打开可恢复调整参数。"))
                  }
                } else {
                  Text(L("SVG 包含合成图像。需要保留可编辑矢量对象，请同时保存 .imgp 项目。"))
                }
              }.font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            }
          }.padding(.trailing, 2)
        }.scrollContentBackground(.hidden).pageScrollStyle(.vertical)
      }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      Divider()
      HStack(spacing: 12) {
        Text(L("下一步选择保存位置")).font(.system(size: 12)).foregroundStyle(.secondary)
        Spacer()
        Button(L("取消")) { store.sheet = nil }.keyboardShortcut(.cancelAction)
          .buttonStyle(.bordered).tint(.primary)
        Button(L(exportID == "pxd" ? "导出 PSD…" : "导出…")) {
          let id = exportID == "pxd" ? "psd" : exportID
          if let format = ExportFormat.available.first(where: { $0.id == id }) {
            store.export(format: format, width: store.document.width, quality: quality,
              transparency: transparent)
          }
        }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }.controlSize(.large).padding(.horizontal, 26).padding(.vertical, 18)
        .glassSurface(0, attached: true)
    }
  }
  var newProject: some View {
    Form {
      Section(L("名称")) { TextField(L("项目名称"), text: $newName) }
      Section(L("尺寸")) {
        Picker(
          L("预设"),
          selection: Binding(
            get: { "\(Int(newWidth))x\(Int(newHeight))" },
            set: { v in
              let dimensions = v.split(separator: "x").compactMap { Double($0) }
              if dimensions.count == 2 {
                newWidth = dimensions[0]
                newHeight = dimensions[1]
              }
            })
        ) {
          Text(L("1920 × 1080 横向作品")).tag("1920x1080")
          Text(L("1080 × 1350 社交海报")).tag("1080x1350")
          Text(L("3000 × 2000 摄影作品")).tag("3000x2000")
        }.id(AppLocalization.language)
        NumericField(title: "宽", value: newWidth, range: 1...16384) { newWidth = $0 }
        NumericField(title: "高", value: newHeight, range: 1...16384) { newHeight = $0 }
      }
      Section {
        LabeledContent(L("背景"), value: L("透明"))
        LabeledContent(L("颜色"), value: L("sRGB · 300 DPI"))
        Button(L("创建项目")) {
          store.newProject(
            name: newName.isEmpty ? L("未命名") : newName, width: newWidth.rounded(),
            height: newHeight.rounded())
        }.buttonStyle(.borderedProminent).disabled(newWidth * newHeight > 100_000_000)
      }
    }.formStyle(.grouped).pageScrollStyle(.vertical)
  }
  var about: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSImage(named: "AppIcon") ?? NSImage()).resizable().frame(
        width: 80, height: 80)
      Text(L("iMage Pro")).font(.system(size: 32, weight: .semibold))
      Text(L("{0} · Native macOS Preview", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.0")).foregroundStyle(.secondary)
      Text(L("功能不减少，界面不堆积。\n让软件理解你的意图，让你专注于创作。")).multilineTextAlignment(.center).lineSpacing(7)
        .foregroundStyle(.secondary)
      HStack(spacing: 20) {
        Button(L("使用指南")) { store.sheet = "help" }
        Button(L("第三方许可")) { store.sheet = "licenses" }
      }
      HStack(spacing: 12) {
        Link(destination: URL(string: "https://github.com/bossoda7-netizen/iMage-Pro")!) {
          Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
        }
        Link(destination: URL(string: "https://ko-fi.com/T0N028J9BE")!) {
          Label(L("请我一杯咖啡"), systemImage: "cup.and.saucer")
        }
      }.buttonStyle(.bordered).controlSize(.large).tint(.primary)
      Text(L("支持完全自愿，所有功能始终免费。"))
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Text(L("SwiftUI · AppKit · Core Image · Vision")).font(.system(size: 11)).foregroundStyle(
        .tertiary)
    }.frame(maxWidth: .infinity).padding(.top, 20)
  }
  var licenses: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let documents = licenseDocuments, !documents.isEmpty {
        Picker(L("第三方许可"), selection: $licenseIndex) {
          ForEach(Array(documents.enumerated()), id: \.offset) { index, document in
            Text(verbatim: document.title).tag(index)
          }
        }.labelsHidden().onChange(of: licenseIndex) { _, _ in licensePage = 0 }
        let document = documents[min(licenseIndex, documents.count - 1)]
        LicenseTextView(text: document.pages[min(licensePage, document.pages.count - 1)])
          .id("\(licenseIndex)-\(licensePage)")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        if document.pages.count > 1 {
          HStack {
            Button { licensePage -= 1 } label: { Image(systemName: "chevron.left") }
              .disabled(licensePage == 0).accessibilityLabel(L("上一页"))
            Text(L("第 {0} / {1} 页", licensePage + 1, document.pages.count)).monospacedDigit()
            Button { licensePage += 1 } label: { Image(systemName: "chevron.right") }
              .disabled(licensePage == document.pages.count - 1).accessibilityLabel(L("下一页"))
          }
        }
      } else if licenseDocuments != nil {
        Text(L("许可文件未找到。"))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        ProgressView(L("正在加载许可证…"))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      Button(L("返回关于")) { store.sheet = "about" }
    }.padding(26)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      guard licenseDocuments == nil else { return }
      licenseDocuments = await Task.detached(priority: .userInitiated) { LicenseDocument.load() }.value
    }
  }
  var help: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text(L("从创建项目到完成作品")).font(.system(size: 20, weight: .medium))
        Text(L("按下面的顺序开始编辑。快捷键速查在指南末尾，也可在设置 → 快捷键中查看。"))
          .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
        ForEach(UserGuide.sections) { section in
          VStack(alignment: .leading, spacing: 10) {
            Text(L(section.title)).font(.system(size: 16, weight: .semibold))
            ForEach(section.paragraphs, id: \.self) { paragraph in
              Text(L(paragraph)).font(.system(size: 14)).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        Divider()
        DisclosureGroup(L("快捷键速查")) {
          VStack(alignment: .leading, spacing: 16) {
            shortcutRows(ShortcutCatalog.actions, title: "编辑与导航")
            Divider()
            shortcutRows(ShortcutCatalog.tools.map { ($0.title, $0.key.uppercased()) }, title: "切换工具")
          }.padding(.top, 14)
        }
      }.padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .id(AppLocalization.language)
    }.pageScrollStyle(.vertical)
  }

  private func shortcutRows(_ items: [(String, String)], title: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L(title)).font(.system(size: 14, weight: .semibold))
      ForEach(items, id: \.0) { item in
        HStack(alignment: .top, spacing: 20) {
          Text(L(item.0)).frame(maxWidth: .infinity, alignment: .leading)
          Text(L(item.1)).foregroundStyle(.secondary).monospaced()
            .multilineTextAlignment(.trailing)
        }.font(.system(size: 13))
      }
    }
  }
  var shortcuts: [(String, String)] { ShortcutCatalog.guide }
}

/// Displays the combined notices in AppKit's native text system.  A single
/// SwiftUI `Text` containing every notice makes the accessibility tree and
/// layout engine walk hundreds of thousands of characters on the main thread.
private struct LicenseTextView: NSViewRepresentable {
  let text: String

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = LicenseScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.drawsBackground = false
    scroll.scrollerStyle = .overlay
    let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
    editor.isEditable = false
    editor.isSelectable = true
    editor.isRichText = false
    editor.drawsBackground = false
    editor.font = .systemFont(ofSize: 13)
    editor.textColor = .labelColor
    editor.textContainerInset = NSSize(width: 8, height: 8)
    editor.string = text
    editor.textContainer?.widthTracksTextView = true
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.minSize = .zero
    editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
    scroll.documentView = editor
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let editor = scroll.documentView as? NSTextView, editor.string != text else { return }
    editor.string = text
  }
}

private final class LicenseScrollView: NSScrollView {
  override func tile() {
    super.tile()
    guard let editor = documentView as? NSTextView,
      let container = editor.textContainer, let layout = editor.layoutManager else { return }
    let width = max(1, contentSize.width)
    container.containerSize = NSSize(width: max(1, width - editor.textContainerInset.width * 2), height: CGFloat.greatestFiniteMagnitude)
    layout.ensureLayout(for: container)
    let height = max(contentSize.height, ceil(layout.usedRect(for: container).height) + editor.textContainerInset.height * 2)
    if abs(editor.frame.width - width) > 0.5 || abs(editor.frame.height - height) > 0.5 {
      editor.setFrameSize(NSSize(width: width, height: height))
    }
  }
}
