import Foundation

enum CanvasUnit: String, CaseIterable, Identifiable {
  case pixels = "像素", millimeters = "毫米", centimeters = "厘米", inches = "英寸"
  var id: Self { self }
  var symbol: String {
    switch self {
    case .pixels: return "px"
    case .millimeters: return "mm"
    case .centimeters: return "cm"
    case .inches: return "in"
    }
  }
  func pixelsPerUnit(dpi: Double) -> Double {
    switch self {
    case .pixels: return 1
    case .millimeters: return dpi / 25.4
    case .centimeters: return dpi / 2.54
    case .inches: return dpi
    }
  }
}

struct CanvasDraft {
  var name = L("未命名")
  var author = ""
  var width = "1920"
  var height = "1080"
  var resolution = "300"
  var unit = CanvasUnit.pixels
  var lockAspect = false
  var aspectRatio = 16.0 / 9.0
  var showGrid = false
  var showRulers = false

  var dpi: Double? { Double(resolution) }
  var pixelSize: (width: Double, height: Double)? {
    guard let width = Double(width), let height = Double(height), let dpi,
      width.isFinite, height.isFinite, dpi.isFinite,
      width > 0, height > 0, (1...2400).contains(dpi) else { return nil }
    let factor = unit.pixelsPerUnit(dpi: dpi)
    return ((width * factor).rounded(), (height * factor).rounded())
  }
  var validationMessage: String? {
    guard let size = pixelSize else { return "请输入有效的宽高和分辨率（1–2400 DPI）。" }
    guard size.width >= 1, size.height >= 1 else { return "换算后的宽高不能小于 1 px。" }
    guard size.width <= 16384, size.height <= 16384 else { return "画布单边不能超过 16384 px。" }
    guard size.width * size.height <= 100_000_000 else { return "画布总像素不能超过 1 亿。" }
    return nil
  }
  mutating func changeUnit(to newUnit: CanvasUnit) {
    guard newUnit != unit else { return }
    if let dpi, dpi.isFinite, dpi > 0,
      let w = Double(width), let h = Double(height) {
      let factor = unit.pixelsPerUnit(dpi: dpi) / newUnit.pixelsPerUnit(dpi: dpi)
      width = Self.number(w * factor, unit: newUnit)
      height = Self.number(h * factor, unit: newUnit)
    }
    unit = newUnit
  }
  mutating func setDimension(_ text: String, width isWidth: Bool) {
    if isWidth { width = text } else { height = text }
    guard lockAspect, let value = Double(text), value.isFinite, value > 0 else { return }
    if isWidth { height = Self.number(value / aspectRatio, unit: unit) }
    else { width = Self.number(value * aspectRatio, unit: unit) }
  }
  mutating func setAspectLock(_ locked: Bool) {
    if let w = Double(width), let h = Double(height), w.isFinite, h.isFinite, w > 0, h > 0 {
      aspectRatio = w / h
    }
    lockAspect = locked
  }
  mutating func orient(portrait: Bool) {
    guard let w = Double(width), let h = Double(height), w != h,
      (w < h) != portrait else { return }
    swap(&width, &height)
    aspectRatio = h / w
  }
  private static func number(_ value: Double, unit: CanvasUnit) -> String {
    guard value.isFinite, abs(value) < Double(Int.max) else { return String(value) }
    if unit == .pixels { return String(Int(value.rounded())) }
    return String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
      .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
      .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
  }
}

enum PresetCategory: String, CaseIterable, Identifiable {
  case featured = "精选", social = "社交", screen = "屏幕", print = "印刷", photo = "照片", device = "设备"
  var id: Self { self }
}

struct CanvasPreset: Identifiable {
  var id: String
  var name: String
  var width: Double
  var height: Double
  var dpi: Double
  var category: PresetCategory
  var featured = false
  var dimensions: String { "\(Int(width)) × \(Int(height))" }
  static let all: [CanvasPreset] = [
    .init(id: "square", name: "社交方图", width: 1080, height: 1080, dpi: 72, category: .social, featured: true),
    .init(id: "portrait45", name: "社交竖图 · 4:5", width: 1080, height: 1350, dpi: 72, category: .social, featured: true),
    .init(id: "portrait34", name: "社交竖图 · 3:4", width: 1080, height: 1440, dpi: 72, category: .social),
    .init(id: "story", name: "故事 / 竖屏视频", width: 1080, height: 1920, dpi: 72, category: .social, featured: true),
    .init(id: "avatar", name: "头像", width: 512, height: 512, dpi: 72, category: .social),
    .init(id: "red-cover", name: "小红书封面", width: 1242, height: 1660, dpi: 72, category: .social),
    .init(id: "wechat", name: "公众号首图", width: 900, height: 383, dpi: 72, category: .social),
    .init(id: "wechat-square", name: "公众号次图", width: 900, height: 900, dpi: 72, category: .social),
    .init(id: "youtube-cover", name: "YouTube 频道封面", width: 2560, height: 1440, dpi: 72, category: .social),
    .init(id: "video-thumb", name: "视频缩略图", width: 1280, height: 720, dpi: 72, category: .social),
    .init(id: "bilibili", name: "哔哩哔哩封面", width: 1920, height: 1080, dpi: 72, category: .social),
    .init(id: "x-header", name: "X 个人页横幅", width: 1500, height: 500, dpi: 72, category: .social),
    .init(id: "linkedin", name: "LinkedIn 横幅", width: 1584, height: 396, dpi: 72, category: .social),
    .init(id: "facebook", name: "Facebook 封面", width: 820, height: 312, dpi: 72, category: .social),
    .init(id: "hd", name: "HD · 720p", width: 1280, height: 720, dpi: 72, category: .screen),
    .init(id: "fhd", name: "Full HD · 1080p", width: 1920, height: 1080, dpi: 72, category: .screen, featured: true),
    .init(id: "qhd", name: "QHD · 1440p", width: 2560, height: 1440, dpi: 72, category: .screen),
    .init(id: "uhd", name: "4K · UHD", width: 3840, height: 2160, dpi: 72, category: .screen, featured: true),
    .init(id: "dci4k", name: "4K · DCI", width: 4096, height: 2160, dpi: 72, category: .screen),
    .init(id: "5k", name: "5K", width: 5120, height: 2880, dpi: 72, category: .screen),
    .init(id: "6k", name: "6K", width: 6016, height: 3384, dpi: 72, category: .screen),
    .init(id: "8k", name: "8K", width: 7680, height: 4320, dpi: 72, category: .screen),
    .init(id: "web", name: "网页设计", width: 1440, height: 900, dpi: 72, category: .screen),
    .init(id: "wide", name: "超宽屏", width: 3440, height: 1440, dpi: 72, category: .screen),
    .init(id: "a0", name: "A0 · 150 DPI", width: 4967, height: 7022, dpi: 150, category: .print),
    .init(id: "a1", name: "A1", width: 7016, height: 9933, dpi: 300, category: .print),
    .init(id: "a2", name: "A2", width: 4961, height: 7016, dpi: 300, category: .print),
    .init(id: "a3", name: "A3", width: 3508, height: 4961, dpi: 300, category: .print),
    .init(id: "a4", name: "A4", width: 2480, height: 3508, dpi: 300, category: .print, featured: true),
    .init(id: "a5", name: "A5", width: 1748, height: 2480, dpi: 300, category: .print),
    .init(id: "a6", name: "A6 / 明信片", width: 1240, height: 1748, dpi: 300, category: .print),
    .init(id: "b4", name: "B4 · ISO", width: 2953, height: 4169, dpi: 300, category: .print),
    .init(id: "b5", name: "B5 · ISO", width: 2079, height: 2953, dpi: 300, category: .print),
    .init(id: "letter", name: "US Letter", width: 2550, height: 3300, dpi: 300, category: .print),
    .init(id: "legal", name: "US Legal", width: 2550, height: 4200, dpi: 300, category: .print),
    .init(id: "tabloid", name: "Tabloid", width: 3300, height: 5100, dpi: 300, category: .print),
    .init(id: "business", name: "名片 · 90 × 54 mm", width: 1063, height: 638, dpi: 300, category: .print),
    .init(id: "poster", name: "海报 · 50 × 70 cm", width: 5906, height: 8268, dpi: 300, category: .print),
    .init(id: "photo46", name: "照片 · 4 × 6 in", width: 1200, height: 1800, dpi: 300, category: .photo),
    .init(id: "photo57", name: "照片 · 5 × 7 in", width: 1500, height: 2100, dpi: 300, category: .photo),
    .init(id: "photo810", name: "照片 · 8 × 10 in", width: 2400, height: 3000, dpi: 300, category: .photo),
    .init(id: "photo1012", name: "照片 · 10 × 12 in", width: 3000, height: 3600, dpi: 300, category: .photo),
    .init(id: "photo1216", name: "照片 · 12 × 16 in", width: 3600, height: 4800, dpi: 300, category: .photo),
    .init(id: "photo1620", name: "照片 · 16 × 20 in", width: 4800, height: 6000, dpi: 300, category: .photo),
    .init(id: "photo2024", name: "照片 · 20 × 24 in", width: 6000, height: 7200, dpi: 300, category: .photo),
    .init(id: "photography", name: "摄影 · 横向 3:2", width: 3000, height: 2000, dpi: 300, category: .photo, featured: true),
    .init(id: "portrait", name: "摄影 · 纵向 2:3", width: 2000, height: 3000, dpi: 300, category: .photo),
    .init(id: "photo-square", name: "摄影 · 方形", width: 3000, height: 3000, dpi: 300, category: .photo),
    .init(id: "panorama", name: "全景 · 3:1", width: 6000, height: 2000, dpi: 300, category: .photo),
    .init(id: "iphone-large", name: "iPhone · 大屏壁纸", width: 1320, height: 2868, dpi: 72, category: .device),
    .init(id: "iphone", name: "iPhone · 壁纸", width: 1206, height: 2622, dpi: 72, category: .device, featured: true),
    .init(id: "iphone-legacy", name: "iPhone · 1170 px", width: 1170, height: 2532, dpi: 72, category: .device),
    .init(id: "android", name: "Android · 壁纸", width: 1080, height: 2400, dpi: 72, category: .device),
    .init(id: "android-qhd", name: "Android · QHD", width: 1440, height: 3200, dpi: 72, category: .device),
    .init(id: "ipad", name: "iPad · 11 英寸", width: 1668, height: 2420, dpi: 72, category: .device),
    .init(id: "ipad-large", name: "iPad · 13 英寸", width: 2064, height: 2752, dpi: 72, category: .device),
    .init(id: "app-icon", name: "App 图标", width: 1024, height: 1024, dpi: 72, category: .device),
    .init(id: "icon512", name: "图标 · 512 px", width: 512, height: 512, dpi: 72, category: .device),
    .init(id: "favicon", name: "网站图标", width: 64, height: 64, dpi: 72, category: .device),
  ]
}

struct ProjectFolder: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var createdAt = Date()
  var parentID: UUID?
  var libraryIdentifier: String {"folder:"+id.uuidString}
}

struct RecentProject: Codable, Identifiable {
  // Kept for decoding older UI strings and compatibility with the legacy
  // helper. The app now uses recordingUnlimited for its project library.
  static let limit = 8
  var path: String
  var name: String
  var width: Double
  var height: Double
  var lastOpened: Date
  var thumbnail: Data?
  var folderID: UUID?
  var id: String { path }
  var url: URL { URL(fileURLWithPath: path) }

  static func recording(_ entry: RecentProject, in entries: [RecentProject]) -> [RecentProject] {
    let key = entry.url.standardizedFileURL.path
    return Array(([entry] + entries.filter { $0.url.standardizedFileURL.path != key }).prefix(limit))
  }
  static func recordingUnlimited(_ entry: RecentProject, in entries: [RecentProject]) -> [RecentProject] {
    let key = entry.url.standardizedFileURL.path
    return [entry] + entries.filter { $0.url.standardizedFileURL.path != key }
  }
}
