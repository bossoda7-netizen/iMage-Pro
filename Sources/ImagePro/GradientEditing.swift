import AppKit
import CoreImage
import SwiftUI

struct GradientNode: Identifiable, Codable, Equatable {
  var id = UUID()
  var point: Point
  var color: RGBA
  var position: Double?
}
struct GradientOpacityStop: Identifiable, Codable, Equatable {
  var id = UUID()
  var position: Double
  var opacity: Double
}
struct GradientDefinition: Codable, Equatable {
  var style = "mesh"
  var nodes: [GradientNode]
  var softness: Double = 0.7
  var gridSize: Int = 4
  var axisStart: Point?
  var axisEnd: Point?
  var opacityStops: [GradientOpacityStop]?
  var start: Point { axisStart ?? nodes.first?.point ?? Point(x:0,y:0) }
  var end: Point { axisEnd ?? nodes.last?.point ?? Point(x:1,y:1) }
  func location(_ node: GradientNode) -> Double {
    if let position = node.position { return position }
    let dx = end.x-start.x,dy = end.y-start.y
    return min(1,max(0,((node.point.x-start.x)*dx+(node.point.y-start.y)*dy)/max(0.00001,dx*dx+dy*dy)))
  }
  var effectiveOpacityStops: [GradientOpacityStop] {
    (opacityStops?.isEmpty == false ? opacityStops : nil) ?? [GradientOpacityStop(id:nodes.first?.id ?? UUID(),position:0,opacity:1),
                    GradientOpacityStop(id:nodes.last?.id ?? UUID(),position:1,opacity:1)]
  }
  func colorOnly(at position: Double) -> RGBA {
    let sorted = nodes.sorted { location($0)<location($1) }
    guard let first = sorted.first else { return RGBA() }
    var color = first.color
    if position>=location(sorted.last!) { color = sorted.last!.color }
    else if position>location(first) {
      for i in 1..<sorted.count where position<=location(sorted[i]) {
        let a = sorted[i-1],b = sorted[i]
        let t = min(1,max(0,(position-location(a))/max(0.00001,location(b)-location(a))))
        color = RGBA(r:a.color.r+(b.color.r-a.color.r)*t,g:a.color.g+(b.color.g-a.color.g)*t,
          b:a.color.b+(b.color.b-a.color.b)*t,a:a.color.a+(b.color.a-a.color.a)*t)
        break
      }
    }
    return color
  }
  func color(at position: Double) -> RGBA {
    var color = colorOnly(at:position)
    let opacity = effectiveOpacityStops.sorted { $0.position<$1.position }
    var alpha = opacity.first?.opacity ?? 1
    if position >= (opacity.last?.position ?? 1) { alpha = opacity.last?.opacity ?? 1 }
    else if opacity.count > 1 { for i in 1..<opacity.count where position<=opacity[i].position {
      let a = opacity[i-1],b = opacity[i]
      let t = min(1,max(0,(position-a.position)/max(0.00001,b.position-a.position)))
      alpha = a.opacity+(b.opacity-a.opacity)*t;break
    }}
    color.a *= alpha
    return color
  }
  var canvasNodes: [GradientNode] {
    if style == "mesh" || style == "solid" { return nodes }
    guard nodes.count>=2 else { return [] }
    var a = nodes[0],b = nodes[1];a.point = start;b.point = end
    return [a,b]
  }
  static func mesh(_ colors: [RGBA], grid: Int = 4) -> GradientDefinition {
    let n = max(2, min(4, grid))
    let nodes = (0..<n*n).map { i in
      GradientNode(point: Point(x: Double(i%n)/Double(n-1), y: Double(i/n)/Double(n-1)), color: colors[i%colors.count])
    }
    return GradientDefinition(nodes: nodes, gridSize: n)
  }
}

enum GradientRenderer {
  static let context = CIContext()
  static let meshKernel = NativeKernels.color("mesh")
  static func render(_ gradient: GradientDefinition, width: Int, height: Int) -> CGImage {
    let extent = CGRect(x: 0, y: 0, width: max(1,width), height: max(1,height))
    let ci: CIImage
    if gradient.style == "mesh", let kernel = meshKernel {
      var args: [Any] = [CIVector(x: extent.width, y: extent.height), 8+(1-gradient.softness)*48]
      for i in 0..<16 {
        let node = gradient.nodes.indices.contains(i) ? gradient.nodes[i] : GradientNode(point: .init(x: 0, y: 0), color: .init())
        args.append(CIVector(x: node.point.x, y: node.point.y, z: gradient.nodes.indices.contains(i) ? 1 : 0, w: 0))
        args.append(CIVector(x: node.color.r, y: node.color.g, z: node.color.b, w: node.color.a))
      }
      ci = kernel.apply(extent: extent, arguments: args) ?? CIImage(color: .black).cropped(to: extent)
    } else if gradient.style == "solid" {
      let c = gradient.nodes.first?.color ?? RGBA()
      ci = CIImage(color: CIColor(color: c.ns)!).cropped(to: extent)
    } else {
      let axisStart = gradient.start,axisEnd = gradient.end
      let colors = (0...256).map { i -> CGColor in
        let c = gradient.color(at:Double(i)/256)
        return CGColor(colorSpace:ImageRenderer.colorSpace,components:[c.r,c.g,c.b,c.a])!
      } as NSArray
      let locations = (0...256).map { CGFloat($0)/256 }
      if let gradientRef = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations) {
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)
        if let ctx = CGContext(data: &bitmap, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
          let start = CGPoint(x: axisStart.x * extent.width, y: (1 - axisStart.y) * extent.height)
          let end = CGPoint(x: axisEnd.x * extent.width, y: (1 - axisEnd.y) * extent.height)
          if gradient.style == "radial" {
            let center = CGPoint(x: axisStart.x * extent.width, y: (1 - axisStart.y) * extent.height)
            let radius = max(1, hypot(end.x - center.x, end.y - center.y))
            ctx.drawRadialGradient(gradientRef, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
          } else {
            ctx.drawLinearGradient(gradientRef, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
          }
          ci = CIImage(bitmapData: Data(bitmap), bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        } else { ci = CIImage(color: .black).cropped(to: extent) }
      } else { ci = CIImage(color: .black).cropped(to: extent) }
    }
    return context.createCGImage(ci, from: extent, format: .RGBA8, colorSpace: ImageRenderer.colorSpace)!
  }
}
struct GradientPreset: Identifiable {
  var id: Int
  var name: String
  var definition: GradientDefinition
  var thumbnail: CGImage
}
enum GradientPresets {
  static let all: [GradientPreset] = {
    let palettes: [[String]] = [
      ["F69DAE","F8D985","63C0BD","777ADE"], ["04364A","176B87","64CCC5","DAFFFB"],
      ["FF4655","FFB86C","EA00D9","7F00FF"], ["331D2C","3F2E3E","A78295","EFE1D1"],
      ["F6F4EB","91C8E4","749BC2","4682A9"], ["FFF7D4","FFD95A","C07F00","4C3D3D"],
      ["071952","088395","35A29F","F2F7A1"], ["27005D","9400FF","AED2FF","E4F1FF"],
      ["CECE5A","FFE17B","FD8D14","C51605"], ["F1EFEF","CCC8AA","7D7C7C","191717"]]
    func color(_ h: String) -> RGBA { let v = UInt32(h,radix:16)!; return RGBA(r: Double(v>>16)/255,g:Double((v>>8)&255)/255,b:Double(v&255)/255) }
    return (0..<40).map { i in
      let palette = palettes[i%10].map(color)
      let colors = (0..<16).map { j in palette[(j/4+j%4+i/10)%4] }
      var gradient = GradientDefinition.mesh(colors)
      if i/10%2 == 1 { for j in gradient.nodes.indices { gradient.nodes[j].point.x = min(1,max(0,gradient.nodes[j].point.x+sin(Double(j))*0.12)) } }
      gradient.softness = [0.75,0.5,0.9,0.3][i/10]
      return GradientPreset(id: i, name: ["晨光","深海","霓虹","暮色","云端","琥珀","翡翠","紫雾","焰火","石墨"][i%10]+" \(i/10+1)", definition: gradient, thumbnail: GradientRenderer.render(gradient,width:96,height:64))
    }
  }()
  private static let savedKey = "superGradientPresets"
  static func saved() -> [GradientPreset] {
    guard let data = UserDefaults.standard.data(forKey: savedKey),
      let definitions = try? JSONDecoder().decode([GradientDefinition].self, from: data) else { return [] }
    return definitions.enumerated().map { index, definition in
      GradientPreset(id: 1000 + index, name: "我的渐变 \(index + 1)", definition: definition,
        thumbnail: GradientRenderer.render(definition, width: 96, height: 64))
    }
  }
  static func allIncludingSaved() -> [GradientPreset] { all + saved() }
  static func save(_ definition: GradientDefinition) {
    var values = (try? JSONDecoder().decode([GradientDefinition].self,
      from: UserDefaults.standard.data(forKey: savedKey) ?? Data())) ?? []
    values.removeAll { $0 == definition }
    values.insert(definition, at: 0)
    if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: savedKey) }
  }
  static func removeSaved(at index: Int) {
    guard let data = UserDefaults.standard.data(forKey: savedKey),
      var values = try? JSONDecoder().decode([GradientDefinition].self, from: data),
      values.indices.contains(index) else { return }
    values.remove(at: index)
    if let encoded = try? JSONEncoder().encode(values) {
      UserDefaults.standard.set(encoded, forKey: savedKey)
    }
  }
}

extension EditorStore {
  func addGradient(from start: CGPoint, to end: CGPoint) {
    var layer = ImageLayer(name: L(branch.id == "mesh" ? "超级渐变" : "渐变"), kind: .gradient, width: document.width, height: document.height)
    if branch.id == "mesh" { layer.gradient = GradientPresets.all[0].definition }
    else {
      layer.gradient = GradientDefinition(style: branch.id, nodes: [
        GradientNode(point: Point(x:start.x/document.width,y:start.y/document.height),color:foreground,position:0),
        GradientNode(point: Point(x:end.x/document.width,y:end.y/document.height),color:secondaryColor,position:1)],
        axisStart:Point(x:start.x/document.width,y:start.y/document.height),
        axisEnd:Point(x:end.x/document.width,y:end.y/document.height))
    }
    beginTransaction("创建渐变图层")
    edit("创建渐变图层") { doc in let i = doc.insertionIndex; layer.parentID = doc.insertionParent; doc.layers.insert(layer,at:i); doc.selectedLayerID = layer.id }
    if selection != nil { maskFromSelection() }
    endTransaction(); inspector = .special; showInspector = true
    gradientPoint = layer.gradient?.nodes.first?.id
  }
}
struct GradientInspector: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var layer: ImageLayer
  @State private var palette = false
  var gradient: GradientDefinition { layer.gradient! }
  var point: GradientNode? { gradient.nodes.first { $0.id == store.gradientPoint } ?? gradient.nodes.first }
  var body: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack {
        SectionCaption(title: gradient.style == "mesh" ? "超级渐变" : gradient.style == "solid" ? "填充" : "渐变")
      }
      if gradient.style == "mesh" {
        ParameterSlider(store:store,title:"柔和度",value:gradient.softness,range:0...1,unit:"%",percentage:true,defaultValue:0.7) { v in store.updateSelected("调整渐变") { $0.gradient?.softness = v } }
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(gradient.nodes) { node in
              Button { store.gradientPoint = node.id } label: {
                Circle().fill(node.color.color).frame(width:24,height:24)
                  .overlay(Circle().strokeBorder(node.id == point?.id ? Color.primary : .clear,lineWidth:2))
              }.buttonStyle(.plain)
            }.id(AppLocalization.language)
          }
        }.pageScrollStyle(.horizontal)
      } else if gradient.style != "solid" {
        GradientStopEditor(store:store,layer:layer)
      }
      if let point, ["mesh","solid"].contains(gradient.style) {
        Button { palette.toggle() } label: {
          HStack { Text(L("节点颜色")); Spacer(); RoundedRectangle(cornerRadius:7).fill(point.color.color).frame(width:38,height:28) }
        }.buttonStyle(.plain).popover(isPresented:$palette) {
          ModernColorPalette(color:Binding(get:{ self.point?.color ?? point.color },set:{ v in
            store.updateSelected("调整渐变颜色") { l in
              if let i = l.gradient?.nodes.firstIndex(where:{$0.id == point.id}) { l.gradient?.nodes[i].color = v }
            }
          }),editingChanged:{active in if active {store.beginTransaction("调整渐变颜色")} else {store.endTransaction()}}).padding(20).frame(width:300)
        }
      }
      if gradient.style == "mesh" {
        SectionCaption(title:"超级渐变预设")
        Button { GradientPresets.save(gradient); store.notify("已保存为超级渐变预设") } label: {
          Label(L("保存当前渐变"), systemImage: "plus.circle")
        }.buttonStyle(.bordered)
        LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:8) {
          ForEach(GradientPresets.allIncludingSaved()) { preset in
            Button {
              store.updateSelected("更换渐变预设") { $0.gradient = preset.definition }
              store.gradientPoint = preset.definition.nodes.first?.id
              store.chooseTool(.fill,branch:ToolCategory.fill.branches[2])
            } label: { Image(decorative:preset.thumbnail,scale:1).resizable().aspectRatio(1.5,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:7)) }
              .buttonStyle(.plain).help(L(preset.name))
              .contextMenu {
                if preset.id >= 1000 {
                  Button(L("删除预设"), role: .destructive) {
                    GradientPresets.removeSaved(at: preset.id - 1000)
                    store.notify("已删除渐变预设")
                  }
                }
              }
          }.id(AppLocalization.language)
        }
      }
      Text(L(gradient.style == "mesh" ? "拖动画布节点调整颜色分布。" : gradient.style == "solid" ? "纯色填充可随时修改颜色和不透明度。" : "上方编辑不透明度，下方编辑颜色；点击空白处添加色标。画布端点控制方向与范围。"))
        .font(.system(size:11)).foregroundStyle(.secondary)
    }
  }
}


extension ImageEffect {
  var fillGradient: GradientDefinition {
    let angle = value("angle",90)*Double.pi/180
    let radial = style == "radial"
    let a = radial ? Point(x:0.5,y:0.5) : Point(x:0.5-cos(angle)*0.5,y:0.5+sin(angle)*0.5)
    let b = radial ? Point(x:0.5+value("gradientRadius",0.7),y:0.5) : Point(x:0.5+cos(angle)*0.5,y:0.5-sin(angle)*0.5)
    return GradientDefinition(style:radial ? "radial" : "linear",nodes:[
      GradientNode(point:a,color:tint ?? RGBA(r:1,g:1,b:1),position:0),
      GradientNode(point:b,color:targetColor ?? RGBA(r:0.3,g:0.4,b:1),position:1)],axisStart:a,axisEnd:b)
  }
}
