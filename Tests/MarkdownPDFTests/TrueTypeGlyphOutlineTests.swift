import Foundation
@testable import MarkdownPDF
import Testing

/// TrueType glyph outlines read from `glyf` and `loca` bytes built here by hand from the table layout of the OpenType specification. Every
/// expected path is written out: the quadratic curves become the cubic curves PDF draws, the implied on-curve points are the midpoints.
@Suite("TrueType glyph outlines")
struct TrueTypeGlyphOutlineTests {
    typealias Point = TrueTypeGlyphOutline.Point
    typealias Segment = TrueTypeGlyphOutline.Segment

    // MARK: - Byte builders

    private func u16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func i16(_ value: Int) -> [UInt8] {
        u16(value & 0xFFFF)
    }

    private func header(contours: Int) -> [UInt8] {
        i16(contours) + i16(0) + i16(0) + i16(100) + i16(100)
    }

    /// A simple glyph with every coordinate as a two-byte delta (no short vectors, no repeats): flags 0x01 on-curve or 0x00 off-curve.
    private func simpleGlyph(contours: [[(x: Int, y: Int, on: Bool)]]) -> [UInt8] {
        var ends: [UInt8] = []
        var count = 0
        for contour in contours {
            count += contour.count
            ends += u16(count - 1)
        }
        let points = contours.flatMap(\.self)
        var bytes = header(contours: contours.count) + ends + u16(0) // no instructions
        bytes += points.map { $0.on ? UInt8(0x01) : 0x00 }
        var previous = 0
        for point in points {
            bytes += i16(point.x - previous)
            previous = point.x
        }
        previous = 0
        for point in points {
            bytes += i16(point.y - previous)
            previous = point.y
        }
        return bytes
    }

    /// The glyph table and the long `loca` of glyphs given in order (each padded to four bytes).
    private func font(_ glyphs: [[UInt8]]) -> TrueTypeGlyphOutline {
        var glyf: [UInt8] = []
        var offsets = [0]
        for glyph in glyphs {
            glyf += glyph
            while glyf.count % 4 != 0 {
                glyf.append(0)
            }
            offsets.append(glyf.count)
        }
        let loca = offsets.flatMap { [UInt8(($0 >> 24) & 0xFF), UInt8(($0 >> 16) & 0xFF), UInt8(($0 >> 8) & 0xFF), UInt8($0 & 0xFF)] }
        return TrueTypeGlyphOutline(glyf: glyf, loca: loca, longOffsets: true, glyphCount: glyphs.count)
    }

    private func pt(_ x: Double, _ y: Double) -> Point {
        Point(x: x, y: y)
    }

    // MARK: - Simple glyphs

    @Test("a triangle of on-curve points is a move, two lines and a close")
    func triangle() throws {
        let glyph = font([simpleGlyph(contours: [[(0, 0, true), (100, 0, true), (50, 80, true)]])])
        #expect(try glyph.segments(forGlyph: 0) == [.move(pt(0, 0)), .line(pt(100, 0)), .line(pt(50, 80)), .close])
    }

    @Test("an off-curve point is the control point of a quadratic curve, written as the cubic with the control points two thirds along")
    func quadratic() throws {
        // (0,0) on, (30,60) off, (60,0) on: Q0=(0,0) Q1=(30,60) Q2=(60,0): C1 = Q0 + 2/3 (Q1-Q0) = (20,40), C2 = Q2 + 2/3 (Q1-Q2) = (40,40).
        let glyph = font([simpleGlyph(contours: [[(0, 0, true), (30, 60, false), (60, 0, true)]])])
        #expect(try glyph.segments(forGlyph: 0) == [.move(pt(0, 0)), .curve(pt(20, 40), pt(40, 40), pt(60, 0)), .close])
    }

    @Test("two off-curve points in a row imply an on-curve point at their midpoint")
    func impliedPoint() throws {
        // (0,0) on, (0,60) off, (60,60) off, (60,0) on: the implied point is (30,60).
        let glyph = font([simpleGlyph(contours: [[(0, 0, true), (0, 60, false), (60, 60, false), (60, 0, true)]])])
        #expect(try glyph.segments(forGlyph: 0) == [
            .move(pt(0, 0)),
            .curve(pt(0, 40), pt(10, 60), pt(30, 60)),
            .curve(pt(50, 60), pt(60, 40), pt(60, 0)),
            .close,
        ])
    }

    @Test("a contour that begins with an off-curve point starts at the last point when that one is on the curve")
    func startsOffCurve() throws {
        // (30,60) off, (60,0) on, (0,0) on: start at the last point (0,0); the first point is the control of the closing curve.
        let glyph = font([simpleGlyph(contours: [[(30, 60, false), (60, 0, true), (0, 0, true)]])])
        #expect(try glyph.segments(forGlyph: 0) == [.move(pt(0, 0)), .curve(pt(20, 40), pt(40, 40), pt(60, 0)), .close])
    }

    @Test("a contour of off-curve points only starts at the midpoint of its first and last points")
    func allOffCurve() throws {
        // A circle-like contour of four off-curve points at the corners of a square (0,0) (60,0) (60,60) (0,60).
        let glyph = font([simpleGlyph(contours: [[(0, 0, false), (60, 0, false), (60, 60, false), (0, 60, false)]])])
        let segments = try glyph.segments(forGlyph: 0)
        #expect(segments.first == .move(pt(0, 30)))
        #expect(segments.count == 6 && segments.last == .close)
        // Each curve ends at a midpoint of two neighbouring corners.
        let ends = segments.compactMap { segment -> Point? in
            if case let .curve(_, _, end) = segment {
                end
            } else {
                nil
            }
        }
        #expect(ends == [pt(30, 0), pt(60, 30), pt(30, 60), pt(0, 30)])
    }

    @Test("two contours are two closed paths, in order")
    func twoContours() throws {
        let glyph = font([simpleGlyph(contours: [
            [(0, 0, true), (10, 0, true), (10, 10, true)],
            [(20, 20, true), (30, 20, true), (30, 30, true)],
        ])])
        #expect(try glyph.segments(forGlyph: 0) == [
            .move(pt(0, 0)), .line(pt(10, 0)), .line(pt(10, 10)), .close,
            .move(pt(20, 20)), .line(pt(30, 20)), .line(pt(30, 30)), .close,
        ])
    }

    @Test("short vectors and repeated flags decode to the same points as two-byte deltas")
    func shortVectorsAndRepeats() throws {
        // Three on-curve points (0,0) (10,0) (10,10) with flags: on+xShort+xPositive (0x01|0x02|0x10) for x, y short too.
        // Point 1 (0,0): x delta 0 -> "same" (0x10 without short), y delta 0 -> "same" (0x20 without short): flag 0x01|0x10|0x20 = 0x31.
        // Point 2 (10,0): x delta +10 short positive (0x01|0x02|0x10 = 0x13), y delta 0 same (0x20): 0x33. Point 3 (10,10): x same (0x10), y short positive
        // (0x04|0x20): 0x01|0x10|0x04|0x20 = 0x35. The flags of points 1 and 2 are not equal, so the repeat flag is shown on a pair of equal flags below.
        var bytes = header(contours: 1) + u16(2) + u16(0)
        bytes += [0x31, 0x33, 0x35]
        bytes += [10] // x of point 2 (point 1 and point 3 have "same")
        bytes += [10] // y of point 3
        let glyph = font([bytes])
        #expect(try glyph.segments(forGlyph: 0) == [.move(pt(0, 0)), .line(pt(10, 0)), .line(pt(10, 10)), .close])
        // A repeat: flag 0x33 (on-curve, x short and positive, y the same) with the repeat bit 0x08 and a count of 2 covers three points; the
        // x deltas are three bytes of 10: the points are (10,0) (20,0) (30,0).
        var repeated = header(contours: 1) + u16(2) + u16(0)
        repeated += [0x3B, 2] + [10, 10, 10]
        let spread = font([repeated])
        #expect(try spread.segments(forGlyph: 0) == [.move(pt(10, 0)), .line(pt(20, 0)), .line(pt(30, 0)), .close])
    }

    // MARK: - Empty and composite glyphs

    @Test("a glyph with no outline (equal loca offsets) has no segments")
    func emptyGlyph() throws {
        let glyph = font([[], simpleGlyph(contours: [[(0, 0, true), (10, 0, true), (10, 10, true)]])])
        #expect(try glyph.segments(forGlyph: 0).isEmpty)
        #expect(try glyph.segments(forGlyph: 1).count == 4)
    }

    @Test("a composite glyph places its component at an offset, scaled when the component says so")
    func composite() throws {
        let base = simpleGlyph(contours: [[(0, 0, true), (10, 0, true), (10, 10, true)]])
        // Flags: ARG_1_AND_2_ARE_WORDS (0x0001) | ARGS_ARE_XY_VALUES (0x0002); component glyph 0, offset (100, 200); no more components.
        let placed = header(contours: -1) + u16(0x0003) + u16(0) + i16(100) + i16(200)
        // Same with WE_HAVE_A_SCALE (0x0008): scale 2.0 in 2.14 fixed point is 0x8000 (= -2.0 signed!), so use 0.5 = 0x2000.
        let scaled = header(contours: -1) + u16(0x000B) + u16(0) + i16(100) + i16(200) + u16(0x2000)
        let glyph = font([base, placed, scaled])
        #expect(try glyph.segments(forGlyph: 1) == [.move(pt(100, 200)), .line(pt(110, 200)), .line(pt(110, 210)), .close])
        #expect(try glyph.segments(forGlyph: 2) == [.move(pt(100, 200)), .line(pt(105, 200)), .line(pt(105, 205)), .close])
    }

    @Test("a composite of two components draws both, in order")
    func compositeTwo() throws {
        let base = simpleGlyph(contours: [[(0, 0, true), (10, 0, true), (10, 10, true)]])
        // First component with MORE_COMPONENTS (0x0020): flags 0x0023, second 0x0003.
        let two = header(contours: -1) + u16(0x0023) + u16(0) + i16(0) + i16(0) + u16(0x0003) + u16(0) + i16(50) + i16(50)
        let glyph = font([base, two])
        let segments = try glyph.segments(forGlyph: 1)
        #expect(segments.count == 8 && segments[0] == .move(pt(0, 0)) && segments[4] == .move(pt(50, 50)))
    }

    // MARK: - Malformed

    @Test("every malformed outline is refused, never read as something else", arguments: [0, 1, 2, 3, 4] as [Int])
    func malformed(kind: Int) {
        var outline: TrueTypeGlyphOutline = switch kind {
        case 0: font([Array(simpleGlyph(contours: [[(0, 0, true), (10, 0, true), (10, 10, true)]]).prefix(14))]) // cut inside the points
        case 1: font([header(contours: -1) + u16(0x0003) + u16(7) + i16(0) + i16(0)]) // component glyph 7 does not exist
        case 2: font([header(contours: -1) + u16(0x0001) + u16(0) + i16(0) + i16(0)]) // point matching is not supported
        case 3: font([header(contours: -1) + u16(0x0003) + u16(0) + i16(0)]) // composite cut short
        default: font([header(contours: -1) + u16(0x0003) + u16(0) + i16(0) + i16(0)]) // a composite that includes itself
        }
        #expect(throws: (any Error).self) { try outline.segments(forGlyph: 0) }
    }

    @Test("a glyph index beyond the font is refused")
    func outOfRange() {
        let glyph = font([simpleGlyph(contours: [[(0, 0, true), (10, 0, true), (10, 10, true)]])])
        #expect(throws: (any Error).self) { try glyph.segments(forGlyph: 5) }
    }
}
