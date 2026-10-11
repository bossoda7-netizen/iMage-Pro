import SwiftUI

struct GradientStopEditor: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var layer: ImageLayer
  var effectID: UUID? = nil
  @State private var opacityID: UUID?
  var gradient: GradientDefinition { layer.gradient! }
  var colorStop: GradientNode? { gradient.nodes.first {$0.id == store.gradientPoint} ?? gradient.nodes.first }
  var opacityStop: GradientOpacityStop? { gradient.effectiveOpacityStops.first {$0.id == opacityID} }
  func change(_ name: String, _ operation: @escaping (inout GradientDefinition) -> Void) {
    func modify(_ g:inout GradientDefinition) {
      if g.axisStart == nil {g.axisStart = g.start;g.axisEnd = g.end}
      for i in g.nodes.indices where g.nodes[i].position == nil {g.nodes[i].position = g.location(g.nodes[i])}
      operation(&g)
    }
    if let effectID {
      store.updateEffect(effectID,name) {e in var g = e.gradient ?? e.fillGradient;modify(&g);e.gradient = g;e.style = "gradient"}
    } else {
      store.updateSelected(name) {l in guard var g = l.gradient else {return};modify(&g);l.gradient = g}
    }
  }

  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      Picker(L("类型"),selection:Binding(get:{gradient.style},set:{ value in change("更改渐变类型"){$0.style = value} })) {
        Text(L("线性")).tag("linear");Text(L("径向")).tag("radial")
      }.id(AppLocalization.language).pickerStyle(.segmented)
      GeometryReader { geometry in
        let width = geometry.size.width-16
        VStack(spacing:0) {
          Color.clear.frame(height:25).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onEnded { event in
              let position = min(1,max(0,(event.location.x-8)/width))
              let stop = GradientOpacityStop(position:position,opacity:1)
              change("添加不透明度色标") { g in
                if g.opacityStops == nil { g.opacityStops = g.effectiveOpacityStops }
                if (g.opacityStops?.count ?? 0)<32 { g.opacityStops?.append(stop) }
              };opacityID = stop.id
            })
          ZStack {
            Canvas { context,size in
              for y in 0..<3 { for x in 0..<Int(ceil(size.width/8)) {
                context.fill(Path(CGRect(x:x*8,y:y*8,width:8,height:8)),with:.color((x+y)%2 == 0 ? .gray.opacity(0.2) : .gray.opacity(0.4)))
              }}
            }
            LinearGradient(stops:(0...64).map { .init(color:gradient.color(at:Double($0)/64).color,location:Double($0)/64) },startPoint:.leading,endPoint:.trailing)
          }.frame(height:24).clipShape(RoundedRectangle(cornerRadius:4)).padding(.horizontal,8)
            .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(.primary.opacity(0.15)).padding(.horizontal,8))
          Color.clear.frame(height:25).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onEnded { event in
              let position = min(1,max(0,(event.location.x-8)/width))
              let node = GradientNode(point:Point(x:position,y:position),color:gradient.colorOnly(at:position),position:position)
              change("添加颜色色标") { if $0.nodes.count<32 {$0.nodes.append(node)} }
              opacityID = nil;store.gradientPoint = node.id
            })
        }
        ForEach(gradient.effectiveOpacityStops) { stop in
          stopHandle(color:.primary.opacity(stop.opacity),selected:opacityID == stop.id,upper:true)
            .position(x:8+stop.position*width,y:12)
            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("gradient-stops")).onChanged { event in
              opacityID = stop.id;store.beginTransaction("移动不透明度色标")
              change("移动不透明度色标") { g in
                if g.opacityStops == nil { g.opacityStops = g.effectiveOpacityStops }
                if let i = g.opacityStops?.firstIndex(where:{$0.id == stop.id}) { g.opacityStops?[i].position = min(1,max(0,(event.location.x-8)/width)) }
              }
            }.onEnded { _ in store.endTransaction() })
            .accessibilityLabel(L("不透明度色标，位置{0}%，不透明度{1}%", Int(stop.position*100), Int(stop.opacity*100)))
        }.id(AppLocalization.language)
        ForEach(gradient.nodes) { node in
          stopHandle(color:node.color.color,selected:opacityID == nil && colorStop?.id == node.id,upper:false)
            .position(x:8+gradient.location(node)*width,y:62)
            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("gradient-stops")).onChanged { event in
              opacityID = nil;store.gradientPoint = node.id;store.beginTransaction("移动颜色色标")
              change("移动颜色色标") { g in
                if let i = g.nodes.firstIndex(where:{$0.id == node.id}) { g.nodes[i].position = min(1,max(0,(event.location.x-8)/width)) }
              }
            }.onEnded { _ in store.endTransaction() })
            .accessibilityLabel(L("颜色色标，位置{0}%", Int(gradient.location(node)*100)))
        }.id(AppLocalization.language)
      }.coordinateSpace(name:"gradient-stops").frame(height:76)
      if let opacityStop {
        ParameterSlider(store:store,title:"不透明度",value:opacityStop.opacity,range:0...1,percentage:true) { value in
          change("调整不透明度色标") { g in
            if g.opacityStops == nil { g.opacityStops = g.effectiveOpacityStops }
            if let i = g.opacityStops?.firstIndex(where:{$0.id == opacityStop.id}) { g.opacityStops?[i].opacity = value }
          }
        }
        ParameterSlider(store:store,title:"位置",value:opacityStop.position,range:0...1,percentage:true) { value in
          change("移动不透明度色标") { g in
            if g.opacityStops == nil { g.opacityStops = g.effectiveOpacityStops }
            if let i = g.opacityStops?.firstIndex(where:{$0.id == opacityStop.id}) { g.opacityStops?[i].position = value }
          }
        }
      } else if let node = colorStop {
        ModernColorButton(title:"色标颜色",color:Binding(get:{colorStop?.color ?? node.color},set:{ value in
          change("调整渐变颜色") { g in if let i = g.nodes.firstIndex(where:{$0.id == node.id}) {g.nodes[i].color = value} }
        }),editingChanged:{active in if active {store.beginTransaction("调整渐变颜色")} else {store.endTransaction()} })
        ParameterSlider(store:store,title:"位置",value:gradient.location(node),range:0...1,percentage:true) { value in
          change("移动颜色色标") { g in if let i = g.nodes.firstIndex(where:{$0.id == node.id}) {g.nodes[i].position = value} }
        }
      }
      HStack {
        Button(L("删除色标"),role:.destructive) {
          if let opacityID {
            change("删除不透明度色标") { g in
              if g.opacityStops == nil {g.opacityStops = g.effectiveOpacityStops}
              g.opacityStops?.removeAll {$0.id == opacityID}
            };self.opacityID = nil
          } else if let node = colorStop {
            change("删除颜色色标") {$0.nodes.removeAll {$0.id == node.id}}
            store.gradientPoint = gradient.nodes.first?.id
          }
        }.disabled(opacityID != nil ? gradient.effectiveOpacityStops.count<=2 : gradient.nodes.count<=2)
        Spacer()
        Button(L("反向")) {
          change("反向渐变") { g in
            let locations = g.nodes.map { g.location($0) }; for i in g.nodes.indices {g.nodes[i].position = 1-locations[i]}
            if let stops = g.opacityStops { g.opacityStops = stops.map { var stop = $0; stop.position = 1-stop.position; return stop } }
          }
        }
      }.controlSize(.regular)
    }
  }
  private func stopHandle(color:Color,selected:Bool,upper:Bool) -> some View {
    Path { path in
      if upper {
        path.move(to:CGPoint(x:2,y:2));path.addLine(to:CGPoint(x:14,y:2));path.addLine(to:CGPoint(x:14,y:13))
        path.addLine(to:CGPoint(x:8,y:19));path.addLine(to:CGPoint(x:2,y:13))
      } else {
        path.move(to:CGPoint(x:8,y:1));path.addLine(to:CGPoint(x:14,y:7));path.addLine(to:CGPoint(x:14,y:18))
        path.addLine(to:CGPoint(x:2,y:18));path.addLine(to:CGPoint(x:2,y:7))
      }
      path.closeSubpath()
    }.fill(color).overlay {
      RoundedRectangle(cornerRadius:3).strokeBorder(selected ? Color.primary : .secondary.opacity(0.6),lineWidth:selected ? 2 : 0.7)
    }.frame(width:16,height:20).contentShape(Rectangle())
  }
}
