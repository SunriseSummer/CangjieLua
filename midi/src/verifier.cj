package midi

import std.collection.*
import std.fs.*

// ============================================================
// MIDI 验证工具 — 用于测试和验证 MIDI 文件的正确性
// ============================================================

// 将半字节（0-15）转换为对应的十六进制字符
func hexChar(nibble: UInt8): Rune {
    if (nibble < 10) {
        Rune(UInt32(r'0') + UInt32(nibble))
    } else {
        Rune(UInt32(r'A') + UInt32(nibble) - 10)
    }
}

// 将字节数组转换为空格分隔的十六进制字符串表示
// 例如：[0x4D, 0x54] → "4D 54"
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

// 验证 MIDI 文件头部（MThd 块）的格式、轨道数和时间分辨率
// 检查 MThd 签名、长度、format 类型、轨道数量和 TPQ 值
public func verifyMThd(data: Array<UInt8>, expectedFormat: UInt16, expectedTracks: UInt16): Bool {
    if (data.size < 14) {
        println("  ERROR: MIDI file too short (${data.size} bytes)")
        return false
    }
    // 检查 MThd 签名（0x4D546864）
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        println("  ERROR: Invalid MThd signature")
        return false
    }
    // 检查头部长度（固定为 6 字节）
    if (data[4] != 0 || data[5] != 0 || data[6] != 0 || data[7] != 6) {
        println("  ERROR: Invalid MThd length")
        return false
    }
    // 检查 MIDI 格式类型（0 或 1）
    let format = UInt16(data[8]) << 8 | UInt16(data[9])
    if (format != expectedFormat) {
        println("  ERROR: Format mismatch: expected ${expectedFormat}, got ${format}")
        return false
    }
    // 检查轨道数量
    let tracks = UInt16(data[10]) << 8 | UInt16(data[11])
    if (tracks != expectedTracks) {
        println("  ERROR: Track count mismatch: expected ${expectedTracks}, got ${tracks}")
        return false
    }
    // 检查时间分辨率（TPQ，每四分音符的 tick 数）
    let tpq = UInt16(data[12]) << 8 | UInt16(data[13])
    if (tpq != 480) {
        println("  ERROR: Time division mismatch: expected 480, got ${tpq}")
        return false
    }
    true
}

// 读取可变长度值（VLQ），返回 (解析值, 消耗字节数) 元组
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

// 轨道事件解析结果：存储从轨道中提取的 NoteOn 音高和 Program Change 值
class TrackParseResult {
    var noteOnPitches: ArrayList<UInt8>
    var programChanges: ArrayList<UInt8>

    init() {
        this.noteOnPitches = ArrayList<UInt8>()
        this.programChanges = ArrayList<UInt8>()
    }
}

// 解析轨道内的 MIDI 事件，提取 NoteOn 音高和 Program Change 音色号
// 用于验证编码后的 MIDI 文件内容是否正确
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

// 从 MIDI 文件字节数组中提取所有 NoteOn 事件的音高值
// 遍历所有 MTrk 块，解析每个轨道的事件
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

// 从 MIDI 文件字节数组中提取所有 Program Change 的音色号
// 遍历所有 MTrk 块，解析每个轨道的事件
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

// 验证 MIDI 文件中的速度设置是否与预期 BPM 匹配
// 在文件中搜索 Set Tempo Meta 事件（FF 51 03），比较微秒值
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

// 统计 MIDI 文件中的 MTrk 块数量
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

// 将 MIDI 字节数组保存到指定文件路径
public func saveMidiFile(path: String, data: Array<UInt8>): Unit {
    // UInt8 和 Byte 在 Cangjie 中是同类型
    File.writeTo(Path(path), data)
}
