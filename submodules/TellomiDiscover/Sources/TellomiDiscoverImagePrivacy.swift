import Foundation

/// Removes GPS and other location metadata from JPEG, PNG, and WebP without re-encoding pixels.
/// A file with no location metadata is returned unchanged. Orientation tag 0x0112 is kept.
/// HEIC is not parsed here; the app transcodes it to JPEG and then uses this function.
public func tellomiDiscoverStripImageLocation(_ data: Data) -> Data? {
    if data.count >= 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xD8 {
        return tellomiStripJPEGLocation(data)
    }
    if data.starts(with: Data([137, 80, 78, 71, 13, 10, 26, 10])) {
        return tellomiStripPNGLocation(data)
    }
    if data.count >= 12, data.prefix(4) == Data("RIFF".utf8), data.dropFirst(8).prefix(4) == Data("WEBP".utf8) {
        return tellomiStripWebPLocation(data)
    }
    return nil
}

/// EXIF orientation, when the container still has tag 0x0112. Nil when the file has no such tag.
public func tellomiDiscoverImageOrientation(_ data: Data) -> Int? {
    let tiff = tellomiImageTIFFPayloads(data)
    for payload in tiff {
        if let value = tellomiTIFFOrientation(payload) {
            return value
        }
    }
    return nil
}

/// True when a parsed container still has a GPS IFD or an XMP GPS field.
public func tellomiDiscoverImageHasLocation(_ data: Data) -> Bool {
    if tellomiImageContainersHaveGPS(data) {
        return true
    }
    return data.range(of: Data("GPSLatitude".utf8)) != nil || data.range(of: Data("GPSLongitude".utf8)) != nil
}

private func tellomiStripJPEGLocation(_ data: Data) -> Data? {
    let bytes = [UInt8](data)
    guard bytes.count > 4 else {
        return nil
    }
    var output = Data()
    output.append(contentsOf: bytes[0 ..< 2])
    var index = 2
    var changed = false
    while index + 1 < bytes.count {
        guard bytes[index] == 0xFF else {
            return nil
        }
        var markerIndex = index + 1
        while markerIndex < bytes.count, bytes[markerIndex] == 0xFF {
            markerIndex += 1
        }
        guard markerIndex < bytes.count else {
            return nil
        }
        let marker = bytes[markerIndex]
        if marker == 0xD9 || marker == 0xDA {
            output.append(contentsOf: bytes[index...])
            break
        }
        if marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
            output.append(contentsOf: bytes[index ... markerIndex])
            index = markerIndex + 1
            continue
        }
        guard markerIndex + 3 < bytes.count else {
            return nil
        }
        let length = (Int(bytes[markerIndex + 1]) << 8) + Int(bytes[markerIndex + 2])
        let end = markerIndex + 1 + length
        guard length >= 2, end <= bytes.count else {
            return nil
        }
        let payload = Data(bytes[(markerIndex + 3) ..< end])
        if marker == 0xE1, payload.starts(with: Data("Exif\0\0".utf8)) {
            let tiff = payload.dropFirst(6)
            guard let rewritten = tellomiTIFFDroppingGPS(Data(tiff)) else {
                return nil
            }
            if rewritten == tiff {
                output.append(contentsOf: bytes[index ..< end])
            } else {
                changed = true
                output.append(tellomiJPEGAPP1(prefix: Data("Exif\0\0".utf8), body: rewritten))
            }
        } else if marker == 0xE1, payload.starts(with: Data("http://ns.adobe.com/xap/1.0/\0".utf8)) {
            guard let rewritten = tellomiXMPDroppingGPS(payload) else {
                return nil
            }
            if rewritten == payload {
                output.append(contentsOf: bytes[index ..< end])
            } else if rewritten.isEmpty {
                changed = true
            } else {
                changed = true
                output.append(tellomiJPEGAPP1(prefix: Data(), body: rewritten))
            }
        } else {
            output.append(contentsOf: bytes[index ..< end])
        }
        index = end
    }
    return changed ? output : data
}

private func tellomiStripPNGLocation(_ data: Data) -> Data? {
    let bytes = [UInt8](data)
    guard bytes.count >= 8 else {
        return nil
    }
    var output = Data(bytes[0 ..< 8])
    var index = 8
    var changed = false
    while index + 12 <= bytes.count {
        let length = tellomiBigU32(bytes, index)
        let typeStart = index + 4
        let dataStart = index + 8
        let dataEnd = dataStart + Int(length)
        let chunkEnd = dataEnd + 4
        guard dataEnd >= dataStart, chunkEnd <= bytes.count else {
            return nil
        }
        let type = Data(bytes[typeStart ..< dataStart])
        let chunk = Data(bytes[dataStart ..< dataEnd])
        if type == Data("eXIf".utf8) {
            guard let rewritten = tellomiTIFFDroppingGPS(chunk) else {
                return nil
            }
            if rewritten == chunk {
                output.append(contentsOf: bytes[index ..< chunkEnd])
            } else {
                changed = true
                output.append(tellomiPNGChunk(type: type, data: rewritten))
            }
        } else if type == Data("tEXt".utf8) || type == Data("iTXt".utf8) {
            if let rewritten = tellomiPNGTextDroppingGPS(chunk), rewritten != chunk {
                changed = true
                if !rewritten.isEmpty {
                    output.append(tellomiPNGChunk(type: type, data: rewritten))
                }
            } else if tellomiPNGTextDroppingGPS(chunk) == nil {
                return nil
            } else {
                output.append(contentsOf: bytes[index ..< chunkEnd])
            }
        } else if type == Data("zTXt".utf8) {
            let keyword = chunk.prefix { $0 != 0 }
            let name = String(data: keyword, encoding: .isoLatin1)?.lowercased() ?? ""
            if name.contains("exif") || name.contains("xmp") || name.contains("gps") {
                changed = true
            } else {
                output.append(contentsOf: bytes[index ..< chunkEnd])
            }
        } else {
            output.append(contentsOf: bytes[index ..< chunkEnd])
        }
        index = chunkEnd
        if type == Data("IEND".utf8) {
            break
        }
    }
    guard index == bytes.count || Data(bytes[index...]).isEmpty else {
        return changed ? output : nil
    }
    return changed ? output : data
}

private func tellomiStripWebPLocation(_ data: Data) -> Data? {
    let bytes = [UInt8](data)
    guard bytes.count >= 12 else {
        return nil
    }
    var chunks: [(type: Data, payload: Data)] = []
    var index = 12
    var changed = false
    while index + 8 <= bytes.count {
        let type = Data(bytes[index ..< index + 4])
        let size = Int(tellomiLittleU32(bytes, index + 4))
        let start = index + 8
        let end = start + size
        guard size >= 0, end <= bytes.count else {
            return nil
        }
        var payload = Data(bytes[start ..< end])
        if type == Data("EXIF".utf8) {
            let prefix: Data
            let tiff: Data
            if payload.starts(with: Data("Exif\0\0".utf8)) {
                prefix = Data("Exif\0\0".utf8)
                tiff = payload.dropFirst(6)
            } else {
                prefix = Data()
                tiff = payload
            }
            guard let rewritten = tellomiTIFFDroppingGPS(Data(tiff)) else {
                return nil
            }
            if rewritten != tiff {
                changed = true
                payload = prefix + rewritten
            }
        } else if type == Data("XMP ".utf8) {
            guard let rewritten = tellomiXMPDroppingGPS(payload) else {
                return nil
            }
            if rewritten != payload {
                changed = true
                payload = rewritten
            }
        }
        if !payload.isEmpty || (type != Data("EXIF".utf8) && type != Data("XMP ".utf8)) {
            chunks.append((type, payload))
        }
        index = end + (size % 2)
    }
    guard !changed else {
        return tellomiWebPFile(chunks)
    }
    return data
}

private func tellomiJPEGAPP1(prefix: Data, body: Data) -> Data {
    var payload = prefix
    payload.append(body)
    var segment = Data([0xFF, 0xE1])
    let length = payload.count + 2
    segment.append(UInt8((length >> 8) & 0xFF))
    segment.append(UInt8(length & 0xFF))
    segment.append(payload)
    return segment
}

private func tellomiPNGChunk(type: Data, data: Data) -> Data {
    var chunk = Data()
    let length = UInt32(data.count)
    chunk.append(UInt8((length >> 24) & 0xFF))
    chunk.append(UInt8((length >> 16) & 0xFF))
    chunk.append(UInt8((length >> 8) & 0xFF))
    chunk.append(UInt8(length & 0xFF))
    chunk.append(type)
    chunk.append(data)
    var crcSource = type
    crcSource.append(data)
    let crc = tellomiCRC32(crcSource)
    chunk.append(UInt8((crc >> 24) & 0xFF))
    chunk.append(UInt8((crc >> 16) & 0xFF))
    chunk.append(UInt8((crc >> 8) & 0xFF))
    chunk.append(UInt8(crc & 0xFF))
    return chunk
}

private func tellomiWebPFile(_ chunks: [(type: Data, payload: Data)]) -> Data {
    var body = Data("WEBP".utf8)
    for chunk in chunks {
        var payload = chunk.payload
        if chunk.type == Data("VP8X".utf8), payload.count >= 1 {
            var flags = [UInt8](payload)
            let hasEXIF = chunks.contains { $0.type == Data("EXIF".utf8) && !$0.payload.isEmpty }
            let hasXMP = chunks.contains { $0.type == Data("XMP ".utf8) && !$0.payload.isEmpty }
            if hasEXIF {
                flags[0] |= 0x08
            } else {
                flags[0] &= ~0x08
            }
            if hasXMP {
                flags[0] |= 0x04
            } else {
                flags[0] &= ~0x04
            }
            payload = Data(flags)
        }
        body.append(chunk.type)
        let size = UInt32(payload.count)
        body.append(UInt8(size & 0xFF))
        body.append(UInt8((size >> 8) & 0xFF))
        body.append(UInt8((size >> 16) & 0xFF))
        body.append(UInt8((size >> 24) & 0xFF))
        body.append(payload)
        if payload.count % 2 == 1 {
            body.append(0)
        }
    }
    var file = Data("RIFF".utf8)
    let size = UInt32(body.count)
    file.append(UInt8(size & 0xFF))
    file.append(UInt8((size >> 8) & 0xFF))
    file.append(UInt8((size >> 16) & 0xFF))
    file.append(UInt8((size >> 24) & 0xFF))
    file.append(body)
    return file
}

private func tellomiPNGTextDroppingGPS(_ data: Data) -> Data? {
    guard let zero = data.firstIndex(of: 0) else {
        return data
    }
    let keyword = data[..<zero]
    let name = String(data: keyword, encoding: .isoLatin1)?.lowercased() ?? ""
    if name.contains("gps") {
        return Data()
    }
    let text = data[data.index(after: zero)...]
    if name.contains("xmp") || name.contains("xml") || name.contains("exif") {
        guard let rewritten = tellomiXMPDroppingGPS(Data(text)) else {
            return nil
        }
        if rewritten.isEmpty {
            return Data()
        }
        if rewritten == text {
            return data
        }
        var joined = Data(keyword)
        joined.append(0)
        joined.append(rewritten)
        return joined
    }
    return data
}

private func tellomiXMPDroppingGPS(_ data: Data) -> Data? {
    guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
        return nil
    }
    guard text.contains("GPS") else {
        return data
    }
    let patterns = [
        "\\s[\\w:.-]*GPS[\\w:.-]*\\s*=\\s*\"[^\"]*\"",
        "\\s[\\w:.-]*GPS[\\w:.-]*\\s*=\\s*'[^']*'",
        "<([\\w:.-]*GPS[\\w:.-]*)\\b[^>]*>.*?</\\1>",
        "<[\\w:.-]*GPS[\\w:.-]*\\b[^>]*/>"
    ]
    for pattern in patterns {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        text = expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
    if text.contains("GPS") {
        return Data()
    }
    return Data(text.utf8)
}

private struct TellomiTIFFItem {
    var verbatim: Data?
    var tag: UInt16
    var type: UInt16
    var count: UInt32
    var external: Data?
    var nested: [TellomiTIFFItem]?
}

private struct TellomiTIFFParsed {
    var little: Bool
    var items: [TellomiTIFFItem]
    var thumbnail: [TellomiTIFFItem]
    var thumbnailJPEG: Data?
    var hadGPS: Bool
}

private func tellomiTIFFDroppingGPS(_ data: Data) -> Data? {
    guard let parsed = tellomiParseTIFF(data) else {
        return nil
    }
    guard parsed.hadGPS else {
        return data
    }
    return tellomiWriteTIFF(parsed)
}

private func tellomiParseTIFF(_ data: Data) -> TellomiTIFFParsed? {
    let bytes = [UInt8](data)
    guard bytes.count >= 8 else {
        return nil
    }
    let little: Bool
    if bytes[0] == 0x49 && bytes[1] == 0x49 {
        little = true
    } else if bytes[0] == 0x4D && bytes[1] == 0x4D {
        little = false
    } else {
        return nil
    }
    guard tellomiU16(bytes, 2, little) == 42 else {
        return nil
    }
    let offset = Int(tellomiU32(bytes, 4, little))
    var hadGPS = false
    guard let root = tellomiParseTIFFIFD(bytes, offset, little: little, hadGPS: &hadGPS) else {
        return nil
    }
    return TellomiTIFFParsed(little: little, items: root.items, thumbnail: root.thumbnail, thumbnailJPEG: root.thumbnailJPEG, hadGPS: hadGPS)
}

private struct TellomiTIFFIFD {
    var items: [TellomiTIFFItem]
    var thumbnail: [TellomiTIFFItem]
    var thumbnailJPEG: Data?
}

private func tellomiParseTIFFIFD(_ bytes: [UInt8], _ offset: Int, little: Bool, hadGPS: inout Bool) -> TellomiTIFFIFD? {
    guard offset >= 0, offset + 2 <= bytes.count else {
        return nil
    }
    let count = Int(tellomiU16(bytes, offset, little))
    let directoryEnd = offset + 2 + count * 12
    guard count < 10_000, directoryEnd + 4 <= bytes.count else {
        return nil
    }
    var items: [TellomiTIFFItem] = []
    var jpegOffset: Int?
    var jpegLength: Int?
    for entry in 0 ..< count {
        let start = offset + 2 + entry * 12
        let tag = tellomiU16(bytes, start, little)
        let type = tellomiU16(bytes, start + 2, little)
        let components = tellomiU32(bytes, start + 4, little)
        if tag == 0x8825 {
            hadGPS = true
            continue
        }
        if tag == 0x8769 || tag == 0xA005 {
            let nestedOffset = Int(tellomiU32(bytes, start + 8, little))
            guard let nested = tellomiParseTIFFIFD(bytes, nestedOffset, little: little, hadGPS: &hadGPS) else {
                return nil
            }
            items.append(TellomiTIFFItem(verbatim: nil, tag: tag, type: type, count: components, external: nil, nested: nested.items))
            continue
        }
        guard let unit = tellomiTIFFUnitSize(type) else {
            return nil
        }
        let size = unit * Int(components)
        guard size >= 0, components <= 50_000_000 else {
            return nil
        }
        if tag == 0x0201 {
            jpegOffset = Int(tellomiU32(bytes, start + 8, little))
            continue
        }
        if tag == 0x0202 {
            jpegLength = Int(tellomiU32(bytes, start + 8, little))
            continue
        }
        if size <= 4 {
            items.append(TellomiTIFFItem(verbatim: Data(bytes[start ..< start + 12]), tag: tag, type: type, count: components, external: nil, nested: nil))
        } else {
            let dataOffset = Int(tellomiU32(bytes, start + 8, little))
            guard dataOffset >= 0, dataOffset + size <= bytes.count else {
                return nil
            }
            items.append(TellomiTIFFItem(verbatim: nil, tag: tag, type: type, count: components, external: Data(bytes[dataOffset ..< dataOffset + size]), nested: nil))
        }
    }
    let next = Int(tellomiU32(bytes, directoryEnd, little))
    var thumbnail: [TellomiTIFFItem] = []
    var thumbnailJPEG: Data?
    if let jpegOffset, let jpegLength, jpegOffset >= 0, jpegLength >= 0, jpegOffset + jpegLength <= bytes.count {
        thumbnailJPEG = Data(bytes[jpegOffset ..< jpegOffset + jpegLength])
    }
    if next != 0 {
        guard let linked = tellomiParseTIFFIFD(bytes, next, little: little, hadGPS: &hadGPS) else {
            return nil
        }
        thumbnail = linked.items
        if thumbnailJPEG == nil {
            thumbnailJPEG = linked.thumbnailJPEG
        }
    }
    return TellomiTIFFIFD(items: items, thumbnail: thumbnail, thumbnailJPEG: thumbnailJPEG)
}

private func tellomiWriteTIFF(_ parsed: TellomiTIFFParsed) -> Data? {
    var blob = Data(count: 8)
    blob[0] = parsed.little ? 0x49 : 0x4D
    blob[1] = blob[0]
    tellomiPutU16(&blob, 2, 42, parsed.little)
    guard let ifd = tellomiWriteTIFFIFD(parsed.items, thumbnail: parsed.thumbnail, thumbnailJPEG: parsed.thumbnailJPEG, little: parsed.little, blob: &blob) else {
        return nil
    }
    tellomiPutU32(&blob, 4, UInt32(ifd), parsed.little)
    return blob
}

private func tellomiWriteTIFFIFD(_ items: [TellomiTIFFItem], thumbnail: [TellomiTIFFItem], thumbnailJPEG: Data?, little: Bool, blob: inout Data) -> Int? {
    var stored = items
    if let thumbnailJPEG {
        stored.append(TellomiTIFFItem(verbatim: nil, tag: 0x0201, type: 4, count: 1, external: thumbnailJPEG, nested: nil))
        var length = Data(count: 4)
        tellomiPutU32(&length, 0, UInt32(thumbnailJPEG.count), little)
        stored.append(TellomiTIFFItem(verbatim: nil, tag: 0x0202, type: 4, count: 1, external: nil, nested: nil))
        stored[stored.count - 1].verbatim = nil
        stored[stored.count - 1].external = length
    }
    let start = blob.count
    tellomiAppendU16(&blob, UInt16(stored.count), little)
    var patches: [(at: Int, item: TellomiTIFFItem)] = []
    for item in stored {
        if let verbatim = item.verbatim, item.nested == nil, item.external == nil {
            blob.append(verbatim)
            continue
        }
        tellomiAppendU16(&blob, item.tag, little)
        tellomiAppendU16(&blob, item.type, little)
        tellomiAppendU32(&blob, item.count, little)
        if item.tag == 0x0202, let external = item.external, external.count == 4 {
            blob.append(external)
        } else if item.tag == 0x0201 || item.external != nil || item.nested != nil {
            patches.append((blob.count, item))
            tellomiAppendU32(&blob, 0, little)
        } else {
            return nil
        }
    }
    let nextAt = blob.count
    tellomiAppendU32(&blob, 0, little)
    for patch in patches {
        let offset = blob.count
        tellomiPutU32(&blob, patch.at, UInt32(offset), little)
        if let nested = patch.item.nested {
            guard tellomiWriteTIFFIFD(nested, thumbnail: [], thumbnailJPEG: nil, little: little, blob: &blob) != nil else {
                return nil
            }
        } else if let external = patch.item.external {
            blob.append(external)
        }
    }
    if !thumbnail.isEmpty || thumbnailJPEG != nil {
        guard let child = tellomiWriteTIFFIFD(thumbnail, thumbnail: [], thumbnailJPEG: thumbnailJPEG, little: little, blob: &blob) else {
            return nil
        }
        tellomiPutU32(&blob, nextAt, UInt32(child), little)
    }
    return start
}

private func tellomiTIFFOrientation(_ data: Data) -> Int? {
    guard let parsed = tellomiParseTIFF(data) else {
        return nil
    }
    return tellomiOrientation(in: parsed.items, little: parsed.little)
}

private func tellomiOrientation(in items: [TellomiTIFFItem], little: Bool) -> Int? {
    for item in items {
        if item.tag == 0x0112, let verbatim = item.verbatim, verbatim.count == 12 {
            let bytes = [UInt8](verbatim)
            let type = tellomiU16(bytes, 2, little)
            if type == 3 {
                return Int(tellomiU16(bytes, 8, little))
            }
        }
        if let nested = item.nested, let value = tellomiOrientation(in: nested, little: little) {
            return value
        }
    }
    return nil
}

private func tellomiImageTIFFPayloads(_ data: Data) -> [Data] {
    var found: [Data] = []
    if data.count >= 2, data[data.startIndex] == 0xFF {
        let bytes = [UInt8](data)
        var index = 2
        while index + 4 < bytes.count, bytes[index] == 0xFF {
            var markerIndex = index + 1
            while markerIndex < bytes.count, bytes[markerIndex] == 0xFF {
                markerIndex += 1
            }
            guard markerIndex < bytes.count else {
                break
            }
            let marker = bytes[markerIndex]
            if marker == 0xDA || marker == 0xD9 {
                break
            }
            if marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
                index = markerIndex + 1
                continue
            }
            guard markerIndex + 3 < bytes.count else {
                break
            }
            let length = (Int(bytes[markerIndex + 1]) << 8) + Int(bytes[markerIndex + 2])
            let end = markerIndex + 1 + length
            guard length >= 2, end <= bytes.count else {
                break
            }
            let payload = Data(bytes[(markerIndex + 3) ..< end])
            if payload.starts(with: Data("Exif\0\0".utf8)) {
                found.append(payload.dropFirst(6))
            }
            index = end
        }
    }
    if data.starts(with: Data([137, 80, 78, 71, 13, 10, 26, 10])) {
        let bytes = [UInt8](data)
        var index = 8
        while index + 8 <= bytes.count {
            let length = Int(tellomiBigU32(bytes, index))
            let type = Data(bytes[(index + 4) ..< (index + 8)])
            let start = index + 8
            let end = start + length
            guard end + 4 <= bytes.count else {
                break
            }
            if type == Data("eXIf".utf8) {
                found.append(Data(bytes[start ..< end]))
            }
            index = end + 4
        }
    }
    if data.count >= 12, data.prefix(4) == Data("RIFF".utf8) {
        let bytes = [UInt8](data)
        var index = 12
        while index + 8 <= bytes.count {
            let type = Data(bytes[index ..< index + 4])
            let size = Int(tellomiLittleU32(bytes, index + 4))
            let start = index + 8
            let end = start + size
            guard end <= bytes.count else {
                break
            }
            if type == Data("EXIF".utf8) {
                let payload = Data(bytes[start ..< end])
                if payload.starts(with: Data("Exif\0\0".utf8)) {
                    found.append(payload.dropFirst(6))
                } else {
                    found.append(payload)
                }
            }
            index = end + (size % 2)
        }
    }
    return found
}

private func tellomiImageContainersHaveGPS(_ data: Data) -> Bool {
    for payload in tellomiImageTIFFPayloads(data) {
        if tellomiParseTIFF(payload)?.hadGPS == true {
            return true
        }
    }
    return false
}

private func tellomiTIFFUnitSize(_ type: UInt16) -> Int? {
    switch type {
    case 1, 2, 6, 7:
        return 1
    case 3, 8:
        return 2
    case 4, 9, 11:
        return 4
    case 5, 10, 12:
        return 8
    default:
        return nil
    }
}

private func tellomiU16(_ bytes: [UInt8], _ offset: Int, _ little: Bool) -> UInt16 {
    if little {
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }
    return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
}

private func tellomiU32(_ bytes: [UInt8], _ offset: Int, _ little: Bool) -> UInt32 {
    if little {
        return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
    return (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
}

private func tellomiBigU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    return tellomiU32(bytes, offset, false)
}

private func tellomiLittleU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    return tellomiU32(bytes, offset, true)
}

private func tellomiAppendU16(_ data: inout Data, _ value: UInt16, _ little: Bool) {
    if little {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    } else {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}

private func tellomiAppendU32(_ data: inout Data, _ value: UInt32, _ little: Bool) {
    if little {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    } else {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}

private func tellomiPutU16(_ data: inout Data, _ offset: Int, _ value: UInt16, _ little: Bool) {
    if little {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    } else {
        data[offset] = UInt8((value >> 8) & 0xFF)
        data[offset + 1] = UInt8(value & 0xFF)
    }
}

private func tellomiPutU32(_ data: inout Data, _ offset: Int, _ value: UInt32, _ little: Bool) {
    if little {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    } else {
        data[offset] = UInt8((value >> 24) & 0xFF)
        data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF)
        data[offset + 3] = UInt8(value & 0xFF)
    }
}

private func tellomiCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0 ..< 8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >>= 1
            }
        }
    }
    return crc ^ 0xFFFF_FFFF
}
