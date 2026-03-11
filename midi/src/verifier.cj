package midi

import std.collection.*
import std.fs.*

// ============================================================
// MIDI 验证工具
// ============================================================

func hexChar(nibble: UInt8): Rune {
    if (nibble < 10) {
        Rune(UInt32(r'0') + UInt32(nibble))
    } else {
        Rune(UInt32(r'A') + UInt32(nibble) - 10)
    }
}

public func bytesToHex(data: Array<UInt8>): String {
    let sb = StringBuilder()
    for (i in 0..data.size) {
        if (i > 0) { sb.append(" ") }
        let b = data[i]
        sb.append(hexChar(b >> 4))
        sb.append(hexChar(b & 0x0F))
    }
    sb.toString()
}

public func verifyMThd(data: Array<UInt8>, expectedFormat: UInt16, expectedTracks: UInt16): Bool {
    if (data.size < 14) {
        println("  ERROR: MIDI file too short (${data.size} bytes)")
        return false
    }
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        println("  ERROR: Invalid MThd signature")
        return false
    }
    if (data[4] != 0 || data[5] != 0 || data[6] != 0 || data[7] != 6) {
        println("  ERROR: Invalid MThd length")
        return false
    }
    let format = UInt16(data[8]) << 8 | UInt16(data[9])
    if (format != expectedFormat) {
        println("  ERROR: Format mismatch: expected ${expectedFormat}, got ${format}")
        return false
    }
    let tracks = UInt16(data[10]) << 8 | UInt16(data[11])
    if (tracks != expectedTracks) {
        println("  ERROR: Track count mismatch: expected ${expectedTracks}, got ${tracks}")
        return false
    }
    let tpq = UInt16(data[12]) << 8 | UInt16(data[13])
    if (tpq != 480) {
        println("  ERROR: Time division mismatch: expected 480, got ${tpq}")
        return false
    }
    true
}

// 读取 VLQ 值，返回 (value, bytesConsumed)
func readVLQAt(data: Array<UInt8>, pos: Int64, size: Int64): (UInt32, Int64) {
    var value: UInt32 = 0
    var i = pos
    while (i < size) {
        let b = data[i]
        value = (value << 7) | UInt32(b & 0x7F)
        i++
        if ((b & 0x80) == 0) {
            break
        }
    }
    return (value, i - pos)
}

// 解析轨道内的事件，提取 Note On 音高和 Program Change
class TrackParseResult {
    var noteOnPitches: ArrayList<UInt8>
    var programChanges: ArrayList<UInt8>

    init() {
        this.noteOnPitches = ArrayList<UInt8>()
        this.programChanges = ArrayList<UInt8>()
    }
}

func parseTrackEvents(data: Array<UInt8>, trackStart: Int64, trackEnd: Int64): TrackParseResult {
    let result = TrackParseResult()
    var j = trackStart
    let size = data.size

    while (j < trackEnd && j < size) {
        // 读取 delta-time (VLQ)
        let vlqResult = readVLQAt(data, j, if (trackEnd < size) { trackEnd } else { size })
        j += vlqResult[1]

        if (j >= trackEnd || j >= size) { break }

        let status = data[j]

        if ((status & 0xF0) == 0x90) {
            // Note On
            if (j + 2 < size) {
                result.noteOnPitches.add(data[j + 1])
            }
            j += 3
        } else if ((status & 0xF0) == 0x80) {
            // Note Off
            j += 3
        } else if ((status & 0xF0) == 0xC0) {
            // Program Change
            if (j + 1 < size) {
                result.programChanges.add(data[j + 1])
            }
            j += 2
        } else if (status == 0xFF) {
            // Meta event
            if (j + 2 < size) {
                let metaLen = Int64(data[j + 2])
                j += 3 + metaLen
            } else {
                j++
            }
        } else {
            j++
        }
    }

    result
}

public func extractNoteOnPitches(data: Array<UInt8>): ArrayList<UInt8> {
    let pitches = ArrayList<UInt8>()
    let size = data.size
    var i: Int64 = 14

    while (i < size) {
        if (i + 8 <= size && data[i] == 0x4D && data[i + 1] == 0x54 && data[i + 2] == 0x72 && data[i + 3] == 0x6B) {
            let trackLen = Int64(UInt32(data[i + 4]) << 24 | UInt32(data[i + 5]) << 16 | UInt32(data[i + 6]) << 8 | UInt32(data[i + 7]))
            let trackStart = i + 8
            let trackEnd = trackStart + trackLen

            let result = parseTrackEvents(data, trackStart, trackEnd)
            for (p in result.noteOnPitches) { pitches.add(p) }

            i = trackEnd
        } else {
            i++
        }
    }
    pitches
}

public func extractProgramChanges(data: Array<UInt8>): ArrayList<UInt8> {
    let programs = ArrayList<UInt8>()
    let size = data.size
    var i: Int64 = 14

    while (i < size) {
        if (i + 8 <= size && data[i] == 0x4D && data[i + 1] == 0x54 && data[i + 2] == 0x72 && data[i + 3] == 0x6B) {
            let trackLen = Int64(UInt32(data[i + 4]) << 24 | UInt32(data[i + 5]) << 16 | UInt32(data[i + 6]) << 8 | UInt32(data[i + 7]))
            let trackStart = i + 8
            let trackEnd = trackStart + trackLen

            let result = parseTrackEvents(data, trackStart, trackEnd)
            for (p in result.programChanges) { programs.add(p) }

            i = trackEnd
        } else {
            i++
        }
    }
    programs
}

public func verifyTempo(data: Array<UInt8>, expectedBPM: Int64): Bool {
    let expectedMicro = UInt32(60000000 / expectedBPM)
    let size = data.size
    var i: Int64 = 14

    while (i + 5 < size) {
        if (data[i] == 0xFF && data[i + 1] == 0x51 && data[i + 2] == 0x03) {
            let micro = UInt32(data[i + 3]) << 16 | UInt32(data[i + 4]) << 8 | UInt32(data[i + 5])
            if (micro == expectedMicro) { return true }
            let diff = if (micro > expectedMicro) { micro - expectedMicro } else { expectedMicro - micro }
            if (diff <= 1) { return true }
            println("  WARN: Tempo mismatch: expected ${expectedMicro}, got ${micro}")
            return false
        }
        i++
    }
    println("  ERROR: Set Tempo event not found")
    false
}

public func countTracks(data: Array<UInt8>): Int64 {
    var count: Int64 = 0
    let size = data.size
    var i: Int64 = 0
    while (i + 3 < size) {
        if (data[i] == 0x4D && data[i + 1] == 0x54 && data[i + 2] == 0x72 && data[i + 3] == 0x6B) {
            count++
            i += 4
        } else {
            i++
        }
    }
    count
}

public func saveMidiFile(path: String, data: Array<UInt8>): Unit {
    // UInt8 和 Byte 在 Cangjie 中是同类型
    File.writeTo(Path(path), data)
}
