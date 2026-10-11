import AppKit
import SwiftUI

struct BezierAnchor: Identifiable, Codable, Equatable {
  var id = UUID()
  var point: Point
  var incoming: Point?
  var outgoing: Point?
  var independentHandles: Bool?
  mutating func moveHandle(to location: CGPoint, incoming isIncoming: Bool, independent: Bool, constrained: Bool) {
    let target = Point(constrained ? TransformGeometry.constrained(location, around: point.cg) : location)
    if independent { independentHandles = true }
    if isIncoming { incoming = target } else { outgoing = target }
    if independentHandles != true {
      let opposite = Point(x:2*point.x-target.x,y:2*point.y-target.y)
      if isIncoming { outgoing = opposite } else { incoming = opposite }
    }
  }
  func mapped(_ operation: (Point) -> Point) -> BezierAnchor {
    var copy = self; copy.point = operation(point)
    copy.incoming = incoming.map(operation); copy.outgoing = outgoing.map(operation)
    return copy
  }
}
enum BezierGeometry {
  static func toggleSmooth(_ anchors: inout [BezierAnchor], index: Int, closed: Bool) {
    guard anchors.indices.contains(index) else { return }
    if anchors[index].incoming != nil || anchors[index].outgoing != nil {
      anchors[index].incoming = nil; anchors[index].outgoing = nil
      anchors[index].independentHandles = nil
      return
    }
    let center = anchors[index].point
    let before = index > 0 ? anchors[index-1].point : closed ? anchors.last!.point : center
    let after = index+1 < anchors.count ? anchors[index+1].point : closed ? anchors.first!.point : center
    let dx = after.x-before.x,dy = after.y-before.y
    anchors[index].incoming = Point(x:center.x-dx/6,y:center.y-dy/6)
    anchors[index].outgoing = Point(x:center.x+dx/6,y:center.y+dy/6)
    anchors[index].independentHandles = nil
  }
  static func path(_ anchors: [BezierAnchor], closed: Bool, size: CGSize? = nil) -> CGPath {
    let values = size.map { size in anchors.map { a in a.mapped { Point(x:$0.x*size.width,y:$0.y*size.height) } } } ?? anchors
    let path = CGMutablePath()
    guard let first = values.first else { return path }
    path.move(to:first.point.cg)
    func segment(_ from: BezierAnchor, _ to: BezierAnchor) {
      if from.outgoing != nil || to.incoming != nil {
        path.addCurve(to:to.point.cg,control1:(from.outgoing ?? from.point).cg,control2:(to.incoming ?? to.point).cg)
      } else { path.addLine(to:to.point.cg) }
    }
    for i in 1..<values.count { segment(values[i-1],values[i]) }
    if closed { segment(values.last!,first); path.closeSubpath() }
    return path
  }
}
extension EditorStore {
  func createBezierPath(_ anchors: [BezierAnchor], closed: Bool) {
    guard anchors.count >= 2 else { return }
    let all = anchors.flatMap { [$0.point] + [$0.incoming,$0.outgoing].compactMap{$0} }
    let xs = all.map(\.x), ys = all.map(\.y)
    let rect = CGRect(x:(xs.min() ?? 0)-4,y:(ys.min() ?? 0)-4,
      width:max(8,(xs.max() ?? 0)-(xs.min() ?? 0)+8),height:max(8,(ys.max() ?? 0)-(ys.min() ?? 0)+8))
    var layer = ImageLayer(name:L("钢笔路径"),kind:.shape,width:rect.width,height:rect.height)
    layer.x = rect.minX; layer.y = rect.minY; layer.color = foreground; layer.shape = "pen"; layer.cornerRadius = 3
    layer.pathClosed = closed
    layer.bezierAnchors = anchors.map { a in a.mapped { Point(x:($0.x-rect.minX)/rect.width,y:($0.y-rect.minY)/rect.height) } }
    edit("绘制钢笔路径") { doc in let i = doc.insertionIndex; layer.parentID = doc.insertionParent; doc.layers.insert(layer,at:i); doc.selectedLayerID = layer.id }
    inspector = .special; showInspector = true
    layerPreviews[layer.id] = renderer.previewLayer(layer,assets:active.assets,scale:1)
  }
}

extension BezierGeometry {
  /// Fit a continuous cubic path to freehand samples, retaining corners at a useful spacing.
  static func freehand(_ samples: [Point], spacing: Double = 4) -> [BezierAnchor] {
    guard let first = samples.first else { return [] }
    var points = [first]
    for p in samples.dropFirst() where hypot(p.x-points.last!.x,p.y-points.last!.y)>=spacing { points.append(p) }
    if let end = samples.last, end != points.last {points.append(end)}
    return points.indices.map { i in
      let p = points[i], before = points[max(0,i-1)], after = points[min(points.count-1,i+1)]
      let dx = (after.x-before.x)/6,dy = (after.y-before.y)/6
      return BezierAnchor(point:p,incoming:i == 0 ? nil : Point(x:p.x-dx,y:p.y-dy),
        outgoing:i == points.count-1 ? nil : Point(x:p.x+dx,y:p.y+dy))
    }
  }
  static func samples(_ anchors: [BezierAnchor], closed: Bool, size: CGSize) -> [Point] {
    guard anchors.count>=2 else { return [] }
    let a = anchors.map { $0.mapped {Point(x:$0.x*size.width,y:$0.y*size.height)} }
    var result = [a[0].point]
    for i in 0..<(closed ? a.count : a.count-1) {
      let from = a[i], to = a[(i+1)%a.count], p = from.point, q = from.outgoing ?? p, r = to.incoming ?? to.point, s = to.point
      let length = hypot(q.x-p.x,q.y-p.y)+hypot(r.x-q.x,r.y-q.y)+hypot(s.x-r.x,s.y-r.y)
      let steps = min(2048,max(4,Int(ceil(length/2))))
      for j in 1...steps {
        let t = Double(j)/Double(steps),u = 1-t
        result.append(Point(x:u*u*u*p.x+3*u*u*t*q.x+3*u*t*t*r.x+t*t*t*s.x,
          y:u*u*u*p.y+3*u*u*t*q.y+3*u*t*t*r.y+t*t*t*s.y))
      }
    }
    return result
  }
}
extension EditorStore {
  func pathSamples(_ layer: ImageLayer) -> [Point] {
    let local = layer.bezierAnchors.map { BezierGeometry.samples($0,closed:layer.pathClosed == true,size:CGSize(width:layer.width,height:layer.height)) }
      ?? (layer.vectorPoints ?? []).map {Point(x:$0.x*layer.width,y:$0.y*layer.height)}
    return local.map { TransformGeometry.displayPoint($0.cg,layer:layer) }.map(Point.init)
  }
  func pathToSelection() {
    guard let layer = selected else {return}
    let points = pathSamples(layer)
    guard points.count>2 else {return}
    applySelection(SelectionRegion(type:"lasso",points:points),mode:"new")
  }
  func strokePath() {
    guard let layer = selected else {return}
    let points = pathSamples(layer)
    guard points.count>1 else {return}
    beginTransaction("画笔描边路径")
    addLayer(.paint)
    var stroke = BrushStroke(points:points,color:foreground,size:brushSize,opacity:brushOpacity*brushFlow,
      hardness:brushHardness,erasing:false,clip:nil,dynamics:brushDynamics)
    if let selection,let target = selected {stroke.clip = localSelection(selection,layer:target)}
    appendStroke(stroke);endTransaction()
  }
  func fillPath() {
    guard var layer = selected,layer.isPath else {return}
    layer.id = UUID();layer.name = L("路径填充");layer.shape = "pathFill";layer.pathClosed = true;layer.color = foreground
    edit("填充路径") {doc in let i = doc.insertionIndex; layer.parentID = doc.insertionParent; doc.layers.insert(layer,at:i); doc.selectedLayerID = layer.id}
    inspector = .special
  }
  func pathAsMask() {
    guard let layer = selected,layer.isPath,
      let i = document.layers.firstIndex(where:{$0.id == layer.id}),
      let target = document.layers.dropFirst(i+1).first(where:{!$0.isPath && $0.kind != .group && !$0.locked}) else {return}
    pathToSelection();selectLayer(target.id);beginTransaction("路径转蒙版");maskFromSelection();endTransaction()
  }
}
