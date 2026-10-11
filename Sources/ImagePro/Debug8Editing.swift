import AppKit
import SwiftUI

extension EditorStore {
  func moveInspectorEffect(_ source:UUID,relativeTo target:UUID,after:Bool) {
    guard source != target,let effects = selected?.effects,
      let from = effects.firstIndex(where:{$0.id == source}),effects.contains(where:{$0.id == target}) else {return}
    var reordered = effects;let effect = reordered.remove(at:from)
    guard let to = reordered.firstIndex(where:{$0.id == target}) else {return}
    reordered.insert(effect,at:to+(after ? 1 : 0))
    guard reordered != effects else {return}
    updateSelected("调整效果顺序") {$0.effects = reordered}
  }
  var selectedContentBounds:CGRect? {
    let ids = descendants(of:selectedIDs)
    let bounds = document.layers.filter {ids.contains($0.id) && $0.kind != .group && $0.kind != .adjustment}
      .reduce(CGRect.null) {$0.union(SnapEngine.bounds($1))}
    return bounds.isNull ? nil : bounds
  }
  func resizeSelectedFromCenter(width:Double? = nil,height:Double? = nil) {
    updateSelected("调整尺寸") {layer in
      let center = CGPoint(x:layer.x+layer.width/2,y:layer.y+layer.height/2)
      let ratio = layer.width/max(1,layer.height)
      if let width {
        layer.width = max(1,min(16384,width))
        if layer.aspectLocked == true {layer.height = layer.width/ratio}
      }
      if let height {
        layer.height = max(1,min(16384,height))
        if layer.aspectLocked == true {layer.width = layer.height*ratio}
      }
      let limit = min(1,16384/max(layer.width,layer.height))
      layer.width *= limit;layer.height *= limit
      layer.x = center.x-layer.width/2;layer.y = center.y-layer.height/2
    }
  }
}

/// Imported images have arbitrary intrinsic sizes. A native, non-interactive
/// thumbnail prevents that size from expanding SwiftUI's pointer hit region.
struct LayerThumbnail:NSViewRepresentable {
  let image:CGImage
  func makeNSView(context:Context)->ThumbnailView {ThumbnailView()}
  func updateNSView(_ view:ThumbnailView,context:Context) {
    view.wantsLayer = true;view.layer?.contents = image
    view.layer?.contentsGravity = .resizeAspectFill
    view.layer?.masksToBounds = true;view.layer?.cornerRadius = 7
  }
}
final class ThumbnailView:NSView {
  override var intrinsicContentSize:NSSize {NSSize(width:34,height:37)}
  override func hitTest(_ point:NSPoint)->NSView? {nil}
}

struct ScrubMotion {
  var translation:CGFloat = 0
  mutating func append(delta:CGFloat) {translation += delta}
}

struct CanvasPixelSample {
  let x:Int
  let y:Int
  let color:RGBA
  var hex:String {String(format:"#%02X%02X%02X",Int((color.r*255).rounded()),Int((color.g*255).rounded()),Int((color.b*255).rounded()))}
  static func read(_ image:CGImage,point:CGPoint,canvas:CGSize)->CanvasPixelSample? {
    guard point.x >= 0,point.y >= 0,point.x < canvas.width,point.y < canvas.height else {return nil}
    let x = Int(floor(point.x/canvas.width*Double(image.width)))
    let y = Int(floor(point.y/canvas.height*Double(image.height)))
    guard let color = NSBitmapImageRep(cgImage:image).colorAt(x:x,y:y) else {return nil}
    return CanvasPixelSample(x:x,y:y,color:RGBA(color))
  }
}
