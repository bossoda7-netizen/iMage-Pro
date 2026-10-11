import AppKit
import CoreText
import SwiftUI

struct TextStyle: Codable, Equatable {
  var bold = false
  var italic = false
  var underline = false
  var strikethrough = false
  var alignment = 0
  var verticalAlignment = 0
  var tracking: Double = 0
  var lineHeight: Double = 1
  var paragraphBefore: Double = 0
  var paragraphAfter: Double = 0
  var vertical = false
  /// Optional for compatibility with existing documents; test point text grows while typing.
  var pointText: Bool?
}
struct BrushDynamics: Codable, Equatable {
  var tip = "round"
  var mode = "brush"
  var spacing: Double = 0.12
  var angle: Double = 0
  var roundness: Double = 1
  var scatter: Double = 0
  var sizeJitter: Double = 0
  var opacityJitter: Double = 0
  var pressure = true
  var wetness: Double = 0.5
  var texture: Double = 0.35
  var smoothing: Double = 0.25
}
struct SelectionSpan: Codable, Equatable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double
  var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
struct BrushTip: Identifiable {
  var id: String
  var name: String
  var symbol: String
  static let all: [BrushTip] = [
    .init(id: "round", name: "圆头", symbol: "circle.fill"),
    .init(id: "soft", name: "柔边", symbol: "circle.dotted"),
    .init(id: "square", name: "方头", symbol: "square.fill"),
    .init(id: "flat", name: "扁头", symbol: "rectangle.fill"),
    .init(id: "chalk", name: "粉笔", symbol: "scribble"),
    .init(id: "bristle", name: "鬃毛", symbol: "line.3.horizontal"),
    .init(id: "splatter", name: "飞溅", symbol: "sparkles"),
    .init(id: "grain", name: "颗粒", symbol: "circle.grid.3x3.fill"),
    .init(id: "star", name: "星形", symbol: "star.fill"),
    .init(id: "leaf", name: "叶片", symbol: "leaf.fill"),
    .init(id: "cross", name: "十字", symbol: "plus"),
    .init(id: "ring", name: "空心圆", symbol: "circle"),
    .init(id: "oval", name: "椭圆", symbol: "oval.fill"),
    .init(id: "diagonal", name: "brush.chisel", symbol: "line.diagonal"),
    .init(id: "fan", name: "扇形", symbol: "fan"),
    .init(id: "rake", name: "排刷", symbol: "line.3.horizontal"),
    .init(id: "charcoal", name: "炭笔", symbol: "pencil"),
    .init(id: "cloud", name: "云雾", symbol: "cloud.fill"),
    .init(id: "wet", name: "湿边", symbol: "drop.fill"),
    .init(id: "stripe", name: "条纹", symbol: "line.3.horizontal"),
    .init(id: "triangle", name: "三角", symbol: "triangle.fill"),
    .init(id: "diamond", name: "菱形", symbol: "diamond.fill"),
    .init(id: "hexagon", name: "六边形", symbol: "hexagon.fill"),
    .init(id: "flower", name: "花瓣", symbol: "camera.macro"),
    .init(id: "heart", name: "心形", symbol: "heart.fill"),
    .init(id: "squares", name: "散落方块", symbol: "square.grid.3x3.fill"),
    .init(id: "dots", name: "点阵", symbol: "circle.grid.3x3.fill"),
    .init(id: "grass", name: "草叶", symbol: "leaf"),
    .init(id: "speckle", name: "斑点", symbol: "sparkles"),
    .init(id: "grid", name: "网格", symbol: "square.grid.3x3"),
    .init(id: "dash", name: "细线", symbol: "minus"),
    .init(id: "fuzzy", name: "绒毛", symbol: "sun.max.fill"),
    .init(id: "spray", name: "喷点", symbol: "aqi.medium"),
    .init(id: "dry", name: "干刷", symbol: "paintbrush"),
    .init(id: "canvas", name: "画布纹理", symbol: "square.dashed"),
    .init(id: "fine", name: "细尖", symbol: "pencil.tip"),
  ]

}
struct ShapePreset: Identifiable {
  var id: String
  var name: String
  var symbol: String
  static let all: [ShapePreset] = [
    .init(id: "rectangle", name: "矩形", symbol: "rectangle.fill"),
    .init(id: "roundedRectangle", name: "圆角矩形", symbol: "rectangle.roundedtop.fill"),
    .init(id: "ellipse", name: "椭圆", symbol: "circle.fill"),
    .init(id: "heart", name: "心形", symbol: "heart.fill"),
    .init(id: "arrow", name: "箭头", symbol: "arrow.right"),
    .init(id: "diamond", name: "菱形", symbol: "diamond.fill"),
    .init(id: "triangle", name: "三角形", symbol: "triangle.fill"),
    .init(id: "hexagon", name: "六边形", symbol: "hexagon.fill"),
    .init(id: "star", name: "五角星", symbol: "star.fill"),
    .init(id: "star8", name: "八角星", symbol: "seal.fill"),
    .init(id: "cross", name: "十字", symbol: "plus"),
    .init(id: "bubble", name: "对话框", symbol: "bubble.left.fill"),
    .init(id: "ticket", name: "票券", symbol: "ticket.fill"),
    .init(id: "shield", name: "盾牌", symbol: "shield.fill"),
    .init(id: "ring", name: "圆环", symbol: "circle.circle"),
    .init(id: "chevron", name: "折箭头", symbol: "chevron.right"),
    .init(id: "trapezoid", name: "梯形", symbol: "trapezoid.and.line.vertical.fill"),
    .init(id: "parallelogram", name: "平行四边形", symbol: "rhombus.fill"),
    .init(id: "cloud", name: "云朵", symbol: "cloud.fill"),
    .init(id: "flower", name: "花朵", symbol: "camera.macro"),
    .init(id: "burst", name: "爆炸形", symbol: "sun.max.fill"),
    .init(id: "crescent", name: "月牙", symbol: "moon.fill"),
    .init(id: "teardrop", name: "水滴", symbol: "drop.fill"),
    .init(id: "capsule", name: "胶囊", symbol: "capsule.fill"),
    .init(id: "pentagon", name: "五边形", symbol: "pentagon.fill"),
    .init(id: "octagon", name: "八边形", symbol: "octagon.fill"),
    .init(id: "bookmark", name: "书签", symbol: "bookmark.fill"),
  ]
}
enum ShapeGeometry {
  static func path(_ name: String, rect: CGRect, radius: Double = 20, sides: Int = 6) -> CGPath {
    let p = CGMutablePath()
    let w = rect.width
    let h = rect.height
    func polygon(_ values: [(Double, Double)]) {
      guard let first = values.first else { return }
      p.move(to: CGPoint(x: rect.minX + first.0 * w, y: rect.minY + first.1 * h))
      for (x, y) in values.dropFirst() {
        p.addLine(to: CGPoint(x: rect.minX + x * w, y: rect.minY + y * h))
      }
      p.closeSubpath()
    }
    func radial(_ count: Int, inner: Double? = nil) {
      let n = inner == nil ? count : count * 2
      polygon(
        (0..<n).map { i in
          let a = Double(i) * 2 * .pi / Double(n) - .pi / 2
          let r = inner == nil || i.isMultiple(of: 2) ? 0.5 : inner!
          return (0.5 + cos(a) * r, 0.5 + sin(a) * r)
        })
    }
    switch name {
    case "ellipse": p.addEllipse(in: rect)
    case "roundedRectangle", "capsule":
      let r = name == "capsule" ? min(w, h) / 2 : min(radius, min(w, h) / 2)
      p.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
    case "polygon": radial(max(3, min(24, sides)))
    case "pentagon": radial(5)
    case "hexagon": radial(6)
    case "octagon": radial(8)
    case "star": radial(max(3, min(24, sides)), inner: 0.21)
    case "star8": radial(8, inner: 0.27)
    case "burst": radial(16, inner: 0.32)
    case "flower": radial(12, inner: 0.39)
    case "triangle": polygon([(0.5, 0), (1, 1), (0, 1)])
    case "diamond": polygon([(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)])
    case "arrow":
      polygon([(0, 0.3), (0.62, 0.3), (0.62, 0), (1, 0.5), (0.62, 1), (0.62, 0.7), (0, 0.7)])
    case "chevron": polygon([(0, 0), (0.45, 0), (1, 0.5), (0.45, 1), (0, 1), (0.55, 0.5)])
    case "cross":
      polygon([
        (0.33, 0), (0.67, 0), (0.67, 0.33), (1, 0.33), (1, 0.67), (0.67, 0.67), (0.67, 1),
        (0.33, 1), (0.33, 0.67), (0, 0.67), (0, 0.33), (0.33, 0.33),
      ])
    case "trapezoid": polygon([(0.25, 0), (0.75, 0), (1, 1), (0, 1)])
    case "parallelogram": polygon([(0.3, 0), (1, 0), (0.7, 1), (0, 1)])
    case "shield": polygon([(0, 0), (1, 0), (0.9, 0.65), (0.5, 1), (0.1, 0.65)])
    case "bookmark": polygon([(0, 0), (1, 0), (1, 1), (0.5, 0.7), (0, 1)])
    case "ring":
      p.addEllipse(in: rect)
      p.addEllipse(in: rect.insetBy(dx: w * 0.2, dy: h * 0.2))
    case "bubble":
      p.addRoundedRect(
        in: CGRect(x: rect.minX, y: rect.minY, width: w, height: h * 0.78), cornerWidth: w * 0.12,
        cornerHeight: h * 0.12)
      polygon([(0.18, 0.7), (0.18, 1), (0.46, 0.7)])
    case "cloud":
      for (x, y, s) in [(0.0, 0.35, 0.5), (0.2, 0.0, 0.6), (0.53, 0.28, 0.47)] {
        p.addEllipse(
          in: CGRect(x: rect.minX + x * w, y: rect.minY + y * h, width: s * w, height: s * h))
      }
      p.addRect(
        CGRect(x: rect.minX + w * 0.2, y: rect.minY + h * 0.5, width: w * 0.6, height: h * 0.35))
    case "heart":
      p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
      p.addCurve(
        to: CGPoint(x: rect.midX, y: rect.minY + h * 0.22),
        control1: CGPoint(x: rect.minX - w * 0.4, y: rect.midY),
        control2: CGPoint(x: rect.minX + w * 0.1, y: rect.minY - h * 0.35))
      p.addCurve(
        to: CGPoint(x: rect.midX, y: rect.maxY),
        control1: CGPoint(x: rect.maxX - w * 0.1, y: rect.minY - h * 0.35),
        control2: CGPoint(x: rect.maxX + w * 0.4, y: rect.midY))
      p.closeSubpath()
    case "teardrop":
      p.move(to: CGPoint(x: rect.midX, y: rect.minY))
      p.addCurve(
        to: CGPoint(x: rect.midX, y: rect.maxY),
        control1: CGPoint(x: rect.maxX * 1.1, y: rect.midY),
        control2: CGPoint(x: rect.maxX, y: rect.maxY))
      p.addCurve(
        to: CGPoint(x: rect.midX, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.maxY),
        control2: CGPoint(x: rect.minX - w * 0.1, y: rect.midY))
      p.closeSubpath()
    case "crescent":
      p.addEllipse(in: rect)
      p.addEllipse(
        in: rect.offsetBy(dx: w * 0.22, dy: -h * 0.08).insetBy(dx: w * 0.06, dy: h * 0.06))
    case "ticket":
      polygon([
        (0, 0), (1, 0), (1, 0.35), (0.9, 0.5), (1, 0.65), (1, 1), (0, 1), (0, 0.65), (0.1, 0.5),
        (0, 0.35),
      ])
    default: p.addRect(rect)
    }
    return p
  }
}

@MainActor final class FontCatalog: ObservableObject {
  static let shared = FontCatalog()
  @Published var families: [String] = []
  init() { reload() }
  func reload() {
    families = NSFontManager.shared.availableFontFamilies.sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }
  func members(_ family: String) -> [(name: String, face: String)] {
    (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { row in
      guard row.count >= 2, let name = row[0] as? String, let face = row[1] as? String,
        !name.isEmpty else { return nil }
      return (name, face)
    }
  }
  func importFonts() throws {
    let panel = NSOpenPanel()
    panel.title = L("加载字体…")
    panel.prompt = L("添加")
    panel.allowedContentTypes = [.font]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
        "ImagePro/Fonts")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for source in panel.urls {
      let target = directory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
      try FileManager.default.copyItem(at: source, to: target)
      var failure: Unmanaged<CFError>?
      guard CTFontManagerRegisterFontsForURL(target as CFURL, .process, &failure) else {
        throw ImageProError.message("无法加载字体：\(source.lastPathComponent)")
      }
    }
    reload()
  }
  static func registerBundledAndPersonalFonts() {
    let personal = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0
    ].appendingPathComponent("ImagePro/Fonts")
    for folder in [Bundle.main.resourceURL?.appendingPathComponent("Fonts"), personal].compactMap({
      $0
    }) {
      for url
        in (try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: nil)) ?? []
      where ["otf", "ttf", "ttc"].contains(url.pathExtension.lowercased()) {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      }
    }
  }
}

struct VectorNode: Codable, Equatable {
  var kind: Int
  var points: [Point]
  static func path(_ nodes: [VectorNode], size: CGSize) -> CGPath {
    let path = CGMutablePath()
    for node in nodes {
      let p = node.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
      switch node.kind {
      case 0: if p.count == 1 { path.move(to: p[0]) }
      case 1: if p.count == 1 { path.addLine(to: p[0]) }
      case 2: if p.count == 2 { path.addQuadCurve(to: p[1], control: p[0]) }
      case 3: if p.count == 3 { path.addCurve(to: p[2], control1: p[0], control2: p[1]) }
      case 4: path.closeSubpath()
      default: break
      }
    }
    return path
  }
}
