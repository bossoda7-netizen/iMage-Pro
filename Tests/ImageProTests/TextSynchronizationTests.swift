import XCTest
import AppKit
@testable import ImagePro

final class TextSynchronizationTests:XCTestCase {
  @MainActor func fixture(point:Bool = false) -> (EditorStore,CanvasNSView) {
    let store = EditorStore(loadRecovery:false)
    store.active.document.width = 400;store.active.document.height = 300;store.active.document.layers = []
    store.chooseTool(.text)
    store.addLayer(.text,rect:CGRect(x:20,y:30,width:320,height:240))
    store.updateSelected("Fixture") {l in
      l.text = "Text\nSecond line";l.fontName = "HelveticaNeue";l.fontSize = 24;l.color = RGBA(r:1,g:0,b:0)
      var style = TextStyle();style.tracking = 1;style.pointText = point;l.textStyle = style
      l.textRuns = [TextRun(location:0,length:(l.text as NSString).length,font:l.fontName,size:24,color:l.color,tracking:1,bold:false,italic:false,underline:false,strikethrough:false)]
      l.importedTextAppearance = TextAppearance(l)
    }
    let view = CanvasNSView(frame:CGRect(x:0,y:0,width:400,height:300));view.store = store
    store.textEditingLayerID = store.selected?.id;view.syncTextEditor()
    return (store,view)
  }
  @MainActor func testInspectorTypographyUsesSameAttributesAsFinalRendering() throws {
    let (s,v) = fixture();let editor = try XCTUnwrap(v.textEditor)
    s.updateSelected("Inspector typography") {l in
      l.fontName = "Menlo-Regular";l.fontSize = 32;l.color = RGBA(r:0,g:0,b:1)
      var style = l.textStyle ?? TextStyle()
      style.bold = true;style.italic = true;style.underline = true;style.strikethrough = true
      style.tracking = 12;style.lineHeight = 1.8;style.paragraphBefore = 10;style.paragraphAfter = 18
      style.alignment = 2;style.verticalAlignment = 2;l.textStyle = style
    }
    v.syncTextEditor()
    let a = try XCTUnwrap(editor.textStorage).attributes(at:0,effectiveRange:nil)
    let final = TextLayout.attributed(try XCTUnwrap(s.selected)).attributes(at:0,effectiveRange:nil)
    let font = try XCTUnwrap(a[.font] as? NSFont)
    XCTAssertEqual(font.fontName,(final[.font] as? NSFont)?.fontName);XCTAssertEqual(font.pointSize,32,accuracy:0.01)
    let traits = NSFontManager.shared.traits(of:font)
    XCTAssertTrue(traits.contains(.boldFontMask));XCTAssertTrue(traits.contains(.italicFontMask))
    XCTAssertEqual(a[.kern] as? Double,12);XCTAssertEqual(a[.underlineStyle] as? Int,1);XCTAssertEqual(a[.strikethroughStyle] as? Int,1)
    let color = try XCTUnwrap(a[.foregroundColor] as? NSColor).usingColorSpace(.sRGB)!
    XCTAssertGreaterThan(color.blueComponent,0.99)
    let paragraph = try XCTUnwrap(a[.paragraphStyle] as? NSParagraphStyle)
    XCTAssertEqual(paragraph.alignment,.right);XCTAssertEqual(paragraph.lineHeightMultiple,1.8,accuracy:0.001)
    XCTAssertEqual(paragraph.paragraphSpacingBefore,10);XCTAssertEqual(paragraph.paragraphSpacing,18)
    XCTAssertGreaterThan(editor.textContainerInset.height,0)
    XCTAssertEqual(editor.textContainerInset.height,TextLayout.verticalOffset(try XCTUnwrap(s.selected)),accuracy:0.01)
    v.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
    v.syncTextEditor()
    XCTAssertEqual(editor.textStorage?.attribute(.kern,at:0,effectiveRange:nil) as? Double,12)
    XCTAssertEqual(editor.textStorage?.attribute(.underlineStyle,at:0,effectiveRange:nil) as? Int,1)
    v.finishTextEditing()
  }
  @MainActor func testInspectorContentAndDisablingRunDecorationsRemainEffective() throws {
    let (s,v) = fixture();let editor = try XCTUnwrap(v.textEditor)
    s.updateSelected("Inspector content") {l in l.text = "Changed from inspector";l.textRuns = nil;l.importedTextAppearance = nil}
    v.syncTextEditor();XCTAssertEqual(editor.string,"Changed from inspector")
    s.updateSelected("Enable decorations") {l in l.textStyle?.underline = true;l.textStyle?.strikethrough = true;l.textStyle?.tracking = 8}
    v.syncTextEditor();v.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
    s.updateSelected("Disable decorations") {l in l.textStyle?.underline = false;l.textStyle?.strikethrough = false;l.textStyle?.tracking = 0}
    v.syncTextEditor()
    XCTAssertEqual(editor.textStorage?.attribute(.underlineStyle,at:0,effectiveRange:nil) as? Int,0)
    XCTAssertEqual(editor.textStorage?.attribute(.strikethroughStyle,at:0,effectiveRange:nil) as? Int,0)
    XCTAssertEqual(editor.textStorage?.attribute(.kern,at:0,effectiveRange:nil) as? Double,0)
    XCTAssertEqual(editor.string,s.selected?.text)
    v.finishTextEditing()
  }
  @MainActor func testPointTextResizesForInspectorFontAndKeepsRotatedAnchor() throws {
    let (s,v) = fixture(point:true)
    s.updateSelected("Rotate") {$0.rotation = 27}
    let before = try XCTUnwrap(s.selected),anchor = TransformGeometry.displayPoint(.zero,layer:before)
    s.updateSelected("Increase size") {$0.fontSize *= 2}
    v.syncTextEditor()
    let after = try XCTUnwrap(s.selected),next = TransformGeometry.displayPoint(.zero,layer:after)
    XCTAssertGreaterThan(after.width,before.width*1.8)
    XCTAssertEqual(next.x,anchor.x,accuracy:0.0001);XCTAssertEqual(next.y,anchor.y,accuracy:0.0001)
    v.finishTextEditing()
  }
  @MainActor func testVerticalLayoutAndInspectorFocusKeepNativeEditing() throws {
    let (s,v) = fixture();let editor = try XCTUnwrap(v.textEditor)
    s.updateSelected("Vertical") {$0.textStyle?.vertical = true}
    v.syncTextEditor();XCTAssertEqual(editor.layoutOrientation,.vertical)
    v.textDidEndEditing(Notification(name:NSText.didEndEditingNotification,object:editor))
    XCTAssertTrue(v.textEditor === editor);XCTAssertEqual(s.textEditingLayerID,s.selected?.id)
    s.updateSelected("Horizontal") {$0.textStyle?.vertical = false}
    v.syncTextEditor();XCTAssertEqual(editor.layoutOrientation,.horizontal)
    v.finishTextEditing()
  }
  @MainActor func testSwitchingToolEndsInlineEditingWithoutLosingText() throws {
    let (s,v) = fixture();let editor = try XCTUnwrap(v.textEditor)
    editor.string = "Keep edited text"
    v.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
    s.chooseTool(.crop)
    v.syncTextEditor()
    XCTAssertNil(s.textEditingLayerID);XCTAssertNil(v.textEditor)
    XCTAssertEqual(s.selected?.text,"Keep edited text")
    XCTAssertEqual(s.compositorToolID,"crop")
  }
}
