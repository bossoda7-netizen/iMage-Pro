import AppKit
import CoreImage
import SwiftUI
import Vision

struct FaceRegion: Codable, Equatable {
  var contour: [Point]?
  var bounds: CGRect
  var leftEye: [Point]
  var rightEye: [Point]
  var outerLips: [Point]
  var innerLips: [Point]
  var brows: [[Point]]
}
enum PortraitDetection {
  static func faces(_ image: CGImage) throws -> [FaceRegion] {
    let request = VNDetectFaceLandmarksRequest()
    try VNImageRequestHandler(cgImage:image).perform([request])
    return (request.results ?? []).prefix(16).map { observation in
      let b = observation.boundingBox
      func points(_ region: VNFaceLandmarkRegion2D?) -> [Point] {
        (region?.normalizedPoints ?? []).map { Point(x:b.minX+Double($0.x)*b.width,y:1-b.minY-Double($0.y)*b.height) }
      }
      return FaceRegion(contour:points(observation.landmarks?.faceContour),bounds:CGRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height),
        leftEye:points(observation.landmarks?.leftEye),rightEye:points(observation.landmarks?.rightEye),
        outerLips:points(observation.landmarks?.outerLips),innerLips:points(observation.landmarks?.innerLips),
        brows:[points(observation.landmarks?.leftEyebrow),points(observation.landmarks?.rightEyebrow)])
    }
  }
  static func body(_ image: CGImage) throws -> [Point] {
    let request = VNDetectHumanBodyPoseRequest()
    try VNImageRequestHandler(cgImage:image).perform([request])
    guard let observation = request.results?.first else { return [] }
    let names: [VNHumanBodyPoseObservation.JointName] = [.leftShoulder,.rightShoulder,.leftHip,.rightHip,.leftKnee,.rightKnee,.leftAnkle,.rightAnkle]
    return try names.map { name -> Point in
      let p = try observation.recognizedPoint(name)
      guard p.confidence > 0.35 else { return Point(x:-1,y:-1) }
      return Point(x:p.x,y:1-p.y)
    }
  }
}
extension EditorStore {
  func detectPortrait(for effectID: UUID, body: Bool = false) {
    guard let layer = selected, !busy,
      let image = renderer.renderLayer(layer,assets:active.assets,scale:min(1,1400/max(layer.width,layer.height))) else { return }
    let project = activeID, layerID = layer.id
    busy = true;notify(body ? "正在本机识别人物姿态…" : "正在本机识别人脸…")
    Task.detached(priority:.userInitiated) {
      do {
        let faces = body ? [] : try PortraitDetection.faces(image)
        let joints = body ? try PortraitDetection.body(image) : []
        await MainActor.run {
          self.busy = false
          guard self.activeID == project, self.selected?.id == layerID,
            self.selected?.effects.contains(where:{$0.id == effectID}) == true else { return }
          self.updateEffect(effectID,"识别人像区域") {
            if body {
              $0.bodyJoints = joints
              if joints.count >= 4, joints[2].x >= 0, joints[3].x >= 0 {
                $0.set("centerX",(joints[2].x+joints[3].x)/2)
                $0.set("centerY",(joints[2].y+joints[3].y)/2)
                $0.set("regionSize",max(0.12,min(0.8,abs(joints[2].x-joints[3].x)*2.5)))
              }
            } else { $0.faces = faces; if !faces.isEmpty {$0.style = "face"} }
          }
          self.notify(body ? (joints.isEmpty ? "未识别到可靠人物关节，暂未应用形变" : "已识别人物，参数可继续微调")
            : faces.isEmpty ? "未识别到人脸，暂未应用美颜" : "已识别 \(faces.count) 张人脸")
        }
      } catch { await MainActor.run {self.busy = false;self.fail(error)} }
    }
  }
}

enum PortraitEffects {
  static let bodyKernel = NativeKernels.warp("poseBody")
  static func body(_ e:ImageEffect,image:CIImage) -> CIImage {
    guard let kernel = bodyKernel,let joints = e.bodyJoints,joints.count>=4,joints.prefix(4).allSatisfy({$0.x>=0 && $0.y>=0}) else {return image}
    let missing = Point(x: 0.5, y: 0.8)
    let lk = joints.count > 4 ? joints[4] : missing
    let rk = joints.count > 5 ? joints[5] : missing
    let la = joints.count > 6 ? joints[6] : missing
    let ra = joints.count > 7 ? joints[7] : missing
    let validLegs = joints.count >= 8 && joints[4].x >= 0 && joints[5].x >= 0 && joints[6].x >= 0 && joints[7].x >= 0
    return kernel.apply(extent:image.extent,roiCallback:{_,_ in image.extent},image:image.clampedToExtent(),arguments:[
      CIVector(x:image.extent.width,y:image.extent.height),CIVector(x:image.extent.minX,y:image.extent.minY),
      CIVector(x:joints[0].x,y:joints[0].y),CIVector(x:joints[1].x,y:joints[1].y),
      CIVector(x:joints[2].x,y:joints[2].y),CIVector(x:joints[3].x,y:joints[3].y),
      CIVector(x:lk.x,y:lk.y),CIVector(x:rk.x,y:rk.y),
      CIVector(x:la.x,y:la.y),CIVector(x:ra.x,y:ra.y),validLegs ? 1.0:0.0,
      e.value("deformation",0.3),e.value("waist"),e.value("shoulders"),e.value("legs")]) ?? image
  }
  static func faceMask(_ faces:[FaceRegion], extent:CGRect, feature:String) -> CIImage {
    let w = max(1,Int(extent.width)),h = max(1,Int(extent.height))
    guard let cg = ImageRenderer.bitmap(w,h) else { return CIImage(color:.black).cropped(to:extent) }
    cg.setFillColor(NSColor.black.cgColor);cg.fill(CGRect(x:0,y:0,width:w,height:h))
    cg.translateBy(x:0,y:Double(h));cg.scaleBy(x:Double(w),y:-Double(h))
    func polygon(_ points:[Point], white:Bool) {
      guard let first = points.first else { return }
      cg.setFillColor((white ? NSColor.white : .black).cgColor)
      cg.move(to:first.cg);for p in points.dropFirst(){cg.addLine(to:p.cg)};cg.closePath();cg.fillPath()
    }
    func ellipse(_ rect:CGRect,white:Bool) { cg.setFillColor((white ? NSColor.white : .black).cgColor);cg.fillEllipse(in:rect) }
    func bounds(_ points:[Point]) -> CGRect {
      let xs = points.map(\.x),ys = points.map(\.y)
      return CGRect(x:xs.min() ?? 0,y:ys.min() ?? 0,width:(xs.max() ?? 0)-(xs.min() ?? 0),height:(ys.max() ?? 0)-(ys.min() ?? 0))
    }
    for f in faces {
      switch feature {
      case "skin":
        if let contour = f.contour,contour.count>=4 {
          // Vision's contour follows the jaw, not the hairline. Close it with a
          // rounded forehead cap through the top of the face bounds.
          let first = contour.first!,last = contour.last!
          let centerX = f.bounds.midX,top = f.bounds.minY
          var outline = contour
          let leftToRight = last.x < first.x
          let minX = min(first.x,last.x),maxX = max(first.x,last.x)
          for i in 0...24 {
            let t = Double(i)/24
            let x = leftToRight ? minX+(maxX-minX)*t : maxX-(maxX-minX)*t
            let u = (x-centerX)/max(0.001,(maxX-minX)/2)
            let y = top+f.bounds.height*0.18*(1-sqrt(max(0,1-u*u)))
            outline.append(Point(x:x,y:y))
          }
          polygon(outline,white:true)
        } else {ellipse(f.bounds.insetBy(dx:f.bounds.width*0.08,dy:f.bounds.height*0.03),white:true)}
        polygon(f.leftEye,white:false);polygon(f.rightEye,white:false)
        polygon(f.outerLips,white:false);for brow in f.brows {polygon(brow,white:false)}
      case "lips":polygon(f.outerLips,white:true);polygon(f.innerLips,white:false)
      case "teeth":polygon(f.innerLips,white:true)
      case "eyes":polygon(f.leftEye,white:true);polygon(f.rightEye,white:true)
      case "circles":
        for points in [f.leftEye,f.rightEye] {
          let b = bounds(points);ellipse(CGRect(x:b.minX,y:b.maxY,width:b.width,height:max(b.height,f.bounds.height*0.07)),white:true)
        }
      case "blush":
        for x in [0.22,0.78] { ellipse(CGRect(x:f.bounds.minX+f.bounds.width*(x-0.13),y:f.bounds.minY+f.bounds.height*0.5,width:f.bounds.width*0.26,height:f.bounds.height*0.18),white:true) }
      default:break
      }
    }
    let mask = CIImage(cgImage:cg.makeImage()!).transformed(by:CGAffineTransform(translationX:extent.minX,y:extent.minY))
    return mask.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey: feature == "blush" ? extent.width*0.012 : max(0.5,extent.width*0.0015)]).cropped(to:extent)
  }
  static func beauty(_ e:ImageEffect,image:CIImage) -> CIImage {
    let extent = image.extent
    let faces = e.faces ?? []
    if faces.isEmpty { return image }
    var result = image
    let smooth = image.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":e.value("smoothing",0.04),"inputSharpness":e.value("detail",0.4)])
      .applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:1+e.value("warmth",0.05)])
    let mask:CIImage
    if !faces.isEmpty { mask = faceMask(faces,extent:extent,feature:"skin") }
    else {
      mask = CIFilter(name:"CIRadialGradient",parameters:[kCIInputCenterKey:CIVector(x:extent.minX+extent.width*e.value("centerX",0.5),y:extent.minY+extent.height*(1-e.value("centerY",0.5))),
        "inputRadius0":min(extent.width,extent.height)*e.value("regionSize",0.25),"inputRadius1":min(extent.width,extent.height)*e.value("regionSize",0.25)*1.6,
        "inputColor0":CIColor.white,"inputColor1":CIColor.black])!.outputImage!.cropped(to:extent)
    }
    // Keep skin retouching and face lift local to the detected face mask. A global
    // brightness adjustment was the reason highlights outside the face were lifted
    // and the facial result looked imprecise.
    result = smooth.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:mask])
    let faceBrightness = e.value("brightness", 0.02)
    if abs(faceBrightness) > 0.0001 {
      let lifted = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: faceBrightness * 1.6])
      result = lifted.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: mask])
    }
    func apply(_ processed:CIImage,_ feature:String,_ amount:Double) {
      guard amount > 0, !faces.isEmpty else { return }
      let mixed = AdvancedEffects.blend(processed,over:result,amount:amount)
      result = mixed.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:faceMask(faces,extent:extent,feature:feature)])
    }
    if e.value("lipstick") > 0 {
      let color = e.targetColor ?? RGBA(r:0.75,g:0.08,b:0.2)
      let tint = CIImage(color:CIColor(color:color.ns)!).cropped(to:extent)
      apply(tint.applyingFilter("CIColorBlendMode",parameters:[kCIInputBackgroundImageKey:result]),"lips",e.value("lipstick"))
    }
    let blush = CIImage(color:CIColor(red:0.95,green:0.25,blue:0.32)).cropped(to:extent)
    apply(blush.applyingFilter("CISoftLightBlendMode",parameters:[kCIInputBackgroundImageKey:result]),"blush",e.value("blush"))
    apply(result.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.6]),"circles",e.value("darkCircles"))
    apply(result.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.15,kCIInputBrightnessKey:0.08]),"teeth",e.value("teeth"))
    apply(result.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:0.5]).applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.35]),"eyes",e.value("eyes"))
    let light = e.value("lighting")
    if light != 0 {
      let x = e.value("lightX",0.35),y = e.value("lightY",0.2),radius = e.value("lightRadius",0.6)*min(extent.width,extent.height)
      var lm = CIFilter(name:"CIRadialGradient",parameters:[kCIInputCenterKey:CIVector(x:extent.minX+extent.width*x,y:extent.minY+extent.height*(1-y)),"inputRadius0":0,"inputRadius1":max(1,radius),"inputColor0":CIColor.white,"inputColor1":CIColor.black])!.outputImage!
      lm = lm.cropped(to:extent).applyingFilter("CIMultiplyCompositing",parameters:[kCIInputBackgroundImageKey:mask])
      let lit = result.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:light])
      result = lit.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:lm])
    }
    return AdvancedEffects.blend(result,over:image,amount:e.amount)
  }
}
