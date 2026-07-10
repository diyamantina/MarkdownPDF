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

    /// The charstring with all subroutine calls inlined. Throws on a malformed charstring
    /// (truncated operand, out-of-range subroutine, excessive nesting) rather than trapping.
    func desubroutinize(_ charstring: [UInt8]) throws -> [UInt8] {
        var output: [UInt8] = []
        var hintCount = 0
        try expand(charstring, into: &output, hintCount: &hintCount, depth: 0)
        return output
    }

    private func expand(
        _ charstring: [UInt8],
        into output: inout [UInt8],
        hintCount: inout Int,
        depth: Int,
    ) throws {
        guard depth < Self.maxDepth else {
            throw DesubroutinizeError.malformed(reason: "subroutine nesting exceeds \(Self.maxDepth)")
        }
        // Pending number operands not yet emitted: their encoded bytes, and their integer
        // values (for a subroutine index). Cleared at every operator.
        var pendingBytes: [[UInt8]] = []
        var pendingValues: [Int] = []
        var cursor = 0

        func flushOperands() {
            for bytes in pendingBytes {
                output.append(contentsOf: bytes)
            }
            pendingBytes.removeAll(keepingCapacity: true)
            pendingValues.removeAll(keepingCapacity: true)
        }

        while cursor < charstring.count {
            let byte = charstring[cursor]
            switch byte {
            case 28: // shortint: 3 bytes, signed 16-bit
                guard cursor + 3 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated shortint operand")
                }
                let value = Int(Int16(bitPattern: UInt16(charstring[cursor + 1]) << 8 | UInt16(charstring[cursor + 2])))
                pendingBytes.append(Array(charstring[cursor ..< cursor + 3]))
                pendingValues.append(value)
                cursor += 3
            case 255: // 16.16 fixed: 5 bytes; never a subroutine index, value unused
                guard cursor + 5 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated fixed operand")
                }
                pendingBytes.append(Array(charstring[cursor ..< cursor + 5]))
                pendingValues.append(0)
                cursor += 5
            case 32 ... 246:
                pendingBytes.append([byte])
                pendingValues.append(Int(byte) - 139)
                cursor += 1
            case 247 ... 250:
                guard cursor + 2 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated operand")
                }
                pendingBytes.append(Array(charstring[cursor ..< cursor + 2]))
                pendingValues.append((Int(byte) - 247) * 256 + Int(charstring[cursor + 1]) + 108)
                cursor += 2
            case 251 ... 254:
                guard cursor + 2 <= charstring.count else {
                    throw DesubroutinizeError.malformed(reason: "truncated operand")
                }
                pendingBytes.append(Array(charstring[cursor ..< cursor + 2]))
                pendingValues.append(-(Int(byte) - 251) * 256 - Int(charstring[cursor + 1]) - 108)
                cursor += 2
            case 10, 29: // callsubr / callgsubr
                guard let index = pendingValues.last else {
                    throw DesubroutinizeError.malformed(reason: "subroutine call with empty stack")
                }
                // Emit every operand except the index (which the call consumes), then
                // inline the subroutine body in its place.
                for bytes in pendingBytes.dropLast() {
                    output.append(contentsOf: bytes)
                }
                pendingBytes.removeAll(keepingCapacity: true)
                pendingValues.removeAll(keepingCapacity: true)
                let subrs = byte == 10 ? localSubrs : globalSubrs
                let bias = byte == 10 ? localBias : globalBias
                let subrIndex = index + bias
                guard subrs.indices.contains(subrIndex) else {
                    throw DesubroutinizeError.malformed(reason: "subroutine index \(subrIndex) out of range")
                }
                try expand(subrs[subrIndex], into: &output, hintCount: &hintCount, depth: depth + 1)
                cursor += 1
            case 11: // return: end of a subroutine body
                // Operands the subroutine leaves on the stack belong to its caller, so
                // emit them before unwinding rather than dropping them.
                flushOperands()
                return
            case 1, 3, 18, 23: // hstem, vstem, hstemhm, vstemhm
                hintCount += pendingValues.count / 2
                flushOperands()
                output.append(byte)
                cursor += 1
            case 19, 20: // hintmask, cntrmask
                // Operands preceding a mask are an implicit vstem hint declaration.
                hintCount += pendingValues.count / 2
                flushOperands()
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
                flushOperands()
                output.append(byte)
                output.append(charstring[cursor + 1])
                cursor += 2
            default: // endchar (14) and outline operators (moveto/lineto/curveto)
                flushOperands()
                output.append(byte)
                cursor += 1
            }
        }
        // A subroutine body may end without an explicit `return`; its trailing operands
        // still belong to the caller's stack, so emit them before unwinding.
        flushOperands()
    }
}
