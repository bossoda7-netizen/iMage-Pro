import AppKit
import CoreText

/// Shared by the canvas text system, image renderer and point-text measurement.
/// Imported runs retain their appearance until the corresponding global control changes.
enum TextLayout {
  static func attributed(_ layer:ImageLayer,scale:Double = 1) -> NSMutableAttributedString {
    let style = layer.textStyle ?? TextStyle()
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.alignment = [.left,.center,.right,.justified][max(0,min(3,style.alignment))]
    paragraph.lineHeightMultiple = style.lineHeight
    paragraph.paragraphSpacingBefore = style.paragraphBefore*scale
    paragraph.paragraphSpacing = style.paragraphAfter*scale
    var font = NSFont(name:layer.fontName,size:layer.fontSize*scale) ?? .systemFont(ofSize:layer.fontSize*scale)
    if style.bold {font = NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask)}
    if style.italic {font = NSFontManager.shared.convert(font,toHaveTrait:.italicFontMask)}
    var attrs:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:layer.color.ns,.paragraphStyle:paragraph,
      .kern:style.tracking*scale,.underlineStyle:style.underline ? 1 : 0,.strikethroughStyle:style.strikethrough ? 1 : 0]
    let traits = NSFontManager.shared.traits(of:font)
    if style.bold && !traits.contains(.boldFontMask) {attrs[.strokeWidth] = -2.0}
    if style.italic && !traits.contains(.italicFontMask) {attrs[.obliqueness] = 0.2}
    if style.vertical {attrs[.verticalGlyphForm] = 1}
    let string = NSMutableAttributedString(string:layer.text,attributes:attrs)
    // A document may mix CJK, emoji and Latin glyphs while storing one font
    // family. Ask Core Text for a fallback face per composed character so a
    // missing glyph never renders as an empty box or gets clipped by the
    // renderer's single-font fallback.
    let baseFont = font as CTFont
    let nsText = layer.text as NSString
    var characterIndex = 0
    while characterIndex < nsText.length {
      let range = nsText.rangeOfComposedCharacterSequence(at: characterIndex)
      let substring = nsText.substring(with: range)
      let fallback = CTFontCreateForString(baseFont, substring as CFString,
        CFRange(location: 0, length: substring.utf16.count))
      string.addAttribute(.font, value: fallback, range: range)
      characterIndex = range.location + range.length
    }
    let baseline = layer.importedTextAppearance
    let oldStyle = baseline?.style ?? TextStyle()
    for run in layer.textRuns ?? [] where run.location>=0 && run.location<string.length {
      let count = min(run.length,string.length-run.location);guard count>0 else {continue}
      let name = layer.fontName == baseline?.font ? run.font : layer.fontName
      let size = run.size*layer.fontSize/max(1,baseline?.size ?? layer.fontSize)*scale
      var face = NSFont(name:name,size:size) ?? .systemFont(ofSize:size)
      let bold = style.bold == oldStyle.bold ? run.bold : style.bold
      let italic = style.italic == oldStyle.italic ? run.italic : style.italic
      if bold {face = NSFontManager.shared.convert(face,toHaveTrait:.boldFontMask)}
      else if style.bold != oldStyle.bold {face = NSFontManager.shared.convert(face,toHaveTrait:.unboldFontMask)}
      if italic {face = NSFontManager.shared.convert(face,toHaveTrait:.italicFontMask)}
      else if style.italic != oldStyle.italic {face = NSFontManager.shared.convert(face,toHaveTrait:.unitalicFontMask)}
      string.addAttributes([.strokeWidth: bold && !NSFontManager.shared.traits(of:face).contains(.boldFontMask) ? -2.0 : 0.0,
        .obliqueness: italic && !NSFontManager.shared.traits(of:face).contains(.italicFontMask) ? 0.2 : 0.0, .font:face,.foregroundColor:layer.color == baseline?.color ? run.color.ns : layer.color.ns,
        .kern:(style.tracking == oldStyle.tracking ? run.tracking : style.tracking)*scale,
        .underlineStyle:(style.underline == oldStyle.underline ? run.underline : style.underline) ? 1 : 0,
        .strikethroughStyle:(style.strikethrough == oldStyle.strikethrough ? run.strikethrough : style.strikethrough) ? 1 : 0],
        range:NSRange(location:run.location,length:count))
    }
    // Text runs may have been imported with a single font that does not contain
    // every CJK, symbol or emoji glyph. Re-resolve each composed character from
    // the font currently assigned to that run so run styling is preserved while
    // Core Text still gets a real fallback face for missing glyphs.
    characterIndex = 0
    while characterIndex < string.length {
      let range = nsText.rangeOfComposedCharacterSequence(at: characterIndex)
      let substring = string.attributedSubstring(from: range).string
      let current = (string.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? font
      let fallback = CTFontCreateForString(current as CTFont, substring as CFString,
        CFRange(location: 0, length: substring.utf16.count))
      string.addAttribute(.font, value: fallback, range: range)
      characterIndex = range.location + range.length
    }
    return string
  }
  static func draw(_ layer: ImageLayer, in bounds: CGRect, context cg: CGContext) {
    let value = attributed(layer)
    if layer.textStyle?.vertical == true {
      cg.saveGState();cg.translateBy(x:0,y:bounds.height);cg.scaleBy(x:1,y:-1);cg.textMatrix = .identity
      let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(value),CFRange(location:0,length:value.length),
        CGPath(rect:bounds,transform:nil),[kCTFrameProgressionAttributeName:CTFrameProgression.rightToLeft.rawValue] as CFDictionary)
      CTFrameDraw(frame,cg);cg.restoreGState()
    } else {
      let graphics = NSGraphicsContext(cgContext: cg, flipped: true)
      NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = graphics
      value.draw(with: bounds.offsetBy(dx:0,dy:verticalOffset(layer,attributed:value)),options:[.usesLineFragmentOrigin,.usesFontLeading])
      NSGraphicsContext.restoreGraphicsState()
    }
  }
  static func typingAttributes(_ layer:ImageLayer,scale:Double) -> [NSAttributedString.Key:Any] {
    var sample = layer;sample.text = " ";sample.textRuns = nil
    return attributed(sample,scale:scale).attributes(at:0,effectiveRange:nil)
  }
  static func verticalOffset(_ layer:ImageLayer,attributed:NSAttributedString? = nil) -> Double {
    let style = layer.textStyle ?? TextStyle()
    guard !style.vertical,style.verticalAlignment>0 else {return 0}
    let measured = (attributed ?? self.attributed(layer)).boundingRect(with:CGSize(width:layer.width,height:100_000),
      options:[.usesLineFragmentOrigin,.usesFontLeading]).height
    return max(0,(layer.height-measured)/(style.verticalAlignment == 1 ? 2 : 1))
  }
  static func resizePointText(_ layer:inout ImageLayer) {
    guard layer.kind == .text,layer.contentPlacement == nil,layer.textStyle?.pointText == true else {return}
    if layer.textStyle?.vertical == true {
      let lines = layer.text.components(separatedBy:"\n")
      let step = layer.fontSize * (layer.textStyle?.lineHeight ?? 1)
      layer.width = max(layer.fontSize*1.3,Double(lines.count)*step+layer.fontSize*0.25)
      layer.height = max(layer.fontSize*1.3,Double(lines.map(\.count).max() ?? 1)*(layer.fontSize+(layer.textStyle?.tracking ?? 0))+layer.fontSize*0.25)
      return
    }
    let measured = attributed(layer).boundingRect(with:CGSize(width:100_000,height:100_000),options:[.usesLineFragmentOrigin,.usesFontLeading])
    let anchor = TransformGeometry.displayPoint(.zero,layer:layer)
    layer.width = min(32768,max(16,ceil(measured.width+layer.fontSize*0.1)))
    layer.height = min(32768,max(16,ceil(max(measured.height,layer.fontSize*(layer.textStyle?.lineHeight ?? 1)))))
    let moved = TransformGeometry.displayPoint(.zero,layer:layer)
    layer.x += anchor.x-moved.x;layer.y += anchor.y-moved.y
  }
}
