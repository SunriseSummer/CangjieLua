package midi.core

import std.collection.*

// ============================================================
// 文本乐谱解析器 — 音符与和弦解析
// 基础类型和字符工具见 parser_utils.cj
// ============================================================

// ── 音符标记解析 ──

// 解析单个音符标记，如 "C#4 8" → 音高 + 时值
// 返回 pitch=-1 表示解析失败
func parseNoteToken(runes: Array<Rune>, startPos: Int64, size: Int64): NoteTokenResult {
    var i = startPos
    let base = basePitch(runes[i])
    if (base < 0) {
        return NoteTokenResult(-1, 0, i + 1)
    }
    i++

    // 处理升降号（# 升半音，b 降半音）
    var offset: Int64 = 0
    if (i < size && runes[i] == r'#') {
        offset = 1
        i++
    } else if (i < size && runes[i] == r'b') {
        offset = -1
        i++
    }

    // 读取八度数字（0-9）
    if (i >= size || !isDigitRune(runes[i])) {
        return NoteTokenResult(-1, 0, i)
    }
    let octave = runeToDigit(runes[i])
    i++

    // 计算 MIDI 音高值：(八度+1)*12 + 基础音名偏移 + 升降号
    let pitch = (octave + 1) * 12 + base + offset

    // 跳过空白，读取时值
    while (i < size && isSpaceRune(runes[i])) { i++ }
    let durResult = readNumber(runes, i, size)
    i = durResult.newPos
    let ticks = Int64(durationToTicks(durResult.value))

    NoteTokenResult(pitch, ticks, i)
}

// ── 和弦解析 ──

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

    // 跳过右方括号 ']'
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
