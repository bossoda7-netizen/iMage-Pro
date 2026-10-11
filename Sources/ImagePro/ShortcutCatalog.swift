import Foundation
import AppKit

struct EditorToolShortcut {
  let key: String
  let title: String
  let category: ToolCategory
  let branches: [String]
}
enum ShortcutCatalog {
  static let tools: [EditorToolShortcut] = [
    .init(key:"v",title:"移动",category:.move,branches:[]),
    .init(key:"m",title:"矩形 / 椭圆选区",category:.selection,branches:["rectangle","ellipse"]),
    .init(key:"l",title:"自由 / 多边形套索",category:.selection,branches:["lasso","polygonLasso"]),
    .init(key:"w",title:"快速选择 / 颜色范围",category:.selection,branches:["smart","colorRange"]),
    .init(key:"b",title:"画笔",category:.brush,branches:ToolCategory.brush.branches.filter {$0.id != "eraser"}.map(\.id)),
    .init(key:"e",title:"橡皮",category:.eraser,branches:[]),
    .init(key:"g",title:"渐变 / 填充",category:.fill,branches:["linear","radial","mesh","bucket","solid"]),
    .init(key:"j",title:"智能修复",category:.retouch,branches:["heal","smooth"]),
    .init(key:"s",title:"仿制图章",category:.retouch,branches:["stamp"]),
    .init(key:"o",title:"减淡 / 加深 / 海绵",category:.retouch,branches:["dodge","burn","sponge"]),
    .init(key:"r",title:"涂抹 / 模糊 / 锐化",category:.retouch,branches:["smudge","blurBrush","sharpenBrush"]),
    .init(key:"p",title:"钢笔 / 自由路径",category:.path,branches:[]),
    .init(key:"t",title:"文字",category:.text,branches:[]),
    .init(key:"u",title:"形状",category:.shape,branches:[]),
    .init(key:"c",title:"裁剪",category:.crop,branches:[]),
    .init(key:"i",title:"吸管",category:.eyedropper,branches:[]),
    .init(key:"h",title:"抓手",category:.hand,branches:[]),
    .init(key:"z",title:"缩放",category:.zoom,branches:[])
  ]
  static let actions: [(String,String)] = [ ("新建 / 打开 / 保存","⌘N / ⌘O / ⌘S"), ("另存为 / 导出","⇧⌘S / ⇧⌘E"),
      ("撤销 / 重做（含绘制中的钢笔节点）","⌘Z / ⇧⌘Z"),
      ("自由变换 / 应用 / 取消","⌘T / 回车 / Esc"),
      ("全选 / 取消选区 / 反选","⌘A / ⌘D / ⇧⌘I"),
      ("复制 / 粘贴图层、选区、效果器或标尺","⌘C / ⌘V"),
      ("数字调节 / 恢复滑轨默认值","左右拖动数字 / 双击滑块"),
      ("直线或 45° 笔触 / 画布多选","⇧ 绘制 / ⇧ 点击"),
      ("图层列表：多选 / 连续范围","⌘ 点击 / ⇧ 点击"),
      ("标尺：撤销 / 重做 / 删除 / 完成","⌘Z / ⇧⌘Z / Delete / 回车"),
      ("选区或图层复制 / 剪切到新图层","⌘J / ⇧⌘J"),
      ("编组 / 取消编组","⌘G / ⇧⌘G"), ("建立 / 释放剪切蒙版","⌥⌘G 或 ⌥ 点击图层间隙"),
      ("图层上移 / 下移","⌘] / ⌘["), ("图层置顶 / 置底","⇧⌘] / ⇧⌘["),
      ("放大 / 缩小 / 适合窗口 / 实际像素","⌘+ / ⌘− / ⌘0 / ⌘1"),
      ("临时抓手","空格拖动"), ("切换同组工具","⇧ + 工具快捷键"),
      ("画笔大小 / 硬度","[ / ]；⇧[ / ⇧]"), ("不透明度 / 流量","数字 1–0 / ⇧ + 数字 1–0"),
      ("交换颜色 / 默认黑白","X / D"), ("画笔临时取色 / 仿制图章采样","⌥ 点击"),
      ("微调对象位置","方向键（⇧ 为 10 px）"),
      ("钢笔移动当前锚点 / 独立方向柄","绘制中按空格拖动 / ⌥ 拖动"),
      ("结束路径 / 闭合路径 / 删除上一节点","回车 / ⇧回车 / Delete"),
      ("编辑画布文字 / 完成文字编辑","双击文字 / ⌘回车"),
      ("路径转选区 / 画笔描边路径","⇧⌘Return / 路径右键菜单"),
      ("显示图层 / 调节器","⌥⌘L / ⌥⌘I"),
      ("裁切：对称裁切 / 应用 / 取消","⌥ 拖动 / 回车 / Esc"),
      ("液化推移","⇧⌘X"),
      ("文字：字距 / 行距","⌥←→ / ⌥↑↓（⇧ 为大步进）") ]
  static var guide: [(String,String)] { actions + tools.map { ($0.title,$0.key.uppercased()) } }
}
extension EditorStore {
  @discardableResult func selectToolShortcut(_ key: String, cycle: Bool = false) -> Bool {
    guard let shortcut = ShortcutCatalog.tools.first(where:{$0.key == key}) else { return false }
    let branches = shortcut.category.branches.filter { shortcut.branches.isEmpty || shortcut.branches.contains($0.id) }
    let ordered = shortcut.branches.isEmpty ? branches : shortcut.branches.compactMap { id in branches.first {$0.id == id} }
    let old = toolDefaults[shortcut.category.rawValue]
    let index = ordered.firstIndex(where:{$0.id == old}) ?? 0
    let branch = ordered.isEmpty ? nil : ordered[cycle ? (index+1)%ordered.count : index]
    chooseTool(shortcut.category,branch:branch)
    return true
  }
  func selectAll() {
    selection = SelectionRegion(type:"rectangle",points:[Point(x:0,y:0),Point(x:document.width,y:document.height)])
  }
}

extension EditorStore {
  func actualPixels() {
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    zoom = max(0.05,min(20,1/(min(canvasViewport.width/document.width,canvasViewport.height/document.height)*scale)))
  }
  func reorderSelected(up:Bool,edge:Bool = false) {
    guard let layer = selected,let i = document.layers.firstIndex(where:{$0.id == layer.id}) else {return}
    let siblings = document.layers.indices.filter {document.layers[$0].parentID == layer.parentID}
    guard let offset = siblings.firstIndex(of:i) else {return}
    let destination = edge ? (up ? siblings.first : siblings.last) : siblings.indices.contains(offset+(up ? -1 : 1)) ? siblings[offset+(up ? -1 : 1)] : nil
    guard let destination,destination != i else {return}
    moveLayer(layer.id,before:document.layers[destination].id,after:!up)
  }
}
