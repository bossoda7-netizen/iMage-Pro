import AppKit
import SwiftUI

extension BlendMode {
  static let groups: [(String,[BlendMode])] = [
    ("基本",[.normal,.dissolve]),
    ("变暗",[.darken,.multiply,.colorBurn,.linearBurn,.darkerColor]),
    ("变亮",[.lighten,.screen,.colorDodge,.linearDodge,.lighterColor]),
    ("对比",[.overlay,.softLight,.hardLight,.vividLight,.linearLight,.pinLight,.hardMix]),
    ("比较",[.difference,.exclusion,.subtract,.divide]),
    ("颜色",[.hue,.saturation,.color,.luminosity])]
}
extension EditorStore {
  func deleteSelectedLayers() {
    let ids = descendants(of:selectedIDs)
    guard !document.layers.contains(where: {ids.contains($0.id) && $0.locked}) else {return}
    edit("删除选中图层") {doc in doc.layers.removeAll {ids.contains($0.id)};doc.selectedLayerID = nil}
    multiSelectedLayers = [];layerSelectionAnchor = nil
  }
}
/// Keep the visibility control separate from the row's drag and context-menu surfaces.
struct LayerVisibilityButton:NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  var visible:Bool
  var name:String
  var action:()->Void
  func makeNSView(context:Context)->VisibilityButton {
    let button = VisibilityButton();button.isBordered = false;button.bezelStyle = .regularSquare
    button.target = button;button.action = #selector(VisibilityButton.clicked)
    return button
  }
  func updateNSView(_ button:VisibilityButton,context:Context) {
    button.onClick = action
    button.image = NSImage(systemSymbolName:visible ? "eye" : "eye.slash",accessibilityDescription:nil)
    button.imagePosition = .imageOnly;button.contentTintColor = .labelColor
    button.setAccessibilityLabel(L(visible ? "隐藏{0}" : "显示{0}", name))
    button.toolTip = L(visible ? "隐藏{0}" : "显示{0}", name)
  }
}
final class VisibilityButton:NSButton {
  var onClick:(()->Void)?
  override var mouseDownCanMoveWindow:Bool {false}
  @objc func clicked() {onClick?()}
}
/// Native coordinates stay stable while SwiftUI relocates the floating panel.
struct ScopeDragSurface:NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  var begin:()->Void
  var changed:(CGPoint)->Void
  var end:()->Void
  func makeNSView(context:Context)->ScopeDragView {ScopeDragView()}
  func updateNSView(_ view:ScopeDragView,context:Context) {view.begin = begin;view.changed = changed;view.end = end}
}
final class ScopeDragView:NSView {
  var begin:(()->Void)?;var changed:((CGPoint)->Void)?;var end:(()->Void)?
  private var start:NSPoint?
  override var mouseDownCanMoveWindow:Bool {false}
  override func mouseDown(with event:NSEvent) {start = event.locationInWindow;begin?()}
  override func mouseDragged(with event:NSEvent) {
    guard let start else {return}
    changed?(CGPoint(x:event.locationInWindow.x-start.x,y:start.y-event.locationInWindow.y))
  }
  override func mouseUp(with event:NSEvent) {start = nil;end?()}
}

/// A canvas sampler shared by the toolbar and color palettes. The loupe has no
/// crosshair, and reading canvas pixels avoids screen-recording permissions.
final class CanvasColorSampling {
  static let shared = CanvasColorSampling()
  var receive:((RGBA)->Void)?
  var active:Bool {receive != nil}
  func begin(_ receive:@escaping (RGBA)->Void) {
    self.receive = receive
    if let window = NSApp.keyWindow,let content = window.contentView {
      func canvas(_ view:NSView)->CanvasNSView? {
        if let view = view as? CanvasNSView {return view}
        for child in view.subviews {if let found = canvas(child) {return found}}
        return nil
      }
      if let canvas = canvas(content) {window.makeFirstResponder(canvas);window.invalidateCursorRects(for:canvas);canvas.needsDisplay = true}
    }
  }
  func commit(_ color:RGBA) {let callback = receive;receive = nil;callback?(color)}
  func cancel() {receive = nil}
}
