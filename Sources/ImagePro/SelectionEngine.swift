import AppKit
import CoreImage

enum SelectionEngine {
  static func region(
    image: CGImage, point: CGPoint, canvasSize: CGSize, tolerance: Double, contiguous: Bool,
    brushDiameter: Double = 0
  ) -> SelectionRegion? {
    let maxSize = 900.0
    let scale = min(1, maxSize / Double(max(image.width, image.height)))
    let w = max(1, Int(Double(image.width) * scale))
    let h = max(1, Int(Double(image.height) * scale))
    guard let cg = ImageRenderer.bitmap(w, h) else { return nil }
    cg.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let bytes = cg.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    let sx = max(0, min(w - 1, Int(point.x / canvasSize.width * Double(w))))
    let sy = max(0, min(h - 1, Int(point.y / canvasSize.height * Double(h))))
    let seed = (sy * w + sx) * 4
    let alpha = max(1, Int(bytes[seed + 3]))
    let target = (0..<3).map { Double(bytes[seed + $0]) * 255 / Double(alpha) }
    let radius = contiguous ? max(0,brushDiameter/2*Double(w)/canvasSize.width) : 0
    var targets = [target]
    if radius > 1 {
      for angle in 0..<8 {
        let a = Double(angle) * .pi / 4
        let x = max(0,min(w-1,sx+Int(cos(a)*radius*0.65))),y = max(0,min(h-1,sy+Int(sin(a)*radius*0.65)))
        let sample = (y*w+x)*4,sa = max(1,Int(bytes[sample+3]))
        if sa >= 4 { targets.append((0..<3).map { Double(bytes[sample+$0])*255/Double(sa) }) }
      }
    }
    let threshold = pow(max(0.005,tolerance)*255,2)*3
    func matches(_ i: Int) -> Bool {
      let a = Int(bytes[i * 4 + 3])
      if a < 4 { return alpha < 4 }
      let r = Double(bytes[i*4])*255/Double(a),g = Double(bytes[i*4+1])*255/Double(a),b = Double(bytes[i*4+2])*255/Double(a)
      return targets.contains { sample in
        let dr = r-sample[0],dg = g-sample[1],db = b-sample[2]
        return dr*dr+dg*dg+db*db < threshold
      }
    }
    var selected = [UInt8](repeating: 0, count: w * h)
    if contiguous {
      var visited = [UInt8](repeating: 0, count: w * h)
      var queue = [sy * w + sx]
      var head = 0
      visited[queue[0]] = 1
      if radius > 1 {
        for y in max(0,sy-Int(ceil(radius)))...min(h-1,sy+Int(ceil(radius))) {
          for x in max(0,sx-Int(ceil(radius)))...min(w-1,sx+Int(ceil(radius)))
            where hypot(Double(x-sx),Double(y-sy)) <= radius && visited[y*w+x] == 0 {
            queue.append(y*w+x);visited[y*w+x] = 1
          }
        }
      }
      while head < queue.count {
        let i = queue[head]
        head += 1
        guard matches(i) else { continue }
        selected[i] = 1
        let x = i % w
        let y = i / w
        for next in [
          x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1,
        ] where next >= 0 && visited[next] == 0 {
          visited[next] = 1
          queue.append(next)
        }
      }
    } else {
      for i in 0..<w * h where matches(i) { selected[i] = 1 }
    }
    return spans(selected, width: w, height: h, size: canvasSize)
  }
  static func spans(_ bytes: [UInt8], width: Int, height: Int, size: CGSize) -> SelectionRegion? {
    var spans = [SelectionSpan]()
    let sx = size.width / Double(width)
    let sy = size.height / Double(height)
    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0
    for y in 0..<height {
      var x = 0
      while x < width {
        if bytes[y * width + x] == 0 {
          x += 1
          continue
        }
        let start = x
        while x < width && bytes[y * width + x] != 0 { x += 1 }
        spans.append(
          .init(x: Double(start) * sx, y: Double(y) * sy, width: Double(x - start) * sx, height: sy)
        )
        minX = min(minX, start)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y + 1)
      }
    }
    guard !spans.isEmpty else { return nil }
    var edges = [Int: [Int]]()
    let stride = width + 1
    func add(_ x: Int, _ y: Int, _ xx: Int, _ yy: Int) {
      edges[y * stride + x, default: []].append(yy * stride + xx)
    }
    for y in 0..<height {
      for x in 0..<width where bytes[y * width + x] != 0 {
        if y == 0 || bytes[(y - 1) * width + x] == 0 { add(x, y, x + 1, y) }
        if x == width - 1 || bytes[y * width + x + 1] == 0 { add(x + 1, y, x + 1, y + 1) }
        if y == height - 1 || bytes[(y + 1) * width + x] == 0 { add(x + 1, y + 1, x, y + 1) }
        if x == 0 || bytes[y * width + x - 1] == 0 { add(x, y + 1, x, y) }
      }
    }
    var contours = [[Point]]()
    while let origin = edges.keys.first {
      var current = origin
      var vertices = [Int]()
      var steps = 0
      repeat {
        vertices.append(current)
        guard var destinations = edges[current], let next = destinations.popLast() else { break }
        if destinations.isEmpty {
          edges.removeValue(forKey: current)
        } else {
          edges[current] = destinations
        }
        current = next
        steps += 1
      } while current != origin && steps <= width * height * 4
      if vertices.count >= 3 {
        var compact = [Point]()
        for i in vertices.indices {
          let previous = vertices[(i + vertices.count - 1) % vertices.count]
          let v = vertices[i]
          let next = vertices[(i + 1) % vertices.count]
          if (previous % stride == v % stride && next % stride == v % stride)
            || (previous / stride == v / stride && next / stride == v / stride)
          {
            continue
          }
          compact.append(Point(x: Double(v % stride) * sx, y: Double(v / stride) * sy))
        }
        if compact.count >= 3 { contours.append(compact) }
      }
    }
    return SelectionRegion(
      type: "pixels",
      points: [
        .init(x: Double(minX) * sx, y: Double(minY) * sy),
        .init(x: Double(maxX) * sx, y: Double(maxY) * sy),
      ], contours: contours, spans: spans)

  }
  static func combine(_ old: SelectionRegion?, _ new: SelectionRegion, mode: String, size: CGSize)
    -> SelectionRegion
  {
    guard let old, mode != "new" else { return new }
    let scale = min(1, 900 / max(size.width, size.height))
    let w = max(1, Int(size.width * scale))
    let h = max(1, Int(size.height * scale))
    guard let oldMask = mask(old, size: size, maxSize: 900),
      let newMask = mask(new, size: size, maxSize: 900),
      let a = ImageRenderer.bitmap(w, h), let b = ImageRenderer.bitmap(w, h)
    else { return new }
    a.draw(oldMask, in: CGRect(x: 0, y: 0, width: w, height: h))
    b.draw(newMask, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let ap = a.data?.assumingMemoryBound(to: UInt8.self),
      let bp = b.data?.assumingMemoryBound(to: UInt8.self)
    else { return new }
    var pixels = [UInt8](repeating: 0, count: w * h)
    for i in 0..<w * h {
      let av = ap[i * 4] > 127
      let bv = bp[i * 4] > 127
      let match = mode == "add" ? av || bv : mode == "subtract" ? av && !bv : av && bv
      pixels[i] = match ? 1 : 0
    }
    return spans(pixels, width: w, height: h, size: size)
      ?? SelectionRegion(type: "rectangle", points: [.init(x: 0, y: 0), .init(x: 0, y: 0)])
  }
  static func contains(_ selection: SelectionRegion, point: CGPoint, canvas: CGSize) -> Bool {
    let inside = selection.path.contains(point)
    return selection.inverted == true
      ? CGRect(origin: .zero, size: canvas).contains(point) && !inside : inside
  }
  static func mask(_ selection: SelectionRegion, size: CGSize, maxSize: Double? = nil) -> CGImage? {
    let scale: Double =
      maxSize.map { limit -> Double in
        Swift.min(1.0, limit / Double(Swift.max(size.width, size.height)))
      } ?? 1.0
    guard
      let cg = ImageRenderer.bitmap(
        max(1, Int(size.width * scale)), max(1, Int(size.height * scale)))
    else { return nil }
    cg.setFillColor(NSColor.black.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    cg.translateBy(x: 0, y: Double(cg.height))
    cg.scaleBy(x: scale, y: -scale)
    cg.setFillColor(NSColor.white.cgColor)
    if selection.inverted == true {
      cg.addRect(CGRect(origin: .zero, size: size))
      cg.addPath(selection.path)
      cg.drawPath(using: .eoFill)
    } else {
      cg.addPath(selection.path)
      cg.drawPath(
        using: ["shape:ring", "shape:crescent"].contains(selection.type) ? .eoFill : .fill)
    }
    guard let mask = cg.makeImage() else { return nil }
    if (selection.feather ?? 0) > 0 {
      let ci = CIImage(cgImage: mask).clampedToExtent().applyingFilter(
        "CIGaussianBlur", parameters: [kCIInputRadiusKey: (selection.feather ?? 0) * scale])
      return CIContext().createCGImage(
        ci, from: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    return mask
  }
}
enum TransformGeometry {
  static let handles: [(Double, Double)] = [
    (0, 0), (0.5, 0), (1, 0), (1, 0.5), (1, 1), (0.5, 1), (0, 1), (0, 0.5),
  ]
  static func resize(
    _ layer: ImageLayer, handle: Int, delta: CGPoint, keepAspect: Bool, fromCenter: Bool = false
  ) -> ImageLayer {
    guard handles.indices.contains(handle) else { return layer }
    let (hx, hy) = handles[handle]
    let angle = -layer.rotation * .pi / 180
    let dx = delta.x * cos(angle) - delta.y * sin(angle)
    let dy = delta.x * sin(angle) + delta.y * cos(angle)
    let multiplier = fromCenter ? 2.0 : 1.0
    var w = layer.width + (hx == 0 ? -dx : hx == 1 ? dx : 0) * multiplier
    var h = layer.height + (hy == 0 ? -dy : hy == 1 ? dy : 0) * multiplier
    w = min(16384, max(1, w))
    h = min(16384, max(1, h))
    if keepAspect {
      let ratio = layer.width / layer.height
      if hx == 0.5 {
        w = h * ratio
      } else if hy == 0.5 {
        h = w / ratio
      } else if abs(w - layer.width) / layer.width > abs(h - layer.height) / layer.height {
        h = w / ratio
      } else {
        w = h * ratio
      }
    }
    let limitScale = min(1, 16384 / max(w, h))
    w *= limitScale
    h *= limitScale
    let shiftX = fromCenter ? 0 : (w - layer.width) * (hx - 0.5)
    let shiftY = fromCenter ? 0 : (h - layer.height) * (hy - 0.5)
    let rotation = layer.rotation * .pi / 180
    var result = layer
    result.width = w
    result.height = h
    let centerX = layer.x + layer.width / 2 + shiftX * cos(rotation) - shiftY * sin(rotation)
    let centerY = layer.y + layer.height / 2 + shiftX * sin(rotation) + shiftY * cos(rotation)
    result.x = centerX - w / 2
    result.y = centerY - h / 2
    return result
  }
}
