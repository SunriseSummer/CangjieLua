package midi.core

import std.collection.*

// ============================================================
// 文本乐谱解析器 — 辅助类型与工具函数
// ============================================================

// ── 解析辅助类型 ──

// 数字解析结果：value 为解析出的数值，newPos 为消耗后的位置
class NumberResult {
    var value: Int64
    var newPos: Int64
    init(value: Int64, newPos: Int64) {
        this.value = value
        this.newPos = newPos
    }
}

// 音符标记解析结果：pitch 为 MIDI 音高，ticks 为持续时值
class NoteTokenResult {
    var pitch: Int64
    var ticks: Int64
    var newPos: Int64
    init(pitch: Int64, ticks: Int64, newPos: Int64) {
        this.pitch = pitch
        this.ticks = ticks
        this.newPos = newPos
    }
}

// 和弦解析结果：chord 为和弦信息，newPos 为消耗后的位置
class ChordParseResult {
    var chord: ChordInfo
    var newPos: Int64
    init(chord: ChordInfo, newPos: Int64) {
        this.chord = chord
        this.newPos = newPos
    }
}

// ── 字符判断工具 ──

// 获取音名对应的半音偏移（C=0, D=2, E=4, F=5, G=7, A=9, B=11）
func basePitch(noteRune: Rune): Int64 {
    if (noteRune == r'C') { return 0 }
    if (noteRune == r'D') { return 2 }
    if (noteRune == r'E') { return 4 }
    if (noteRune == r'F') { return 5 }
    if (noteRune == r'G') { return 7 }
    if (noteRune == r'A') { return 9 }
    if (noteRune == r'B') { return 11 }
    return -1
}

// readNumber 中用于标记原始 tick 值的偏移量常量
let RAW_TICK_OFFSET: Int64 = 10000

// 判断字符是否为合法音名（A-G）
func isNoteName(ch: Rune): Bool {
    ch == r'A' || ch == r'B' || ch == r'C' || ch == r'D' ||
    ch == r'E' || ch == r'F' || ch == r'G'
}

// 判断字符是否为十进制数字
func isDigitRune(ch: Rune): Bool {
    ch >= r'0' && ch <= r'9'
}

// 判断字符是否为空白字符（空格或制表符）
func isSpaceRune(ch: Rune): Bool {
    ch == r' ' || ch == r'\t'
}

// 将数字字符转换为对应的整数值
func runeToDigit(ch: Rune): Int64 {
    ch.position() - r'0'.position()
}

// ── 时值转换 ──

// 将时值标记转换为 MIDI tick 数（基准：480 ticks = 四分音符）
// duration > RAW_TICK_OFFSET：原始 tick 值（减去偏移量后返回）
// duration < 0：附点音符（基础时值 × 1.5）
// duration == 0：默认四分音符（480 ticks）
func durationToTicks(duration: Int64): UInt32 {
    if (duration == 0) { return 480 }
    // 原始 tick 值（readNumber 添加了 RAW_TICK_OFFSET 偏移）
    if (duration > RAW_TICK_OFFSET) {
        return UInt32(duration - RAW_TICK_OFFSET)
    }
    if (duration < 0) {
        // 附点音符：基础时值 × 1.5
        let base = UInt32(480 * 4 / (-duration))
        return base * 3 / 2
    }
    UInt32(480 * 4 / duration)
}

// ── 基本解析函数 ──

// 从 runes 数组的 startPos 位置读取一个时值数字
// 支持格式：4（标准时值）、4.（附点，返回 -4）、T216（原始 tick，返回 216+偏移）
func readNumber(runes: Array<Rune>, startPos: Int64, size: Int64): NumberResult {
    var i = startPos

    // 检测 T 前缀（原始 tick 值）
    if (i < size && runes[i] == r'T') {
        i++
        var num: Int64 = 0
        var found = false
        while (i < size && isDigitRune(runes[i])) {
            num = num * 10 + runeToDigit(runes[i])
            i++
            found = true
        }
        if (!found) { return NumberResult(4, i) }
        // 用 RAW_TICK_OFFSET 标记原始 tick 值
        return NumberResult(num + RAW_TICK_OFFSET, i)
    }

    // 读取普通数字
    var num: Int64 = 0
    var found = false
    while (i < size && isDigitRune(runes[i])) {
        num = num * 10 + runeToDigit(runes[i])
        i++
        found = true
    }
    if (!found) {
        return NumberResult(4, i)   // 默认四分音符
    }
    // 检测附点记号（"."）
    if (i < size && runes[i] == r'.') {
        i++
        return NumberResult(-num, i)  // 负值表示附点
    }
    NumberResult(num, i)
}

// 解析单个音符标记，如 "C#4 8" → 音高 + 时值
// 返回 pitch=-1 表示解析失败
func parseNoteToken(runes: Array<Rune>, startPos: Int64, size: Int64): NoteTokenResult {
    var i = startPos
    let base = basePitch(runes[i])
    if (base < 0) {
        return NoteTokenResult(-1, 0, i + 1)
    }
    i++

    // 处理升降号（# 或 b）
    var offset: Int64 = 0
    if (i < size && runes[i] == r'#') {
        offset = 1
        i++
    } else if (i < size && runes[i] == r'b') {
        offset = -1
        i++
    }

    // 读取八度数字
    if (i >= size || !isDigitRune(runes[i])) {
        return NoteTokenResult(-1, 0, i)
    }
    let octave = runeToDigit(runes[i])
    i++

    // 计算 MIDI 音高值
    let pitch = (octave + 1) * 12 + base + offset

    // 跳过空白，读取时值
    while (i < size && isSpaceRune(runes[i])) { i++ }
    let durResult = readNumber(runes, i, size)
    i = durResult.newPos
    let ticks = Int64(durationToTicks(durResult.value))

    NoteTokenResult(pitch, ticks, i)
}

// 解析和弦内容（方括号 [ ... ] 之间的多个音符）
// 返回包含所有音高的 ChordInfo 和消耗后的位置
func parseChordContent(runes: Array<Rune>, startPos: Int64, size: Int64): ChordParseResult {
    var i = startPos
    let pitches = ArrayList<UInt8>()

    // 逐个解析方括号内的音符
    while (i < size && runes[i] != r']') {
        // 跳过空白
        while (i < size && runes[i] != r']' && isSpaceRune(runes[i])) { i++ }
        if (i >= size || runes[i] == r']') { break }

        if (isNoteName(runes[i])) {
            let base = basePitch(runes[i])
            i++

            var offset: Int64 = 0
            if (i < size && runes[i] == r'#') { offset = 1; i++ }
            else if (i < size && runes[i] == r'b') { offset = -1; i++ }

            if (i < size && isDigitRune(runes[i])) {
                let octave = runeToDigit(runes[i])
                i++
                pitches.add(UInt8((octave + 1) * 12 + base + offset))
            }
        } else {
            i++
        }
    }

    // 跳过右方括号
    if (i < size && runes[i] == r']') { i++ }

    // 跳过空白，读取和弦整体时值
    while (i < size && isSpaceRune(runes[i])) { i++ }
    let durResult = readNumber(runes, i, size)
    i = durResult.newPos

    ChordParseResult(ChordInfo(pitches, durationToTicks(durResult.value)), i)
}

// ── 文本处理工具 ──

// 去除行内注释（"//" 及之后的内容）
func stripComment(line: String): String {
    let runes = line.toRuneArray()
    let size = runes.size
    var i: Int64 = 0
    let sb = StringBuilder()
    while (i < size) {
        if (i + 1 < size && runes[i] == r'/' && runes[i + 1] == r'/') {
            break
        }
        sb.append(runes[i])
        i++
    }
    sb.toString()
}

// 按空白字符分割字符串，返回各个非空词元
func splitWhitespace(s: String): ArrayList<String> {
    let result = ArrayList<String>()
    var current = StringBuilder()
    var inWord = false
    for (ch in s.toRuneArray()) {
        if (isSpaceRune(ch)) {
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
