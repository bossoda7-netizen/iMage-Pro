import SwiftUI
import AppKit

struct CompositorToolControls: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store:EditorStore
  var body:some View {
    HStack(spacing:12) {
      Text(L(store.branch.title)).font(.system(size:13,weight:.medium))
      switch store.compositorToolID {
      case "miganHeal","smudge","liquify":
        ParameterSlider(store:store,title:"大小",value:store.brushSize,range:1...1000,unit:" px") {store.brushSize = $0}
        ParameterSlider(store:store,title:"硬度",value:store.brushHardness,range:0...1,percentage:true) {store.brushHardness = $0}
        ParameterSlider(store:store,title:MIGANInpainting.isHealing(store.compositorToolID ?? "") ? "不透明度" : "强度",value:store.brushOpacity,range:0...1,percentage:true) {store.brushOpacity = $0}
      case "crop":
        Picker(L("比例"),selection:$store.cropRatio) {
          ForEach(["free","1:1","4:3","3:4","3:2","2:3","16:9","9:16"],id:\.self) {Text(L($0 == "free" ? "自由比例" : $0)).tag($0)}
        }.id(AppLocalization.language).labelsHidden().frame(width:150).onChange(of:store.cropRatio) {_,_ in store.constrainCropRatio()}
        Text(L("⌥ 对称裁切 · 回车应用")).font(.system(size:11)).foregroundStyle(.secondary)
        Spacer()
        Button(L("取消")) {store.deselect()}
        Button(L("应用")) {store.cropToSelection()}.disabled(store.selection?.type != "crop")
      case "horizontalText":
        if let layer = store.selected,layer.kind == .text {
          Menu(layer.fontName) {
            ForEach(["PingFangSC-Regular","PingFangSC-Semibold","HelveticaNeue","HelveticaNeue-Bold","TimesNewRomanPSMT","Menlo-Regular"],id:\.self) {name in
              Button(name) {store.updateSelected("字体") {$0.fontName = name}}
            }
          }.frame(width:170)
          ParameterSlider(store:store,title:"字号",value:layer.fontSize,range:6...512,unit:" px") {v in store.updateSelected("字号") {$0.fontSize = v}}
          ColorWell(store:store,layer:true)
          Button(L("完成")) {store.textEditingLayerID = nil}.disabled(store.textEditingLayerID == nil)
        } else {Text(L("点击输入文字 · 拖出段落文本框")).font(.system(size:12)).foregroundStyle(.secondary)}
        Spacer()
      default: EmptyView()
      }
    }.toggleStyle(.checkbox)
  }
}
struct CompositorToolOptions:View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store:EditorStore
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      if store.interactionTool == .text,let layer = store.selected,layer.kind == .text {
        TextProperties(store:store,layer:layer)
      } else {
        Text(L(hint)).font(.system(size:13)).lineSpacing(5)
        if ["smudge","liquify","miganHeal"].contains(store.compositorToolID ?? "") {
          ParameterSlider(store:store,title:"流量",value:store.brushFlow,range:0.01...1,percentage:true) {store.brushFlow = $0}
        }
      }
    }
  }
  var hint:String {
    switch store.compositorToolID {
    case "miganHeal":return "涂过要修复的区域，松开鼠标后在本机处理。模型已内置，无需下载。小范围逐次涂抹可保留更多细节。"
    case "smudge":return "拖动携带并混合笔头下的颜色。强度控制颜色移动量。"
    case "liquify":return "拖动推移图像。原始像素通过位移场重采样，减少连续推移带来的模糊。"
    case "crop":return "拖动创建裁切框，控制点调整边界。⌥ 从中心裁切，⇧ 约束比例，Control 临时关闭吸附。允许扩展画布，原始图层保留。"
    default:return "点击输入文字，拖出段落文本框；在调节器中设置字体与排版。⌥ 左右方向键调整字距，上下方向键调整行距。"
    }
  }
}
