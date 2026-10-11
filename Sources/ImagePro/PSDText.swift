import AppKit

struct TextRun: Codable, Equatable {
  var location: Int
  var length: Int
  var font: String
  var size: Double
  var color: RGBA
  var tracking: Double
  var bold: Bool
  var italic: Bool
  var underline: Bool
  var strikethrough: Bool
}
struct TextAppearance: Codable, Equatable {
  var text: String
  var font: String
  var size: Double
  var color: RGBA
  var style: TextStyle?
  var runs: [TextRun]?
  var width: Double
  var height: Double
  init(_ layer: ImageLayer) {
    text = layer.text; font = layer.fontName; size = layer.fontSize; color = layer.color
    style = layer.textStyle; runs = layer.textRuns; width = layer.width; height = layer.height
  }
}

indirect enum PSDValue {
  case object([String: PSDValue]), array([PSDValue]), string(String), number(Double), bool(Bool), data(Data)
  var object: [String: PSDValue] { if case .object(let v) = self { return v }; return [:] }
  var array: [PSDValue] { if case .array(let v) = self { return v }; return [] }
  var string: String? { if case .string(let v) = self { return v }; return nil }
  var number: Double? { if case .number(let v) = self { return v }; return nil }
  var bool: Bool { if case .bool(let v) = self { return v }; return false }
  var data: Data? { if case .data(let v) = self { return v }; return nil }
  subscript(_ key: String) -> PSDValue { object[key] ?? .object([:]) }
}

struct PSDDescriptor {
  var reader: PSDReader
  mutating func id() throws -> String {
    let n = try reader.int(4)
    guard n <= 1_000_000 else { throw ImageProError.message("PSD 描述符标识过长。") }
    return String(data: try reader.bytes(n == 0 ? 4 : n), encoding: .utf8) ?? ""
  }
  mutating func unicode() throws -> String {
    let n = try reader.int(4)
    guard n <= 1_000_000 else { throw ImageProError.message("PSD 文字过长。") }
    return String(data: try reader.bytes(n*2), encoding: .utf16BigEndian) ?? ""
  }
  mutating func descriptor(_ depth: Int = 0) throws -> PSDValue {
    guard depth < 32 else { throw ImageProError.message("PSD 描述符嵌套过深。") }
    _ = try unicode(); _ = try id()
    let count = try reader.int(4)
    guard count <= 10_000 else { throw ImageProError.message("PSD 描述符项目过多。") }
    var values: [String: PSDValue] = [:]
    for _ in 0..<count { let key = try id(); values[key] = try value(depth+1) }
    return .object(values)
  }
  mutating func value(_ depth: Int) throws -> PSDValue {
    guard depth < 32 else { throw ImageProError.message("PSD 描述符嵌套过深。") }
    let type = try reader.string(4)
    switch type {
    case "TEXT": return .string(try unicode())
    case "long": return .number(Double(try reader.signed(4)))
    case "doub": return .number(try reader.double())
    case "UntF": _ = try reader.bytes(4); return .number(try reader.double())
    case "bool": return .bool(try reader.int(1) != 0)
    case "enum": _ = try id(); return .string(try id())
    case "Objc", "GlbO": return try descriptor(depth+1)
    case "VlLs":
      let count = try reader.int(4)
      guard count <= 100_000 else { throw ImageProError.message("PSD 数组过长。") }
      var result: [PSDValue] = []
      for _ in 0..<count { result.append(try value(depth+1)) }
      return .array(result)
    case "tdta", "alis": return .data(try reader.bytes(reader.int(4)))
    case "type", "GlbC": _ = try unicode(); return .string(try id())
    default: throw ImageProError.message("未支持的 PSD 描述符类型："+type)
    }
  }
}

/// Bounded parser for PSD's PostScript-like EngineData. It handles binary
/// UTF-16 strings and escaped delimiters without executing any PostScript.
struct PSDEngineParser {
  var bytes: [UInt8]
  var index = 0
  mutating func whitespace() {
    while index < bytes.count && [0, 9, 10, 13, 32].contains(bytes[index]) { index += 1 }
  }
  mutating func parse(_ depth: Int = 0) throws -> PSDValue {
    guard depth < 40, index < bytes.count else { throw ImageProError.message("PSD EngineData 无效。") }
    whitespace()
    guard index < bytes.count else { throw ImageProError.message("PSD EngineData 截断。") }
    if bytes[index] == 60, index+1 < bytes.count, bytes[index+1] == 60 {
      index += 2; var dictionary: [String: PSDValue] = [:]
      while index < bytes.count {
        whitespace()
        if index+1 < bytes.count, bytes[index] == 62, bytes[index+1] == 62 { index += 2; return .object(dictionary) }
        guard index < bytes.count, bytes[index] == 47 else { throw ImageProError.message("PSD EngineData 键无效。") }
        index += 1
        let key = token()
        dictionary[key] = try parse(depth+1)
        guard dictionary.count <= 10000 else { throw ImageProError.message("PSD EngineData 过大。") }
      }
    } else if bytes[index] == 91 {
      index += 1; var values: [PSDValue] = []
      while index < bytes.count {
        whitespace()
        if index < bytes.count, bytes[index] == 93 { index += 1; return .array(values) }
        values.append(try parse(depth+1))
        guard values.count <= 100000 else { throw ImageProError.message("PSD EngineData 数组过大。") }
      }
    } else if bytes[index] == 40 {
      index += 1; var data = [UInt8](); var nesting = 1
      while index < bytes.count {
        var byte = bytes[index]; index += 1
        if byte == 92 {
          guard index < bytes.count else { break }
          byte = bytes[index]; index += 1
          if byte >= 48 && byte <= 55 {
            var number = Int(byte-48)
            for _ in 0..<2 where index < bytes.count && bytes[index] >= 48 && bytes[index] <= 55 {
              number = number*8 + Int(bytes[index]-48); index += 1
            }
            data.append(UInt8(truncatingIfNeeded: number)); continue
          }
          if byte == 110 { byte = 10 }; if byte == 114 { byte = 13 }; if byte == 116 { byte = 9 }
          data.append(byte); continue
        }
        if byte == 40 { nesting += 1 }
        if byte == 41 { nesting -= 1; if nesting == 0 {
          let value = Data(data)
          if data.count >= 2 && data[0] == 254 && data[1] == 255 {
            return .string(String(data: value.dropFirst(2), encoding: .utf16BigEndian) ?? "")
          }
          return .string(String(data: value, encoding: .utf8) ?? String(data: value, encoding: .macOSRoman) ?? "")
        } }
        data.append(byte)
      }
    } else {
      let word = token()
      if word == "true" { return .bool(true) }; if word == "false" { return .bool(false) }
      if let n = Double(word), n.isFinite {
        guard abs(n) <= 1_000_000 else { throw ImageProError.message("PSD 文字参数超出范围。") }
        return .number(n)
      }
      if !word.isEmpty { return .string(word) }
    }
    throw ImageProError.message("PSD EngineData 截断或类型无效。")
  }
  mutating func token() -> String {
    let start = index
    while index < bytes.count && ![0,9,10,13,32,91,93,60,62,40,41].contains(bytes[index]) { index += 1 }
    return String(bytes: bytes[start..<index], encoding: .ascii) ?? ""
  }
}

struct PSDTextMetadata {
  var text: String
  var transform: [Double]
  var runs: [TextRun]
  var style: TextStyle
  static func read(_ data: Data) throws -> PSDTextMetadata {
    var reader = PSDReader(data: data)
    guard try reader.int(2) == 1 else { throw ImageProError.message("不支持的 PSD 文字版本。") }
    var transform = [Double]()
    for _ in 0..<6 { transform.append(try reader.double()) }
    _ = try reader.int(2)
    guard try reader.int(4) == 16 else { throw ImageProError.message("不支持的 PSD 描述符版本。") }
    var descriptor = PSDDescriptor(reader: reader)
    let values = try descriptor.descriptor()
    guard let string = values["Txt "].string else { throw ImageProError.message("PSD 文字内容缺失。") }
    let text = string.replacingOccurrences(of: "\0", with: "").replacingOccurrences(of: "\r", with: "\n")
    var engine: PSDValue = .object([:])
    if let raw = values["EngineData"].data, raw.count < 16_000_000 {
      var parser = PSDEngineParser(bytes: Array(raw)); engine = try parser.parse()
    }
    let fonts = engine["ResourceDict"]["FontSet"].array
    let styles = engine["EngineDict"]["StyleRun"]["RunArray"].array
    let lengths = engine["EngineDict"]["StyleRun"]["RunLengthArray"].array
    var runs: [TextRun] = []; var location = 0
    let fontScale = max(0.01, hypot(transform[2], transform[3]))
    for (i, run) in styles.enumerated() {
      let properties = run["StyleSheet"]["StyleSheetData"]
      let fontIndex = Int(properties["Font"].number ?? 0)
      let font = fonts.indices.contains(fontIndex) ? fonts[fontIndex]["Name"].string ?? "Helvetica" : "Helvetica"
      let size = max(1, min(4096, (properties["FontSize"].number ?? 24)*fontScale))
      let components = properties["FillColor"]["Values"].array.map { $0.number ?? 0 }
      let color = components.count >= 4 ? RGBA(r: components[1], g: components[2], b: components[3], a: components[0]) : RGBA(r: 0, g: 0, b: 0)
      let count = lengths.indices.contains(i) ? Int(lengths[i].number ?? 0) : (text as NSString).length
      runs.append(TextRun(location: location, length: max(0, count), font: font, size: size, color: color,
        tracking: (properties["Tracking"].number ?? 0)*size/1000,
        bold: properties["FauxBold"].bool, italic: properties["FauxItalic"].bool,
        underline: properties["Underline"].bool, strikethrough: properties["Strikethrough"].bool))
      location += count
    }
    var style = TextStyle()
    style.vertical = values["Ornt"].string == "Vrtc"
    let paragraph = engine["EngineDict"]["ParagraphRun"]["RunArray"].array.first?["ParagraphSheet"]["Properties"] ?? .object([:])
    style.alignment = max(0, min(3, Int(paragraph["Justification"].number ?? 0)))
    style.lineHeight = min(10, max(0.1, paragraph["AutoLeading"].number ?? 1.2))
    if let first = runs.first {
      style.tracking = first.tracking; style.bold = first.bold; style.italic = first.italic
      style.underline = first.underline; style.strikethrough = first.strikethrough
    }
    return PSDTextMetadata(text: text, transform: transform, runs: runs, style: style)
  }
  func apply(to layer: inout ImageLayer) {
    layer.kind = .text; layer.text = text; layer.textStyle = style; layer.textRuns = runs
    if let first = runs.first { layer.fontName = first.font; layer.fontSize = first.size; layer.color = first.color }
    layer.importedTextAppearance = TextAppearance(layer)
  }
}
