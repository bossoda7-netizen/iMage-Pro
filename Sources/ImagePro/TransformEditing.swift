import AppKit
import CoreImage

enum TransformMode: String, CaseIterable {
  case free = "自由变换", scale = "缩放", rotate = "旋转", skew = "斜切", distort = "扭曲", perspective = "透视", warp = "变形"
}
extension ImageRenderer {
  /// Bake world geometry once; the replacement pixel layer has no residual transforms.
  func bakeLayer(_ layer: ImageLayer, assets: AssetLibrary) -> (image: CGImage, bounds: CGRect)? {
    let q = layer.quad ?? TransformGeometry.corners
    let magnification = max(1, q.map { abs($0.x) + abs($0.y) }.max() ?? 1)
    let p = Self.outset(layer) * magnification
    let rect = SnapEngine.bounds(layer).insetBy(dx: -p, dy: -p).integral
    guard rect.width > 0, rect.height > 0, rect.width <= 16384, rect.height <= 16384,
      rect.width * rect.height <= 40_000_000 else { return nil }
    var doc = ImageDocument(); doc.width = rect.width; doc.height = rect.height
    var local = layer; local.x -= rect.minX; local.y -= rect.minY
    local.opacity = 1; local.blend = .normal; local.parentID = nil; local.visible = true
    doc.layers = [local]
    guard let image = render(doc, assets: assets, maxDimension: nil) else { return nil }
    return (image, rect)
  }
}
extension TransformGeometry {
  static let corners = [Point(x:0,y:0), Point(x:1,y:0), Point(x:1,y:1), Point(x:0,y:1)]
  /// Legacy 3×3 mesh kept for project/test compatibility. New editor transforms use
  /// the denser mesh below, while old documents continue to round-trip unchanged.
  static let warpGrid = (0..<9).map { Point(x:Double($0%3)/2,y:Double($0/3)/2) }
  static let denseWarpGrid = warpGrid(7)
  static func constrained(_ point:CGPoint, around origin:CGPoint) -> CGPoint {
    let delta = CGPoint(x:point.x-origin.x,y:point.y-origin.y)
    let angle = (atan2(delta.y,delta.x)/(.pi/4)).rounded()*(.pi/4)
    let length = hypot(delta.x,delta.y)
    return CGPoint(x:origin.x+cos(angle)*length,y:origin.y+sin(angle)*length)
  }
  static func displayPoint(_ p: CGPoint, layer: ImageLayer) -> CGPoint {
    var value = Point(x:p.x/layer.width,y:p.y/layer.height)
    if let nodes = layer.warpNodes {value = warpPoint(value,nodes:nodes)}
    if let q = layer.quad,let map = ProjectiveMap(q) {value = map.destination(value)}
    let dx = (value.x-0.5)*layer.width*(layer.flippedX == true ? -1 : 1)
    let dy = (value.y-0.5)*layer.height*(layer.flippedY == true ? -1 : 1)
    let a = layer.rotation * .pi/180
    return CGPoint(x:layer.x+layer.width/2+dx*cos(a)-dy*sin(a),y:layer.y+layer.height/2+dx*sin(a)+dy*cos(a))
  }
  static func deformationPoint(_ p:CGPoint, layer:ImageLayer) -> Point {
    let angle = -layer.rotation * .pi/180
    let dx = p.x-layer.x-layer.width/2,dy = p.y-layer.y-layer.height/2
    var local = Point(x:((dx*cos(angle)-dy*sin(angle))*(layer.flippedX == true ? -1 : 1)+layer.width/2)/layer.width,
      y:((dx*sin(angle)+dy*cos(angle))*(layer.flippedY == true ? -1 : 1)+layer.height/2)/layer.height)
    if let q = layer.quad, let map = ProjectiveMap(q), let source = map.source(local) { local = source }
    return local
  }
  static func contentPoint(_ p:CGPoint,layer:ImageLayer) -> CGPoint {
    var local = deformationPoint(p,layer:layer)
    if let nodes = layer.warpNodes,let source = warpSource(local,nodes:nodes) {local = source}
    return CGPoint(x:local.x*layer.width,y:local.y*layer.height)
  }
  static func warpPoint(_ point: Point, nodes: [Point]) -> Point {
    let n = Int(Double(nodes.count).squareRoot().rounded())
    guard n >= 3, n*n == nodes.count else { return point }
    func cubic(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
      0.5 * ((2*b) + (-a+c)*t + (2*a-5*b+4*c-d)*t*t + (-a+3*b-3*c+d)*t*t*t)
    }
    func node(_ x: Int, _ y: Int) -> Point {
      func row(_ row: Int) -> Point {
        if x < 0 { let a = nodes[row*n], b = nodes[row*n+1]; return Point(x:2*a.x-b.x,y:2*a.y-b.y) }
        if x >= n { let a = nodes[row*n+n-1], b = nodes[row*n+n-2]; return Point(x:2*a.x-b.x,y:2*a.y-b.y) }
        return nodes[row*n+x]
      }
      if y < 0 { let a = row(0), b = row(1); return Point(x:2*a.x-b.x,y:2*a.y-b.y) }
      if y >= n { let a = row(n-1), b = row(n-2); return Point(x:2*a.x-b.x,y:2*a.y-b.y) }
      return row(y)
    }
    let u = point.x*Double(n-1), v = point.y*Double(n-1)
    let x = min(n-2,max(0,Int(floor(u)))), y = min(n-2,max(0,Int(floor(v))))
    let rows = (-1...2).map { dy -> Point in
      let q = (-1...2).map { node(x+$0,y+dy) }
      return Point(x:cubic(q[0].x,q[1].x,q[2].x,q[3].x,u-Double(x)),
                   y:cubic(q[0].y,q[1].y,q[2].y,q[3].y,u-Double(x)))
    }
    return Point(x:cubic(rows[0].x,rows[1].x,rows[2].x,rows[3].x,v-Double(y)),
                 y:cubic(rows[0].y,rows[1].y,rows[2].y,rows[3].y,v-Double(y)))
  }
  static func warpSource(_ point: Point, nodes: [Point]) -> Point? {
    var uv = Point(x:min(1,max(0,point.x)),y:min(1,max(0,point.y)))
    var best = Double.infinity
    let n = max(3,Int(Double(nodes.count).squareRoot()))
    // Start near the visible surface, including surfaces displaced outside the original box.
    for y in 0..<n {for x in 0..<n {
      let candidate = Point(x:Double(x)/Double(n-1),y:Double(y)/Double(n-1))
      let p = nodes[y*n+x],distance = hypot(p.x-point.x,p.y-point.y)
      if distance < best {best = distance;uv = candidate}
    }}
    let epsilon = 0.0003
    for _ in 0..<32 {
      let p = warpPoint(uv,nodes:nodes)
      let error = Point(x:p.x-point.x,y:p.y-point.y),distance = hypot(error.x,error.y)
      if distance < 1e-10 {break}
      let px = warpPoint(Point(x:uv.x+epsilon,y:uv.y),nodes:nodes)
      let py = warpPoint(Point(x:uv.x,y:uv.y+epsilon),nodes:nodes)
      let du = Point(x:(px.x-p.x)/epsilon,y:(px.y-p.y)/epsilon)
      let dv = Point(x:(py.x-p.x)/epsilon,y:(py.y-p.y)/epsilon)
      let determinant = du.x*dv.y-du.y*dv.x
      guard abs(determinant)>1e-8 else {return nil}
      let dx = (error.x*dv.y-error.y*dv.x)/determinant
      let dy = (du.x*error.y-du.y*error.x)/determinant
      var factor = 1.0,accepted = false
      for _ in 0..<8 {
        let next = Point(x:uv.x-dx*factor,y:uv.y-dy*factor)
        let q = warpPoint(next,nodes:nodes)
        if next.x.isFinite,next.y.isFinite,abs(next.x)<4,abs(next.y)<4,hypot(q.x-point.x,q.y-point.y)<distance {
          uv = next;accepted = true;break
        }
        factor *= 0.5
      }
      if !accepted {break}
    }
    let p = warpPoint(uv,nodes:nodes)
    guard uv.x >= -0.00001,uv.x <= 1.00001,uv.y >= -0.00001,uv.y <= 1.00001,
      hypot(p.x-point.x,p.y-point.y)<0.0001 else { return nil }
    return uv
  }
  /// Move a soft neighborhood rather than folding one isolated mesh node.
  static func dragWarp(_ nodes:[Point],index:Int,to point:Point) -> [Point] {
    let n = Int(Double(nodes.count).squareRoot())
    guard n>=3,n*n==nodes.count,nodes.indices.contains(index),point.x.isFinite,point.y.isFinite else {return nodes}
    let dx = point.x-nodes[index].x,dy = point.y-nodes[index].y
    let sigma = 1.25
    func candidate(_ factor:Double) -> [Point] {
      nodes.indices.map {i in
        let x = Double(i%n-index%n),y = Double(i/n-index/n)
        let weight = exp(-(x*x+y*y)/(2*sigma*sigma))*factor
        return Point(x:nodes[i].x+dx*weight,y:nodes[i].y+dy*weight)
      }
    }
    let full = candidate(1)
    if validWarp(full) {return full}
    var low = 0.0,high = 1.0
    for _ in 0..<10 {
      let mid = (low+high)/2
      if validWarp(candidate(mid)) {low = mid} else {high = mid}
    }
    return candidate(low)
  }
  static func validWarp(_ nodes:[Point]) -> Bool {
    let n = Int(Double(nodes.count).squareRoot())
    guard n>=3,n*n==nodes.count else {return false}
    let samples = max(18,(n-1)*4),epsilon = 0.0003
    for y in 0...samples {for x in 0...samples {
      let uv = Point(x:Double(x)/Double(samples),y:Double(y)/Double(samples))
      let p = warpPoint(uv,nodes:nodes),px = warpPoint(Point(x:uv.x+epsilon,y:uv.y),nodes:nodes),py = warpPoint(Point(x:uv.x,y:uv.y+epsilon),nodes:nodes)
      let determinant = ((px.x-p.x)*(py.y-p.y)-(px.y-p.y)*(py.x-p.x))/(epsilon*epsilon)
      if !determinant.isFinite || determinant<0.04 {return false}
    }}
    return true
  }
  static func warpGrid(_ dimension: Int) -> [Point] {
    let n = min(9,max(3,dimension))
    return (0..<n*n).map { Point(x:Double($0%n)/Double(n-1),y:Double($0/n)/Double(n-1)) }
  }
  static func resampleWarp(_ nodes: [Point], dimension: Int) -> [Point] {
    warpGrid(dimension).map { warpPoint($0,nodes:nodes) }
  }
  static func displayHandles(_ layer: ImageLayer) -> [Point] {
    let q = layer.quad ?? corners
    guard q.count == 4 else { return corners }
    return (0..<8).map { i in
      if i%2 == 0 { return q[i/2] }
      let a = q[i/2], b = q[(i/2+1)%4]
      return Point(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
    }
  }
  static func deform(_ layer: ImageLayer, handle: Int, delta: CGPoint, mode: TransformMode) -> ImageLayer {
    var copy = layer
    let a = -layer.rotation * .pi/180
    let dx = (delta.x*cos(a)-delta.y*sin(a))/layer.width
    let dy = (delta.x*sin(a)+delta.y*cos(a))/layer.height
    var q = layer.quad ?? corners
    guard q.count == 4 else { return layer }
    let corner = (handle/2)%4
    let affected = handle%2 == 0 ? [corner] : [corner,(corner+1)%4]
    if mode == .distort {
      for i in affected { q[i].x += dx;q[i].y += dy }
    } else if mode == .skew {
      if abs(dx*layer.width) > abs(dy*layer.height) {
        let top = handle < 3
        for i in top ? [0,1] : [2,3] { q[i].x += dx }
      } else {
        let left = handle == 0 || handle > 5
        for i in left ? [0,3] : [1,2] { q[i].y += dy }
      }
    } else if mode == .perspective {
      if abs(dx*layer.width) > abs(dy*layer.height) {
        let top = handle < 3, left = handle == 0 || handle > 5
        let pair = top ? [0,1] : [3,2]
        q[pair[0]].x += left ? dx : -dx; q[pair[1]].x += left ? -dx : dx
      } else {
        let left = handle == 0 || handle > 5, top = handle < 3
        let pair = left ? [0,3] : [1,2]
        q[pair[0]].y += top ? dy : -dy; q[pair[1]].y += top ? -dy : dy
      }
    }
    for i in q.indices { q[i].x = min(3,max(-2,q[i].x));q[i].y = min(3,max(-2,q[i].y)) }
    // Prevent self-intersecting/folded projective quadrilaterals.
    let crosses = (0..<4).map { i -> Double in
      let p = q[i], b = q[(i+1)%4], c = q[(i+2)%4]
      return (b.x-p.x)*(c.y-b.y)-(b.y-p.y)*(c.x-b.x)
    }
    guard crosses.allSatisfy({$0 > 0.0001}) else { return layer }
    copy.quad = q; return copy
  }
}

struct ProjectiveMap {
  let values:[Double]
  init?(_ corners:[Point]) {
    guard corners.count == 4 else { return nil }
    var rows = [[Double]]()
    for (p,q) in zip(TransformGeometry.corners,corners) {
      rows.append([p.x,p.y,1,0,0,0,-q.x*p.x,-q.x*p.y,q.x])
      rows.append([0,0,0,p.x,p.y,1,-q.y*p.x,-q.y*p.y,q.y])
    }
    for i in 0..<8 {
      guard let pivot = (i..<8).max(by:{abs(rows[$0][i]) < abs(rows[$1][i])}),abs(rows[pivot][i]) > 1e-10 else { return nil }
      rows.swapAt(i,pivot)
      let divisor = rows[i][i]
      for j in i..<9 { rows[i][j] /= divisor }
      for k in 0..<8 where k != i {
        let factor = rows[k][i]
        for j in i..<9 { rows[k][j] -= factor*rows[i][j] }
      }
    }
    values = rows.map{$0[8]}
  }
  func destination(_ point:Point) -> Point {
    let d = values[6]*point.x+values[7]*point.y+1
    return Point(x:(values[0]*point.x+values[1]*point.y+values[2])/d,y:(values[3]*point.x+values[4]*point.y+values[5])/d)
  }
  func source(_ point:Point) -> Point? {
    let a = values[0]-point.x*values[6],b = values[1]-point.x*values[7],c = point.x-values[2]
    let d = values[3]-point.y*values[6],e = values[4]-point.y*values[7],f = point.y-values[5]
    let det = a*e-b*d
    guard abs(det)>1e-10 else { return nil }
    return Point(x:(c*e-b*f)/det,y:(a*f-c*d)/det)
  }
}
enum WarpRenderer {
  static let kernel = NativeKernels.warp("smoothWarp")
  static func apply(_ image: CIImage, nodes: [Point], extent: CGRect) -> CIImage {
    guard let kernel else { return image }
    let n = Int(Double(nodes.count).squareRoot().rounded())
    guard (3...9).contains(n), n*n == nodes.count else { return image }
    let args: [Any] = [CIVector(x:image.extent.width,y:image.extent.height),Double(n)] +
      (0..<81).map { i -> CIVector in
        let p = i < nodes.count ? nodes[i] : Point(x:0,y:0)
        return CIVector(x:p.x,y:p.y)
      }
    return kernel.apply(extent:extent,roiCallback:{_,_ in image.extent},image:image,arguments:args) ?? image
  }
}
