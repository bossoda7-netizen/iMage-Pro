// Adapted from robbietilton/Compositor (MIT), revision 11d8d7a.
// Copyright (c) 2026 Wonder Assembly LLC. See ThirdParty/Compositor/LICENSE.
import Foundation
import CoreGraphics
struct CTPlacement: Equatable, Codable, Sendable {
    var origin: CGPoint
    var size: CGSize
    var rotation: CGFloat = 0
    var flipX = false
    var flipY = false
    var center: CGPoint { CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2) }
    var radians: CGFloat { rotation.truncatingRemainder(dividingBy: 360) * .pi / 180 }
    var isValid: Bool {
        [origin.x, origin.y, size.width, size.height, rotation].allSatisfy(\.isFinite)
            && (1...300_000).contains(size.width) && (1...300_000).contains(size.height)
            && abs(origin.x) <= 1_000_000 && abs(origin.y) <= 1_000_000
    }
    func point(_ unit: CGPoint) -> CGPoint {
        let x = (unit.x - 0.5) * size.width, y = (unit.y - 0.5) * size.height
        return CGPoint(x: center.x + x * cos(radians) - y * sin(radians),
                       y: center.y + x * sin(radians) + y * cos(radians))
    }
    func contains(_ point: CGPoint) -> Bool {
        let x = point.x - center.x, y = point.y - center.y
        return abs(x * cos(radians) + y * sin(radians)) <= size.width / 2
            && abs(-x * sin(radians) + y * cos(radians)) <= size.height / 2
    }
    /// Width as a percentage of the `pixelSize` it places (100% draws them 1:1).
    func scalePercent(pixelSize: CGSize) -> CGFloat { size.width / max(1, pixelSize.width) * 100 }
    /// Both sides set to `percent` of `pixelSize`, keeping the center (and rotation and flips).
    func scaled(toPercent percent: CGFloat, pixelSize: CGSize) -> CTPlacement {
        var result = self
        result.size = CGSize(width: pixelSize.width * percent / 100, height: pixelSize.height * percent / 100)
        result.origin = CGPoint(x: center.x - result.size.width / 2, y: center.y - result.size.height / 2)
        return result
    }
    /// Whole pixels and whole degrees: what dragging, scaling and rotating leave behind. Typed values are used
    /// as they are, so a fraction can still be asked for by hand.
    func rounded() -> CTPlacement {
        var result = self
        result.origin = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        result.size = CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
        result.rotation = rotation.rounded()
        return result
    }
    static let handles = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0),
                          CGPoint(x: 1, y: 0.5), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 1),
                          CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0.5)]
}
struct CTTransformDrag {
    enum Mode { case move, resize(Int), rotate, distort(Int) }
    let original: CTPlacement
    let start: CGPoint
    let mode: Mode
    /// The distortion's corners when the drag began; nil for an ordinary transform.
    var originalCorners: [CGPoint]? = nil

    /// Corners after dragging to `point`: a corner handle moves its corner, an edge handle both of
    /// that edge's corners, and the body the whole shape. Nil when the drag isn't distorting.
    func corners(to point: CGPoint, shift: Bool = false) -> [CGPoint]? {
        guard var result = originalCorners else { return nil }
        var dx = point.x - start.x, dy = point.y - start.y
        // Shift keeps what's being dragged on one axis.
        if shift {
            if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 }
        }
        let moved: [Int]
        switch mode {
        case .distort(let index): moved = index.isMultiple(of: 2) ? [index / 2] : [index / 2, (index / 2 + 1) % 4]
        case .move: moved = [0, 1, 2, 3]
        default: return nil
        }
        for corner in moved { result[corner].x += dx; result[corner].y += dy }
        return result
    }

    func updated(to point: CGPoint, lockRatio: Bool, shift: Bool, option: Bool = false) -> CTPlacement {
        var result = original
        switch mode {
        case .distort: break
        case .move:
            var dx = point.x - start.x, dy = point.y - start.y
            if shift {
                if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 }
            }
            result.origin.x += dx
            result.origin.y += dy
        case .rotate:
            let center = original.center
            let delta = atan2(point.y - center.y, point.x - center.x)
                - atan2(start.y - center.y, start.x - center.x)
            result.rotation += delta * 180 / .pi
            if shift { result.rotation = (result.rotation / 15).rounded() * 15 }
        case .resize(let index):
            let handle = CTPlacement.handles[index]
            let anchorUnit = option ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 1 - handle.x, y: 1 - handle.y)
            let anchor = original.point(anchorUnit)
            // Use the initial handle plus pointer delta to avoid a jump on grab.
            let initialHandle = original.point(handle)
            let dx = initialHandle.x + point.x - start.x - anchor.x
            let dy = initialHandle.y + point.y - start.y - anchor.y
            // Center-to-handle distances cover half the size on each axis.
            let span: CGFloat = option ? 2 : 1
            let localX = (dx * cos(original.radians) + dy * sin(original.radians)) * span
            let localY = (-dx * sin(original.radians) + dy * cos(original.radians)) * span
            let sx = handle.x * 2 - 1, sy = handle.y * 2 - 1
            // Dragging a handle past the opposite side turns the layer over rather than stopping at nothing:
            // the size stays positive and the layer is flipped on that axis, as a negative scale would.
            let rawWidth = sx == 0 ? original.size.width : localX * sx
            let rawHeight = sy == 0 ? original.size.height : localY * sy
            let mirroredX = rawWidth < 0, mirroredY = rawHeight < 0
            var width = max(1, abs(rawWidth))
            var height = max(1, abs(rawHeight))
            if lockRatio != shift {
                let factor: CGFloat
                if sx == 0 { factor = height / original.size.height }
                else if sy == 0 { factor = width / original.size.width }
                else {
                    // Project onto the original diagonal for proportional scaling.
                    factor = max(1 / min(original.size.width, original.size.height),
                        (localX * sx * original.size.width + localY * sy * original.size.height)
                        / (original.size.width * original.size.width + original.size.height * original.size.height))
                }
                width = original.size.width * factor
                height = original.size.height * factor
            }
            result.size = CGSize(width: width, height: height)
            if mirroredX { result.flipX.toggle() }
            if mirroredY { result.flipY.toggle() }
            // Turned over, the box lies on the other side of the anchor.
            let offsetX = (0.5 - anchorUnit.x) * width * (mirroredX ? -1 : 1)
            let offsetY = (0.5 - anchorUnit.y) * height * (mirroredY ? -1 : 1)
            let center = CGPoint(x: anchor.x + offsetX * cos(original.radians) - offsetY * sin(original.radians),
                                 y: anchor.y + offsetX * sin(original.radians) + offsetY * cos(original.radians))
            result.origin = CGPoint(x: center.x - width / 2, y: center.y - height / 2)
        }
        return result.isValid ? result : original
    }
}

/// Moving a layer snaps its edges and center to the canvas and to the other layers. The pull is a fixed distance
/// on screen, so it feels the same at any zoom, and small enough to slide past without a fight.
enum CTTransformSnap {
    /// How close, in screen points, a guide comes before it snaps.
    static let distance: CGFloat = 10

    /// `box` moved so that whichever of its left, center or right lands nearest an `xs` target does, and the same
    /// vertically — each axis on its own, and only within `tolerance` document pixels. The targets it landed on
    /// come back too, to draw a line along.
    static func offset(for box: CGRect, xs: [CGFloat], ys: [CGFloat],
                       tolerance: CGFloat) -> (offset: CGSize, x: CGFloat?, y: CGFloat?) {
        let horizontal = shift([box.minX, box.midX, box.maxX], to: xs, tolerance: tolerance)
        let vertical = shift([box.minY, box.midY, box.maxY], to: ys, tolerance: tolerance)
        return (CGSize(width: horizontal.move, height: vertical.move), horizontal.target, vertical.target)
    }
    /// The smallest move that puts one of `guides` on one of `targets`, and the target it met.
    private static func shift(_ guides: [CGFloat], to targets: [CGFloat],
                              tolerance: CGFloat) -> (move: CGFloat, target: CGFloat?) {
        var best: (move: CGFloat, target: CGFloat)?
        for guideValue in guides {
            for target in targets {
                let move = target - guideValue
                guard abs(move) <= tolerance else { continue }
                if let current = best, abs(current.move) <= abs(move) { continue }
                best = (move, target)
            }
        }
        return (best?.move ?? 0, best?.target)
    }
}

enum CTCropGeometry {
    /// Nearest control point first, then an edge; radius is independent of zoom.
    static func handle(at point:CGPoint,in rect:CGRect,scale:CGFloat) -> Int? {
        let radius = 16 / max(0.0001,scale)
        if let nearest = CTPlacement.handles.indices.min(by:{a,b in
            let p = CTPlacement.handles[a],q = CTPlacement.handles[b]
            return hypot(point.x-rect.minX-p.x*rect.width,point.y-rect.minY-p.y*rect.height)
                < hypot(point.x-rect.minX-q.x*rect.width,point.y-rect.minY-q.y*rect.height)
        }) {
            let p = CTPlacement.handles[nearest]
            if hypot(point.x-rect.minX-p.x*rect.width,point.y-rect.minY-p.y*rect.height) <= radius {return nearest}
        }
        if point.x >= rect.minX,point.x <= rect.maxX {
            if abs(point.y-rect.minY)<=radius {return 1}
            if abs(point.y-rect.maxY)<=radius {return 5}
        }
        if point.y >= rect.minY,point.y <= rect.maxY {
            if abs(point.x-rect.maxX)<=radius {return 3}
            if abs(point.x-rect.minX)<=radius {return 7}
        }
        return nil
    }
    static func snapped(_ rect: CGRect) -> CGRect {
        let rect = rect.standardized
        let x = rect.minX.rounded(), y = rect.minY.rounded()
        return CGRect(x: x, y: y, width: max(1, rect.maxX.rounded() - x), height: max(1, rect.maxY.rounded() - y))
    }
    static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && (1...300_000).contains(rect.width) && (1...300_000).contains(rect.height)
            && abs(rect.minX) <= 1_000_000 && abs(rect.minY) <= 1_000_000
    }
    /// A frame dragged from `start` to `end` — or, `symmetric` (Option), grown out from `start` as its center.
    static func create(from start: CGPoint, to end: CGPoint, ratio: CGFloat?, symmetric: Bool = false) -> CGRect {
        var dx = end.x - start.x, dy = end.y - start.y
        if let ratio {
            if abs(dx) > abs(dy) * ratio { dy = (dy < 0 ? -1 : 1) * abs(dx) / ratio }
            else { dx = (dx < 0 ? -1 : 1) * abs(dy) * ratio }
        }
        if symmetric {
            return snapped(CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2))
        }
        return snapped(CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy)))
    }
}

struct CTCropDrag {
    enum Mode { case create, move, resize(Int) }
    let start: CGPoint
    let original: CGRect
    let mode: Mode
    /// `symmetric` (Option held) keeps the frame's center fixed: the opposite edges move with the dragged ones.
    func updated(to point: CGPoint, ratio: CGFloat?, symmetric: Bool = false) -> CGRect {
        switch mode {
        case .create: return CTCropGeometry.create(from: start, to: point, ratio: ratio, symmetric: symmetric)
        case .move: return CTCropGeometry.snapped(original.offsetBy(dx: point.x - start.x, dy: point.y - start.y))
        case .resize(let index):
            let transform = CTPlacement(origin: original.origin, size: original.size)
            let drag = CTTransformDrag(original: transform, start: start, mode: .resize(index))
            let next = drag.updated(to: point, lockRatio: ratio != nil, shift: false, option: symmetric)
            return CTCropGeometry.snapped(CGRect(origin: next.origin, size: next.size))
        }
    }
}

/// Crop edges snap to nearby layer and canvas edges while dragging.
struct CTCropSnap {
    /// Document x and y positions to snap to.
    let xs: [CGFloat]
    let ys: [CGFloat]
    /// How close, in document pixels, an edge must come to snap.
    let tolerance: CGFloat

    private func nearest(_ value: CGFloat, in targets: [CGFloat]) -> CGFloat? {
        var best: CGFloat?
        for target in targets where abs(target - value) <= tolerance {
            if let current = best, abs(current - value) <= abs(target - value) { continue }
            best = target
        }
        return best
    }

    /// Moving the frame snaps its closest edges and keeps its size; creating or resizing snaps only the
    /// edges on the side being dragged — mirrored about the center when `symmetric`. With a fixed ratio only
    /// moves snap, so the ratio stays exact.
    func apply(_ rect: CGRect, drag: CTCropDrag, point: CGPoint, ratio: CGFloat?, symmetric: Bool = false) -> CGRect {
        guard tolerance > 0 else { return rect }
        let horizontal: Bool, vertical: Bool
        switch drag.mode {
        case .move:
            func shift(_ edges: [CGFloat], _ targets: [CGFloat]) -> CGFloat {
                edges.compactMap { edge in nearest(edge, in: targets).map { $0 - edge } }.min { abs($0) < abs($1) } ?? 0
            }
            return rect.offsetBy(dx: shift([rect.minX, rect.maxX], xs), dy: shift([rect.minY, rect.maxY], ys))
        case .create:
            guard ratio == nil else { return rect }
            horizontal = true; vertical = true
        case .resize(let index):
            guard ratio == nil else { return rect }
            let handle = CTPlacement.handles[index]
            horizontal = handle.x != 0.5; vertical = handle.y != 0.5
        }
        var result = rect
        // The dragged edge is the one on the pointer's side.
        if horizontal {
            if abs(point.x - result.minX) <= abs(point.x - result.maxX) {
                if let x = nearest(result.minX, in: xs), x < result.maxX { result = CGRect(x: x, y: result.minY, width: result.maxX - x, height: result.height) }
            } else if let x = nearest(result.maxX, in: xs), x > result.minX { result.size.width = x - result.minX }
        }
        if vertical {
            if abs(point.y - result.minY) <= abs(point.y - result.maxY) {
                if let y = nearest(result.minY, in: ys), y < result.maxY { result = CGRect(x: result.minX, y: y, width: result.width, height: result.maxY - y) }
            } else if let y = nearest(result.maxY, in: ys), y > result.minY { result.size.height = y - result.minY }
        }
        if symmetric {
            // The snapped (dragged) edge sets the half size; the opposite edge mirrors it about the center.
            var center = CGPoint(x: drag.original.midX, y: drag.original.midY)
            if case .create = drag.mode { center = drag.start }
            if horizontal {
                let half = point.x >= center.x ? result.maxX - center.x : center.x - result.minX
                if half >= 0.5 { result.origin.x = center.x - half; result.size.width = half * 2 }
            }
            if vertical {
                let half = point.y >= center.y ? result.maxY - center.y : center.y - result.minY
                if half >= 0.5 { result.origin.y = center.y - half; result.size.height = half * 2 }
            }
        }
        return result
    }
}
