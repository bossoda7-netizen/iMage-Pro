// Adapted from Compositor's WarpStroke and CloneStamp (MIT).
// Copyright (c) 2026 Wonder Assembly LLC. See ThirdParty/Compositor/LICENSE.
import AppKit
import CoreImage

/// Per-gesture working copy. Original assets remain immutable until a single commit.
@MainActor final class CompositorPixelStroke {
    let layer: ImageLayer
    let project: UUID
    let mode: String
    let diameter: CGFloat
    let hardness: CGFloat
    let strength: CGFloat
    let width: Int
    let height: Int
    let context: CGContext
    private let pixels: UnsafeMutablePointer<UInt8>
    private let original: [UInt8]
    private var coverage: [UInt8]
    private let clip: [UInt8]?
    private(set) var points: [CGPoint] = []
    var gpu: CTMetalWarp?
    private var cpuImage: CGImage?
    private var last: CGPoint?
    private var carried: [Float] = []
    private var scratch: [Float] = []
    var changed = false

    init?(store: EditorStore, useGPU: Bool = true) {
        guard let layer = store.selected, !layer.locked, layer.kind != .group, layer.kind != .adjustment,
              !store.editingMask else { store.notify("选择可编辑的图像图层"); return nil }
        guard layer.width * layer.height <= 40_000_000, max(layer.width,layer.height) <= 8192 else {
            store.notify("当前工具支持 8192 px、4000 万像素以内的图层"); return nil
        }
        var raw = layer; raw.effects = []; raw.maskAssetID = nil; raw.maskStrokes = nil;raw.warpNodes = nil
        raw.maskEnabled = false
        guard let image = store.renderer.renderLayer(raw, assets: store.active.assets),
              let context = Self.bitmap(image.width,image.height), let data = context.data else { return nil }
        context.draw(image, in: CGRect(x:0,y:0,width:image.width,height:image.height))
        self.layer = layer; project = store.document.id; mode = store.compositorToolID ?? ""
        self.context = context; width = image.width; height = image.height
        pixels = data.assumingMemoryBound(to: UInt8.self)
        original = Array(UnsafeBufferPointer(start:pixels,count:width*height*4))
        coverage = [UInt8](repeating:0,count:width*height)
        let factor = CGFloat(width)/layer.width
        diameter = max(2,store.brushSize*factor)
        hardness = min(0.98,max(0,store.brushHardness))
        strength = min(1,max(0,store.brushOpacity*store.brushFlow))
        gpu = useGPU && ["smudge","liquify"].contains(mode) ? CTMetalWarp(pixels:context) : nil
        cpuImage = context.makeImage()
        if let selection = store.selection {
            let region = store.localSelection(selection,layer:layer)
            if let mask = SelectionEngine.mask(region,size:CGSize(width:layer.width,height:layer.height)),
               let c = Self.bitmap(width,height), let d = c.data {
                c.draw(mask,in:CGRect(x:0,y:0,width:width,height:height))
                let p = d.assumingMemoryBound(to:UInt8.self)
                clip = (0..<width*height).map { p[$0*4] }
            } else { return nil }
        } else { clip = nil }
    }
    static func bitmap(_ w:Int,_ h:Int) -> CGContext? {
        CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                  space:ImageRenderer.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    }
    func pixelPoint(_ p:CGPoint) -> CGPoint {
        let local = TransformGeometry.contentPoint(p,layer:layer)
        return CGPoint(x:local.x*CGFloat(width)/layer.width,y:local.y*CGFloat(height)/layer.height)
    }
    func appendDocument(_ point:CGPoint,store:EditorStore) {
        let p = pixelPoint(point)
        if ["smudge","liquify"].contains(mode) { append(p); changed = !points.isEmpty; return }
        let start = last ?? p
        let count = max(1,Int(ceil(hypot(p.x-start.x,p.y-start.y)/max(1,diameter*0.05))))
        for i in 1...count {
            let t = CGFloat(i)/CGFloat(count)
            let dab = CGPoint(x:start.x+(p.x-start.x)*t,y:start.y+(p.y-start.y)*t)
            dabPixels(dab)
        }
        last = p; points.append(p); cpuImage = nil
    }
    func resetToOriginal() {
        gpu?.read(into:context)
        original.withUnsafeBufferPointer {if let base = $0.baseAddress {pixels.update(from:base,count:original.count)}}
        coverage = [UInt8](repeating:0,count:width*height);points = [];last = nil;carried = [];scratch = [];changed = false
        if gpu != nil {gpu = CTMetalWarp(pixels:context)}
        cpuImage = context.makeImage()
    }
    private func dabPixels(_ center:CGPoint) {
        let r = radius, cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        for dy in -r...r { for dx in -r...r {
            let x = cx+dx,y = cy+dy
            guard x>=0,y>=0,x<width,y<height else { continue }
            let i = y*width+x
            let amount = weight(Float(dx*dx+dy*dy).squareRoot()/Float(diameter/2))*Float(clip?[i] ?? 255)/255
            let value = UInt8(max(0,min(255,(amount*255).rounded())))
            guard value>coverage[i] else { continue }
            coverage[i] = value; changed = true
        }}
    }
    func healingJob() -> CTHealingJob { CTHealingJob(original:original,coverage:coverage,width:width,height:height,opacity:Float(strength),backend:mode) }
    /// The painted area stays visible until the asynchronous repair is ready.
    func coverageImage() -> CGImage? {
        guard MIGANInpainting.isHealing(mode),changed else {return nil}
        var rgba = [UInt8](repeating:0,count:width*height*4)
        for i in 0..<coverage.count {
            let alpha = UInt8(Double(coverage[i])*0.42)
            rgba[i*4] = alpha;rgba[i*4+1] = UInt8(Double(alpha)*0.5)
            rgba[i*4+2] = UInt8(Double(alpha)*0.28);rgba[i*4+3] = alpha
        }
        guard let provider = CGDataProvider(data:Data(rgba) as CFData) else {return nil}
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
          space:ImageRenderer.colorSpace,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
    }
    func result() -> CGImage? { image }
    private func clippedImage() -> CGImage? {
        guard let clip,["smudge","liquify"].contains(mode) else { return context.makeImage() }
        var result = Array(UnsafeBufferPointer(start:pixels,count:width*height*4))
        for i in 0..<width*height {
            let a = Float(clip[i])/255
            for k in 0..<4 {
                let index = i*4+k
                let before = Float(original[index]),after = Float(result[index])
                let value = (before+(after-before)*a).rounded()
                result[index] = UInt8(max(0,min(255,value)))
            }
        }
        guard let provider = CGDataProvider(data:Data(result) as CFData) else {return nil}
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
          space:ImageRenderer.colorSpace,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
    }
    func preview(store:EditorStore) -> LayerPreview? {
        guard !MIGANInpainting.isHealing(mode), let image = self.image else {return nil}
        // Use an isolated asset library: live frames never create permanent project assets.
        let assets = AssetLibrary()
        let id = assets.insertTransient(image)
        var shown = layer; shown.kind = .raster;shown.assetID = id;shown.strokes = [];shown.rasterPlacement = nil;shown.contentPlacement = nil
        if let mask = layer.maskAssetID,let data = store.active.assets.data[mask] {assets.insert(data,id:mask)}
        return store.renderer.previewLayer(shown,assets:assets,scale:min(1,1200/max(layer.width,layer.height)))
    }
    var image: CGImage? {
        if let gpu { if cpuImage == nil {gpu.read(into:context);cpuImage = clippedImage()} }
        else if cpuImage == nil {cpuImage = clippedImage()}
        return cpuImage
    }
    private var radius: Int { Int((diameter / 2).rounded(.up)) }
    /// How much a dab moves pixels at a distance `u` (0 center, 1 rim) from its center.
    private func weight(_ u: Float) -> Float {
        guard u < 1 else { return 0 }
        let h = Float(hardness)
        guard u > h else { return 1 }
        let t = (1 - u) / (1 - h)
        return t * t * (3 - 2 * t)
    }

    /// Continues the stroke to `point`, dabbing along the way, then refreshes `image`.
    func append(_ point: CGPoint) {
        guard let from = last else {
            last = point
            if mode == "smudge" {
                if let gpu { gpu.pickUp(at: point, radius: radius); gpu.commit() } else { pickUp(at: point) }
            }
            return
        }
        let distance = hypot(point.x - from.x, point.y - from.y)
        // Smudge drags the pixels one dab's spacing at a time and mixes them with what's there: spaced widely, each step
        // left a faint copy of what it dragged, echoes along the stroke. A pixel apart (a little more for a huge brush)
        // the steps run together into one continuous smear.
        let spacing = max(1, diameter * (mode == "smudge" ? 0.005 : 0.025))
        guard distance >= spacing else { return }
        let steps = Int((distance / spacing).rounded(.up))
        var previous = from
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let next = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
            if let gpu {
                if mode == "smudge" { gpu.smudge(at: next, radius: radius, diameter: diameter, hardness: hardness, strength: strength) }
                else { gpu.push(from: previous, to: next, radius: radius, diameter: diameter, hardness: hardness, strength: strength) }
            } else if mode == "smudge" { smudge(at: next) } else { push(from: previous, to: next) }
            points.append(next)
            previous = next
        }
        last = point
        if let gpu {
            gpu.commit()
            cpuImage = nil
        } else {
            cpuImage = nil
        }
    }

    private func pickUp(at center: CGPoint) {
        let r = radius, side = 2 * r + 1
        carried = [Float](repeating: 0, count: side * side * 4)
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        for dy in -r...r {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                let p = (y * width + x) * 4, c = ((dy + r) * side + dx + r) * 4
                for k in 0..<4 { carried[c + k] = Float(pixels[p + k]) }
            }
        }
    }

    private func smudge(at center: CGPoint) {
        let r = radius, side = 2 * r + 1
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        let keep = Float(strength), invR = 1 / Float(diameter / 2)
        for dy in -r...r {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                let w = weight(Float(dx * dx + dy * dy).squareRoot() * invR)
                guard w > 0 else { continue }
                let p = (y * width + x) * 4, c = ((dy + r) * side + dx + r) * 4
                for k in 0..<4 {
                    let under = Float(pixels[p + k])
                    // What was under the brush at the last dab, laid down here at the smudge's strength: all of it drags the pixels along; less mixes them with what's here, softening the trail.
                    let painted = under + (carried[c + k] - under) * w * keep
                    pixels[p + k] = UInt8(max(0, min(255, painted.rounded())))
                    // The brush then carries what it just left, and nothing older: holding on to what it picked up
                    // at the start stamped it again at every dab, a trail of ghost copies.
                    carried[c + k] = painted
                }
            }
        }
    }

    /// Forward warp: pixels under the brush move with it, most at its center, fading to none at its rim.
    private func push(from a: CGPoint, to b: CGPoint) {
        let r = radius
        let move = SIMD2<Float>(Float(b.x - a.x), Float(b.y - a.y)) * Float(strength)
        let margin = Int(ceil(max(abs(move.x), abs(move.y)))) + 2
        let cx = Int(b.x.rounded()), cy = Int(b.y.rounded())
        // A copy of the area as it was before this dab, which the dab samples from.
        let x0 = max(0, cx - r - margin), x1 = min(width - 1, cx + r + margin)
        let y0 = max(0, cy - r - margin), y1 = min(height - 1, cy + r + margin)
        guard x0 <= x1, y0 <= y1 else { return }
        let cw = x1 - x0 + 1, ch = y1 - y0 + 1
        if scratch.count < cw * ch * 4 { scratch = [Float](repeating: 0, count: cw * ch * 4) }
        for y in 0..<ch {
            for x in 0..<cw {
                let p = ((y + y0) * width + x + x0) * 4, s = (y * cw + x) * 4
                for k in 0..<4 { scratch[s + k] = Float(pixels[p + k]) }
            }
        }
        let invR = 1 / Float(diameter / 2)
        for dy in -r...r {
            let y = cy + dy
            guard y >= y0, y <= y1 else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= x0, x <= x1 else { continue }
                let w = weight(Float(dx * dx + dy * dy).squareRoot() * invR)
                guard w > 0 else { continue }
                // Bilinear sample of the old pixels, from behind the brush's travel.
                let sx = min(Float(cw - 1), max(0, Float(x - x0) - move.x * w))
                let sy = min(Float(ch - 1), max(0, Float(y - y0) - move.y * w))
                let ix = min(cw - 2, Int(sx)), iy = min(ch - 2, Int(sy))
                guard ix >= 0, iy >= 0 else { continue }
                let fx = sx - Float(ix), fy = sy - Float(iy)
                let p = (y * width + x) * 4
                let s00 = (iy * cw + ix) * 4, s10 = s00 + 4, s01 = s00 + cw * 4, s11 = s01 + 4
                for k in 0..<4 {
                    let top = scratch[s00 + k] + (scratch[s10 + k] - scratch[s00 + k]) * fx
                    let bottom = scratch[s01 + k] + (scratch[s11 + k] - scratch[s01 + k]) * fx
                    pixels[p + k] = UInt8(max(0, min(255, (top + (bottom - top) * fy).rounded())))
                }
            }
        }
    }
}

struct CTHealingJob: Sendable {
    let original: [UInt8]
    let coverage: [UInt8]
    let width: Int
    let height: Int
    let opacity: Float
    var backend = "miganHeal"
    func repairedImage() throws -> CGImage {
        try MIGANInpainting.run(original:original,coverage:coverage,width:width,height:height,
            opacity:opacity,backend:backend)
    }
    func run() -> CGImage? { try? repairedImage() }
}
