import AppKit
import SwiftUI

struct LayerDragSurface:NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  var id:UUID
  var name:String
  var begin:()->Void
  var select:()->Void
  var cancel:()->Void = {}
  var preview:CGImage? = nil
  var accessibilityPrefix = "选择或拖动图层："
  var exposesAccessibility = true
  func makeNSView(context:Context)->LayerDragNSView {LayerDragNSView()}
  func updateNSView(_ view:LayerDragNSView,context:Context) {
    view.layerID = id;view.name = name;view.begin = begin;view.select = select;view.cancel = cancel;view.preview = preview
    view.setAccessibilityElement(exposesAccessibility);view.setAccessibilityRole(.button)
    view.setAccessibilityLabel(L(accessibilityPrefix)+name)
  }
}
/// Track the entire mouse sequence ourselves. System drag sessions can lose
/// their destination when a SwiftUI lazy row moves during animated reordering.
final class LayerDragNSView:NSView {
  var layerID = UUID()
  var begin:(()->Void)?
  var select:(()->Void)?
  var cancel:(()->Void)?
  var preview:CGImage?
  var name = ""
  private static var activeDrag:LayerDragNSView?
  private weak var dragWindow:NSWindow?
  private var pointerMonitor:Any?
  private var ghost:NSView?
  private var down:NSEvent?
  private var started = false
  private var cancelMonitor:Any?
  private var scrollTimer:Timer?
  private var pointer:NSPoint = .zero
  private weak var dragScroll:NSScrollView?
  override var mouseDownCanMoveWindow:Bool {false}
  override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
  override func hitTest(_ point:NSPoint)->NSView? {
    guard bounds.contains(convert(point,from:superview)) else {return nil}
    if NSApp?.currentEvent?.type == .rightMouseDown {return nil}
    return super.hitTest(point)
  }
  override func accessibilityPerformPress()->Bool {select?();return true}
  deinit {scrollTimer?.invalidate();if let cancelMonitor {NSEvent.removeMonitor(cancelMonitor)}}
  private func reset() {
    scrollTimer?.invalidate();scrollTimer = nil;dragScroll = nil
    ghost?.removeFromSuperview();ghost = nil
    down = nil;started = false;NSCursor.arrow.set()
    if let pointerMonitor {NSEvent.removeMonitor(pointerMonitor);self.pointerMonitor = nil}
    if Self.activeDrag === self {Self.activeDrag = nil}
    dragWindow = nil
    if let cancelMonitor {NSEvent.removeMonitor(cancelMonitor);self.cancelMonitor = nil}
  }
  override func mouseDown(with event:NSEvent) {
    reset();down = event;dragWindow = window;pointer = event.locationInWindow
    Self.activeDrag = self
    pointerMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDragged,.leftMouseUp]) {[weak self] event in
      guard let self,self.down != nil,event.window === self.dragWindow else {return event}
      if event.type == .leftMouseDragged {self.mouseDragged(with:event)} else {self.mouseUp(with:event)}
      return nil
    }
    cancelMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) {[weak self] event in
      guard let self,self.down != nil,event.keyCode == 53 else {return event}
      if self.started {self.cancel?()};self.reset();return nil
    }
  }
  override func mouseDragged(with event:NSEvent) {
    guard let down,hypot(event.locationInWindow.x-down.locationInWindow.x,event.locationInWindow.y-down.locationInWindow.y)>4 else {return}
    if !started {
      started = true;begin?();NSCursor.closedHand.set()
      var ancestor:NSView? = superview
      while let view = ancestor {if let scroll = view as? NSScrollView {dragScroll = scroll;break};ancestor = view.superview}
      if dragScroll == nil,let host = dragWindow?.contentView {
        func find(_ view:NSView) -> NSScrollView? {
          if let scroll = view as? NSScrollView,scroll.hasVerticalScroller,scroll.convert(scroll.bounds,to:nil).contains(event.locationInWindow) {return scroll}
          for child in view.subviews {if let scroll = find(child) {return scroll}}
          return nil
        }
        dragScroll = find(host)
      }
      let timer = Timer(timeInterval:1/60,repeats:true) {[weak self] _ in self?.scrollAtEdge()}
      scrollTimer = timer;RunLoop.main.add(timer,forMode:.common)
      if let host = dragWindow?.contentView {
        let view = DragGhostView(frame:NSRect(x:0,y:0,width:130,height:44))
        view.wantsLayer = true;view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        view.layer?.borderColor = NSColor.separatorColor.cgColor;view.layer?.borderWidth = 0.5
        view.layer?.shadowOpacity = 0.16;view.layer?.shadowRadius = 8
        if let preview {view.layer?.contents = preview;view.layer?.contentsGravity = .resizeAspect}
        else {
          let label = NSTextField(labelWithString:name);label.font = .systemFont(ofSize:12,weight:.medium)
          label.lineBreakMode = .byTruncatingTail;label.frame = NSRect(x:10,y:14,width:110,height:16)
          view.addSubview(label)
        }
        host.addSubview(view);ghost = view
      }
    }
    if let ghost,let host = ghost.superview {
      let p = host.convert(event.locationInWindow,from:nil)
      CATransaction.begin();CATransaction.setDisableActions(true)
      ghost.frame.origin = CGPoint(x:p.x+12,y:p.y-ghost.bounds.height/2);CATransaction.commit()
    }
    pointer = event.locationInWindow
    if let target = LayerDropNSView.target(in:dragWindow,at:event.locationInWindow) {
      let p = target.convert(event.locationInWindow,from:nil)
      target.hover?(CGPoint(x:p.x/max(1,target.bounds.width),y:target.isFlipped ? p.y/max(1,target.bounds.height) : 1-p.y/max(1,target.bounds.height)))
    }
  }
  private func scrollAtEdge() {
    guard started,let scroll = dragScroll,let document = scroll.documentView else {return}
    let clip = scroll.contentView,p = clip.convert(pointer,from:nil),edge:CGFloat = 42
    let view = clip.bounds
    var delta:CGFloat = 0
    if p.y < view.minY+edge {delta = -min(1,(view.minY+edge-p.y)/edge)*12}
    else if p.y > view.maxY-edge {delta = min(1,(p.y-view.maxY+edge)/edge)*12}
    guard delta != 0 else {return}
    let origin = CGPoint(x:view.minX,y:min(max(0,view.minY+delta),max(0,document.bounds.height-view.height)))
    clip.scroll(to:origin);scroll.reflectScrolledClipView(clip)
    let clipped = NSPoint(x:min(max(pointer.x,scroll.convert(scroll.bounds,to:nil).minX+2),scroll.convert(scroll.bounds,to:nil).maxX-2),
      y:min(max(pointer.y,scroll.convert(scroll.bounds,to:nil).minY+2),scroll.convert(scroll.bounds,to:nil).maxY-2))
    if let target = LayerDropNSView.target(in:dragWindow,at:clipped) {
      let q = target.convert(clipped,from:nil)
      target.hover?(CGPoint(x:q.x/max(1,target.bounds.width),y:target.isFlipped ? q.y/max(1,target.bounds.height) : 1-q.y/max(1,target.bounds.height)))
    }
  }
  private func dropPoint(_ point:NSPoint)->NSPoint {
    guard let scroll = dragScroll else {return point}
    let r = scroll.convert(scroll.bounds,to:nil)
    guard point.x >= r.minX-24,point.x <= r.maxX+24 else {return point}
    return NSPoint(x:min(r.maxX-2,max(r.minX+2,point.x)),y:min(r.maxY-2,max(r.minY+2,point.y)))
  }
  override func mouseUp(with event:NSEvent) {
    guard down != nil else {return}
    if started {
      if let target = LayerDropNSView.target(in:dragWindow,at:dropPoint(event.locationInWindow)) {
        if let settling = ghost,let host = settling.superview {
          let targetFrame = host.convert(target.bounds,from:target)
          ghost = nil
          NSAnimationContext.runAnimationGroup({context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            settling.animator().frame = NSRect(x:targetFrame.midX-65,y:targetFrame.midY-22,width:130,height:44)
            settling.animator().alphaValue = 0
          },completionHandler:{settling.removeFromSuperview()})
        }
        target.drop?()
      }
      else {cancel?()}
    } else {select?()}
    reset()
  }
}
struct LayerDropSurface:NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  var priority:Int
  var hover:(CGPoint)->Void = {_ in}
  var drop:()->Void
  func makeNSView(context:Context)->LayerDropNSView {LayerDropNSView()}
  func updateNSView(_ view:LayerDropNSView,context:Context) {view.priority = priority;view.hover = hover;view.drop = drop}
}
final class LayerDropNSView:NSView {
  private final class Weak {weak var value:LayerDropNSView?;init(_ value:LayerDropNSView){self.value = value}}
  private static var registry:[Weak] = []
  var priority = 0
  var hover:((CGPoint)->Void)?
  var drop:(()->Void)?
  override init(frame:NSRect) {super.init(frame:frame);Self.registry.append(Weak(self));setAccessibilityElement(false)}
  required init?(coder:NSCoder) {fatalError("init(coder:) is unavailable")}
  override func hitTest(_ point:NSPoint)->NSView? {nil}
  static func target(in window:NSWindow?,at point:NSPoint)->LayerDropNSView? {
    guard let window else {return nil}
    registry.removeAll {$0.value == nil}
    return registry.compactMap(\.value).filter {$0.window === window && !$0.isHiddenOrHasHiddenAncestor && $0.convert($0.bounds.intersection($0.visibleRect),to:nil).contains(point)}.max {$0.priority<$1.priority}
  }
}

private final class DragGhostView:NSView { override func hitTest(_ point:NSPoint)->NSView? {nil} }

struct ClippingGapSurface:NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  var clipped:Bool
  var action:()->Void
  func makeNSView(context:Context)->ClippingGapView {ClippingGapView()}
  func updateNSView(_ view:ClippingGapView,context:Context) {view.clipped = clipped;view.action = action}
}
final class ClippingGapView:NSView {
  var clipped = false
  var action:(()->Void)?
  private var tracking:NSTrackingArea?
  private var monitor:Any?
  override var mouseDownCanMoveWindow:Bool {false}
  override func viewDidMoveToWindow() {
    if let monitor {NSEvent.removeMonitor(monitor);self.monitor = nil}
    if window != nil {monitor = NSEvent.addLocalMonitorForEvents(matching:.flagsChanged) {[weak self] event in self?.updatePointer(event.modifierFlags);return event}}
  }
  deinit {if let monitor {NSEvent.removeMonitor(monitor)}}
  override func updateTrackingAreas() {
    super.updateTrackingAreas();if let tracking {removeTrackingArea(tracking)}
    tracking = NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.inVisibleRect,.mouseEnteredAndExited,.mouseMoved],owner:self);addTrackingArea(tracking!)
  }
  private func updatePointer(_ flags:NSEvent.ModifierFlags) {
    guard let window,bounds.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil)) else {return}
    if flags.contains(.option) {ToolCursors.clipping(release:clipped).set()} else {NSCursor.arrow.set()}
    needsDisplay = true
  }
  override func mouseEntered(with event:NSEvent) {updatePointer(event.modifierFlags)}
  override func mouseMoved(with event:NSEvent) {updatePointer(event.modifierFlags)}
  override func mouseExited(with event:NSEvent) {NSCursor.arrow.set();needsDisplay = true}
  override func mouseDown(with event:NSEvent) {if event.modifierFlags.contains(.option) {action?();updatePointer(event.modifierFlags)}}
  override func draw(_ rect:NSRect) {
    guard let window,NSEvent.modifierFlags.contains(.option),bounds.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil)) else {return}
    NSColor.labelColor.withAlphaComponent(0.4).setFill()
    NSBezierPath(roundedRect:NSRect(x:6,y:bounds.midY-1,width:bounds.width-12,height:2),xRadius:1,yRadius:1).fill()
  }
}
