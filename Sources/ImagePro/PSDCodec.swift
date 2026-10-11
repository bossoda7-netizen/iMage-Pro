import AppKit
import CZlib

struct PSDReader {
  let data: Data
  var offset = 0
  mutating func bytes(_ count: Int) throws -> Data {
    guard count >= 0, offset <= data.count - count else {
      throw ImageProError.message("PSD 文件截断或区块长度无效。")
    }
    defer { offset += count }
    return data.subdata(in: offset..<offset + count)
  }
  mutating func int(_ count: Int) throws -> Int {
    let value = try bytes(count).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    guard value <= UInt64(Int.max) else { throw ImageProError.message("PSD 区块过大。") }
    return Int(value)
  }
  mutating func signed(_ count: Int) throws -> Int {
    let value = try int(count)
    if count == 2 { return Int(Int16(bitPattern: UInt16(value))) }
    return Int(Int32(bitPattern: UInt32(value)))
  }
  mutating func string(_ count: Int) throws -> String {
    String(data: try bytes(count), encoding: .ascii) ?? ""
  }
  mutating func double() throws -> Double {
    let bits = try bytes(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    let result = Double(bitPattern: bits)
    guard result.isFinite else { throw ImageProError.message("PSD 包含无效的小数参数。") }
    return result
  }
  mutating func pascal(_ alignment: Int) throws -> String {
    let count = try int(1)
    let data = try bytes(count)
    let padding = (alignment - (count + 1) % alignment) % alignment
    _ = try bytes(padding)
    return String(data: data, encoding: .macOSRoman) ?? L("layer.generic")
  }
}
private struct PSDRecord {
  var rect: CGRect
  var channels: [(Int, Int)]
  var name: String
  var opacity: Double
  var visible: Bool
  var locked: Bool
  var blend: BlendMode
  var section = 0
  var maskRect: CGRect?
  var maskDefault = 255
  var maskDisabled = false
  var maskInverted = false
  var hasUnsupportedMetadata = false
  var text: PSDTextMetadata?
}
struct PSDEmbeddedProject: Codable {
  var signature = "imageProProjectV2"
  var archive: ProjectArchive
  var assets: [String: Data]
}
enum PSDCodec {
  static let blendKeys: [BlendMode: String] = [
    .normal: "norm", .dissolve: "diss", .darken: "dark", .multiply: "mul ", .colorBurn: "idiv", .linearBurn: "lbrn", .darkerColor: "dkCl",
    .lighten: "lite", .screen: "scrn", .colorDodge: "div ", .linearDodge: "lddg", .lighterColor: "lgCl",
    .overlay: "over", .softLight: "sLit", .hardLight: "hLit", .vividLight: "vLit", .linearLight: "lLit", .pinLight: "pLit", .hardMix: "hMix",
    .difference: "diff", .exclusion: "smud", .subtract: "fsub", .divide: "fdiv",
    .hue: "hue ", .saturation: "sat ", .color: "colr", .luminosity: "lum "
  ]
  static func read(_ bytes: Data) throws -> (
    ImageDocument, AssetLibrary, String?, PSDEmbeddedProject?
  ) {
    var reader = PSDReader(data: bytes)
    guard try reader.string(4) == "8BPS" else { throw ImageProError.message("不是有效的 PSD / PSB 文件。") }
    let version = try reader.int(2)
    guard version == 1 || version == 2 else { throw ImageProError.message("不支持这个 PSD 版本。") }
    _ = try reader.bytes(6)
    let channels = try reader.int(2)
    let height = try reader.int(4)
    let width = try reader.int(4)
    let depth = try reader.int(2)
    let mode = try reader.int(2)
    guard width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 100_000_000,
      depth == 8 || depth == 16, mode == 3 || mode == 1
    else {
      throw ImageProError.message("当前分层 PSD 支持 RGB / 灰度 8 或 16 bit；CMYK、32 bit 与超大 PSB 需要转换后导入。")
    }
    _ = try reader.bytes(reader.int(4))
    var resources = PSDReader(data: try reader.bytes(reader.int(4)))
    var embedded: PSDEmbeddedProject?
    while resources.offset + 12 <= resources.data.count {
      guard try resources.string(4) == "8BIM" else { break }
      let id = try resources.int(2)
      _ = try resources.pascal(2)
      let length = try resources.int(4)
      let value = try resources.bytes(length)
      if length % 2 == 1 { _ = try resources.bytes(1) }
      if id == 4001, length < 256_000_000,
        let project = try? JSONDecoder().decode(PSDEmbeddedProject.self, from: value),
        project.signature == "imageProProjectV2"
      {
        embedded = project
      }
    }
    if let embedded {
      try embedded.archive.document.validate()
      for entry in embedded.archive.undo + embedded.archive.redo {
        try entry.before.validate()
        try entry.after.validate()
      }
      let library = AssetLibrary()
      for (id, data) in embedded.assets {
        guard UUID(uuidString: id) != nil else { throw ImageProError.message("PSD 内嵌项目资源标识无效。") }
        library.insert(data, id: id)
      }
      for layer in embedded.archive.document.layers {
        for id in [layer.assetID, layer.maskAssetID].compactMap({ $0 }) {
          guard library.image(id) != nil else { throw ImageProError.message("PSD 内嵌资源缺失。") }
        }
      }
      return (embedded.archive.document, library, nil, embedded)
    }
    var document = ImageDocument()
    document.width = Double(width)
    document.height = Double(height)
    let library = AssetLibrary()
    let lengthBytes = version == 2 ? 8 : 4
    var layerSection = PSDReader(data: try reader.bytes(reader.int(lengthBytes)))
    guard layerSection.data.count >= lengthBytes else {
      throw ImageProError.message("PSD 没有图层记录；请以带图层的 PSD 保存。")
    }
    var info = PSDReader(data: try layerSection.bytes(layerSection.int(lengthBytes)))
    // Some high-bit-depth PSDs store layer information in a global Lr16 block.
    if info.data.isEmpty {
      if layerSection.offset + 4 <= layerSection.data.count {
        _ = try layerSection.bytes(layerSection.int(4))
      }
      while layerSection.offset + 12 <= layerSection.data.count {
        let signature = try layerSection.string(4)
        let key = try layerSection.string(4)
        let value = try layerSection.bytes(layerSection.int(signature == "8B64" ? 8 : 4))
        if key == "Lr16" || key == "Layr" {
          info = PSDReader(data: value)
          break
        }
      }
    }
    guard info.data.count >= 2 else { throw ImageProError.message("PSD 没有可恢复的分层数据。") }
    let count = abs(try info.signed(2))
    guard count <= 1000 else { throw ImageProError.message("PSD 图层数量超出 1000。") }
    var records = [PSDRecord]()
    var unsupported = 0
    var unknownBlends = 0
    for _ in 0..<count {
      let top = try info.signed(4)
      let left = try info.signed(4)
      let bottom = try info.signed(4)
      let right = try info.signed(4)
      let n = try info.int(2)
      guard n <= 64 else { throw ImageProError.message("PSD 通道数量无效。") }
      var channelInfo = [(Int, Int)]()
      for _ in 0..<n { channelInfo.append((try info.signed(2), try info.int(lengthBytes))) }
      guard try info.string(4) == "8BIM" else { throw ImageProError.message("PSD 混合区块无效。") }
      let blendKey = try info.string(4)
      let opacity = Double(try info.int(1)) / 255
      _ = try info.int(1)
      let flags = try info.int(1)
      _ = try info.int(1)
      var extra = PSDReader(data: try info.bytes(info.int(4)))
      var record = PSDRecord(
        rect: CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top)),
        channels: channelInfo, name: L("layer.generic"), opacity: opacity, visible: flags & 2 == 0,
        locked: flags & 1 != 0, blend: blendKeys.first { $0.value == blendKey }?.key ?? .normal)
      if !blendKeys.values.contains(blendKey) && blendKey != "pass" { unknownBlends += 1 }
      var mask = PSDReader(data: try extra.bytes(extra.int(4)))
      if mask.data.count >= 18 {
        let mt = try mask.signed(4)
        let ml = try mask.signed(4)
        let mb = try mask.signed(4)
        let mr = try mask.signed(4)
        record.maskRect = CGRect(x: ml, y: mt, width: max(0, mr - ml), height: max(0, mb - mt))
        record.maskDefault = try mask.int(1)
        let mf = try mask.int(1)
        if mf & 1 != 0 {
          record.maskRect = record.maskRect?.offsetBy(dx: Double(left), dy: Double(top))
        }
        record.maskDisabled = mf & 2 != 0
        record.maskInverted = mf & 4 != 0
      }
      _ = try extra.bytes(extra.int(4))
      record.name = try extra.pascal(4)
      while extra.offset + 12 <= extra.data.count {
        let signature = try extra.string(4)
        let key = try extra.string(4)
        guard signature == "8BIM" || signature == "8B64" else { break }
        let blockSize = try extra.int(signature == "8B64" ? 8 : 4)
        let block = try extra.bytes(blockSize)
        if blockSize % 2 == 1 && extra.offset < extra.data.count { _ = try extra.bytes(1) }
        if key == "luni" {
          var unicode = PSDReader(data: block)
          let n = try unicode.int(4)
          if n <= 1_000_000 {
            record.name =
              String(data: try unicode.bytes(n * 2), encoding: .utf16BigEndian) ?? record.name
          }
        } else if key == "lsct" || key == "lsdk" {
          var section = PSDReader(data: block)
          record.section = try section.int(4)
        } else if key == "TySh" {
          record.text = try? PSDTextMetadata.read(block)
          if record.text == nil { record.hasUnsupportedMetadata = true }
        } else if ["SoLd", "SoLE", "vmsk", "lfx2", "lrFX", "brit", "levl", "curv", "hue2"]
          .contains(key)
        {
          record.hasUnsupportedMetadata = true
        }
      }
      if record.hasUnsupportedMetadata { unsupported += 1 }
      records.append(record)
    }
    var imported = [(ImageLayer, Int)]()
    for record in records {
      let w = Int(record.rect.width)
      let h = Int(record.rect.height)
      guard w <= 32768, h <= 32768, w * h <= 100_000_000 else {
        throw ImageProError.message("PSD 单个图层过大。")
      }
      var planes = [Int: [UInt8]]()
      for (id, length) in record.channels {
        let encoded = try info.bytes(length)
        let mask = id == -2 || id == -3
        let cw = mask ? Int(record.maskRect?.width ?? 0) : w
        let ch = mask ? Int(record.maskRect?.height ?? 0) : h
        if cw > 0, ch > 0, cw * ch <= 100_000_000 {
          planes[id] = try decodeChannel(
            encoded, width: cw, height: ch, depth: depth, version: version)
        }
      }
      var layer = ImageLayer(
        name: record.name, kind: record.section == 1 || record.section == 2 ? .group : .raster,
        width: max(1, record.rect.width), height: max(1, record.rect.height))
      layer.x = record.rect.minX
      layer.y = record.rect.minY
      layer.opacity = record.opacity
      layer.blend = record.blend
      layer.visible = record.visible
      layer.locked = record.locked
      if layer.kind != .group, record.section != 3, w > 0, h > 0 {
        let pixels = w * h
        var rgba = [UInt8](repeating: 255, count: pixels * 4)
        for i in 0..<pixels {
          rgba[i * 4] = planes[0]?[i] ?? 0
          rgba[i * 4 + 1] = planes[mode == 1 ? 0 : 1]?[i] ?? 0
          rgba[i * 4 + 2] = planes[mode == 1 ? 0 : 2]?[i] ?? 0
          rgba[i * 4 + 3] = planes[-1]?[i] ?? 255
        }
        guard let image = makeImage(rgba, width: w, height: h) else {
          throw ImageProError.message("PSD 图层解码失败。")
        }
        layer.assetID = try library.insert(image)
        if let maskData = planes[-2], let mr = record.maskRect, let cg = ImageRenderer.bitmap(w, h)
        {
          cg.setFillColor(NSColor(white: Double(record.maskDefault) / 255, alpha: 1).cgColor)
          cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
          cg.translateBy(x: 0, y: Double(h))
          cg.scaleBy(x: 1, y: -1)
          var maskRGBA = [UInt8]()
          maskRGBA.reserveCapacity(maskData.count * 4)
          for value in maskData {
            let v = record.maskInverted ? 255 - value : value
            maskRGBA.append(contentsOf: [v, v, v, 255])
          }
          if let maskImage = makeImage(maskRGBA, width: Int(mr.width), height: Int(mr.height)) {
            ImageRenderer.draw(
              maskImage, in: mr.offsetBy(dx: -record.rect.minX, dy: -record.rect.minY), context: cg)
            if let result = cg.makeImage() {
              layer.maskAssetID = try library.insert(result)
              layer.maskEnabled = !record.maskDisabled
            }
          }
        }
      }
      if let text = record.text, layer.kind != .group { text.apply(to: &layer) }
      imported.append((layer, record.section))
    }
    // PSD records are bottom-to-top. Resolve folder dividers in top-to-bottom UI order.
    var stack = [UUID]()
    for (var layer, section) in imported.reversed() {
      if section == 3 {
        if !stack.isEmpty { stack.removeLast() }
        continue
      }
      layer.parentID = stack.last
      if layer.kind == .group { stack.append(layer.id) }
      if layer.kind == .group || layer.assetID != nil { document.layers.append(layer) }
    }
    document.selectedLayerID = document.layers.first { $0.kind != .group }?.id
    guard !document.layers.isEmpty else { throw ImageProError.message("这个 PSD 没有可读取的像素图层。") }
    try document.validate()
    let warning =
      unsupported > 0 || unknownBlends > 0 || depth == 16
      ? "已恢复 \(document.layers.count) 个图层。部分文字、矢量、智能对象或样式使用 PSD 缓存像素；当前编辑器输出为 8 bit。" : nil
    _ = channels
    return (document, library, warning, nil)
  }
  static func decodeChannel(_ bytes: Data, width: Int, height: Int, depth: Int, version: Int) throws
    -> [UInt8]
  {
    var r = PSDReader(data: bytes)
    let compression = try r.int(2)
    let rowBytes = width * (depth / 8)
    let size = rowBytes * height
    var decoded = [UInt8]()
    switch compression {
    case 0: decoded = Array(try r.bytes(size))
    case 1:
      var counts = [Int]()
      for _ in 0..<height { counts.append(try r.int(version == 2 ? 4 : 2)) }
      for count in counts {
        let row = Array(try r.bytes(count))
        var output = [UInt8]()
        var i = 0
        while i < row.count, output.count < rowBytes {
          let n = Int(Int8(bitPattern: row[i]))
          i += 1
          if n >= 0 {
            let length = n + 1
            guard i + length <= row.count else { throw ImageProError.message("PSD RLE 数据无效。") }
            output.append(contentsOf: row[i..<i + length])
            i += length
          } else if n > -128 {
            guard i < row.count else { throw ImageProError.message("PSD RLE 数据无效。") }
            output.append(contentsOf: repeatElement(row[i], count: 1 - n))
            i += 1
          }
        }
        guard output.count == rowBytes else { throw ImageProError.message("PSD RLE 行长度错误。") }
        decoded.append(contentsOf: output)
      }
    case 2, 3:
      let input = try r.bytes(bytes.count - r.offset)
      decoded = [UInt8](repeating: 0, count: size)
      var length = uLongf(size)
      let result = input.withUnsafeBytes { src in
        decoded.withUnsafeMutableBytes { dst in
          uncompress(
            dst.bindMemory(to: UInt8.self).baseAddress!, &length,
            src.bindMemory(to: UInt8.self).baseAddress!, uLong(input.count))
        }
      }
      guard result == Z_OK, Int(length) == size else {
        throw ImageProError.message("PSD ZIP 解压失败。")
      }
      if compression == 3 {
        if depth == 8 {
          for y in 0..<height {
            for x in 1..<rowBytes {
              let i = y * rowBytes + x
              decoded[i] = decoded[i] &+ decoded[i - 1]
            }
          }
        } else {
          for y in 0..<height {
            for x in 1..<width {
              let i = y * rowBytes + x * 2
              let previous = i - 2
              let v = (UInt16(decoded[i]) << 8) | UInt16(decoded[i + 1])
              let a = (UInt16(decoded[previous]) << 8) | UInt16(decoded[previous + 1])
              let sum = v &+ a
              decoded[i] = UInt8(sum >> 8)
              decoded[i + 1] = UInt8(truncatingIfNeeded: sum)
            }
          }
        }
      }
    default: throw ImageProError.message("未知的 PSD 压缩方式。")
    }
    return depth == 8 ? decoded : stride(from: 0, to: decoded.count, by: 2).map { decoded[$0] }
  }
  static func makeImage(_ rgba: [UInt8], width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0, let provider = CGDataProvider(data: Data(rgba) as CFData) else {
      return nil
    }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: ImageRenderer.colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
      decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
  static func write(
    document: ImageDocument, assets: AssetLibrary, renderer: ImageRenderer,
    archive: ProjectArchive? = nil
  ) throws -> Data {
    try document.validate()
    guard document.width <= 30000, document.height <= 30000 else {
      throw ImageProError.message("PSD 尺寸超出格式限制。")
    }
    let w = Int(document.width)
    let h = Int(document.height)
    var out = Data()
    out.ascii("8BPS")
    out.be(1, 2)
    out.append(Data(repeating: 0, count: 6))
    out.be(4, 2)
    out.be(h, 4)
    out.be(w, 4)
    out.be(8, 2)
    out.be(3, 2)
    out.be(0, 4)
    var resources = Data()
    if let archive {
      let embedded = try JSONEncoder().encode(
        PSDEmbeddedProject(archive: archive, assets: assets.data))
      guard embedded.count < 256_000_000 else {
        throw ImageProError.message("PSD 内嵌原生项目过大，请先保存 .imgp 项目。")
      }
      resources.ascii("8BIM")
      resources.be(4001, 2)
      resources.be(0, 2)
      resources.be(embedded.count, 4)
      resources.append(embedded)
      if embedded.count % 2 == 1 { resources.be(0, 1) }
    }
    out.be(resources.count, 4)
    out.append(resources)
    // Native FX graphs have no universal PSD equivalent. Keep the complete source
    // layer stack in a hidden group and include an exact visible projection for
    // external editors; the embedded archive restores semantic layers in image Pro.
    var externalDocument = document
    if document.layers.contains(where: { $0.kind == .adjustment }) {
      guard let merged = renderer.render(document,assets:assets,maxDimension:nil) else {
        throw ImageProError.message("无法生成 PSD 调整图层兼容预览。")
      }
      var projection = ImageLayer(name:L("image Pro · FX 兼容合成"),kind:.raster,width:document.width,height:document.height)
      projection.assetID = try assets.insert(merged)
      var group = ImageLayer(name:L("原始图层 · 含 image Pro FX"),kind:.group,width:document.width,height:document.height)
      group.visible = false
      let preserved = document.layers.map { layer -> ImageLayer in
        var copy = layer
        if copy.parentID == nil { copy.parentID = group.id }
        return copy
      }
      externalDocument.layers = [projection,group] + preserved
    }
    var exportLayers = [(ImageLayer, Int)]()
    func appendChildren(_ parent: UUID?) {
      for layer in externalDocument.layers where layer.parentID == parent {
        if layer.kind == .group {
          exportLayers.append((layer, 1))
          appendChildren(layer.id)
          var end = layer
          end.name = "</Layer group>"
          exportLayers.append((end, 3))
        } else {
          exportLayers.append((layer, 0))
        }
      }
    }
    appendChildren(nil)
    exportLayers.reverse()
    var records = Data()
    var channelData = Data()
    records.be(-exportLayers.count, 2)
    for (layer, section) in exportLayers {
      let rect: CGRect
      let image: CGImage?
      if section != 0 {
        rect = .zero
        image = nil
      } else {
        let q = layer.quad ?? TransformGeometry.corners
        let padding = ImageRenderer.outset(layer)*max(1,q.map {abs($0.x)+abs($0.y)}.max() ?? 1)
        rect = SnapEngine.bounds(layer).insetBy(dx:-padding,dy:-padding).integral
        guard rect.width <= 32768, rect.height <= 32768, rect.width * rect.height <= 40_000_000
        else { throw ImageProError.message("变换后的 PSD 图层过大，请缩小图层或保存 .imgp。") }
        var temp = document
        temp.width = rect.width
        temp.height = rect.height
        var l = layer
        l.x -= rect.minX
        l.y -= rect.minY
        l.parentID = nil
        l.visible = true
        l.opacity = 1
        l.blend = .normal
        temp.layers = [l]
        image = renderer.render(temp, assets: assets, maxDimension: nil)
      }
      let planes: [[UInt8]] = image.map { pixelPlanes($0) } ?? [[], [], [], []]
      records.be(Int(rect.minY), 4)
      records.be(Int(rect.minX), 4)
      records.be(Int(rect.maxY), 4)
      records.be(Int(rect.maxX), 4)
      records.be(4, 2)
      for (i, id) in [0, 1, 2, -1].enumerated() {
        let encoded = planes[i].isEmpty ? Data([0, 0]) : try encodeZIP(planes[i])
        records.be(id, 2)
        records.be(encoded.count, 4)
        channelData.append(encoded)
      }
      records.ascii("8BIM")
      records.ascii(blendKeys[layer.blend] ?? "norm")
      records.be(Int((layer.opacity * 255).rounded()), 1)
      records.be(0, 1)
      records.be((layer.visible ? 0 : 2) | (layer.locked ? 1 : 0), 1)
      records.be(0, 1)
      var extra = Data()
      extra.be(0, 4)
      extra.be(0, 4)
      extra.pascal(layer.name, alignment: 4)
      var name = Data()
      name.be(layer.name.utf16.count, 4)
      for c in layer.name.utf16 { name.be(Int(c), 2) }
      extra.ascii("8BIMluni")
      extra.be(name.count, 4)
      extra.append(name)
      if name.count % 2 == 1 { extra.be(0, 1) }
      if section != 0 {
        extra.ascii("8BIMlsct")
        extra.be(12, 4)
        extra.be(section, 4)
        extra.ascii("8BIM")
        extra.ascii("pass")
      }
      records.be(extra.count, 4)
      records.append(extra)
    }
    records.append(channelData)
    if records.count % 2 == 1 { records.be(0, 1) }
    var layerMask = Data()
    layerMask.be(records.count, 4)
    layerMask.append(records)
    layerMask.be(0, 4)
    out.be(layerMask.count, 4)
    out.append(layerMask)
    out.be(0, 2)
    guard let merged = renderer.render(document, assets: assets, maxDimension: nil) else {
      throw ImageProError.message("PSD 合成预览渲染失败。")
    }
    for plane in pixelPlanes(merged) { out.append(contentsOf: plane) }
    return out
  }
  static func encodeZIP(_ plane: [UInt8]) throws -> Data {
    var length = compressBound(uLong(plane.count))
    var output = [UInt8](repeating: 0, count: Int(compressBound(uLong(plane.count))))
    let status = plane.withUnsafeBytes { input in
      output.withUnsafeMutableBytes { target in
        compress2(
          target.bindMemory(to: UInt8.self).baseAddress!, &length,
          input.bindMemory(to: UInt8.self).baseAddress!, uLong(plane.count), Z_BEST_SPEED)
      }
    }
    guard status == Z_OK else { throw ImageProError.message("PSD 通道压缩失败。") }
    var data = Data([0, 2])
    data.append(contentsOf: output.prefix(Int(length)))
    return data
  }
  static func pixelPlanes(_ image: CGImage) -> [[UInt8]] {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let count = image.width * image.height
    var planes = Array(repeating: [UInt8](repeating: 0, count: count), count: 4)
    guard let data = bitmap.bitmapData else { return planes }
    // NSBitmapImageRep created from CGImage may use premultiplied components.
    for y in 0..<image.height {
      for x in 0..<image.width {
        let index = y * image.width + x
        let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
        let alpha = bitmap.hasAlpha ? Int(data[offset + 3]) : 255
        for c in 0..<3 {
          let raw = Int(data[offset + c])
          planes[c][index] = UInt8(
            min(
              255,
              bitmap.bitmapFormat.contains(.alphaNonpremultiplied) || alpha == 0
                ? raw : raw * 255 / max(1, alpha)))
        }
        planes[3][index] = UInt8(alpha)
      }
    }
    return planes
  }
}
extension Data {
  fileprivate mutating func be(_ value: Int, _ count: Int) {
    for i in (0..<count).reversed() { append(UInt8(truncatingIfNeeded: value >> (i * 8))) }
  }
  fileprivate mutating func ascii(_ value: String) { append(value.data(using: .ascii) ?? Data()) }
  fileprivate mutating func pascal(_ value: String, alignment: Int) {
    let bytes = Array((value.data(using: .macOSRoman) ?? Data("Layer".utf8)).prefix(255))
    be(bytes.count, 1)
    append(contentsOf: bytes)
    append(Data(repeating: 0, count: (alignment - (bytes.count + 1) % alignment) % alignment))
  }
}
