import AppKit
import CoreText

extension EditorStore {
  func textToShape() {
    guard let layer = selected, layer.kind == .text, !layer.locked else { return }
    let style = layer.textStyle ?? TextStyle()
    var font =
      NSFont(name: layer.fontName, size: layer.fontSize)
      ?? NSFont.systemFont(ofSize: layer.fontSize)
    if style.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
    if style.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = [.left, .center, .right, .justified][max(0, min(3, style.alignment))]
    paragraph.lineHeightMultiple = style.lineHeight
    paragraph.paragraphSpacingBefore = style.paragraphBefore
    paragraph.paragraphSpacing = style.paragraphAfter
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font, .kern: style.tracking, .paragraphStyle: paragraph,
    ]
    var nodes = [VectorNode]()
    func append(_ path: CGPath, offset: CGPoint) {
      path.applyWithBlock { pointer in
        let e = pointer.pointee
        let count: Int
        switch e.type {
        case .moveToPoint, .addLineToPoint: count = 1
        case .addQuadCurveToPoint: count = 2
        case .addCurveToPoint: count = 3
        case .closeSubpath: count = 0
        @unknown default: count = 0
        }
        let values = (0..<count).map { i in
          Point(
            x: (e.points[i].x + offset.x) / layer.width,
            y: 1 - (e.points[i].y + offset.y) / layer.height)
        }
        nodes.append(VectorNode(kind: Int(e.type.rawValue), points: values))
      }
    }
    func appendLine(_ line: CTLine, origin: CGPoint) {
      for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n)
        var positions = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        let attributes = CTRunGetAttributes(run) as NSDictionary
        let runFont = attributes[kCTFontAttributeName] as! CTFont
        for i in 0..<n {
          if let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
            append(
              path, offset: CGPoint(x: origin.x + positions[i].x, y: origin.y + positions[i].y))
          }
        }
      }
    }
    if style.vertical {
      var row = 0
      var column = 0
      let step = layer.fontSize * style.lineHeight
      for c in layer.text {
        if c == "\n" || Double(row + 1) * step > layer.height {
          column += 1
          row = 0
          if c == "\n" { continue }
        }
        let line = CTLineCreateWithAttributedString(
          NSAttributedString(string: String(c), attributes: attrs))
        appendLine(
          line,
          origin: CGPoint(
            x: layer.width - Double(column + 1) * (layer.fontSize + style.tracking),
            y: layer.height - Double(row) * step - font.ascender))
        row += 1
      }
    } else {
      let string = TextLayout.attributed(layer)
      let framesetter = CTFramesetterCreateWithAttributedString(string)
      let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: 0, length: 0),
        CGPath(rect: CGRect(x: 0, y: 0, width: layer.width, height: layer.height), transform: nil),
        nil)
      let lines = CTFrameGetLines(frame) as! [CTLine]
      var origins = [CGPoint](repeating: .zero, count: lines.count)
      CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
      let height = string.boundingRect(
        with: CGSize(width: layer.width, height: 100000),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
      ).height
      let shift =
        style.verticalAlignment == 1
        ? max(0, (layer.height - height) / 2)
        : style.verticalAlignment == 2 ? max(0, layer.height - height) : 0
      for i in lines.indices {
        appendLine(lines[i], origin: CGPoint(x: origins[i].x, y: origins[i].y - shift))
      }
    }
    guard !nodes.isEmpty else {
      notify("该字体不提供可转换的矢量轮廓")
      return
    }
    updateSelected("文字转换为形状") {
      $0.kind = .shape
      $0.shape = "textOutline"
      $0.vectorOutline = nodes
      $0.vectorPoints = nil
      $0.name += L(" · 轮廓")
    }
  }
}
