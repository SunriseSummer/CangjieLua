package midi.decoder

import std.fs.*

// ============================================================
// MIDI 反编译器：.mid 二进制 → 无损原始事件文本
// ============================================================

// ── 十六进制工具 ──

let HEX_CHARS: Array<Rune> = [
    r'0', r'1', r'2', r'3', r'4', r'5', r'6', r'7',
    r'8', r'9', r'A', r'B', r'C', r'D', r'E', r'F'
]

// 单字节 → 两位大写十六进制字符串
func byteToHex(b: UInt8): String {
    let hi = HEX_CHARS[Int64(b >> 4)]
    let lo = HEX_CHARS[Int64(b & 0x0F)]
    "${hi}${lo}"
}

// ── 轨道原始事件输出 ──

// 解码单个 MTrk 的二进制事件，输出每个事件为一行文本：
//   <delta_decimal> <hex_bytes...>
// 其中 hex_bytes 是事件在 MIDI 二进制中的原始字节（保留 Running Status）
func decodeTrackRaw(sb: StringBuilder, data: Array<UInt8>,
                    trackStart: Int64, trackEnd: Int64): Unit {
    var j = trackStart
    var runningStatus: UInt8 = 0

    while (j < trackEnd && j < data.size) {
        // 读取 VLQ delta-time
        let vlq = decReadVLQ(data, j, trackEnd)
        let delta = vlq.value
        j = vlq.newPos
        if (j >= trackEnd) { break }

        // 记录事件字节起始位置
        let eventStart = j
        let firstByte = data[j]

        if (firstByte >= 0x80) {
            // 新的 status 字节
            if (firstByte == 0xFF) {
                // Meta 事件: FF type vlq_len data...
                j++ // FF
                if (j >= trackEnd) { break }
                j++ // type
                let metaVLQ = decReadVLQ(data, j, trackEnd)
                j = metaVLQ.newPos + Int64(metaVLQ.value)
                runningStatus = 0
            } else if (firstByte == 0xF0 || firstByte == 0xF7) {
                // SysEx: F0/F7 vlq_len data...
                j++ // status
                let sysVLQ = decReadVLQ(data, j, trackEnd)
                j = sysVLQ.newPos + Int64(sysVLQ.value)
                runningStatus = 0
            } else {
                // Channel Voice/Mode 消息
                let eventType = firstByte & 0xF0
                runningStatus = firstByte
                j++ // status
                if (eventType == 0xC0 || eventType == 0xD0) {
                    j += 1 // 1 个数据字节
                } else {
                    j += 2 // 2 个数据字节
                }
            }
        } else {
            // Running Status（无 status 字节，复用上一个 status）
            let eventType = runningStatus & 0xF0
            if (eventType == 0xC0 || eventType == 0xD0) {
                j += 1
            } else {
                j += 2
            }
        }

        // 限制 j 不超过 trackEnd
        if (j > trackEnd) { j = trackEnd }

        // 输出: <delta> <hex bytes>
        sb.append("${delta}")
        var k = eventStart
        while (k < j) {
            sb.append(" ${byteToHex(data[k])}")
            k++
        }
        sb.append("\n")
    }
}

// ── 反编译主函数 ──

// MIDI 文件字节数组 → 无损原始事件文本（MIDI_RAW 格式）
// 保留所有 MIDI 事件（包括 Running Status），确保重新编码后二进制完全一致
public func decompile(data: Array<UInt8>): String {
    if (data.size < 14) {
        return "// Error: Invalid MIDI file (too short)\n"
    }
    // 验证 MThd 签名
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        return "// Error: Invalid MIDI file (bad MThd)\n"
    }

    let format = Int64(decReadU16(data, 8))
    let numTracks = Int64(decReadU16(data, 10))
    let tpq = Int64(decReadU16(data, 12))

    let sb = StringBuilder()
    sb.append("MIDI_RAW\n")
    sb.append("TPQ ${tpq}\n")
    sb.append("FORMAT ${format}\n")

    var pos: Int64 = 14
    var ti: Int64 = 0
    while (ti < numTracks) {
        if (pos + 8 > data.size) { break }
        // 验证 MTrk 签名
        if (data[pos] != 0x4D || data[pos + 1] != 0x54 ||
            data[pos + 2] != 0x72 || data[pos + 3] != 0x6B) { break }

        let trackLen = Int64(decReadU32(data, pos + 4))
        let trackStart = pos + 8
        let trackEnd = trackStart + trackLen

        sb.append("\nTRACK\n")
        decodeTrackRaw(sb, data, trackStart, trackEnd)
        sb.append("TRACK_END\n")

        pos = trackEnd
        ti++
    }

    sb.toString()
}

// 反编译 .mid 文件为文本乐谱
public func decompileToString(midPath: String): String {
    let data = File.readFrom(Path(midPath))
    decompile(data)
}
