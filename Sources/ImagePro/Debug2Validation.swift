import Foundation

enum Debug2Validation {
  static func point(_ p:Point) -> Bool { p.x.isFinite && p.y.isFinite && abs(p.x) <= 100000 && abs(p.y) <= 100000 }
  static func color(_ c:RGBA) -> Bool { [c.r,c.g,c.b,c.a].allSatisfy { $0.isFinite && (0...1).contains($0) } }
  static func validate(_ layer:ImageLayer) throws {
    let validMask = [layer.maskDensity,layer.maskOpacity].compactMap{$0}.allSatisfy { $0.isFinite && (0...1).contains($0) }
      && (layer.maskFeather.map { $0.isFinite && (0...500).contains($0) } ?? true)
      && (layer.maskStrokes?.count ?? 0) <= 100000
      && (layer.maskStrokes?.allSatisfy { $0.points.count <= 1_000_000 && $0.points.allSatisfy(point)
        && $0.size.isFinite && (0.1...5000).contains($0.size) && $0.opacity.isFinite && (0...1).contains($0.opacity)
        && $0.hardness.isFinite && (0...1).contains($0.hardness) && color($0.color) } ?? true)
    let validTransforms = (layer.quad.map { $0.count == 4 && $0.allSatisfy(point) } ?? true)
      && (layer.warpNodes.map { let n = Int(Double($0.count).squareRoot().rounded()); return (3...9).contains(n) && n * n == $0.count && $0.allSatisfy(point) } ?? true)
      && (layer.bezierAnchors.map { $0.count <= 100000 && $0.allSatisfy { point($0.point) && [$0.incoming,$0.outgoing].compactMap{$0}.allSatisfy(point) } } ?? true)
    let validStorage = [layer.rasterPlacement,layer.contentPlacement,layer.maskPlacement].compactMap {$0}.allSatisfy {rect in
      [rect.minX,rect.minY,rect.width,rect.height].allSatisfy {$0.isFinite && abs($0)<=100000} && rect.width>0 && rect.height>0
    }
    let validEffectStrength = layer.effects.allSatisfy {$0.intensity.map {$0.isFinite && (0...1).contains($0)} ?? true}
    var validGradient = true
    if let g = layer.gradient {
      validGradient = ["mesh","linear","radial","solid"].contains(g.style) && (g.style == "solid" ? g.nodes.count == 1 : (2...32).contains(g.nodes.count))
        && g.nodes.allSatisfy { point($0.point) && color($0.color) && ($0.position.map { $0.isFinite && (0...1).contains($0) } ?? true) }
        && [g.axisStart,g.axisEnd].compactMap{$0}.allSatisfy(point)
        && (g.opacityStops.map { $0.count<=32 && $0.allSatisfy { $0.position.isFinite && (0...1).contains($0.position) && $0.opacity.isFinite && (0...1).contains($0.opacity) } } ?? true) && g.softness.isFinite && (0...1).contains(g.softness)
    }
    let validText = layer.text.count <= 1_000_000 && (layer.textRuns?.count ?? 0) <= 10000
      && (layer.textRuns?.allSatisfy { $0.location >= 0 && $0.location <= 1_000_000 && $0.length >= 0 && $0.length <= 1_000_000
        && $0.size.isFinite && (1...4096).contains($0.size) && $0.tracking.isFinite && color($0.color) } ?? true)
    let validFaces = layer.effects.allSatisfy { e in
      (e.tonalCurves.map {$0.count<=4 && $0.values.allSatisfy { (2...32).contains($0.count) && $0.allSatisfy {point($0) && (0...1).contains($0.x) && (0...1).contains($0.y)} }} ?? true) && (e.faces?.count ?? 0) <= 16 && (e.faces?.allSatisfy { f in
        [f.bounds.minX,f.bounds.minY,f.bounds.width,f.bounds.height].allSatisfy { $0.isFinite && abs($0) <= 10 }
        && ((f.contour ?? [])+f.leftEye+f.rightEye+f.outerLips+f.innerLips+f.brows.flatMap{$0}).allSatisfy(point)
      } ?? true) && (e.bodyJoints?.allSatisfy(point) ?? true)
    }
    for effect in layer.effects {
      if let gradient = effect.gradient {var value = ImageLayer(name:"",kind:.gradient,width:1,height:1);value.gradient = gradient;try validate(value)}
    }
    guard validStorage && validEffectStrength && validMask && validTransforms && validGradient && validText && validFaces else {
      throw ImageProError.message("项目包含无效的蒙版、渐变、文字或变换参数。")
    }
  }
}
