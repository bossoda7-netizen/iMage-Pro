import AppKit

enum PixelRetouch {
  struct Surface {
    var pixels: [UInt8]
    var width: Int
    var height: Int
    init?(_ image: CGImage) {
      width = image.width; height = image.height
      guard let context = ImageRenderer.bitmap(width,height) else { return nil }
      context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
      guard let data = context.data else { return nil }
      pixels = Array(UnsafeBufferPointer(start:data.assumingMemoryBound(to:UInt8.self),count:width*height*4))
    }
    func sample(_ x: Double, _ y: Double) -> [Double] {
      let px = min(width-1,max(0,Int(x.rounded()))), py = min(height-1,max(0,Int(y.rounded())))
      let i = (py*width+px)*4
      return (0..<4).map { Double(pixels[i+$0])/255 }
    }
    func average(_ p: CGPoint, radius: Double) -> [Double] {
      var sum = [Double](repeating:0,count:4)
      for y in -2...2 { for x in -2...2 {
        let c = sample(p.x+Double(x)*radius/2,p.y+Double(y)*radius/2)
        for k in 0..<4 { sum[k] += c[k]/25 }
      }}
      return sum
    }
    func image() -> CGImage? {
      guard let provider = CGDataProvider(data:Data(pixels) as CFData) else { return nil }
      return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
        space:ImageRenderer.colorSpace,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
        provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
    }
  }
  static func influence(_ distance: Double, radius: Double, hardness: Double) -> Double {
    let t = max(0,min(1,(radius-distance)/max(0.5,radius*(1-hardness))))
    return t*t*(3-2*t)
  }
  /// Smudge transports colour from the previous dab, then picks up the result.
  /// No blur filter or whole-stroke direction is involved.
  static func smudge(_ image: CGImage, points: [CGPoint], radius: Double,
    hardness: Double, strength: Double) -> CGImage? {
    guard points.count>1, var output = Surface(image) else { return image }
    let radius = max(1,radius), step = max(1,radius*0.2)
    var previous = points[0]
    for end in points.dropFirst() {
      let distance = hypot(end.x-previous.x,end.y-previous.y)
      let count = max(1,Int(ceil(distance/step)))
      let start = previous
      for j in 1...count {
        let destination = CGPoint(x:start.x+(end.x-start.x)*Double(j)/Double(count),
          y:start.y+(end.y-start.y)*Double(j)/Double(count))
        let size = Int(ceil(radius))
        var patch: [(Int,[Double],Double)] = []
        for y in -size...size { for x in -size...size {
          let px = Int(destination.x.rounded())+x,py = Int(destination.y.rounded())+y
          guard px>=0,py>=0,px<output.width,py<output.height else { continue }
          let weight = influence(hypot(Double(x),Double(y)),radius:radius,hardness:hardness)*strength
          if weight>0 { patch.append(((py*output.width+px)*4,output.sample(previous.x+Double(x),previous.y+Double(y)),weight)) }
        }}
        for (index,color,weight) in patch { for k in 0..<4 {
          let old = Double(output.pixels[index+k])/255
          output.pixels[index+k] = UInt8(min(255,max(0,((old*(1-weight)+color[k]*weight)*255).rounded())))
        }}
        previous = destination
      }
    }
    return output.image()
  }
  /// A sampled texture patch is corrected to the destination's low-frequency
  /// lighting. Automatic mode chooses a nearby patch by boundary similarity.
  static func heal(_ image: CGImage, points: [CGPoint], radius: Double, source: CGPoint?) -> CGImage? {
    guard let original = Surface(image), var output = Surface(image), let first = points.first else { return image }
    let radius = max(2,radius)
    let minX = max(0,Int((points.map(\.x).min() ?? 0)-radius)),maxX = min(image.width-1,Int((points.map(\.x).max() ?? 0)+radius))
    let minY = max(0,Int((points.map(\.y).min() ?? 0)-radius)),maxY = min(image.height-1,Int((points.map(\.y).max() ?? 0)+radius))
    guard minX<=maxX,minY<=maxY else { return image }
    var offset = CGPoint(x:(source?.x ?? 0)-first.x,y:(source?.y ?? 0)-first.y)
    if source == nil {
      var best = Double.infinity
      for multiplier in [2.5,4.0,6.0] { for angle in 0..<16 {
        let a = Double(angle)*2 * .pi/16
        let candidate = CGPoint(x:cos(a)*radius*multiplier,y:sin(a)*radius*multiplier)
        var score = 0.0, valid = true
        for point in [points.first!,points[points.count/2],points.last!] {
          for direction in 0..<12 {
            let a = Double(direction)*2 * .pi/12
            let edge = CGPoint(x:point.x+cos(a)*radius,y:point.y+sin(a)*radius)
            let src = CGPoint(x:edge.x+candidate.x,y:edge.y+candidate.y)
            if src.x<0 || src.y<0 || src.x>=Double(image.width) || src.y>=Double(image.height) { valid = false;break }
            let left = original.sample(edge.x,edge.y),right = original.sample(src.x,src.y)
            for k in 0..<3 { score += pow(left[k]-right[k],2) }
            // Avoid sampling the blemish/target from another part of the stroke.
            if points.contains(where:{hypot($0.x-src.x,$0.y-src.y)<radius}) { valid = false;break }
          }
          if !valid { break }
        }
        if valid,score<best { best = score;offset = candidate }
      }}
      guard best.isFinite else {return image}
    }
    // Estimate lighting from the surrounding ring, excluding the repair target.
    func ring(_ point: CGPoint) -> [Double] {
      var sum = [Double](repeating:0,count:4)
      for i in 0..<24 {
        let a = Double(i)*2 * .pi/24,c = original.sample(point.x+cos(a)*radius*1.2,point.y+sin(a)*radius*1.2)
        for k in 0..<4 { sum[k] += c[k]/24 }
      }
      return sum
    }
    let lighting = points.map { ring($0) }
    let sourceAverages = points.map {original.average(CGPoint(x:$0.x+offset.x,y:$0.y+offset.y),radius:radius)}
    for y in minY...maxY { for x in minX...maxX {
      let point = CGPoint(x:x,y:y)
      guard let closest = points.indices.min(by:{hypot(points[$0].x-point.x,points[$0].y-point.y)<hypot(points[$1].x-point.x,points[$1].y-point.y)}) else { continue }
      guard hypot(points[closest].x-point.x,points[closest].y-point.y)<=radius else { continue }
      let sample = original.sample(point.x+offset.x,point.y+offset.y)
      let average = sourceAverages[closest]
      let index = (y*image.width+x)*4
      for k in 0..<3 {
        output.pixels[index+k] = UInt8(min(255,max(0,(sample[k]-average[k]+lighting[closest][k])*255)))
      }
    }}
    return output.image()
  }
}
