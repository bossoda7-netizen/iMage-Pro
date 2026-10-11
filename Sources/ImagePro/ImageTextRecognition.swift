import AppKit
import Vision

/// Raster text has no font metadata. Preserve observed line breaks, text size,
/// alignment and colour as editable rich text instead of inventing font names.
enum ImageTextRecognition {
  static func recognize(_ image: CGImage, logicalWidth: Double) throws -> NSAttributedString {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage:image).perform([request])
    let observations = (request.results ?? []).sorted {
      if abs($0.boundingBox.midY-$1.boundingBox.midY) > min($0.boundingBox.height,$1.boundingBox.height)*0.5 {
        return $0.boundingBox.midY > $1.boundingBox.midY
      }
      return $0.boundingBox.minX < $1.boundingBox.minX
    }
    let output = NSMutableAttributedString(string:"")
    let bitmap = NSBitmapImageRep(cgImage:image)
    let factor = logicalWidth / Double(image.width)
    for (index, observation) in observations.enumerated() {
      guard let line = observation.topCandidates(1).first?.string, !line.isEmpty else { continue }
      let box = observation.boundingBox
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = abs(box.midX-0.5)<0.06 && box.width<0.8 ? .center : .left
      paragraph.paragraphSpacing = max(1,box.height*Double(image.height)*factor*0.15)
      let size = max(8,min(512,box.height*Double(image.height)*factor))
      // Estimate the foreground as the contrasting portion of the text region.
      var samples: [NSColor] = []
      for y in 0..<8 { for x in 0..<24 {
        let px = min(image.width-1,max(0,Int((box.minX+box.width*(Double(x)+0.5)/24)*Double(image.width))))
        let py = min(image.height-1,max(0,Int((1-box.maxY+box.height*(Double(y)+0.5)/8)*Double(image.height))))
        if let c = bitmap.colorAt(x:px,y:py)?.usingColorSpace(.deviceRGB), c.alphaComponent>0.5 { samples.append(c) }
      }}
      let sorted = samples.sorted { $0.brightnessComponent < $1.brightnessComponent }
      let median = sorted.isEmpty ? NSColor.white : sorted[sorted.count/2]
      let color = sorted.isEmpty ? NSColor.black : median.brightnessComponent>0.5
        ? sorted[max(0,sorted.count/10)] : sorted[min(sorted.count-1,sorted.count*9/10)]
      output.append(NSAttributedString(string:(index == 0 ? "" : "\n")+line,
        attributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:color,.paragraphStyle:paragraph]))
    }
    return output
  }
}

extension EditorStore {
  func extractImageText() {
    guard !busy, let layer = selected, layer.kind != .group,
      let image = renderer.renderLayer(layer,assets:active.assets,scale:min(1,3000/max(layer.width,layer.height))) else { return }
    let project = activeID, width = layer.width
    busy = true
    notify("正在识别图片文字…")
    Task.detached(priority:.userInitiated) {
      do {
        let text = try ImageTextRecognition.recognize(image,logicalWidth:width)
        let plainText = text.string
        let richText = try? text.data(from:NSRange(location:0,length:text.length),
          documentAttributes:[.documentType:NSAttributedString.DocumentType.rtf])
        await MainActor.run {
          self.busy = false
          guard self.activeID == project else { return }
          guard !plainText.isEmpty else { self.notify("未识别到文字",warning:true);return }
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(plainText,forType:.string)
          if let richText { NSPasteboard.general.setData(richText,forType:.rtf) }
          self.notify("图片文字已复制，保留可识别的排版")
        }
      } catch { await MainActor.run { self.busy = false;self.fail(error) } }
    }
  }
}
