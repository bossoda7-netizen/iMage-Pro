import SwiftUI

struct CurveEditor: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store:EditorStore
  var effect:ImageEffect
  @State private var channel = "RGB"
  @State private var selectedIndex = 0
  var prefix:String {channel == "RGB" ? "curve" : channel.lowercased()+"Curve"}
  var points:[Point] {effect.curvePoints(prefix)}
  var tint:Color {channel == "Red" ? .red : channel == "Green" ? .green : channel == "Blue" ? .blue : .primary}
  func change(_ name:String,_ operation:@escaping (inout [Point])->Void) {
    let key = prefix
    store.updateEffect(effect.id,name) { e in
      var points = e.curvePoints(key);operation(&points)
      if e.tonalCurves == nil {e.tonalCurves = [:]};e.tonalCurves?[key] = points
    }
  }
  var body:some View {
    VStack(spacing:12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(L("通道")).font(.system(size: 12)).foregroundStyle(.secondary)
        Picker(L("通道"),selection:$channel) {
          Text(L("RGB")).tag("RGB");Text(L("红")).tag("Red");Text(L("绿")).tag("Green");Text(L("蓝")).tag("Blue")
        }.id(AppLocalization.language).labelsHidden().pickerStyle(.segmented).onChange(of:channel) {_,_ in selectedIndex = 0}
      }
      GeometryReader { geometry in
        ZStack {
          HistogramView(image:store.effectInput(effect.id),channel:channel).allowsHitTesting(false)
          Canvas {context,size in
            var grid = Path()
            for i in 0...4 {
              let x = size.width*Double(i)/4,y = size.height*Double(i)/4
              grid.move(to:CGPoint(x:x,y:0));grid.addLine(to:CGPoint(x:x,y:size.height))
              grid.move(to:CGPoint(x:0,y:y));grid.addLine(to:CGPoint(x:size.width,y:y))
            }
            context.stroke(grid,with:.color(.secondary.opacity(0.18)),lineWidth:0.5)
            var reference = Path();reference.move(to:CGPoint(x:0,y:size.height));reference.addLine(to:CGPoint(x:size.width,y:0))
            context.stroke(reference,with:.color(.secondary.opacity(0.4)),style:StrokeStyle(lineWidth:0.7,dash:[3,3]))
            var path = Path()
            for i in 0...256 {
              let x = Double(i)/256,y = AdvancedEffects.evaluateCurve(points,x)
              let p = CGPoint(x:x*size.width,y:(1-y)*size.height)
              if i == 0 {path.move(to:p)} else {path.addLine(to:p)}
            }
            context.stroke(path,with:.color(tint),lineWidth:2)
          }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { event in
            let p = Point(x:min(1,max(0,event.location.x/geometry.size.width)),y:min(1,max(0,1-event.location.y/geometry.size.height)))
            guard points.count<16,!points.contains(where:{abs($0.x-p.x)<0.01}) else {return}
            selectedIndex = points.filter {$0.x<p.x}.count
            change("添加曲线控制点") {$0.append(p);$0.sort {$0.x<$1.x}}
          })
          ForEach(points.indices,id:\.self) { i in
            Circle().fill(tint).frame(width:i == selectedIndex ? 10 : 7,height:i == selectedIndex ? 10 : 7)
              .overlay(Circle().stroke(.background,lineWidth:1)).frame(width:22,height:22).contentShape(Circle())
              .position(x:points[i].x*geometry.size.width,y:(1-points[i].y)*geometry.size.height)
              .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("tonal-curve")).onChanged { event in
                selectedIndex = i;store.beginTransaction("调整曲线")
                change("调整曲线") { p in
                  guard p.indices.contains(i) else {return}
                  let low = i == 0 ? 0 : p[i-1].x+0.002,high = i == p.count-1 ? 1 : p[i+1].x-0.002
                  p[i] = Point(x:min(high,max(low,event.location.x/geometry.size.width)),y:min(1,max(0,1-event.location.y/geometry.size.height)))
                }
              }.onEnded { event in
                if i>0,i<points.count-1,(event.location.y < -16 || event.location.y > geometry.size.height+16) {
                  change("删除曲线控制点") {if $0.indices.contains(i) {$0.remove(at:i)}};selectedIndex = 0
                }
                store.endTransaction()
              }).accessibilityLabel(L("曲线控制点，输入{0}，输出{1}", Int(points[i].x*255), Int(points[i].y*255)))
          }.id(AppLocalization.language)
        }.coordinateSpace(name:"tonal-curve")
      }.frame(height:190).padding(.horizontal,11)
      if points.indices.contains(selectedIndex) {
        ParameterSlider(store:store,title:"输入",value:points[selectedIndex].x*255,range:0...255,digits:0) {value in
          let index = selectedIndex
          change("调整曲线输入") {p in
            guard p.indices.contains(index) else {return}
            p[index].x = min(index == p.count-1 ? 1 : p[index+1].x-0.002,max(index == 0 ? 0 : p[index-1].x+0.002,value/255))
          }
        }
        ParameterSlider(store:store,title:"输出",value:points[selectedIndex].y*255,range:0...255,digits:0) {value in
          let index = selectedIndex;change("调整曲线输出") {if $0.indices.contains(index) {$0[index].y = value/255}}
        }
      }
      HStack {
        Button(L("删除点")) {let index = selectedIndex;change("删除曲线点") {$0.remove(at:index)};selectedIndex = 0}
          .disabled(selectedIndex == 0 || selectedIndex>=points.count-1)
        Spacer()
        Button(L("重置通道")) {change("重置曲线") {$0 = [Point(x:0,y:0),Point(x:1,y:1)]};selectedIndex = 0}
      }
    }
  }
}
struct HistogramView:View {
  @ObservedObject private var localization = LocalizationState.shared
  var image:CGImage?
  var channel = "RGB"
  static func bins(_ image:CGImage,channel:String)->[Double] {
    guard let cg = ImageRenderer.bitmap(256,128) else {return []}
    cg.draw(image,in:CGRect(x:0,y:0,width:256,height:128))
    guard let bytes = cg.data?.assumingMemoryBound(to:UInt8.self) else {return []}
    var bins = [Double](repeating:0,count:256)
    for i in 0..<256*128 {
      let a = Double(bytes[i*4+3])/255
      guard a>0.001 else {continue}
      let values = (0..<3).map {min(255,Double(bytes[i*4+$0])/a)}
      let value = channel == "Red" ? values[0] : channel == "Green" ? values[1] : channel == "Blue" ? values[2] : values[0]*0.2126+values[1]*0.7152+values[2]*0.0722
      bins[min(255,max(0,Int(value)))] += a
    }
    return bins
  }
  var body:some View {
    Canvas {context,size in
      guard let image else {return}
      let bins = Self.bins(image,channel:channel),peak = max(1,bins.max() ?? 1)
      var path = Path();path.move(to:CGPoint(x:0,y:size.height))
      for i in bins.indices {path.addLine(to:CGPoint(x:Double(i)*size.width/255,y:size.height*(1-sqrt(bins[i]/peak))))}
      path.addLine(to:CGPoint(x:size.width,y:size.height));path.closeSubpath()
      context.fill(path,with:.color(.secondary.opacity(0.25)))
    }.background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:6))
      .accessibilityLabel(L("{0} 输入直方图，横轴从阴影到高光，纵轴表示像素分布", L(["Red":"红", "Green":"绿", "Blue":"蓝"][channel] ?? channel)))
  }
}
