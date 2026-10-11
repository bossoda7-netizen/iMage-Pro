import AppKit

extension CanvasNSView {
  func installDraftUndo() {
    store?.canvasUndo = { [weak self] in
      guard let self else {return false}
      if let editor = self.textEditor,editor.undoManager?.canUndo == true {editor.undoManager?.undo();self.publishPenHistory();return true}
      guard let snapshot = self.penUndo.popLast() else {return false}
      self.penRedo.append(self.penAnchors);self.penAnchors = snapshot
      self.penDrag = nil;self.pendingPenEdit = nil;self.publishPenHistory();self.needsDisplay = true;return true
    }
    store?.canvasRedo = { [weak self] in
      guard let self else {return false}
      if let editor = self.textEditor,editor.undoManager?.canRedo == true {editor.undoManager?.redo();self.publishPenHistory();return true}
      guard let snapshot = self.penRedo.popLast() else {return false}
      self.penUndo.append(self.penAnchors);self.penAnchors = snapshot
      self.publishPenHistory();self.needsDisplay = true;return true
    }
  }
  func savePenUndo() {penUndo.append(penAnchors);penRedo.removeAll();publishPenHistory()}
  func publishPenHistory() {store?.canvasCanUndo = !penUndo.isEmpty || textEditor?.undoManager?.canUndo == true;store?.canvasCanRedo = !penRedo.isEmpty || textEditor?.undoManager?.canRedo == true}
  func resetPenDraft() {
    penAnchors = [];penUndo = [];penRedo = [];pendingPenEdit = nil;penDrag = nil;penEdit = nil
    publishPenHistory()
  }
  func syncTextEditor() {
    guard let store else {return}
    guard let id = store.textEditingLayerID,id == store.selected?.id,
      let layer = store.document.layers.first(where:{$0.id == id}),layer.kind == .text,
      store.document.id == textProjectID || textEditor == nil else {
      if textEditor != nil {finishTextEditing()};return
    }
    if textEditor == nil {
      store.beginTransaction("编辑文字")
      textBefore = layer;textProjectID = store.document.id
      let editor = CanvasTextView(frame:.zero)
      editor.owner = self;editor.delegate = self;editor.allowsUndo = true
      editor.isRichText = true;editor.isAutomaticQuoteSubstitutionEnabled = false
      do {
        editor.textContainer?.replaceLayoutManager(CTSelectionLayout())
        editor.selectedTextAttributes = [.backgroundColor:NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45)]
      }
      editor.isAutomaticDashSubstitutionEnabled = false;editor.drawsBackground = false
      editor.textContainerInset = .zero;editor.textContainer?.lineFragmentPadding = 0
      editor.isVerticallyResizable = false;editor.isHorizontallyResizable = false
      editor.string = layer.text;textEditor = editor;addSubview(editor)
      window?.makeFirstResponder(editor);editor.selectAll(nil)
      compositeKey = nil
    }
    guard let editor = textEditor else {return}
    let rect = imageRect
    editor.frameRotation = 0
    let origin = TransformGeometry.displayPoint(.zero,layer:layer)
    editor.frame = CGRect(x:rect.minX+origin.x*scale,y:rect.minY+origin.y*scale,width:layer.width*scale,height:layer.height*scale)
    editor.frameRotation = -layer.rotation
    let style = layer.textStyle ?? TextStyle()
    synchronizingText = true
    let selected = editor.selectedRange()
    let value = TextLayout.attributed(layer,scale:scale)
    if !editor.hasMarkedText() {
      editor.textStorage?.setAttributedString(value)
      editor.setSelectedRange(NSRange(location:min(selected.location,value.length),length:min(selected.length,max(0,value.length-min(selected.location,value.length)))))
    }
    editor.typingAttributes = value.length>0 ? value.attributes(at:min(max(0,editor.selectedRange().location-1),value.length-1),effectiveRange:nil) : TextLayout.typingAttributes(layer,scale:scale)
    editor.insertionPointColor = layer.color.ns
    editor.textContainerInset = CGSize(width:0,height:TextLayout.verticalOffset(layer)*scale)
    editor.setLayoutOrientation(style.vertical ? .vertical : .horizontal)
    synchronizingText = false
    if style.pointText == true {
      editor.textContainer?.containerSize = CGSize(width:100_000,height:100_000)
      editor.textContainer?.widthTracksTextView = false
    } else {
      editor.textContainer?.widthTracksTextView = true
      editor.textContainer?.containerSize = editor.bounds.size
    }
  }
  func finishTextEditing(cancel:Bool = false) {
    guard let editor = textEditor else {return}
    let before = textBefore,project = textProjectID
    textEditor = nil;textBefore = nil;textProjectID = nil
    editor.delegate = nil;editor.removeFromSuperview()
    if cancel,let before,store?.document.id == project {
      if let original = compositorNewTextBefore {store?.edit("取消新建文字") {$0 = original}}
      else {store?.updateSelected("取消文字编辑") {$0 = before}}
    } else if editor.string.isEmpty,let original = compositorNewTextBefore,store?.document.id == project {
      store?.edit("取消空文字") {$0 = original}
    }
    compositorNewTextBefore = nil
    store?.textEditingLayerID = nil
    store?.endTransaction();publishPenHistory();compositeKey = nil;needsDisplay = true
    window?.makeFirstResponder(self)
  }
}
extension CanvasNSView: NSTextViewDelegate {
  func textDidChange(_ notification: Notification) {
    guard !synchronizingText,let textEditor,store?.selected?.id == textBefore?.id else {return}
    var runs = [TextRun]()
    textEditor.textStorage?.enumerateAttributes(in:NSRange(location:0,length:(textEditor.string as NSString).length)) { attrs,range,_ in
      let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize:14)
      let traits = NSFontManager.shared.traits(of:font)
      runs.append(TextRun(location:range.location,length:range.length,font:font.fontName,size:font.pointSize/scale,
        color:RGBA(attrs[.foregroundColor] as? NSColor ?? .black),tracking:(attrs[.kern] as? Double ?? 0)/scale,
        bold:traits.contains(.boldFontMask),italic:traits.contains(.italicFontMask),underline:(attrs[.underlineStyle] as? Int ?? 0)>0,
        strikethrough:(attrs[.strikethroughStyle] as? Int ?? 0)>0))
    }
    store?.updateSelected("编辑文字") {l in
      l.text = textEditor.string;l.textRuns = runs
      let title = textEditor.string.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? ""
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { l.name = String(trimmed.prefix(32)) }
      l.importedTextAppearance = TextAppearance(l)
    }
    syncTextEditor()
    DispatchQueue.main.async { [weak self] in self?.publishPenHistory() }
  }
  func textDidEndEditing(_ notification: Notification) {
    // Inspector controls keep the native editor and selection alive. Explicit completion,
    // changing the selected layer or clicking the canvas finishes the edit.
  }
}
final class CanvasTextView: NSTextView {
  let editingUndoManager = UndoManager()
  override var undoManager: UndoManager? {editingUndoManager}
  weak var owner: CanvasNSView?
  override var mouseDownCanMoveWindow: Bool {false}
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {owner?.finishTextEditing(cancel:true);return}
    if event.modifierFlags.contains(.option),[123,124,125,126].contains(event.keyCode),let store = owner?.store {
      let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
      store.updateSelected("文字间距") {layer in
        var style = layer.textStyle ?? TextStyle()
        switch event.keyCode {
        case 123:style.tracking -= step
        case 124:style.tracking += step
        case 126:style.lineHeight = max(0.1,style.lineHeight-step/max(1,layer.fontSize))
        default:style.lineHeight += step/max(1,layer.fontSize)
        }
        layer.textStyle = style
      }
      owner?.syncTextEditor();return
    }
    if event.keyCode == 36,event.modifierFlags.contains(.command) {owner?.finishTextEditing();return}
    super.keyDown(with:event)
  }
}

// Compositor's translucent native text selection layout, adapted to our inline editor.
// Copyright (c) 2026 Wonder Assembly LLC (MIT); ThirdParty/Compositor/LICENSE.
final class CTSelectionLayout: NSLayoutManager {
  override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
    forCharacterRange charRange: NSRange, color: NSColor) {
    color.withAlphaComponent(min(color.alphaComponent,0.45)).setFill()
    super.fillBackgroundRectArray(rectArray,count:rectCount,forCharacterRange:charRange,color:color)
  }
  override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    // The canvas renders glyphs with layer opacity, masks and effects. AppKit draws selection and caret only.
  }
}
