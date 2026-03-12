package midi.encoder

import std.collection.*

// ============================================================
// 编码器共用工具函数
// ============================================================

let TICKS_PER_QUARTER: UInt16 = 480   // 每四分音符 tick 数
let DEFAULT_VELOCITY: UInt8 = 80      // 默认音符力度

// ── 十六进制解析工具 ──

// 单个十六进制字符 → 数值 (0-15)，无效返回 -1
func hexCharValue(ch: Rune): Int64 {
    if (ch >= r'0' && ch <= r'9') { return ch.position() - r'0'.position() }
    if (ch >= r'A' && ch <= r'F') { return ch.position() - r'A'.position() + 10 }
    if (ch >= r'a' && ch <= r'f') { return ch.position() - r'a'.position() + 10 }
    return -1
}

// 两位十六进制字符串 → UInt8
func parseHexByte(s: String): UInt8 {
    let runes = s.toRuneArray()
    if (runes.size != 2) { return 0 }
    let hi = hexCharValue(runes[0])
    let lo = hexCharValue(runes[1])
    if (hi < 0 || lo < 0) { return 0 }
    UInt8(hi * 16 + lo)
}

// ── 音名解析工具 ──

// 音名基础值: C=0, D=2, E=4, F=5, G=7, A=9, B=11
func encBasePitch(noteRune: Rune): Int64 {
    if (noteRune == r'C') { return 0 }
    if (noteRune == r'D') { return 2 }
    if (noteRune == r'E') { return 4 }
    if (noteRune == r'F') { return 5 }
    if (noteRune == r'G') { return 7 }
    if (noteRune == r'A') { return 9 }
    if (noteRune == r'B') { return 11 }
    return -1
}

// 音名字符串 → MIDI 音高 (如 "C4" → 60, "C#4" → 61, "Db4" → 61)
func noteNameToMidi(name: String): Int64 {
    let runes = name.toRuneArray()
    if (runes.size < 2) { return -1 }
    let base = encBasePitch(runes[0])
    if (base < 0) { return -1 }
    var i: Int64 = 1
    var accidental: Int64 = 0
    if (i < runes.size && runes[i] == r'#') { accidental = 1; i++ }
    else if (i < runes.size && runes[i] == r'b') { accidental = -1; i++ }
    // 读取八度数字（可能为负数如 C-1）
    var neg = false
    if (i < runes.size && runes[i] == r'-') { neg = true; i++ }
    if (i >= runes.size) { return -1 }
    var octave: Int64 = 0
    while (i < runes.size && runes[i] >= r'0' && runes[i] <= r'9') {
        octave = octave * 10 + (runes[i].position() - r'0'.position())
        i++
    }
    if (neg) { octave = -octave }
    (octave + 1) * 12 + base + accidental
}

// ── 格式检测 ──

// 判断输入是否为 MIDI 可读事件格式（以 "MIDI" 开头）
func isMidiReadableFormat(input: String): Bool {
    input.trimAscii().startsWith("MIDI")
}

// ── 字符串工具 ──

// 按空白分割字符串
func splitByWhitespace(s: String): ArrayList<String> {
    let result = ArrayList<String>()
    var current = StringBuilder()
    var inWord = false
    for (ch in s.toRuneArray()) {
        if (ch == r' ' || ch == r'\t') {
            if (inWord) {
                result.add(current.toString())
                current = StringBuilder()
                inWord = false
            }
        } else {
            current.append(ch)
            inWord = true
        }
    }
    if (inWord) { result.add(current.toString()) }
    result
}

// ── MIDI 文件组装工具 ──

// 将多个轨道数据组装为完整 MIDI 文件（MThd + MTrk 块）
func assembleMidiFile(trackDataList: ArrayList<ArrayList<UInt8>>,
                      format: UInt16, tpq: UInt16): Array<UInt8> {
    let trackCount = trackDataList.size
    let result = ArrayList<UInt8>()
    // MThd 标识
    result.add(0x4D); result.add(0x54); result.add(0x68); result.add(0x64)
    writeUInt32BE(result, 6)
    writeUInt16BE(result, format)
    writeUInt16BE(result, UInt16(trackCount))
    writeUInt16BE(result, tpq)

    for (td in trackDataList) {
        // MTrk 标识
        result.add(0x4D); result.add(0x54); result.add(0x72); result.add(0x6B)
        writeUInt32BE(result, UInt32(td.size))
        for (b in td) { result.add(b) }
    }

    result.toArray()
}
