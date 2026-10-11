import AppKit

struct ContentAnchors {
  var x: [Double]
  var y: [Double]
}
struct SnapGuide: Equatable {
  var axis: Int
  var position: Double
}
enum SnapEngine {
  static func content(_ image: CGImage) -> ContentAnchors {
    let scale = min(1,160/Double(max(image.width,image.height)))
    let w = max(2,Int(Double(image.width)*scale)), h = max(2,Int(Double(image.height)*scale))
    guard let cg = ImageRenderer.bitmap(w,h) else { return ContentAnchors(x:[],y:[]) }
    cg.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
    guard let p = cg.data?.assumingMemoryBound(to:UInt8.self) else { return ContentAnchors(x:[],y:[]) }
    var xs = [Double](repeating:0,count:w), ys = [Double](repeating:0,count:h)
    func luminance(_ x: Int, _ y: Int) -> Double { let i = (y*w+x)*4;return (Double(p[i])*0.2126+Double(p[i+1])*0.7152+Double(p[i+2])*0.0722) }
    for y in 1..<h-1 { for x in 1..<w-1 {
      xs[x] += abs(luminance(x+1,y)-luminance(x-1,y))
      ys[y] += abs(luminance(x,y+1)-luminance(x,y-1))
    } }
    func peaks(_ values:[Double]) -> [Double] {
      guard let maximum = values.max(),maximum > 100 else { return [] }
      var indices:[Int] = []
      for i in values.indices.sorted(by:{ values[$0] > values[$1] }) {
        if values[i] < maximum*0.45 { break }
        if indices.allSatisfy({ abs($0-i) > values.count/16 }) { indices.append(i) }
        if indices.count >= 6 { break }
      }
      return indices.map{ Double($0)/Double(values.count) }
    }
    return ContentAnchors(x:peaks(xs),y:peaks(ys))
  }
  static func snap(_ value:Double, sources:[Double], targets:[Double], tolerance:Double) -> (Double, Double?) {
    var best = tolerance, delta = 0.0, guide:Double?
    for source in sources { for target in targets {
      let d = target-source
      if abs(d) < best { best = abs(d);delta = d;guide = target }
    } }
    return (value+delta,guide)
  }
  static func bounds(_ layer:ImageLayer) -> CGRect {
    let a = layer.rotation * .pi/180
    let points = (layer.quad ?? TransformGeometry.corners).map { p -> CGPoint in
      let x = (p.x-0.5)*layer.width*(layer.flippedX == true ? -1 : 1)
      let y = (p.y-0.5)*layer.height*(layer.flippedY == true ? -1 : 1)
      return CGPoint(x:layer.x+layer.width/2+x*cos(a)-y*sin(a),y:layer.y+layer.height/2+x*sin(a)+y*cos(a))
    }
    let xs = points.map(\.x),ys = points.map(\.y)
    return CGRect(x:xs.min() ?? 0,y:ys.min() ?? 0,width:(xs.max() ?? 0)-(xs.min() ?? 0),height:(ys.max() ?? 0)-(ys.min() ?? 0))
  }
}
extension EditorStore {
  func snapTargets(excluding id:UUID?) -> (x:[Double],y:[Double]) {
    var xs = [0.0,document.width/2,document.width],ys = [0.0,document.height/2,document.height]
    if showGrid {
      xs += stride(from:0.0,through:document.width,by:100).map{$0}
      ys += stride(from:0.0,through:document.height,by:100).map{$0}
    }
    for layer in document.layers where layer.id != id && layer.kind != .group && layer.kind != .adjustment && document.isVisible(layer) {
      let b = SnapEngine.bounds(layer)
      xs += [b.minX,b.midX,b.maxX];ys += [b.minY,b.midY,b.maxY]
      if contentSnapping, layer.rotation == 0, let key = layer.assetID, let anchors = contentAnchors[key] {
        xs += anchors.x.map{layer.x+$0*layer.width};ys += anchors.y.map{layer.y+$0*layer.height}
      }
    }
    return (xs,ys)
  }
  func weightedSnapTargets(excluding id:UUID?) -> (x:[SnapTarget],y:[SnapTarget]) {
    var xs = [SnapTarget(position:document.width/2,strength:2.4),SnapTarget(position:0,strength:1),SnapTarget(position:document.width,strength:1)]
    var ys = [SnapTarget(position:document.height/2,strength:2.4),SnapTarget(position:0,strength:1),SnapTarget(position:document.height,strength:1)]
    for layer in document.layers where layer.id != id && !selectedIDs.contains(layer.id) && layer.kind != .group && layer.kind != .adjustment && document.isVisible(layer) {
      let b = SnapEngine.bounds(layer)
      xs += [SnapTarget(position:b.midX,strength:1.7),SnapTarget(position:b.minX,strength:1),SnapTarget(position:b.maxX,strength:1)]
      ys += [SnapTarget(position:b.midY,strength:1.7),SnapTarget(position:b.minY,strength:1),SnapTarget(position:b.maxY,strength:1)]
      if contentSnapping,layer.rotation == 0,let id = layer.assetID,let content = contentAnchors[id] {
        xs += content.x.map {SnapTarget(position:layer.x+$0*layer.width,strength:0.7)}
        ys += content.y.map {SnapTarget(position:layer.y+$0*layer.height,strength:0.7)}
      }
    }
    if showGrid {
      xs += stride(from:0.0,through:document.width,by:100).map {SnapTarget(position:$0,strength:0.5)}
      ys += stride(from:0.0,through:document.height,by:100).map {SnapTarget(position:$0,strength:0.5)}
    }
    return (xs,ys)
  }
  func snappedPosition(_ layer:ImageLayer, scale:Double) -> CGPoint {
    guard snapping else {snapGuides = [];return CGPoint(x:layer.x,y:layer.y)}
    let t = weightedSnapTargets(excluding:layer.id),b = SnapEngine.bounds(layer)
    let x = SnapEngine.weighted(layer.x,sources:[b.minX,b.midX,b.maxX],targets:t.x,tolerance:6/max(0.05,scale))
    let y = SnapEngine.weighted(layer.y,sources:[b.minY,b.midY,b.maxY],targets:t.y,tolerance:6/max(0.05,scale))
    snapGuides = [x.1.map {SnapGuide(axis:0,position:$0)},y.1.map {SnapGuide(axis:1,position:$0)}].compactMap {$0}
    return CGPoint(x:x.0,y:y.0)
  }
  func snappedPoint(_ point:CGPoint,scale:Double) -> CGPoint {
    guard snapping else {return point}
    let t = weightedSnapTargets(excluding:selected?.id)
    let x = SnapEngine.weighted(point.x,sources:[point.x],targets:t.x,tolerance:5/max(0.05,scale))
    let y = SnapEngine.weighted(point.y,sources:[point.y],targets:t.y,tolerance:5/max(0.05,scale))
    snapGuides = [x.1.map {SnapGuide(axis:0,position:$0)},y.1.map {SnapGuide(axis:1,position:$0)}].compactMap {$0}
    return CGPoint(x:x.0,y:y.0)
  }
}
struct SnapTarget {var position:Double;var strength:Double}
extension SnapEngine {
  static func weighted(_ value:Double,sources:[Double],targets:[SnapTarget],tolerance:Double)->(Double,Double?) {
    var best = Double.infinity,delta = 0.0,guide:Double?
    for source in sources {for target in targets {
      let distance = target.position-source
      guard abs(distance)<tolerance*target.strength else {continue}
      let score = (abs(distance)+tolerance*0.12)/target.strength
      if score<best {best = score;delta = distance;guide = target.position}
    }}
    return (value+delta,guide)
  }
}
