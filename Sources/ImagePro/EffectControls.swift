import AppKit
import SwiftUI

struct AdvancedEffectControls: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var effect: ImageEffect
  @State private var stylePicker = false
  @State private var colorBand = 0
  @State private var channel = 0
  func param(_ title: String, _ key: String, _ range: ClosedRange<Double>, _ fallback: Double = 0)
    -> some View
  {
    ParameterSlider(
      store: store, title: title, value: effect.value(key, fallback), range: range, digits: 2, defaultValue: ImageEffect(effect.kind).value(key,fallback)
    ) { v in store.updateEffect(effect.id, "调整" + title) { $0.set(key, v) } }
  }
  func property(
    _ title: String, _ key: WritableKeyPath<ImageEffect, Double>, _ range: ClosedRange<Double>
  ) -> some View {
    ParameterSlider(
      store: store, title: title, value: effect[keyPath: key], range: range, digits: 2, defaultValue: ImageEffect(effect.kind)[keyPath: key]
    ) { v in store.updateEffect(effect.id, "调整" + title) { $0[keyPath: key] = v } }
  }
  func color(_ title: String, _ key: WritableKeyPath<ImageEffect, RGBA?>, _ fallback: RGBA)
    -> some View
  {
    ModernColorButton(title:title,color:Binding(
      get:{effect[keyPath:key] ?? fallback},
      set:{v in store.updateEffect(effect.id,"调整"+title) { $0[keyPath:key] = v }}),
      editingChanged:{active in if active {store.beginTransaction("调整"+title)} else {store.endTransaction()}})
  }
  @ViewBuilder var body: some View {
    switch effect.kind {
    case .color:
      property("曝光", \.exposure, -5...5)
      param("高光", "highlights", -1...1)
      param("tone.shadows", "shadows", -1...1)
      property("亮度", \.brightness, -0.5...0.5)
      property("对比度", \.contrast, 0...2)
      property("饱和度", \.saturation, 0...2)
      param("黑点", "blackPoint", -1...1)
      param("纹理", "texture", -1...1)
      param("清晰度", "clarity", -1...1)
    case .hue:
      param("色相", "hue", -180...180)
      param("饱和度", "saturation", -1...1)
      param("tone.value", "lightness", -1...1)
    case .selective:
      ColorBandPicker(selection: $colorBand)
      param("色相", "hue\(colorBand)", -180...180)
      param("饱和度", "sat\(colorBand)", -1...1)
      param("tone.value", "light\(colorBand)", -1...1)
    case .wheels:
      ForEach(0..<3) { i in
        VStack(spacing: 12) {
          SectionCaption(title: ["高光", "中间调", "tone.shadows"][i])
          EffectColorWheel(store: store, effect: effect, index: i).frame(width: 170, height: 170)
            .frame(maxWidth: .infinity)
          param("亮度", "wheelLift\(i)", -0.4...0.4)
        }
      }.id(AppLocalization.language)
    case .levels:
      VStack(alignment: .leading, spacing: 6) {
        Text(L("通道")).font(.system(size: 12)).foregroundStyle(.secondary)
        Picker(L("通道"),selection:$channel) {Text(L("RGB")).tag(0);Text(L("红")).tag(1);Text(L("绿")).tag(2);Text(L("蓝")).tag(3)}.id(AppLocalization.language).labelsHidden().pickerStyle(.segmented)
      }
      HistogramView(image:store.effectInput(effect.id),channel:["RGB","Red","Green","Blue"][channel]).frame(height:85)
      let prefix = ["","red_","green_","blue_"][channel]
      SectionCaption(title:"输入色阶")
      param("黑点",prefix+"black",0...0.95)
      param("中间调",prefix+"gamma",0.1...3,1)
      param("白点",prefix+"white",0.05...1,1)
      SectionCaption(title:"输出色阶")
      param("黑点",prefix+"outBlack",0...1)
      param("白点",prefix+"outWhite",0...1,1)
    case .curves:
      CurveEditor(store: store, effect: effect)
      Text(L("点击曲线添加控制点，拖出图谱可删除。RGB 与各颜色通道叠加生效。")).font(.system(size: 11)).foregroundStyle(.secondary)
    case .replace, .removeColor:
      color("选取颜色", \.sourceColor, RGBA(r: 1, g: 0, b: 0))
      if effect.kind == .replace { color("替换颜色", \.targetColor, RGBA(r: 0, g: 0.4, b: 1)) }
      param("颜色范围", "range", 0.005...1, 0.2)
    case .channels:
      VStack(alignment: .leading, spacing: 6) {
        Text(L("输出通道")).font(.system(size: 12)).foregroundStyle(.secondary)
        Picker(L("输出通道"), selection: $channel) {
          Text(L("红")).tag(0)
          Text(L("绿")).tag(1)
          Text(L("蓝")).tag(2)
        }.id(AppLocalization.language).labelsHidden().pickerStyle(.segmented)
      }
      ForEach(0..<3) { i in
        param(["红", "绿", "蓝"][i] + "输入", "channel\(channel)_\(i)", -2...2, channel == i ? 1 : 0)
      }.id(AppLocalization.language)
      param("常量", "bias\(channel)", -1...1)
    case .lut:
      Button(L("导入 .cube LUT…")) { store.importLUT(effect) }
      if let dimension = effect.lutDimension {
        Text(L("{0} 阶 LUT", dimension)).font(.system(size: 12)).foregroundStyle(.secondary)
      } else {
        Text(L("添加后导入 LUT 文件以启用颜色映射。")).font(.system(size: 12)).foregroundStyle(.secondary)
      }
    case .colorize: color("单色", \.tint, RGBA(r: 0.7, g: 0.4, b: 0.2))
    case .blur, .gaussianBlur, .motionBlur, .focusBlur, .distort, .bumpDistort, .pinchDistort, .stretchDistort, .twirlDistort, .waveDistort:
      let style = effect.kind.independentStyle ?? effect.style ?? (effect.kind.isBlur ? "gaussian" : "bump")
      if effect.kind.isBlur {
        property("半径", \.radius, 0...150)
        if style == "motion" {param("角度", "angle", -180...180)}
        if style == "focus" || style == "tilt" {
          param("清晰范围", "regionSize", 0.01...0.8, 0.15)
          param("过渡范围", "transition", 0.01...0.8, 0.3)
          param("中心 X", "centerX", 0...1, 0.5);param("中心 Y", "centerY", 0...1, 0.5)
        }
      } else if style == "wave" {
        param("振幅", "amplitude", 0...100, 12)
        param("波长", "wavelength", 8...500, 80)
        param("方向", "angle", -180...180)
        param("相位", "phase", -180...180)
      } else {
        if style != "twirl" {param("形变", "deformation", -1...1, 0.3)}
        param("范围", "regionSize", 0.01...1, 0.35)
        if ["stretch","twirl","vortex","tunnel"].contains(style) {param("角度", "angle", -180...180, style == "twirl" ? 45 : 0)}
        param("中心 X", "centerX", 0...1, 0.5);param("中心 Y", "centerY", 0...1, 0.5)
      }
    case .body:
      Button(L("识别人物")) { store.detectPortrait(for:effect.id,body:true) }.disabled(store.busy)
      param("瘦身 / 扩张", "deformation", -1...1, 0.3)
      param("腰部", "waist", -1...1)
      param("肩部", "shoulders", -1...1)
      param("腿部延伸", "legs", -1...1)
      Text(L("按识别的肩、髋与腿部关节定位；未识别区域不施加形变。")).font(.system(size: 11)).foregroundStyle(.secondary)
    case .beauty:
      Button(L("识别人脸")) { store.detectPortrait(for:effect.id) }.disabled(store.busy)
      Text(L("已识别 {0} 张人脸", effect.faces?.count ?? 0)).font(.system(size:11)).foregroundStyle(.secondary)
      param("肤质平滑", "smoothing", 0...0.2, 0.04)
      param("保留细节", "detail", 0...1, 0.4)
      param("提亮", "brightness", -0.2...0.2, 0.02)
      param("暖度", "warmth", -0.2...0.2, 0.05)
      param("黑眼圈淡化", "darkCircles", 0...1)
      param("亮眼", "eyes", 0...1)
      param("牙齿净白", "teeth", 0...1)
      SectionCaption(title:"妆容")
      param("唇色", "lipstick", 0...1)
      color("口红颜色", \.targetColor, RGBA(r:0.75,g:0.08,b:0.2))
      param("腮红", "blush", 0...1)
      SectionCaption(title:"灯光")
      param("补光", "lighting", -2...2)
      param("灯光 X", "lightX", 0...1, 0.35)
      param("灯光 Y", "lightY", 0...1, 0.2)
      param("灯光半径", "lightRadius", 0.05...2, 0.6)
      param("作用范围", "regionSize", 0.02...1, 0.25)
    case .outline, .shadow, .innerShadow, .outerGlow, .innerGlow, .bevel:
      property(effect.kind == .outline ? "宽度" : "半径", \.radius, 0...100)
      color(
        "颜色", \.tint,
        effect.kind == .shadow || effect.kind == .innerShadow
          ? RGBA(r: 0, g: 0, b: 0) : RGBA(r: 1, g: 1, b: 1))
      if effect.kind == .outline {
        Picker(
          L("位置"),
          selection: Binding(
            get: { effect.style ?? "outside" },
            set: { v in store.updateEffect(effect.id, "描边位置") { $0.style = v } })
        ) {
          Text(L("外部")).tag("outside")
          Text(L("内部")).tag("inside")
          Text(L("居中")).tag("center")
        }.id(AppLocalization.language)
      }
      if effect.kind == .shadow || effect.kind == .innerShadow {
        param("距离", "distance", 0...200, 8)
        param("角度", "angle", -180...180, 45)
      }
      if [.shadow,.innerShadow,.outerGlow,.innerGlow].contains(effect.kind) {
        ParameterSlider(store:store,title:"style.spread",value:min(1,effect.value("spread") > 1 ? effect.value("spread")/50 : effect.value("spread")),range:0...1,unit:"%",percentage:true,defaultValue:0) {v in store.updateEffect(effect.id,"调整style.spread") {$0.set("spread",v)}}
      }
      if effect.kind == .bevel {
        param("光照角度", "angle", -180...180, 45)
        param("光照高度", "altitude", 0...90, 35)
        param("深度", "depth", 0...20, 4)
      }
    case .fillStyle:
      Picker(L("填充"), selection:Binding(get:{effect.style == "solid" || effect.style == nil ? "solid" : "gradient"},set:{v in
        store.updateEffect(effect.id,"填充样式") {e in
          e.style = v
          if v == "gradient",e.gradient == nil {e.gradient = e.fillGradient}
        }
      })) {Text(L("纯色")).tag("solid");Text(L("渐变")).tag("gradient")}.id(AppLocalization.language).pickerStyle(.segmented)
      if effect.style == "gradient" || effect.style == "radial" {
        let definition = effect.gradient ?? effect.fillGradient
        let layer = {var l = ImageLayer(name:L("填充"),kind:.gradient,width:1,height:1);l.gradient = definition;return l}()
        GradientStopEditor(store:store,layer:layer,effectID:effect.id)
      } else {color("颜色", \.tint, RGBA(r:1,g:1,b:1))}
    case .sharpen:
      property("半径", \.radius,0.1...30)
      param("锐化量","sharpness",0...5,1)
      param("阈值","threshold",0...0.2,0.02)
    case .bloom:
      property("扩散半径",\.radius,0...150)
      param("高光阈值","threshold",0...1,0.7)
    case .grain:
      param("颗粒大小","grainSize",1...12,1)
      param("强度","strength",0...1,0.275)
      VStack(alignment: .leading, spacing: 6) {
        Text(L("噪点样式")).font(.system(size: 12)).foregroundStyle(.secondary)
        Picker(L("噪点样式"), selection: Binding(get:{Int(effect.value("style",0))}, set:{v in store.updateEffect(effect.id,"噪点样式"){$0.set("style",Double(v))}})) {
          Text(L("细腻")).tag(0); Text(L("有机")).tag(1); Text(L("粗粒")).tag(2); Text(L("高感")).tag(3)
        }.id(AppLocalization.language).labelsHidden().pickerStyle(.segmented)
      }
      Toggle(L("彩色颗粒"),isOn:Binding(get:{effect.value("colored")>0.5},set:{v in store.updateEffect(effect.id,"颗粒色彩"){$0.set("colored",v ? 1 : 0)}}))
    case .pixelate:
      property("像素块大小",\.radius,1...150)
      param("中心 X","centerX",0...1,0.5);param("中心 Y","centerY",0...1,0.5)
    case .vignette:
      param("vignette.shading","intensity",-2...2,1)
      param("范围","vignetteSize",0.05...1.5,0.6)
      param("柔度","falloff",0...1,0.5)
      param("中心 X","centerX",0...1,0.5);param("中心 Y","centerY",0...1,0.5)
    case .monochrome:
      SectionCaption(title:"颜色明度")
      ForEach(0..<6) {i in param(["红","黄","绿","青","蓝","洋红"][i],"mono\(i)",-1...1)}.id(AppLocalization.language)
    case .hdr:
      param("阴影恢复","shadows",0...1,0.4)
      param("高光恢复","highlights",0...1,0.4)
      param("局部细节","detail",0...1,0.2)
      property("细节半径",\.radius,1...100)
    case .fade:
      param("阴影褪色","fadeShadows",0...1,0.5)
      param("高光褪色","fadeHighlights",0...1,0.2)
    case .custom:
      Text(L(effect.filterName ?? "扩展效果")).font(.system(size:13)).foregroundStyle(.secondary)
    }
    if effect.kind.isLayerStyle {
      Toggle(L("屏蔽剪切蒙版内容"), isOn: Binding(get: {effect.value("ignoreClipping",1) > 0.5},
        set: {v in store.updateEffect(effect.id,"图层样式作用范围") {$0.set("ignoreClipping", v ? 1 : 0)}}))
    }
    if ![.beauty,.body].contains(effect.kind) {
      Divider()
      ParameterSlider(store:store,title:"不透明度",value:effect.amount,range:0...1,unit:"%",percentage:true,defaultValue:1) {v in store.updateEffect(effect.id,"调整不透明度") {$0.amount = v}}
    }
  }
}
struct EffectColorWheel: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var effect: ImageEffect
  var index: Int
  var body: some View {
    GeometryReader { g in
      let r = g.size.width / 2
      ZStack {
        Circle().fill(
          AngularGradient(
            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
        Circle().fill(
          RadialGradient(
            colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: r))
        Circle().stroke(.white, lineWidth: 2).background(Circle().fill(.black.opacity(0.3))).frame(
          width: 12, height: 12
        ).position(
          x: r + effect.value("wheelX\(index)") * (r - 7),
          y: r + effect.value("wheelY\(index)") * (r - 7))
      }
      .contentShape(Circle()).gesture(
        DragGesture(minimumDistance: 0).onChanged { e in
          store.beginTransaction("调整色轮")
          var x = (e.location.x - r) / (r - 7)
          var y = (e.location.y - r) / (r - 7)
          let d = hypot(x, y)
          if d > 1 {
            x /= d
            y /= d
          }
          store.updateEffect(effect.id, "调整色轮") {
            $0.set("wheelX\(index)", x)
            $0.set("wheelY\(index)", y)
          }
        }.onEnded { _ in store.endTransaction() }
      )
      .onTapGesture(count: 2) {
        store.updateEffect(effect.id, "重置色轮") {
          $0.set("wheelX\(index)", 0)
          $0.set("wheelY\(index)", 0)
        }
      }.accessibilityLabel(L("{0}色轮", L(["高光","中间调","tone.shadows"][index])))
    }
  }
}
struct ColorBandPicker: View {
  @ObservedObject private var localization = LocalizationState.shared
  @Binding var selection: Int
  let hues: [Double] = [0, 0.083333, 0.166667, 0.333333, 0.5, 0.666667, 0.75, 0.833333]
  let names = ["红", "橙", "黄", "绿", "青", "蓝", "紫", "洋红"]
  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<8) { i in
        Button {
          selection = i
        } label: {
          Circle().fill(Color(hue: hues[i], saturation: 0.85, brightness: 0.9)).frame(
            width: 25, height: 25
          ).overlay(Circle().stroke(Color.primary.opacity(selection == i ? 1 : 0), lineWidth: 2))
            .padding(2)
        }.buttonStyle(.plain).help(L(names[i]))
      }.id(AppLocalization.language)
    }
  }
}
