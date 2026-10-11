import AppKit

enum BrushEngine {
  static func draw(_ stroke: BrushStroke, context cg: CGContext) {
    guard let dynamics = stroke.dynamics, let first = stroke.points.first else { return }
    cg.saveGState()
    defer { cg.restoreGState() }
    if let clip = stroke.clip {
      if clip.inverted == true { cg.addRect(cg.boundingBoxOfClipPath) }
      cg.addPath(clip.path)
      cg.clip(using: clip.inverted == true ? .evenOdd : .winding)
    }
    cg.setBlendMode(
      stroke.erasing ? .destinationOut : dynamics.mode == "marker" ? .multiply : .normal)
    let spacing = max(0.5, stroke.size * max(0.01, dynamics.spacing))
    let color = stroke.color.ns.cgColor
    var index = 0
    var remainder = 0.0
    func noise(_ seed: Int) -> Double {
      Double(UInt32(truncatingIfNeeded: seed &* 1_664_525 &+ 1_013_904_223) % 10000) / 10000
    }
    func stamp(_ point: CGPoint, pressure: Double) {
      let n = index
      index += 1
      let pressureScale = dynamics.pressure ? max(0.15, pressure) : 1
      let size = stroke.size * pressureScale * (1 - dynamics.sizeJitter * noise(n + 100))
      let alpha = stroke.opacity * (1 - dynamics.opacityJitter * noise(n + 900))
      let x = point.x + (noise(n + 301) - 0.5) * size * dynamics.scatter
      let y = point.y + (noise(n + 711) - 0.5) * size * dynamics.scatter
      cg.saveGState()
      cg.translateBy(x: x, y: y)
      cg.rotate(by: dynamics.angle * .pi / 180)
      cg.scaleBy(x: 1, y: max(0.05, dynamics.roundness))
      cg.setFillColor(color)
      cg.setStrokeColor(color)
      cg.setAlpha(alpha)
      let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
      let mode = dynamics.mode
      if (mode == "airbrush" && dynamics.tip == "round") || ["soft", "cloud", "fuzzy"].contains(dynamics.tip)
        || (stroke.hardness < 0.2 && dynamics.tip == "round")
      {
        for ring in stride(from: 1.0, through: 0.1, by: -0.1) {
          cg.setAlpha(alpha * (1 - ring) * 0.09)
          cg.fillEllipse(in: rect.insetBy(dx: size * (1 - ring) / 2, dy: size * (1 - ring) / 2))
        }
      } else if (mode == "watercolor" && dynamics.tip == "round") || dynamics.tip == "wet" {
        cg.setAlpha(alpha * (1 - dynamics.wetness * 0.7) * 0.2)
        cg.fillEllipse(in: rect)
        cg.setAlpha(alpha * 0.12)
        cg.setLineWidth(max(0.5, size * 0.04))
        cg.strokeEllipse(in: rect.insetBy(dx: size * 0.06, dy: size * 0.06))
      } else if (mode == "oil" && dynamics.tip == "round") || ["bristle", "rake", "dry"].contains(dynamics.tip) {
        let bristles = dynamics.tip == "rake" ? 5 : dynamics.tip == "dry" ? 18 : 12
        for bristle in 0..<bristles {
          cg.setAlpha(alpha * (0.35 + noise(n + bristle) * 0.4))
          cg.fill(
            CGRect(
              x: -size / 2 + Double(bristle) * size / Double(bristles), y: -size * 0.3, width: size / 20,
              height: size * 0.6))
        }
      } else if ((mode == "pencil" || mode == "texture") && dynamics.tip == "round")
        || ["chalk", "grain", "splatter", "charcoal", "speckle", "spray"].contains(dynamics.tip)
      {
        let dots = ["splatter":9,"grain":32,"chalk":46,"charcoal":18,"speckle":14,"spray":64][dynamics.tip] ?? 22
        for dot in 0..<dots {
          let a = noise(n * 31 + dot) * 2 * .pi
          let distance = sqrt(noise(n * 71 + dot)) * size / 2
          let diameter = max(0.4, size * (mode == "pencil" ? 0.08 : 0.04 + noise(dot + n) * 0.1))
          cg.setAlpha(alpha * (1 - dynamics.texture * noise(dot * 71 + n)))
          cg.fillEllipse(
            in: CGRect(
              x: cos(a) * distance, y: sin(a) * distance, width: diameter, height: diameter))
        }
      } else {
        if stroke.hardness < 0.95 {
          cg.setShadow(offset: .zero, blur: size * (1 - stroke.hardness) * 0.22, color: color)
        }
        switch dynamics.tip {
        case "oval": cg.fillEllipse(in: rect.insetBy(dx: size * 0.3, dy: 0))
        case "fine": cg.fillEllipse(in: rect.insetBy(dx: size * 0.4, dy: size * 0.4))
        case "diagonal":
          cg.rotate(by: .pi / 4)
          cg.fill(rect.insetBy(dx: 0, dy: size * 0.35))
        case "dash": cg.fill(rect.insetBy(dx: 0, dy: size * 0.44))
        case "triangle", "diamond", "hexagon", "flower", "heart":
          cg.addPath(ShapeGeometry.path(dynamics.tip, rect: rect))
          cg.fillPath()
        case "squares", "dots":
          for row in 0..<3 {
            for col in 0..<3 {
              let dot = CGRect(
                x: -size / 2 + Double(col) * size / 3, y: -size / 2 + Double(row) * size / 3,
                width: size * 0.13, height: size * 0.13)
              if dynamics.tip == "dots" { cg.fillEllipse(in: dot) } else { cg.fill(dot) }
            }
          }
        case "stripe", "grid", "canvas":
          cg.setLineWidth(max(0.5, size * 0.035))
          for i in 0..<6 {
            let v = -size / 2 + Double(i) * size / 5
            cg.move(to: CGPoint(x: v, y: -size / 2))
            cg.addLine(to: CGPoint(x: v, y: size / 2))
            if dynamics.tip != "stripe" {
              cg.move(to: CGPoint(x: -size / 2, y: v))
              cg.addLine(to: CGPoint(x: size / 2, y: v))
            }
          }
          cg.strokePath()
        case "fan", "grass":
          cg.setLineWidth(max(0.5, size * 0.02))
          for i in 0..<7 {
            cg.move(to: CGPoint(x: 0, y: size / 2))
            let x = (Double(i) / 6 - 0.5) * size
            cg.addQuadCurve(
              to: CGPoint(x: x, y: -size / 2), control: CGPoint(x: x * 0.1, y: -size * 0.15))
          }
          cg.strokePath()
        case "square", "flat":
          cg.fill(dynamics.tip == "flat" ? rect.insetBy(dx: 0, dy: size * 0.25) : rect)
        case "star", "cross", "leaf":
          cg.addPath(
            ShapeGeometry.path(dynamics.tip == "leaf" ? "teardrop" : dynamics.tip, rect: rect))
          cg.fillPath()
        case "ring":
          cg.setLineWidth(size * 0.1)
          cg.strokeEllipse(in: rect.insetBy(dx: size * 0.1, dy: size * 0.1))
        default:
          if mode == "marker" {
            cg.fill(rect.insetBy(dx: size * 0.15, dy: size * 0.3))
          } else {
            cg.fillEllipse(in: rect)
          }
        }
      }
      cg.restoreGState()
    }
    func pressure(_ i: Int) -> Double {
      guard let pressures = stroke.pressures, pressures.indices.contains(i) else { return 1 }
      return pressures[i] > 0 ? pressures[i] : 1
    }
    var smoothed = [first]
    for point in stroke.points.dropFirst() {
      let previous = smoothed.last!
      let v = dynamics.smoothing
      smoothed.append(
        Point(x: previous.x * v + point.x * (1 - v), y: previous.y * v + point.y * (1 - v)))
    }
    stamp(first.cg, pressure: pressure(0))
    for i in 1..<smoothed.count {
      let a = smoothed[i - 1]
      let b = smoothed[i]
      let distance = hypot(b.x - a.x, b.y - a.y)
      guard distance > 0 else { continue }
      var step = spacing - remainder
      while step <= distance {
        let t = step / distance
        stamp(
          CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
          pressure: pressure(i - 1) + (pressure(i) - pressure(i - 1)) * t)
        step += spacing
      }
      remainder = (remainder + distance).truncatingRemainder(dividingBy: spacing)
    }
  }
}
