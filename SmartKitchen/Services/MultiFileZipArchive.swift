import Foundation

// MARK: - Multi-file Zip Archive (Stored only)
//
// Extension to SimpleZipArchive supporting multiple files per archive.
// Compatible with the existing single-file archiver (which is kept intact in
// BackupManager.swift for backward compatibility).
//
// Format reference: APPNOTE.TXT 6.3.10. Compression method = 0 (Stored).

struct ZipFileEntry {
    let path: String      // e.g. "media/<recipe-id>/0.jpg"
    let data: Data
}

enum MultiFileZipArchive {
    static func archive(_ entries: [ZipFileEntry]) throws -> Data {
        var archive = Data()

        struct CentralRecord {
            let nameData: Data
            let crc: UInt32
            let size: UInt32
            let localHeaderOffset: UInt32
        }
        var centrals: [CentralRecord] = []

        for entry in entries {
            guard let nameData = entry.path.data(using: .utf8) else {
                throw BackupTransferError.invalidFileName
            }
            guard nameData.count <= Int(UInt16.max), entry.data.count <= Int(UInt32.max) else {
                throw BackupTransferError.payloadTooLarge
            }

            let crc = CRC32.checksum(of: entry.data)
            let localOffset = UInt32(archive.count)

            // Local file header
            archive.appendUInt32(0x04034B50)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(0) // method 0 = stored
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(crc)
            archive.appendUInt32(UInt32(entry.data.count))
            archive.appendUInt32(UInt32(entry.data.count))
            archive.appendUInt16(UInt16(nameData.count))
            archive.appendUInt16(0)
            archive.append(nameData)
            archive.append(entry.data)

            centrals.append(CentralRecord(
                nameData: nameData,
                crc: crc,
                size: UInt32(entry.data.count),
                localHeaderOffset: localOffset
            ))
        }

        let centralDirectoryOffset = UInt32(archive.count)

        for record in centrals {
            archive.appendUInt32(0x02014B50)
            archive.appendUInt16(20)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(record.crc)
            archive.appendUInt32(record.size)
            archive.appendUInt32(record.size)
            archive.appendUInt16(UInt16(record.nameData.count))
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(0)
            archive.appendUInt32(record.localHeaderOffset)
            archive.append(record.nameData)
        }

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

        archive.appendUInt32(0x06054B50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(centrals.count))
        archive.appendUInt16(UInt16(centrals.count))
        archive.appendUInt32(centralDirectorySize)
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)

        return archive
    }

    /// Extract every file from a stored-method ZIP.
    /// Returns a map [path -> data].
    static func extractAll(from archive: Data) throws -> [String: Data] {
        var result: [String: Data] = [:]
        var offset = 0

        while offset + 30 <= archive.count {
            let signature = try archive.readUInt32(at: offset)

            if signature == 0x04034B50 {
                let compressionMethod = try archive.readUInt16(at: offset + 8)
                guard compressionMethod == 0 else {
                    throw BackupTransferError.unsupportedZipCompression
                }

                let payloadSize = Int(try archive.readUInt32(at: offset + 18))
                let nameLength = Int(try archive.readUInt16(at: offset + 26))
                let extraLength = Int(try archive.readUInt16(at: offset + 28))
                let nameStart = offset + 30
                let nameEnd = nameStart + nameLength
                let dataStart = nameEnd + extraLength
                let dataEnd = dataStart + payloadSize

                guard dataEnd <= archive.count else {
                    throw BackupTransferError.invalidArchive
                }

                let entryNameData = archive.subdata(in: nameStart..<nameEnd)
                let entryName = String(data: entryNameData, encoding: .utf8) ?? ""
                let payload = archive.subdata(in: dataStart..<dataEnd)
                if !entryName.isEmpty && !entryName.hasSuffix("/") {
                    result[entryName] = payload
                }

                offset = dataEnd
            } else if signature == 0x02014B50 || signature == 0x06054B50 {
                break
            } else {
                throw BackupTransferError.invalidArchive
            }
        }

        return result
    }
}
