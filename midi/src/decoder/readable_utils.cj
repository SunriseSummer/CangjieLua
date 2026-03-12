package midi.decoder

// ============================================================
// MIDI 可读格式解码器 — 十六进制工具与 Running Status 检测
// 轨道事件解码逻辑见 readable_decoder.cj
// ============================================================

// ── 十六进制工具 ──

// 十六进制字符查找表（0-F）
let HEX_CHARS: Array<Rune> = [
    r'0', r'1', r'2', r'3', r'4', r'5', r'6', r'7',
    r'8', r'9', r'A', r'B', r'C', r'D', r'E', r'F'
]

// 将单字节转换为两位大写十六进制字符串（如 0x3A → "3A"）
func byteToHex(b: UInt8): String {
    let hi = HEX_CHARS[Int64(b >> 4)]
    let lo = HEX_CHARS[Int64(b & 0x0F)]
    "${hi}${lo}"
}

// ── Running Status 检测 ──

// 扫描所有轨道，检测原始 MIDI 二进制是否使用了 Running Status 压缩
// 遍历每个轨道的事件，若发现数据字节（< 0x80）出现在事件首位则判定为使用了 Running Status
func detectRunningStatus(data: Array<UInt8>, headerEnd: Int64, numTracks: Int64): Bool {
    var pos = headerEnd
    var ti: Int64 = 0
    while (ti < numTracks) {
        if (pos + 8 > data.size) { break }
        // 检查 MTrk 标记
        if (data[pos] != 0x4D || data[pos + 1] != 0x54 ||
            data[pos + 2] != 0x72 || data[pos + 3] != 0x6B) { break }
        let trackLen = Int64(decReadU32(data, pos + 4))
        let trackStart = pos + 8
        let trackEnd = trackStart + trackLen

        var j = trackStart
        while (j < trackEnd && j < data.size) {
            // 读取 delta-time（可变长度）
            let vlq = decReadVLQ(data, j, trackEnd)
            j = vlq.newPos
            if (j >= trackEnd) { break }
            let firstByte = data[j]
            if (firstByte >= 0x80) {
                if (firstByte == 0xFF) {
                    // Meta 事件：跳过类型字节和数据
                    j++
                    if (j >= trackEnd) { break }
                    j++ // type
                    let metaVLQ = decReadVLQ(data, j, trackEnd)
                    j = metaVLQ.newPos + Int64(metaVLQ.value)
                } else if (firstByte == 0xF0 || firstByte == 0xF7) {
                    // SysEx 事件：跳过数据
                    j++
                    let sysVLQ = decReadVLQ(data, j, trackEnd)
                    j = sysVLQ.newPos + Int64(sysVLQ.value)
                } else {
                    // 通道事件：跳过状态字节和数据字节
                    let eventType = firstByte & 0xF0
                    j++
                    if (eventType == 0xC0 || eventType == 0xD0) { j += 1 }
                    else { j += 2 }
                }
            } else {
                // 首字节 < 0x80，说明使用了 Running Status
                return true
            }
        }
        pos = trackEnd
        ti++
    }
    false
}
