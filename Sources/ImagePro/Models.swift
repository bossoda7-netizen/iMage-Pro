import AppKit
import SwiftUI

struct Point: Codable, Equatable {
  var x: Double
  var y: Double
  init(_ p: CGPoint) {
    x = p.x
    y = p.y
  }
  init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
  var cg: CGPoint { CGPoint(x: x, y: y) }
}

struct ClipboardAsset: Codable {
  var id: String
  var data: Data
}

struct ClipboardLayerPayload: Codable {
  var layer: ImageLayer
  var assets: [ClipboardAsset]
}

struct RulerMeasurement: Codable, Equatable, Identifiable {
  var id = UUID()
  var start: Point
  var end: Point
  var tool: RulerTool?
  var locked: Bool?
  var length: Double { hypot(end.x - start.x, end.y - start.y) }
  var angle: Double { atan2(end.y - start.y, end.x - start.x) * 180 / .pi }
}

enum RulerTool: String, Codable, CaseIterable, Identifiable {
  case ruler = "尺子", protractor = "量角器", compass = "圆规", guides = "辅助线"
  var id: String { rawValue }
  var symbol: String {
    switch self { case .ruler: return "ruler"; case .protractor: return "angle"; case .compass: return "compass.drawing"; case .guides: return "lines.measurement.horizontal" }
  }
}

struct RGBA: Codable, Equatable {
  var r: Double = 0.12
  var g: Double = 0.15
  var b: Double = 0.22
  var a: Double = 1
  var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
  var color: Color { Color(nsColor: ns) }
  init(r: Double = 0.12, g: Double = 0.15, b: Double = 0.22, a: Double = 1) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }
  init(_ color: NSColor) {
    let c = color.usingColorSpace(.sRGB) ?? .black
    r = c.redComponent
    g = c.greenComponent
    b = c.blueComponent
    a = c.alphaComponent
  }
}

enum LayerKind: String, Codable { case raster, paint, text, shape, group, adjustment, gradient }
enum BlendMode: String, Codable, CaseIterable {
  case normal = "正常", dissolve = "溶解"
  case darken = "变暗", multiply = "正片叠底", colorBurn = "颜色加深", linearBurn = "线性加深", darkerColor = "深色"
  case lighten = "变亮", screen = "滤色", colorDodge = "颜色减淡", linearDodge = "线性减淡", lighterColor = "浅色"
  case overlay = "叠加", softLight = "柔光", hardLight = "强光", vividLight = "亮光", linearLight = "线性光", pinLight = "点光", hardMix = "实色混合"
  case difference = "差值", exclusion = "排除", subtract = "减去", divide = "划分"
  case hue = "色相", saturation = "饱和度", color = "颜色", luminosity = "明度"
  var cg: CGBlendMode {
    switch self {
    case .normal, .dissolve: return .normal
    case .darken, .darkerColor: return .darken
    case .multiply: return .multiply
    case .colorBurn: return .colorBurn
    case .linearBurn: return .plusDarker
    case .lighten, .lighterColor: return .lighten
    case .screen: return .screen
    case .colorDodge: return .colorDodge
    case .linearDodge: return .plusLighter
    case .overlay: return .overlay
    case .softLight: return .softLight
    case .hardLight, .vividLight, .linearLight, .pinLight, .hardMix: return .hardLight
    case .difference, .subtract, .divide: return .difference
    case .exclusion: return .exclusion
    case .hue: return .hue
    case .saturation: return .saturation
    case .color: return .color
    case .luminosity: return .luminosity
    }
  }
  var requiresCI: Bool {
    [.dissolve, .linearBurn, .darkerColor, .linearDodge, .lighterColor,
      .vividLight, .linearLight, .pinLight, .hardMix, .subtract, .divide].contains(self)
  }
  var ciFilter: String {
    switch self {
    case .normal, .dissolve: return "CISourceOverCompositing"
    case .darken, .darkerColor: return "CIDarkenBlendMode"
    case .multiply: return "CIMultiplyBlendMode"
    case .colorBurn: return "CIColorBurnBlendMode"
    case .linearBurn: return "CILinearBurnBlendMode"
    case .lighten, .lighterColor: return "CILightenBlendMode"
    case .screen: return "CIScreenBlendMode"
    case .colorDodge: return "CIColorDodgeBlendMode"
    case .linearDodge: return "CILinearDodgeBlendMode"
    case .overlay: return "CIOverlayBlendMode"
    case .softLight: return "CISoftLightBlendMode"
    case .hardLight: return "CIHardLightBlendMode"
    case .vividLight: return "CIVividLightBlendMode"
    case .linearLight: return "CILinearLightBlendMode"
    case .pinLight: return "CIPinLightBlendMode"
    case .hardMix: return "CIVividLightBlendMode"
    case .difference: return "CIDifferenceBlendMode"
    case .exclusion: return "CIExclusionBlendMode"
    case .subtract: return "CISubtractBlendMode"
    case .divide: return "CIDivideBlendMode"
    case .hue: return "CIHueBlendMode"
    case .saturation: return "CISaturationBlendMode"
    case .color: return "CIColorBlendMode"
    case .luminosity: return "CILuminosityBlendMode"
    }
  }
}
enum EffectKind: String, Codable, CaseIterable {
  case color = "色彩调节"
  case blur = "高斯模糊" // Legacy grouped effect retained for project decoding.
  case gaussianBlur = "gaussianBlur", motionBlur = "motionBlur", focusBlur = "focusBlur"
  case bumpDistort = "bumpDistort", pinchDistort = "pinchDistort", stretchDistort = "stretchDistort", twirlDistort = "twirlDistort", waveDistort = "waveDistort"
  case sharpen = "锐化"
  case bloom = "光效"
  case shadow = "阴影"
  case outline = "描边"
  case grain = "胶片颗粒"
  case pixelate = "像素化"
  case vignette = "暗角"
  case monochrome = "黑白"
  case hdr = "智能 HDR"
  case custom = "扩展效果"
  case hue = "色相与饱和度"
  case selective = "选择性颜色"
  case wheels = "色轮"
  case levels = "色阶"
  case curves = "曲线"
  case replace = "替换颜色"
  case removeColor = "移除颜色"
  case fade = "褪色"
  case colorize = "单色化"
  case channels = "通道混合器"
  case lut = "LUT"
  case distort = "扭曲"
  case beauty = "美颜"
  case body = "美体"
  case bevel = "斜角与浮雕"
  case innerShadow = "内阴影"
  case outerGlow = "外发光"
  case innerGlow = "内发光"
  case fillStyle = "填充样式"
  var title: String {
    switch self {
    case .gaussianBlur: return "高斯模糊"
    case .motionBlur: return "运动模糊"
    case .focusBlur: return "聚焦模糊"
    case .bumpDistort: return "凹凸扭曲"
    case .pinchDistort: return "收缩扭曲"
    case .stretchDistort: return "拉伸扭曲"
    case .twirlDistort: return "旋转扭曲"
    case .waveDistort: return "波浪扭曲"
    case .blur: return "模糊"
    case .color: return "基础调节"
    default: return rawValue
    }
  }
  var symbol: String {
    switch self {
    case .color: return "slider.horizontal.3"
    case .blur, .gaussianBlur, .motionBlur, .focusBlur: return "drop.halffull"
    case .sharpen: return "sun.max"
    case .bloom: return "lightbulb"
    case .shadow: return "square.on.square"
    case .outline: return "square.dashed"
    case .grain: return "circle.dotted"
    case .pixelate: return "square.grid.3x3"
    case .vignette: return "camera.filters"
    case .monochrome: return "circle.lefthalf.filled"
    case .hdr: return "sparkles"
    case .custom: return "puzzlepiece.extension"
    case .hue, .selective, .wheels, .replace, .removeColor, .colorize: return "paintpalette"
    case .levels: return "chart.bar"
    case .curves: return "point.topleft.down.to.point.bottomright.curvepath"
    case .channels: return "slider.horizontal.3"
    case .lut: return "square.grid.3x3"
    case .fade: return "sun.haze"
    case .distort, .body, .bumpDistort, .pinchDistort, .stretchDistort, .twirlDistort, .waveDistort: return "waveform.path"
    case .beauty: return "face.smiling"
    case .bevel: return "cube"
    case .innerShadow: return "square.inset.filled"
    case .outerGlow, .innerGlow: return "sparkle"
    case .fillStyle: return "square.fill"
    }
  }
  var subtitle: String {
    switch self {
    case .color: return "曝光、对比与饱和度"
    case .blur, .gaussianBlur: return "柔化细节"
    case .motionBlur: return "沿指定方向模拟运动"
    case .focusBlur: return "保留焦点并柔化周围"
    case .sharpen: return "恢复清晰的边缘"
    case .bloom: return "柔和的高光扩散"
    case .shadow: return "赋予内容空间感"
    case .outline: return "强调对象轮廓"
    case .grain: return "细腻的胶片质感"
    case .pixelate: return "像素风格与隐私处理"
    case .vignette: return "让视线聚焦中心"
    case .monochrome: return "纯粹的明暗层次"
    case .hdr: return "平衡阴影与高光"
    case .custom: return "扩展提供的处理能力"
    case .hue: return "独立调节色相与鲜艳度"
    case .selective: return "分别控制八个颜色范围"
    case .wheels: return "高光、中间调与阴影色彩"
    case .levels: return "黑白场与中间调"
    case .curves: return "带直方图的 RGB 色调曲线"
    case .replace: return "按颜色范围替换"
    case .removeColor: return "将目标色变为透明"
    case .fade: return "柔和的褪色质感"
    case .colorize: return "用单一颜色重新着色"
    case .channels: return "RGB 通道独立混合"
    case .lut: return "导入 .cube 色彩查找表"
    case .distort, .bumpDistort, .pinchDistort, .stretchDistort, .twirlDistort: return "可定位的局部形变"
    case .waveDistort: return "连续的正弦波形变"
    case .beauty: return "平滑纹理与肤色调节"
    case .body: return "可定位的局部收缩与扩张"
    case .bevel: return "轮廓的立体高光"
    case .innerShadow: return "对象内部的柔和投影"
    case .outerGlow: return "轮廓向外扩散"
    case .innerGlow: return "轮廓向内扩散"
    case .fillStyle: return "纯色或渐变填充内容轮廓"
    }
  }
}
struct ImageEffect: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: EffectKind
  var name: String
  var enabled = true
  /// Effect opacity is independent from the effect's internal strength. New
  /// effects are fully opaque; individual parameter defaults provide the
  /// restrained starting intensity.
  var amount: Double = 1
  /// Legacy Debug6 project field; retained for decoding, no longer a global strength multiplier.
  var intensity: Double?
  var radius: Double = 10
  var brightness: Double = 0
  var contrast: Double = 1
  var saturation: Double = 1
  var exposure: Double = 0
  var filterName: String?
  var tonalCurves: [String:[Point]]?
  var parameters: [String: Double]?
  var style: String?
  var tint: RGBA?
  var sourceColor: RGBA?
  var targetColor: RGBA?
  var faces: [FaceRegion]?
  var bodyJoints: [Point]?
  var lutData: Data?
  var lutDimension: Int?
  var gradient: GradientDefinition?
  func value(_ key: String, _ fallback: Double = 0) -> Double { parameters?[key] ?? fallback }
  mutating func set(_ key: String, _ value: Double) {
    if parameters == nil { parameters = [:] }
    parameters?[key] = value
  }
  init(_ kind: EffectKind, name: String? = nil) {
    self.kind = kind
    self.name = name ?? kind.title
    if let style = kind.independentStyle {self.style = style}
    if kind == .beauty {style = "face"}
    if kind == .grain {set("strength",0.275)}
    if kind.isLayerStyle {set("ignoreClipping",1)}
  }
}
struct BrushStroke: Codable, Equatable {
  var points: [Point]
  var color: RGBA
  var size: Double
  var opacity: Double
  var hardness: Double
  var erasing = false
  var clip: SelectionRegion?
  var dynamics: BrushDynamics?
  var pressures: [Double]?
}
struct ImageLayer: Identifiable, Codable, Equatable {
  var id = UUID()
  var name: String
  var kind: LayerKind
  var parentID: UUID?
  /// Clipping mask: this layer is composited through the layer below.
  var clippingMask = false
  var visible = true
  var locked = false
  var opacity: Double = 1
  var blend: BlendMode = .normal
  var x: Double = 0
  var y: Double = 0
  var width: Double
  var height: Double
  var rotation: Double = 0
  var quad: [Point]?
  var warpNodes: [Point]?
  var detachedMaskSource: UUID?
  var contentPlacement: CGRect?
  var rasterPlacement: CGRect?
  var maskPlacement: CGRect?
  var assetID: String?
  var maskAssetID: String?
  var maskEnabled = true
  var maskStrokes: [BrushStroke]?
  var maskDensity: Double?
  var maskOpacity: Double?
  var maskFeather: Double?
  var maskInverted: Bool?
  var strokes: [BrushStroke] = []
  var text = L("你的灵感，从这里开始。")
  var fontName = "PingFangSC-Semibold"
  var fontSize: Double = 72
  var color = RGBA()
  var shape = "rectangle"
  var cornerRadius: Double = 24
  var effects: [ImageEffect] = []
  var textStyle: TextStyle?
  var textRuns: [TextRun]?
  var importedTextAppearance: TextAppearance?
  var aspectLocked: Bool?
  var flippedX: Bool?
  var flippedY: Bool?
  var bezierAnchors: [BezierAnchor]?
  var pathClosed: Bool?
  var vectorOutline: [VectorNode]?
  var vectorPoints: [Point]?
  var shapeSides: Int?
  var gradient: GradientDefinition?
  init(name: String, kind: LayerKind, width: Double, height: Double) {
    self.name = name
    self.kind = kind
    self.width = width
    self.height = height
  }
  var symbol: String {
    switch kind {
    case .raster: return "photo"
    case .paint: return "paintbrush.pointed"
    case .text: return "character"
    case .shape: return shape == "ellipse" ? "circle" : "square"
    case .group: return "folder"
    case .adjustment: return "fx"
    case .gradient: return "rectangle.lefthalf.filled"
    }
  }
}
struct ImageDocument: Codable, Equatable {
  var id = UUID()
  var name = L("未命名")
  var author = ""
  var width: Double = 1920
  var height: Double = 1080
  var dpi: Double = 300
  var colorProfile = "sRGB"
  var layers: [ImageLayer] = []  // Front to back; a folder's children immediately follow it.
  var selectedLayerID: UUID?
  var createdAt = Date()
  var selectedLayer: ImageLayer? { layers.first { $0.id == selectedLayerID } }
  func isVisible(_ layer: ImageLayer) -> Bool {
    guard layer.visible else { return false }
    var parent = layer.parentID
    var visited = Set<UUID>()
    while let id = parent, visited.insert(id).inserted {
      guard let group = layers.first(where: { $0.id == id }), group.visible else { return false }
      parent = group.parentID
    }
    return true
  }
  func effectiveOpacity(_ layer: ImageLayer) -> Double {
    var value = layer.opacity
    var parent = layer.parentID
    var visited = Set<UUID>()
    while let id = parent, visited.insert(id).inserted,
      let group = layers.first(where: { $0.id == id })
    {
      value *= group.opacity
      parent = group.parentID
    }
    return value
  }
  func validate() throws {
    guard width.isFinite, height.isFinite, width >= 1, height >= 1, width <= 16384, height <= 16384,
      width * height <= 100_000_000, dpi.isFinite, dpi > 0, layers.count <= 1000
    else {
      throw ImageProError.message("画布尺寸或图层数量超出支持范围。画布最多 1 亿像素，单边最多 16384 px。")
    }
    let ids = Set(layers.map(\.id))
    guard ids.count == layers.count else { throw ImageProError.message("项目含有重复的图层标识。") }
    for layer in layers {
      guard layer.x.isFinite, layer.y.isFinite, layer.width.isFinite, layer.height.isFinite,
        layer.width > 0, layer.height > 0, layer.width <= 32768, layer.height <= 32768,
        layer.rotation.isFinite, layer.opacity.isFinite, (0...1).contains(layer.opacity),
        layer.fontSize.isFinite, (1...4096).contains(layer.fontSize),
        layer.effects.allSatisfy({
          [$0.radius, $0.amount, $0.brightness, $0.contrast, $0.saturation, $0.exposure].allSatisfy(
            \.isFinite)
        }),
        layer.strokes.count <= 100000,
        layer.strokes.allSatisfy({ stroke in
          stroke.size.isFinite && (0.1...5000).contains(stroke.size)
            && stroke.opacity.isFinite && (0...1).contains(stroke.opacity)
            && stroke.hardness.isFinite && (0...1).contains(stroke.hardness)
            && stroke.points.count <= 1_000_000
            && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        })
      else {
        throw ImageProError.message("项目含有无效的图层参数。")
      }
      let validEffects = layer.effects.allSatisfy { effect in
        (effect.parameters?.values.allSatisfy { $0.isFinite && abs($0) < 1_000_000 } ?? true)
          && [effect.tint, effect.sourceColor, effect.targetColor].compactMap { $0 }.allSatisfy {
            [$0.r, $0.g, $0.b, $0.a].allSatisfy { $0.isFinite && (0...1).contains($0) }
          }
      }
      let validVectors =
        (layer.vectorPoints?.count ?? 0) <= 1_000_000
        && (layer.vectorPoints?.allSatisfy { $0.x.isFinite && $0.y.isFinite } ?? true)
        && (layer.vectorOutline?.count ?? 0) <= 1_000_000
        && (layer.vectorOutline?.allSatisfy {
          (0...4).contains($0.kind) && $0.points.count <= 3
            && $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        } ?? true)
      let textStyle = layer.textStyle ?? TextStyle()
      guard validEffects, validVectors,
        [
          textStyle.tracking, textStyle.lineHeight, textStyle.paragraphBefore,
          textStyle.paragraphAfter,
        ].allSatisfy(\.isFinite) && (0.1...10).contains(textStyle.lineHeight)
      else { throw ImageProError.message("项目包含无效的效果或矢量数据。") }
      try Debug2Validation.validate(layer)
      var parent = layer.parentID
      var seen: Set<UUID> = [layer.id]
      while let id = parent {
        guard seen.insert(id).inserted, let group = layers.first(where: { $0.id == id }),
          group.kind == .group
        else {
          throw ImageProError.message("项目的图层分组关系无效。")
        }
        parent = group.parentID
      }
      for id in [layer.assetID, layer.maskAssetID].compactMap({ $0 }) {
        guard UUID(uuidString: id) != nil else { throw ImageProError.message("项目资源标识无效。") }
      }
    }
  }
}
enum ImageProError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let value) = self { return value }
    return nil
  }
}

struct HistoryEntry: Identifiable, Codable {
  var id = UUID()
  var name: String
  var before: ImageDocument
  var after: ImageDocument
  var date = Date()
}
struct ProjectArchive: Codable {
  var formatVersion = 1
  var document: ImageDocument
  var undo: [HistoryEntry]
  var redo: [HistoryEntry]
}
struct SelectionRegion: Codable, Equatable {
  var type: String
  var points: [Point]
  var contours: [[Point]]?
  var spans: [SelectionSpan]?
  var inverted: Bool?
  var feather: Double?
  var bounds: CGRect {
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    return CGRect(
      x: xs.min() ?? 0, y: ys.min() ?? 0,
      width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
  }
  var path: CGPath {
    if type.hasPrefix("shape:") {
      return ShapeGeometry.path(String(type.dropFirst(6)), rect: bounds)
    }
    if let contours {
      let p = CGMutablePath()
      for contour in contours {
        if let first = contour.first {
          p.move(to: first.cg)
          contour.dropFirst().forEach { p.addLine(to: $0.cg) }
          p.closeSubpath()
        }
      }
      return p
    }
    if let spans {
      let p = CGMutablePath()
      for span in spans { p.addRect(span.rect) }
      return p
    }
    if type == "ellipse" { return CGPath(ellipseIn: bounds, transform: nil) }
    if type == "rectangle" || type == "crop" { return CGPath(rect: bounds, transform: nil) }
    let p = CGMutablePath()
    if let first = points.first {
      p.move(to: first.cg)
      points.dropFirst().forEach { p.addLine(to: $0.cg) }
      p.closeSubpath()
    }
    return p
  }
}
enum ToolCategory: String, CaseIterable, Identifiable {
  case canvas = "画布"
  case move = "移动"
  case selection = "选择"
  case brush = "画笔"
  case eraser = "橡皮"
  case shape = "形状"
  case text = "文字"
  case crop = "裁剪"
  case hand = "抓手"
  case zoom = "缩放"
  case fill = "填充"
  case retouch = "修饰"
  case clone = "仿制"
  case dodge = "明暗"
  case detail = "细节"
  case eyedropper = "取色"
  case gradient = "渐变"
  case path = "路径"
  static var displayed: [ToolCategory] {
    [.canvas, .selection, .text, .shape, .path, .brush, .fill, .retouch]
  }
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .canvas: return "rectangle.on.rectangle"
    case .move: return "cursorarrow"
    case .selection: return "square.dashed"
    case .brush: return "paintbrush.pointed.fill"
    case .eraser: return "eraser.fill"
    case .shape: return "square.on.circle"
    case .text: return "character"
    case .crop: return "crop"
    case .hand: return "hand.draw"
    case .zoom: return "magnifyingglass"
    case .fill: return "drop.fill"
    case .retouch: return "bandage"
    case .clone: return "seal"
    case .dodge: return "circle.lefthalf.filled"
    case .detail: return "drop.halffull"
    case .eyedropper: return "eyedropper"
    case .gradient: return "rectangle.lefthalf.filled"
    case .path: return "point.topleft.down.to.point.bottomright.curvepath"
    }
  }
  var branches: [ToolBranch] {
    switch self {
    case .canvas:
      return [.init("移动", "move", "cursorarrow"), .init("裁切", "crop", "crop"),
        .init("抓手", "hand", "hand.draw"), .init("放大镜", "zoom", "magnifyingglass"),
        .init("取色器", "eyedropper", "eyedropper")]
    case .selection:
      return [
        .init("快速选择", "smart", "paintbrush.pointed"), .init("矩形选框", "rectangle", "square.dashed"),
        .init("椭圆选框", "ellipse", "circle.dashed"), .init("套索", "lasso", "lasso"),
        .init("多边形套索", "polygonLasso", "pentagon"),
        .init("颜色范围", "colorRange", "paintpalette"),
      ]
    case .brush:
      return [
        .init("普通画笔", "brush", "paintbrush.pointed"), .init("铅笔", "pencil", "pencil"),
        .init("马克笔", "marker", "highlighter"), .init("喷枪", "airbrush", "cloud.fog"),
        .init("水彩", "watercolor", "drop"), .init("油画", "oil", "paintbrush"),
        .init("纹理画笔", "texture", "circle.dotted"), .init("橡皮擦", "eraser", "eraser.fill"),
      ]
    case .shape:
      return [
        .init("矩形", "rectangle", "rectangle.fill"),
        .init("圆角矩形", "roundedRectangle", "rectangle.roundedtop.fill"),
        .init("椭圆", "ellipse", "circle.fill"), .init("多边形", "polygon", "pentagon.fill"),
        .init("星形", "star", "star.fill"), .init("直线", "line", "line.diagonal"),
        .init("自定义形状", "custom", "heart.fill"),
      ]
    case .text:
      return [
        .init("横排文字", "horizontalText", "character"), .init("竖排文字", "verticalText", "character"),
      ]
    case .fill: return [
      .init("线性渐变", "linear", "rectangle.lefthalf.filled"),
      .init("径向渐变", "radial", "circle.inset.filled"),
      .init("超级渐变", "mesh", "square.grid.3x3.fill"),
      .init("油漆桶", "bucket", "drop.fill"), .init("颜色填充", "solid", "square.fill")]
    case .retouch:
      return [.init("智能修复", "heal", "sparkles"), .init("纹理平滑", "smooth", "face.smiling"),
        .init("仿制图章", "stamp", "seal"), .init("减淡", "dodge", "sun.max"),
        .init("加深", "burn", "moon"), .init("海绵", "sponge", "drop.halffull"),
        .init("模糊画笔", "blurBrush", "drop"), .init("锐化画笔", "sharpenBrush", "sun.max"),
        .init("涂抹", "smudge", "hand.point.up.left"),
        .init("液化推移", "liquify", "arrow.up.and.down.and.arrow.left.and.right")]
    case .clone: return [.init("仿制图章", "stamp", "seal")]
    case .dodge:
      return [
        .init("减淡", "dodge", "sun.max"), .init("加深", "burn", "moon"),
        .init("海绵", "sponge", "drop.halffull"),
      ]
    case .detail:
      return [
        .init("模糊画笔", "blurBrush", "drop"), .init("锐化画笔", "sharpenBrush", "sun.max"),
        .init("涂抹", "smudge", "hand.point.up.left"),
      ]
    case .gradient:
      return [
        .init("线性渐变", "linear", "rectangle.lefthalf.filled"),
        .init("径向渐变", "radial", "circle.inset.filled"),
      ]
    case .path:
      return [.init("钢笔路径", "pen", "pencil.tip"), .init("自由路径", "freePath", "scribble.variable")]
    default: return [.init(rawValue, String(describing: self), symbol)]
    }
  }
}
struct ToolBranch: Identifiable {
  var title: String
  var id: String
  var symbol: String
  init(_ title: String, _ id: String, _ symbol: String) {
    self.title = title
    self.id = id
    self.symbol = symbol
  }
}
enum InspectorContext: Equatable {
  case tool, special, base, mask
  case effect(UUID)
}
struct ExtensionManifest: Identifiable, Codable {
  var id: String
  var name: String
  var version: String
  var capability: String
  var coreImageFilter: String
  static let allowedFilters = [
    "CISepiaTone", "CIPhotoEffectChrome", "CIPhotoEffectFade", "CIPhotoEffectInstant",
    "CIPhotoEffectNoir", "CIPhotoEffectProcess", "CIPhotoEffectTonal", "CIPhotoEffectTransfer",
    "CIColorInvert", "CIComicEffect", "CIEdges",
  ]
}

extension ImageLayer {
  var isPath: Bool { kind == .shape && ["pen", "freePath"].contains(shape) }
  var specialInspectorTitle: String? {
    if isPath { return "路径" }
    switch kind {
    case .gradient: return gradient?.style == "solid" ? "填充" : "渐变"
    case .text: return "文字"
    case .shape: return "形状"
    default: return nil
    }
  }
  var defaultInspector: InspectorContext { specialInspectorTitle == nil ? .base : .special }
}

extension EffectKind {
  var independentStyle:String? {
    switch self {
    case .gaussianBlur:return "gaussian"
    case .motionBlur:return "motion"
    case .focusBlur:return "focus"
    case .bumpDistort:return "bump"
    case .pinchDistort:return "pinch"
    case .stretchDistort:return "stretch"
    case .twirlDistort:return "twirl"
    case .waveDistort:return "wave"
    default:return nil
    }
  }
  var isBlur:Bool {[.blur,.gaussianBlur,.motionBlur,.focusBlur].contains(self)}
  var isDistortion:Bool {[.distort,.bumpDistort,.pinchDistort,.stretchDistort,.twirlDistort,.waveDistort].contains(self)}
}
