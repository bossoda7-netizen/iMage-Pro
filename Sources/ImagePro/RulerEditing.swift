import AppKit

extension RulerMeasurement {
  var drawingTool: RulerTool {tool ?? .ruler}
  func distance(to p: CGPoint) -> Double {
    let a = start.cg, b = end.cg
    if drawingTool == .compass {return min(hypot(p.x-a.x,p.y-a.y),abs(hypot(p.x-a.x,p.y-a.y)-length))}
    if drawingTool == .guides {return min(abs(p.x-b.x),abs(p.y-b.y))}
    if drawingTool == .protractor {
      let delta = atan2(p.y-a.y,p.x-a.x)-angle*Double.pi/180
      let normalized = atan2(sin(delta),cos(delta))
      if normalized<=0 {return min(hypot(p.x-a.x,p.y-a.y),abs(hypot(p.x-a.x,p.y-a.y)-length))}
    }
    let d = CGPoint(x:b.x-a.x,y:b.y-a.y), l = d.x*d.x+d.y*d.y
    let t = l > 0 ? min(1,max(0,((p.x-a.x)*d.x+(p.y-a.y)*d.y)/l)) : 0
    return hypot(p.x-a.x-t*d.x,p.y-a.y-t*d.y)
  }
}
extension EditorStore {
  func updateRulerMeasurement(_ value: RulerMeasurement) {
    guard let i = rulerMeasurements.firstIndex(where: {$0.id == value.id}), rulerMeasurements[i] != value, rulerMeasurements[i].locked != true else {return}
    rulerUndoSnapshot()
    rulerMeasurements[i] = value
  }
  func toggleRulerLock() {
    guard let i = rulerMeasurements.firstIndex(where: {$0.id == selectedRulerID}) else {return}
    rulerUndoSnapshot();rulerMeasurements[i].locked = !(rulerMeasurements[i].locked ?? false)
  }
  func deleteSelectedRulerMeasurement() {
    guard let id = selectedRulerID, rulerMeasurements.contains(where: {$0.id == id}) else {deleteLastRulerMeasurement();return}
    guard rulerMeasurements.first(where: {$0.id == id})?.locked != true else {return}
    rulerUndoSnapshot(); rulerMeasurements.removeAll {$0.id == id}; selectedRulerID = nil
  }
}
extension CanvasNSView {
  func drawWorkspaceRulers(_ ctx: CGContext) {
    guard let store, store.showRulers else {return}
    let rect = imageRect, thickness = 24.0
    let top = CGRect(x:rect.minX,y:rect.minY-thickness,width:rect.width,height:thickness)
    let left = CGRect(x:rect.minX-thickness,y:rect.minY,width:thickness,height:rect.height)
    ctx.saveGState()
    ctx.setFillColor(NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor)
    ctx.fill(top);ctx.fill(left)
    ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.5).cgColor);ctx.setLineWidth(0.6)
    ctx.stroke(top);ctx.stroke(left)
    let unitsPerPixel = store.rulerValue(1)
    let wanted = 90 / max(0.0001,scale) * unitsPerPixel
    let power = pow(10, floor(log10(max(0.0001,wanted))))
    let major = [1.0,2,5,10].first(where: {$0*power >= wanted})! * power
    let minorPixels = major / 5 / unitsPerPixel
    let font = NSFont.monospacedDigitSystemFont(ofSize:10,weight:.regular)
    let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
    for axis in 0...1 {
      let limit = axis == 0 ? store.document.width : store.document.height
      let count = min(5000, Int(limit/minorPixels))
      guard count >= 0 else {continue}
      for index in 0...count {
        let pixel = Double(index)*minorPixels, position = pixel*scale
        let long = index%5 == 0, length = long ? 9.0 : 4.0
        if axis == 0 {
          ctx.move(to:CGPoint(x:rect.minX+position,y:rect.minY));ctx.addLine(to:CGPoint(x:rect.minX+position,y:rect.minY-length))
        } else {
          ctx.move(to:CGPoint(x:rect.minX,y:rect.minY+position));ctx.addLine(to:CGPoint(x:rect.minX-length,y:rect.minY+position))
        }
        ctx.strokePath()
        if long {
          let v = store.rulerValue(pixel)
          let text = abs(v-v.rounded())<0.001 ? String(Int(v.rounded())) : String(format:"%.2g",v)
          if axis == 0 {text.draw(at:CGPoint(x:rect.minX+position+3,y:rect.minY-thickness+1),withAttributes:attributes)}
          else {ctx.saveGState();ctx.translateBy(x:rect.minX-thickness+1,y:rect.minY+position+3);ctx.rotate(by:-.pi/2);text.draw(at:.zero,withAttributes:attributes);ctx.restoreGState()}
        }
      }
    }
    ctx.restoreGState()
  }
  func drawMeasurement(_ m: RulerMeasurement, context ctx: CGContext) {
    guard let store else {return}
    let selected = store.rulerMode && store.selectedRulerID == m.id
    ctx.saveGState()
    let ink = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .white
    let contrastInk: NSColor = ink.redComponent + ink.greenComponent + ink.blueComponent > 1.5 ? .black : .white
    ctx.setShadow(offset:.zero,blur:1.5/scale,color:contrastInk.withAlphaComponent(0.85).cgColor)
    ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(selected ? 0.95 : 0.68).cgColor)
    ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.8).cgColor)
    ctx.setLineWidth((selected ? 1.6 : 1.0)/scale)
    switch m.drawingTool {
    case .ruler:
      ctx.move(to:m.start.cg);ctx.addLine(to:m.end.cg);ctx.strokePath()
      let count = max(1,min(100,Int(m.length*scale/12))), angle = m.angle * .pi/180
      for i in 0...count {
        let t = Double(i)/Double(count), p = CGPoint(x:m.start.x+(m.end.x-m.start.x)*t,y:m.start.y+(m.end.y-m.start.y)*t)
        let size = Double(i%5 == 0 ? 8 : 4)/scale
        ctx.move(to:p);ctx.addLine(to:CGPoint(x:p.x-sin(angle)*size,y:p.y+cos(angle)*size))
      };ctx.strokePath()
    case .protractor:
      let radius = m.length, angle = m.angle * .pi/180
      ctx.addArc(center:m.start.cg,radius:radius,startAngle:angle - .pi,endAngle:angle,clockwise:false);ctx.strokePath()
      ctx.move(to:m.start.cg);ctx.addLine(to:m.end.cg);ctx.strokePath()
      for degree in stride(from:0,through:180,by:10) {
        let a = angle-Double(degree) * .pi/180
        let r = radius-Double(degree%30 == 0 ? 10 : 5)/scale
        ctx.move(to:CGPoint(x:m.start.x+cos(a)*r,y:m.start.y+sin(a)*r));ctx.addLine(to:CGPoint(x:m.start.x+cos(a)*radius,y:m.start.y+sin(a)*radius));ctx.strokePath()
        if degree%30 == 0 {String(degree).draw(at:CGPoint(x:m.start.x+cos(a)*(r-12/scale),y:m.start.y+sin(a)*(r-12/scale)),withAttributes:[.font:NSFont.systemFont(ofSize:10/scale),.foregroundColor:NSColor.labelColor])}
      }
    case .compass:
      ctx.strokeEllipse(in:CGRect(x:m.start.x-m.length,y:m.start.y-m.length,width:2*m.length,height:2*m.length))
      ctx.setLineDash(phase:0,lengths:[3/scale,3/scale]);ctx.move(to:m.start.cg);ctx.addLine(to:m.end.cg);ctx.strokePath();ctx.setLineDash(phase:0,lengths:[])
      ctx.move(to:CGPoint(x:m.start.x-5/scale,y:m.start.y));ctx.addLine(to:CGPoint(x:m.start.x+5/scale,y:m.start.y))
      ctx.move(to:CGPoint(x:m.start.x,y:m.start.y-5/scale));ctx.addLine(to:CGPoint(x:m.start.x,y:m.start.y+5/scale));ctx.strokePath()
    case .guides:
      ctx.setLineDash(phase:0,lengths:[5/scale,4/scale])
      ctx.move(to:CGPoint(x:m.end.x,y:0));ctx.addLine(to:CGPoint(x:m.end.x,y:store.document.height))
      ctx.move(to:CGPoint(x:0,y:m.end.y));ctx.addLine(to:CGPoint(x:store.document.width,y:m.end.y));ctx.strokePath();ctx.setLineDash(phase:0,lengths:[])
    }
    for p in [m.start,m.end] {ctx.fillEllipse(in:CGRect(x:p.x-3/scale,y:p.y-3/scale,width:6/scale,height:6/scale))}
    let text = m.drawingTool == .protractor ? String(format:"%.1f°",m.angle) : String(format:"%.1f %@",store.rulerValue(m.length),store.rulerUnit)
    text.draw(at:CGPoint(x:m.end.x+8/scale,y:m.end.y+8/scale),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11/scale,weight:.medium),.foregroundColor:NSColor.labelColor,.backgroundColor:NSColor.windowBackgroundColor.withAlphaComponent(0.85)])
    ctx.restoreGState()
  }
}
