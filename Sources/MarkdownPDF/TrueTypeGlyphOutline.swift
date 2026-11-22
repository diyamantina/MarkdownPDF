import Foundation

/// The outlines of the glyphs of a TrueType (`glyf`) font as PDF paths: moves, lines and cubic curves. A quadratic curve of the font (an off-curve
/// control point) becomes the cubic curve with the same shape, its control points two thirds of the way to the quadratic control point; two
/// off-curve points in a row imply an on-curve point at their midpoint. A composite glyph is its components placed by their offsets and scales.
/// Coordinates are font units, y up, like PDF's.
struct TrueTypeGlyphOutline {
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    enum Segment: Equatable {
        case move(Point)
        case line(Point)
        case curve(Point, Point, Point)
        case close
    }

    enum OutlineError: Error, Equatable {
        case glyphOutOfRange(UInt16)
        case unsupportedComposite(reason: String)
        case malformed(reason: String)
    }

    private let glyf: [UInt8]
    private let offsets: [Int]

    /// `loca` is the index to location table: `glyphCount + 1` offsets, four bytes each when `longOffsets`, else two bytes holding half the offset.
    init(glyf: [UInt8], loca: [UInt8], longOffsets: Bool, glyphCount: Int) {
        self.glyf = glyf
        let reader = TrueTypeByteReader(table: "loca", bytes: loca)
        var offsets: [Int] = []
        for index in 0 ... glyphCount {
            if longOffsets, let value = try? reader.uint32(at: index * 4) {
                offsets.append(Int(value))
            } else if !longOffsets, let value = try? reader.uint16(at: index * 2) {
                offsets.append(Int(value) * 2)
            } else {
                break
            }
        }
        self.offsets = offsets
    }

    private var glyphCount: Int {
        max(offsets.count - 1, 0)
    }

    /// The path of a glyph, empty for a glyph with no outline (a space).
    func segments(forGlyph glyph: UInt16) throws -> [Segment] {
        try segments(forGlyph: glyph, depth: 0)
    }

    private func segments(forGlyph glyph: UInt16, depth: Int) throws -> [Segment] {
        guard depth < 8 else { throw OutlineError.unsupportedComposite(reason: "components nest too deeply") }
        guard Int(glyph) < glyphCount else { throw OutlineError.glyphOutOfRange(glyph) }
        let start = offsets[Int(glyph)]
        let end = offsets[Int(glyph) + 1]
        if end <= start {
            return []
        }
        let reader = TrueTypeByteReader(table: "glyf", bytes: glyf)
        try reader.requireRange(offset: start, count: end - start)
        let contours = try Int(reader.int16(at: start))
        if contours >= 0 {
            return try simple(reader: reader, at: start + 10, contours: contours)
        }
        return try composite(reader: reader, at: start + 10, depth: depth)
    }

    // MARK: - Simple glyphs

    private struct OutlinePoint {
        var x: Double
        var y: Double
        var onCurve: Bool
    }

    private func simple(reader: TrueTypeByteReader, at start: Int, contours: Int) throws -> [Segment] {
        var offset = start
        var ends: [Int] = []
        for _ in 0 ..< contours {
            try ends.append(Int(reader.uint16(at: offset)))
            offset += 2
        }
        guard let last = ends.last else { return [] }
        let pointCount = last + 1
        let instructionLength = try Int(reader.uint16(at: offset))
        offset += 2 + instructionLength
        var flags: [UInt8] = []
        while flags.count < pointCount {
            let flag = try reader.uint8(at: offset)
            offset += 1
            flags.append(flag)
            if flag & 0x08 != 0 {
                let repeats = try Int(reader.uint8(at: offset))
                offset += 1
                for _ in 0 ..< repeats where flags.count < pointCount {
                    flags.append(flag)
                }
            }
        }
        func coordinates(short: UInt8, sameOrPositive: UInt8) throws -> [Double] {
            var values: [Double] = []
            var current = 0
            for flag in flags {
                if flag & short != 0 {
                    let delta = try Int(reader.uint8(at: offset))
                    offset += 1
                    current += flag & sameOrPositive != 0 ? delta : -delta
                } else if flag & sameOrPositive == 0 {
                    current += try Int(reader.int16(at: offset))
                    offset += 2
                }
                values.append(Double(current))
            }
            return values
        }
        let xs = try coordinates(short: 0x02, sameOrPositive: 0x10)
        let ys = try coordinates(short: 0x04, sameOrPositive: 0x20)
        var segments: [Segment] = []
        var first = 0
        for end in ends {
            guard end >= first, end < pointCount else { throw OutlineError.malformed(reason: "contour ends are not ascending") }
            let contour = (first ... end).map { OutlinePoint(x: xs[$0], y: ys[$0], onCurve: flags[$0] & 0x01 != 0) }
            segments += Self.path(of: contour)
            first = end + 1
        }
        return segments
    }

    /// One closed contour as a path. The contour starts at its first point when that is on the curve, else at its last point when that is on the
    /// curve, else at the midpoint of the two; the return to the start is the closing of the path (a closing curve when a control point is left).
    private static func path(of contour: [OutlinePoint]) -> [Segment] {
        guard contour.count >= 2 else { return [] }
        var points = contour
        if !points[0].onCurve {
            if let last = points.last, last.onCurve {
                points.insert(points.removeLast(), at: 0)
            } else {
                let a = points[0]
                let b = points[points.count - 1]
                points.insert(OutlinePoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, onCurve: true), at: 0)
            }
        }
        let begin = Point(x: points[0].x, y: points[0].y)
        var segments: [Segment] = [.move(begin)]
        var current = begin
        var control: Point?
        func quadratic(to end: Point, control c: Point) {
            segments.append(.curve(
                Point(x: current.x + 2.0 / 3.0 * (c.x - current.x), y: current.y + 2.0 / 3.0 * (c.y - current.y)),
                Point(x: end.x + 2.0 / 3.0 * (c.x - end.x), y: end.y + 2.0 / 3.0 * (c.y - end.y)),
                end,
            ))
            current = end
        }
        for point in points.dropFirst() {
            let here = Point(x: point.x, y: point.y)
            if point.onCurve {
                if let c = control {
                    quadratic(to: here, control: c)
                    control = nil
                } else if here != current {
                    segments.append(.line(here))
                    current = here
                }
            } else if let c = control {
                quadratic(to: Point(x: (c.x + here.x) / 2, y: (c.y + here.y) / 2), control: c)
                control = here
            } else {
                control = here
            }
        }
        if let c = control {
            quadratic(to: begin, control: c)
        }
        segments.append(.close)
        return segments
    }

    // MARK: - Composite glyphs

    private func composite(reader: TrueTypeByteReader, at start: Int, depth: Int) throws -> [Segment] {
        var offset = start
        var segments: [Segment] = []
        while true {
            let flags = try reader.uint16(at: offset)
            let component = try reader.uint16(at: offset + 2)
            offset += 4
            guard flags & 0x0002 != 0 else {
                throw OutlineError.unsupportedComposite(reason: "a component placed by point matching")
            }
            let dx: Int
            let dy: Int
            if flags & 0x0001 != 0 {
                dx = try Int(reader.int16(at: offset))
                dy = try Int(reader.int16(at: offset + 2))
                offset += 4
            } else {
                dx = try Int(Int8(bitPattern: reader.uint8(at: offset)))
                dy = try Int(Int8(bitPattern: reader.uint8(at: offset + 1)))
                offset += 2
            }
            var a = 1.0, b = 0.0, c = 0.0, d = 1.0
            func fixed(_ at: Int) throws -> Double {
                try Double(reader.int16(at: at)) / 16384
            }
            if flags & 0x0008 != 0 {
                a = try fixed(offset)
                d = a
                offset += 2
            } else if flags & 0x0040 != 0 {
                a = try fixed(offset)
                d = try fixed(offset + 2)
                offset += 4
            } else if flags & 0x0080 != 0 {
                a = try fixed(offset)
                b = try fixed(offset + 2)
                c = try fixed(offset + 4)
                d = try fixed(offset + 6)
                offset += 8
            }
            func move(_ point: Point) -> Point {
                Point(x: a * point.x + c * point.y + Double(dx), y: b * point.x + d * point.y + Double(dy))
            }
            for segment in try self.segments(forGlyph: component, depth: depth + 1) {
                switch segment {
                case let .move(p): segments.append(.move(move(p)))
                case let .line(p): segments.append(.line(move(p)))
                case let .curve(p1, p2, p3): segments.append(.curve(move(p1), move(p2), move(p3)))
                case .close: segments.append(.close)
                }
            }
            if flags & 0x0020 == 0 {
                return segments
            }
        }
    }
}
