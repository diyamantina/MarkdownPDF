import Foundation

/// Rewrites a Type 2 charstring so it calls no subroutines: every `callsubr` and
/// `callgsubr` is replaced by the (recursively desubroutinized) body of the subroutine it
/// names, and the trailing `return` is dropped. The result draws the identical outline
/// but is self-contained, so a subset font can omit the global and local subroutine
/// INDEXes entirely, which is where a CID-keyed CJK font spends most of its non-outline
/// weight and avoids the subroutine renumbering a compacting subset would otherwise need.
///
/// Derived from the Adobe Type 2 Charstring Format (Adobe Tech Note 5177). The operand
/// stack is tracked only enough to read a `callsubr`/`callgsubr` index and to count stem
/// hints, so `hintmask`/`cntrmask` consume the right number of mask bytes; outline
/// operators are copied through verbatim.
struct CFFCharstringDesubroutinizer {
    enum DesubroutinizeError: Error, Equatable {
        case malformed(reason: String)
    }

    private let globalSubrs: [[UInt8]]
    private let localSubrs: [[UInt8]]
    private let globalBias: Int
    private let localBias: Int
    /// Type 2 caps subroutine nesting at 10; allow a little slack and reject beyond it so
    /// a cyclic or adversarial font cannot recurse without bound.
    private static let maxDepth = 60

    init(globalSubrs: [[UInt8]], localSubrs: [[UInt8]]) {
        self.globalSubrs = globalSubrs
        self.localSubrs = localSubrs
        globalBias = Self.bias(count: globalSubrs.count)
        localBias = Self.bias(count: localSubrs.count)
    }

    /// The subroutine-number bias (Type 2 §4.7): the value added to the operand to index
    /// the subroutine INDEX.
    static func bias(count: Int) -> Int {
        if count < 1240 {
            107
        } else if count < 33900 {
            1131
        } else {
            32768
        }
    }

    /// The mirrored Type 2 operand stack, shared across subroutine frames: each pending
    /// number operand's encoded bytes, and its integer value when it has one (a 16.16
    /// fixed operand carries nil; it can never name a subroutine). The stack must be
    /// shared because a subroutine's stem hints may consume operands its caller pushed,
    /// and a subroutine may leave operands (including a further subroutine index) for
    /// its caller; tracking it per frame miscounts hints, which desynchronizes
    /// `hintmask` mask bytes and silently corrupts the rewritten charstring.
    private struct PendingOperands {
        var bytes: [[UInt8]] = []
        var values: [Int?] = []

        mutating func push(_ encoded: [UInt8], _ value: Int?) {
            bytes.append(encoded)
            values.append(value)
        }

        mutating func flush(into output: inout [UInt8]) {
            for encoded in bytes {
                output.append(contentsOf: encoded)
            }
            bytes.removeAll(keepingCapacity: true)
            values.removeAll(keepingCapacity: true)
        }
    }

    /// The charstring with all subroutine calls inlined. Throws on a malformed charstring
    /// (truncated operand, out-of-range subroutine, excessive nesting) rather than trapping.
    func desubroutinize(_ charstring: [UInt8]) throws -> [UInt8] {
        var output: [UInt8] = []
        var hintCount = 0
        var pending = PendingOperands()
        try expand(charstring, into: &output, hintCount: &hintCount, pending: &pending, depth: 0)
        // Trailing operands with no operator to consume them (malformed but harmless):
        // preserve the bytes rather than dropping them.
        pending.flush(into: &output)
        return output
    }

    private func expand(
        _ charstring: [UInt8],
        into output: inout [UInt8],
        hintCount: inout Int,
        pending: inout PendingOperands,
        depth: Int,
    ) throws {
        guard depth < Self.maxDepth else {
            throw DesubroutinizeError.malformed(reason: "subroutine nesting exceeds \(Self.maxDepth)")
        }
        var cursor = 0
        while cursor < charstring.count {
            let byte = charstring[cursor]
            switch byte {
            case 28: // shortint: 3 bytes, signed 16-bit
                guard cursor + 3 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated shortint operand")
                }
                let value = Int(Int16(bitPattern: UInt16(charstring[cursor + 1]) << 8 | UInt16(charstring[cursor + 2])))
                pending.push(Array(charstring[cursor ..< cursor + 3]), value)
                cursor += 3
            case 255: // 16.16 fixed: 5 bytes; never a valid subroutine index
                guard cursor + 5 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated fixed operand")
                }
                pending.push(Array(charstring[cursor ..< cursor + 5]), nil)
                cursor += 5
            case 32 ... 246:
                pending.push([byte], Int(byte) - 139)
                cursor += 1
            case 247 ... 250:
                guard cursor + 2 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated operand")
                }
                pending.push(Array(charstring[cursor ..< cursor + 2]), (Int(byte) - 247) * 256 + Int(charstring[cursor + 1]) + 108)
                cursor += 2
            case 251 ... 254:
                guard cursor + 2 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated operand")
                }
                pending.push(Array(charstring[cursor ..< cursor + 2]), -(Int(byte) - 251) * 256 - Int(charstring[cursor + 1]) - 108)
                cursor += 2
            case 10, 29: // callsubr / callgsubr
                // The call consumes only the top-of-stack index; the operands beneath it
                // stay pending, because the subroutine's own operators (a stem
                // declaration, a further call) may consume them.
                guard let top = pending.values.last else {
                    throw DesubroutinizeError.malformed(reason: "subroutine call with empty stack")
                }
                guard let index = top else {
                    throw DesubroutinizeError.malformed(reason: "subroutine index is not an integer")
                }
                pending.bytes.removeLast()
                pending.values.removeLast()
                let subrs = byte == 10 ? localSubrs : globalSubrs
                let bias = byte == 10 ? localBias : globalBias
                let subrIndex = index + bias
                guard subrs.indices.contains(subrIndex) else {
                    throw DesubroutinizeError.malformed(reason: "subroutine index \(subrIndex) out of range")
                }
                try expand(subrs[subrIndex], into: &output, hintCount: &hintCount, pending: &pending, depth: depth + 1)
                cursor += 1
            case 11: // return: end of a subroutine body
                // Operands the subroutine leaves on the stack (possibly a subroutine
                // index for a caller's later call) belong to the caller, so leave them
                // pending rather than flushing or dropping them.
                return
            case 1, 3, 18, 23: // hstem, vstem, hstemhm, vstemhm
                hintCount += pending.values.count / 2
                pending.flush(into: &output)
                output.append(byte)
                cursor += 1
            case 19, 20: // hintmask, cntrmask
                // Operands preceding a mask are an implicit vstem hint declaration.
                hintCount += pending.values.count / 2
                pending.flush(into: &output)
                output.append(byte)
                cursor += 1
                let maskBytes = (hintCount + 7) / 8
                guard cursor + maskBytes <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated hint mask")
                }
                output.append(contentsOf: charstring[cursor ..< cursor + maskBytes])
                cursor += maskBytes
            case 12: // escape: two-byte operator (flex family, arithmetic)
                guard cursor + 2 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated escape operator")
                }
                pending.flush(into: &output)
                output.append(byte)
                output.append(charstring[cursor + 1])
                cursor += 2
            default: // endchar (14) and outline operators (moveto/lineto/curveto)
                pending.flush(into: &output)
                output.append(byte)
                cursor += 1
            }
        }
        // A subroutine body may end without an explicit `return`; whatever it leaves
        // pending still belongs to the caller, so simply unwind.
    }
}
