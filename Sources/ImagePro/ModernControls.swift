import AppKit
import SwiftUI

struct ShapeThumbnail: View {
  @ObservedObject private var localization = LocalizationState.shared
  var name: String
  var sides = 6
  var body: some View {
    GeometryReader { g in
      Path(ShapeGeometry.path(name, rect: CGRect(origin: .zero, size: g.size), sides: sides))
        .fill(.primary, style: FillStyle(eoFill: ["ring", "crescent"].contains(name)))
    }
  }
}

struct AppearanceChoices: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var body: some View {
    HStack(spacing: 16) {
      ForEach([("light", "浅色"), ("dark", "深色"), ("system", "自动")], id: \.0) { mode in
        Button {
          store.appearance = mode.0
          UserDefaults.standard.set(mode.0, forKey: "appearance")
        } label: {
          VStack(spacing: 9) {
            ZStack(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 10)
                .fill(mode.0 == "dark" ? Color(white: 0.15) : Color(white: 0.91))
              if mode.0 == "system" {
                HStack(spacing: 0) { Color(white: 0.91); Color(white: 0.15) }
                  .clipShape(RoundedRectangle(cornerRadius: 10))
              }
              HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4).fill(.blue).frame(width: 25)
                VStack(spacing: 5) {
                  Capsule().fill(.gray.opacity(0.3)).frame(height: 6)
                  Capsule().fill(.gray.opacity(0.2)).frame(height: 6)
                  Spacer()
                }.padding(.top, 7)
              }.padding(7).frame(height: 45)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7)).padding(10)
            }.frame(width: 112, height: 72)
              .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                store.appearance == mode.0 ? store.accent : .clear, lineWidth: 3))
            Text(L(mode.0 == "light" ? "appearance.light" : mode.0 == "dark" ? "appearance.dark" : "自动")).font(.system(size: 12, weight: .medium))
          }
        }.buttonStyle(.plain)
      }.id(AppLocalization.language)
    }.padding(.vertical, 8)
  }
}

struct ThemeColorChoices: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var body: some View {
    LabeledContent(L("主题色")) {
      HStack(spacing: 9) {
        ForEach(["system", "blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"], id: \.self) { name in
          Button {
            store.themeColor = name
            UserDefaults.standard.set(name, forKey: "themeColor")
          } label: {
            Circle().fill(color(name)).frame(width: 22, height: 22)
              .overlay(Circle().strokeBorder(.white.opacity(store.themeColor == name ? 1 : 0), lineWidth: 3))
              .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
          }.buttonStyle(.plain).help(L(name == "system" ? "跟随系统" : "accent." + name))
        }.id(AppLocalization.language)
      }
    }
  }
  func color(_ name: String) -> Color {
    ["blue": .blue, "purple": .purple, "pink": .pink, "red": .red, "orange": .orange,
     "yellow": .yellow, "green": .green, "graphite": .gray][name] ?? Color(nsColor: .controlAccentColor)
  }
}

struct ModernColorButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  var title: String
  @Binding var color: RGBA
  var editingChanged: (Bool) -> Void = { _ in }
  @State private var showing = false
  var body: some View {
    HStack(spacing:8) {
      Button { showing.toggle() } label: {
        HStack {
          Text(L(title)); Spacer()
          RoundedRectangle(cornerRadius:7).fill(color.color).frame(width:38,height:28)
            .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(.primary.opacity(0.15)))
        }.contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityLabel(L(title))
        .popover(isPresented:$showing) { ModernColorPalette(color:$color,editingChanged:editingChanged).padding(20).frame(width:300) }
      Button {
        showing = false
        CanvasColorSampling.shared.begin {sample in editingChanged(true);color = sample;editingChanged(false)}
      } label: {Image(systemName:"eyedropper").frame(width:28,height:28).contentShape(Rectangle())}
        .buttonStyle(.plain).help(L("吸取"+title)).accessibilityLabel(L("吸取"+title))
    }
  }
}
struct ModernColorPalette: View {
  @ObservedObject private var localization = LocalizationState.shared
  @Environment(\.dismiss) private var dismiss
  @Binding var color: RGBA
  var editingChanged: (Bool) -> Void = { _ in }
  @State private var hue = 0.0
  @State private var hex = ""
  @State private var dragging = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(L("颜色")).font(.system(size: 17, weight: .semibold))
        Spacer()
        Button {
          dismiss()
          CanvasColorSampling.shared.begin {sample in editingChanged(true);color = sample;editingChanged(false)}
        } label: {Image(systemName:"eyedropper").frame(width:28,height:28)}
          .buttonStyle(.plain).help(L("从画布取色")).accessibilityLabel(L("从画布取色"))
        RoundedRectangle(cornerRadius: 7).fill(color.color).frame(width: 36, height: 28)
      }
      GeometryReader { g in
        ZStack {
          Color(hue: hue, saturation: 1, brightness: 1)
          LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
          let c = color.ns.usingColorSpace(.deviceRGB) ?? .black
          Circle().strokeBorder(.white, lineWidth: 2).frame(width: 12, height: 12)
            .shadow(radius: 2).position(x: c.saturationComponent * g.size.width,
              y: (1 - c.brightnessComponent) * g.size.height)
        }.clipShape(RoundedRectangle(cornerRadius: 12))
          .gesture(DragGesture(minimumDistance: 0).onChanged { e in
            if !dragging { dragging = true;editingChanged(true) }
            let s = min(1, max(0, e.location.x / g.size.width))
            let b = 1 - min(1, max(0, e.location.y / g.size.height))
            color = RGBA(NSColor(hue: hue, saturation: s, brightness: b, alpha: color.a))
            hex = hexValue
          }.onEnded { _ in dragging = false;editingChanged(false) })
      }.frame(height: 155)
      HueSpectrumTrack(value:$hue,editingChanged:editingChanged).onChange(of:hue) { _,h in
        let c = color.ns.usingColorSpace(.deviceRGB) ?? .black
        guard abs(h-c.hueComponent)>0.000001 else { return }
        color = RGBA(NSColor(hue:h,saturation:c.saturationComponent,brightness:c.brightnessComponent,alpha:color.a))
        hex = hexValue
      }
      HStack {
        Text(L("HEX")).foregroundStyle(.secondary)
        TextField(L("#RRGGBB"), text: $hex).textFieldStyle(.roundedBorder).onSubmit {
          let cleaned = hex.replacingOccurrences(of: "#", with: "")
          if cleaned.count == 6, let v = UInt32(cleaned, radix: 16) {
            color = RGBA(r: Double(v >> 16)/255, g: Double((v >> 8)&255)/255,
              b: Double(v&255)/255, a: color.a)
            hue = (color.ns.usingColorSpace(.deviceRGB) ?? .black).hueComponent
          }
        }
      }.font(.system(size: 12))
      VStack(alignment: .leading, spacing: 8) {
        HStack {Text(L("color.opacity")); Spacer(); Text(L("{0}%", Int(color.a * 100))).monospacedDigit().foregroundStyle(.secondary)}
        Slider(value: $color.a, in: 0...1, onEditingChanged: editingChanged)
          .controlSize(.small).accessibilityLabel(L("颜色透明度"))
      }.font(.system(size: 12))
      HStack(spacing: 9) {
        ForEach([Color.black, .white, .red, .orange, .yellow, .green, .blue, .purple].indices, id: \.self) { i in
          let colors: [Color] = [.black, .white, .red, .orange, .yellow, .green, .blue, .purple]
          Button { color = RGBA(NSColor(colors[i])); sync() } label: {
            Circle().fill(colors[i]).frame(width: 23, height: 23).overlay(Circle().strokeBorder(.gray.opacity(0.3)))
          }.buttonStyle(.plain)
        }.id(AppLocalization.language)
      }
    }.onAppear { sync() }.onDisappear { if dragging { dragging = false;editingChanged(false) } }
  }
  var hexValue: String { String(format: "#%02X%02X%02X", Int(color.r*255), Int(color.g*255), Int(color.b*255)) }
  func sync() { hue = (color.ns.usingColorSpace(.deviceRGB) ?? .black).hueComponent; hex = hexValue }
}

struct HueSpectrumTrack: View {
  @ObservedObject private var localization = LocalizationState.shared
  @Binding var value: Double
  var editingChanged: (Bool) -> Void
  @State private var dragging = false
  @FocusState private var focused: Bool
  var body: some View {
    GeometryReader { g in
      VStack(spacing:3) {
        LinearGradient(colors:(0...12).map { Color(hue:Double($0)/12,saturation:1,brightness:1) },startPoint:.leading,endPoint:.trailing)
          .frame(height:12).clipShape(Capsule())
        Path { p in p.move(to:CGPoint(x:0,y:8));p.addLine(to:CGPoint(x:5,y:0));p.addLine(to:CGPoint(x:10,y:8));p.closeSubpath() }
          .fill(.primary).frame(width:10,height:8).frame(maxWidth:.infinity,alignment:.leading)
          .offset(x:min(g.size.width-10,max(0,value*g.size.width-5)))
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { event in
        if !dragging {dragging = true;editingChanged(true)}
        value = min(1,max(0,event.location.x/g.size.width))
      }.onEnded {_ in dragging = false;editingChanged(false)})
    }.frame(height:28).focusable().focusEffectDisabled().focused($focused)
      .accessibilityLabel(L("色相")).accessibilityValue(L("{0} 度", Int(value*360)))
      .accessibilityAdjustableAction { direction in
        value = min(1,max(0,value+(direction == .increment ? 1 : -1)/360))
      }
      .onKeyPress(.leftArrow) {value = max(0,value-1/360);return .handled}
      .onKeyPress(.rightArrow) {value = min(1,value+1/360);return .handled}
  }
}
