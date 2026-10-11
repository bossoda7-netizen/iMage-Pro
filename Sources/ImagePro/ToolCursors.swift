import AppKit

enum ToolCursors {
  static func cropResize(diagonal:Bool) -> NSCursor {diagonal ? cropDiagonalDown : cropDiagonalUp}
  private static let cropDiagonalDown = resizeCursor(down:true)
  private static let cropDiagonalUp = resizeCursor(down:false)
  private static func resizeCursor(down:Bool) -> NSCursor {
    let image = NSImage(size:NSSize(width:24,height:24),flipped:true) {_ in
      let p = NSBezierPath()
      func pt(_ x:CGFloat,_ y:CGFloat) -> CGPoint {CGPoint(x:x,y:down ? y : 24-y)}
      p.move(to:pt(4,4));p.line(to:pt(20,20))
      p.move(to:pt(4,11));p.line(to:pt(4,4));p.line(to:pt(11,4))
      p.move(to:pt(13,20));p.line(to:pt(20,20));p.line(to:pt(20,13))
      NSColor.white.setStroke();p.lineWidth = 4;p.stroke()
      NSColor.black.setStroke();p.lineWidth = 1.5;p.stroke();return true
    }
    return NSCursor(image:image,hotSpot:CGPoint(x:12,y:12))
  }
  static func clipping(release:Bool) -> NSCursor {release ? releaseClip : createClip}
  private static let createClip = clipCursor(release:false)
  private static let releaseClip = clipCursor(release:true)
  private static func clipCursor(release:Bool) -> NSCursor {
    let image = NSImage(size:NSSize(width:28,height:28),flipped:true) {_ in
      let p = NSBezierPath();p.move(to:CGPoint(x:2,y:2));p.line(to:CGPoint(x:2,y:17));p.line(to:CGPoint(x:6,y:13));p.line(to:CGPoint(x:10,y:20));p.line(to:CGPoint(x:13,y:18));p.line(to:CGPoint(x:9,y:12));p.line(to:CGPoint(x:15,y:12));p.close()
      NSColor.white.setStroke();p.lineWidth = 3;p.stroke();NSColor.black.setFill();p.fill()
      let box = NSBezierPath(roundedRect:NSRect(x:17,y:14,width:9,height:9),xRadius:1,yRadius:1)
      NSColor.white.setStroke();box.lineWidth = 3;box.stroke();NSColor.black.setStroke();box.lineWidth = 1;box.stroke()
      let mark = NSBezierPath();mark.move(to:CGPoint(x:19,y:18.5));mark.line(to:CGPoint(x:24,y:18.5))
      if !release {mark.move(to:CGPoint(x:21.5,y:16));mark.line(to:CGPoint(x:21.5,y:21))};mark.stroke()
      return true
    }
    return NSCursor(image:image,hotSpot:CGPoint(x:2,y:2))
  }
  private static var cachedDrop: (RGBA, NSCursor)?
  static func drop(_ color: RGBA) -> NSCursor {
    if let cachedDrop, cachedDrop.0 == color { return cachedDrop.1 }
    let image = NSImage(size: NSSize(width: 24, height: 28), flipped: true) { _ in
      let path = NSBezierPath()
      path.move(to: NSPoint(x:12,y:2))
      path.curve(to:NSPoint(x:4,y:18),controlPoint1:NSPoint(x:10,y:7),controlPoint2:NSPoint(x:4,y:12))
      path.curve(to:NSPoint(x:20,y:18),controlPoint1:NSPoint(x:4,y:28),controlPoint2:NSPoint(x:20,y:28))
      path.curve(to:NSPoint(x:12,y:2),controlPoint1:NSPoint(x:20,y:12),controlPoint2:NSPoint(x:14,y:7))
      path.close()
      NSColor.white.setStroke();path.lineWidth = 3;path.stroke()
      color.ns.withAlphaComponent(1).setFill();path.fill()
      NSColor.black.withAlphaComponent(0.85).setStroke();path.lineWidth = 1;path.stroke()
      return true
    }
    let cursor = NSCursor(image:image,hotSpot:NSPoint(x:12,y:2))
    cachedDrop = (color,cursor)
    return cursor
  }
  static let pen: NSCursor = {
    let image = NSImage(size:NSSize(width:18,height:26),flipped:true) { _ in
      let nib = NSBezierPath()
      nib.move(to:NSPoint(x:2,y:23))
      nib.line(to:NSPoint(x:6,y:10));nib.line(to:NSPoint(x:12,y:4))
      nib.line(to:NSPoint(x:16,y:8));nib.line(to:NSPoint(x:10,y:14));nib.close()
      NSColor.white.setStroke();nib.lineWidth = 3;nib.stroke()
      NSColor.black.setFill();nib.fill()
      let slit = NSBezierPath();slit.move(to:NSPoint(x:2,y:23));slit.line(to:NSPoint(x:9,y:12))
      NSColor.white.setStroke();slit.lineWidth = 0.8;slit.stroke()
      return true
    }
    return NSCursor(image:image,hotSpot:NSPoint(x:2,y:23))
  }()
}
