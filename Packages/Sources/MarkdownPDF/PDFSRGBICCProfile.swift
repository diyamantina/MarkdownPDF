import Foundation

enum PDFSRGBICCProfile {
    static let outputConditionIdentifier = "sRGB IEC61966-2.1"

    static var streamDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("N", .int(3)),
            .init("Alternate", .pdfName("DeviceRGB")),
        ])
    }

    static let data: Data = {
        var builder = ICCProfileBuilder()
        builder.addDescription("sRGB IEC61966-2.1")
        builder.addCopyright("Public domain synthetic sRGB-compatible profile")
        builder.addXYZTag("wtpt", x: 0.9642, y: 1.0, z: 0.8249)
        builder.addXYZTag("rXYZ", x: 0.4360747, y: 0.2225045, z: 0.0139322)
        builder.addXYZTag("gXYZ", x: 0.3850649, y: 0.7168786, z: 0.0971045)
        builder.addXYZTag("bXYZ", x: 0.1430804, y: 0.0606169, z: 0.7141733)
        builder.addCurveTag("rTRC", gamma: 2.2)
        builder.addCurveTag("gTRC", gamma: 2.2)
        builder.addCurveTag("bTRC", gamma: 2.2)
        return builder.data()
    }()

    private struct Tag {
        var signature: String
        var data: Data
    }

    private struct ICCProfileBuilder {
        private var tags: [Tag] = []

        mutating func addDescription(_ text: String) {
            var data = Data()
            data.appendSignature("desc")
            data.appendUInt32(0)
            let bytes = Array((text + "\0").utf8)
            data.appendUInt32(UInt32(bytes.count))
            data.append(contentsOf: bytes)
            data.padToFourByteBoundary()
            tags.append(Tag(signature: "desc", data: data))
        }

        mutating func addCopyright(_ text: String) {
            var data = Data()
            data.appendSignature("text")
            data.appendUInt32(0)
            data.append(contentsOf: Array((text + "\0").utf8))
            data.padToFourByteBoundary()
            tags.append(Tag(signature: "cprt", data: data))
        }

        mutating func addXYZTag(_ signature: String, x: Double, y: Double, z: Double) {
            var data = Data()
            data.appendSignature("XYZ ")
            data.appendUInt32(0)
            data.appendS15Fixed16(x)
            data.appendS15Fixed16(y)
            data.appendS15Fixed16(z)
            tags.append(Tag(signature: signature, data: data))
        }

        mutating func addCurveTag(_ signature: String, gamma: Double) {
            var data = Data()
            data.appendSignature("curv")
            data.appendUInt32(0)
            data.appendUInt32(1)
            data.appendUInt16(UInt16((gamma * 256).rounded()))
            data.appendUInt16(0)
            tags.append(Tag(signature: signature, data: data))
        }

        func data() -> Data {
            var tagData = Data()
            let tagTableSize = 4 + tags.count * 12
            var records: [(signature: String, offset: UInt32, size: UInt32)] = []
            var nextOffset = 128 + tagTableSize

            for tag in tags {
                records.append((
                    signature: tag.signature,
                    offset: UInt32(nextOffset),
                    size: UInt32(tag.data.count),
                ))
                tagData.append(tag.data)
                nextOffset += tag.data.count
            }

            var profile = header(size: UInt32(128 + tagTableSize + tagData.count))
            profile.appendUInt32(UInt32(tags.count))
            for record in records {
                profile.appendSignature(record.signature)
                profile.appendUInt32(record.offset)
                profile.appendUInt32(record.size)
            }
            profile.append(tagData)
            return profile
        }

        private func header(size: UInt32) -> Data {
            var data = Data(repeating: 0, count: 128)
            data.writeUInt32(size, at: 0)
            data.writeSignature("mdpf", at: 4)
            data.writeUInt32(0x0210_0000, at: 8)
            data.writeSignature("mntr", at: 12)
            data.writeSignature("RGB ", at: 16)
            data.writeSignature("XYZ ", at: 20)
            data.writeUInt16(2000, at: 24)
            data.writeUInt16(1, at: 26)
            data.writeUInt16(1, at: 28)
            data.writeSignature("acsp", at: 36)
            data.writeSignature("APPL", at: 40)
            data.writeSignature("mdpf", at: 48)
            data.writeS15Fixed16(0.9642, at: 68)
            data.writeS15Fixed16(1.0, at: 72)
            data.writeS15Fixed16(0.8249, at: 76)
            data.writeSignature("mdpf", at: 80)
            return data
        }
    }
}

private extension Data {
    mutating func appendSignature(_ signature: String) {
        append(contentsOf: Array(signature.utf8.prefix(4)))
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendS15Fixed16(_ value: Double) {
        appendUInt32(UInt32(bitPattern: Int32((value * 65536).rounded())))
    }

    mutating func padToFourByteBoundary() {
        while count % 4 != 0 {
            append(0)
        }
    }

    mutating func writeSignature(_ signature: String, at offset: Int) {
        let bytes = Array(signature.utf8.prefix(4))
        replaceSubrange(offset ..< offset + bytes.count, with: bytes)
    }

    mutating func writeUInt16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8((value >> 8) & 0xFF)
        self[offset + 1] = UInt8(value & 0xFF)
    }

    mutating func writeUInt32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8((value >> 24) & 0xFF)
        self[offset + 1] = UInt8((value >> 16) & 0xFF)
        self[offset + 2] = UInt8((value >> 8) & 0xFF)
        self[offset + 3] = UInt8(value & 0xFF)
    }

    mutating func writeS15Fixed16(_ value: Double, at offset: Int) {
        writeUInt32(UInt32(bitPattern: Int32((value * 65536).rounded())), at: offset)
    }
}
