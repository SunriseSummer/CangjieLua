package midi.core

import std.collection.*
import std.convert.*

// ============================================================
// 文本乐谱解析器：文本 → ScoreData
// ============================================================

// ── 解析辅助类型 ──

// 数字解析结果
class NumberResult {
    var value: Int64
    var newPos: Int64
    init(value: Int64, newPos: Int64) {
        this.value = value
        this.newPos = newPos
    }
}

// 音符解析结果
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

// 和弦解析结果
class ChordParseResult {
    var chord: ChordInfo
    var newPos: Int64
    init(chord: ChordInfo, newPos: Int64) {
        this.chord = chord
        this.newPos = newPos
    }
}

// ── 字符判断工具 ──

// 音高基础值: C=0, D=2, E=4, F=5, G=7, A=9, B=11
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

// 时值 → ticks（480 ticks / 四分音符）
func durationToTicks(duration: Int64): UInt32 {
    if (duration <= 0) { return 480 }
    UInt32(480 * 4 / duration)
}

func isNoteName(ch: Rune): Bool {
    ch == r'A' || ch == r'B' || ch == r'C' || ch == r'D' ||
    ch == r'E' || ch == r'F' || ch == r'G'
}

func isDigitRune(ch: Rune): Bool {
    ch >= r'0' && ch <= r'9'
}

func isSpaceRune(ch: Rune): Bool {
    ch == r' ' || ch == r'\t'
}

func runeToDigit(ch: Rune): Int64 {
    ch.position() - r'0'.position()
}

// ── 基本解析函数 ──

// 从 runes 的 startPos 位置读取一个整数
func readNumber(runes: Array<Rune>, startPos: Int64, size: Int64): NumberResult {
    var i = startPos
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
    NumberResult(num, i)
}

// 解析单个音符标记（如 C#4 8）
func parseNoteToken(runes: Array<Rune>, startPos: Int64, size: Int64): NoteTokenResult {
    var i = startPos
    let base = basePitch(runes[i])
    if (base < 0) {
        return NoteTokenResult(-1, 0, i + 1)
    }
    i++

    // 升降号
    var offset: Int64 = 0
    if (i < size && runes[i] == r'#') {
        offset = 1
        i++
    } else if (i < size && runes[i] == r'b') {
        offset = -1
        i++
    }

    // 八度
    if (i >= size || !isDigitRune(runes[i])) {
        return NoteTokenResult(-1, 0, i)
    }
    let octave = runeToDigit(runes[i])
    i++

    let pitch = (octave + 1) * 12 + base + offset

    // 跳过空白，读取时值
    while (i < size && isSpaceRune(runes[i])) { i++ }
    let durResult = readNumber(runes, i, size)
    i = durResult.newPos
    let ticks = Int64(durationToTicks(durResult.value))

    NoteTokenResult(pitch, ticks, i)
}

// 解析和弦内容（[C3 E3 G3] 之间的部分）
func parseChordContent(runes: Array<Rune>, startPos: Int64, size: Int64): ChordParseResult {
    var i = startPos
    let pitches = ArrayList<UInt8>()

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

    if (i < size && runes[i] == r']') { i++ }

    // 跳过空白，读取时值
    while (i < size && isSpaceRune(runes[i])) { i++ }
    let durResult = readNumber(runes, i, size)
    i = durResult.newPos

    ChordParseResult(ChordInfo(pitches, durationToTicks(durResult.value)), i)
}

// ── 行解析 ──

// 去除行内注释（// 之后的内容）
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

// 按空白分割字符串
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

// 解析一行音符/和弦/休止符
func parseNoteLine(line: String, track: TrackData): Unit {
    let runes = line.toRuneArray()
    let size = runes.size
    var i: Int64 = 0

    while (i < size) {
        while (i < size && isSpaceRune(runes[i])) { i++ }
        if (i >= size) { break }

        // 和弦 [...]
        if (runes[i] == r'[') {
            i++
            let cr = parseChordContent(runes, i, size)
            track.elements.add(MusicElement.Chord(cr.chord))
            i = cr.newPos
            continue
        }

        // 休止符 R
        if (runes[i] == r'R') {
            i++
            while (i < size && isSpaceRune(runes[i])) { i++ }
            let dr = readNumber(runes, i, size)
            i = dr.newPos
            track.elements.add(MusicElement.Rest(durationToTicks(dr.value)))
            continue
        }

        // 音符
        if (isNoteName(runes[i])) {
            let nr = parseNoteToken(runes, i, size)
            if (nr.pitch >= 0) {
                track.elements.add(
                    MusicElement.SingleNote(NoteInfo(UInt8(nr.pitch), UInt32(nr.ticks)))
                )
            }
            i = nr.newPos
            continue
        }

        i++
    }
}

// ── 指令处理 ──

// 处理 TEMPO 指令
func handleTempo(parts: ArrayList<String>, score: ScoreData): Unit {
    if (parts.size >= 2) {
        try { score.tempo = Int64.parse(parts[1]) } catch (_: Exception) {}
    }
}

// 处理 VELOCITY 指令
func handleVelocity(parts: ArrayList<String>, track: TrackData): Unit {
    if (parts.size >= 2) {
        try { track.velocity = Int64.parse(parts[1]) } catch (_: Exception) {}
    }
}

// ── 主解析函数 ──

// 解析完整的文本乐谱
public func parseScore(input: String): ScoreData {
    let score = ScoreData()
    var currentTrack = TrackData("default")
    var hasExplicitTrack = false

    for (line in input.split("\n")) {
        let stripped = stripComment(line).trimAscii()
        if (stripped.isEmpty()) { continue }

        if (stripped.startsWith("TEMPO")) {
            handleTempo(splitWhitespace(stripped), score)
            continue
        }

        if (stripped.startsWith("INSTRUMENT")) {
            let parts = splitWhitespace(stripped)
            if (parts.size >= 2) {
                currentTrack.instrument = instrumentNumber(parts[1])
            }
            continue
        }

        if (stripped.startsWith("VELOCITY")) {
            handleVelocity(splitWhitespace(stripped), currentTrack)
            continue
        }

        if (stripped.startsWith("TRACK")) {
            let parts = splitWhitespace(stripped)
            let trackName = if (parts.size >= 2) { parts[1] } else { "track" }
            if (hasExplicitTrack || currentTrack.elements.size > 0) {
                score.tracks.add(currentTrack)
            }
            currentTrack = TrackData(trackName)
            hasExplicitTrack = true
            continue
        }

        parseNoteLine(stripped, currentTrack)
    }

    if (currentTrack.elements.size > 0 || hasExplicitTrack) {
        score.tracks.add(currentTrack)
    }
    if (score.tracks.size == 0) {
        score.tracks.add(TrackData("default"))
    }

    score
}
