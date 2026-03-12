package midi

import std.collection.*
import std.convert.*

// ============================================================
// 解析器：文本乐谱 → MIDI 轨道数据
// ============================================================

public class NoteInfo {
    public var pitch: UInt8
    public var durationTicks: UInt32

    public init(pitch: UInt8, durationTicks: UInt32) {
        this.pitch = pitch
        this.durationTicks = durationTicks
    }
}

public class ChordInfo {
    public var pitches: ArrayList<UInt8>
    public var durationTicks: UInt32

    public init(pitches: ArrayList<UInt8>, durationTicks: UInt32) {
        this.pitches = pitches
        this.durationTicks = durationTicks
    }
}

public enum MusicElement {
    | SingleNote(NoteInfo)
    | Chord(ChordInfo)
    | Rest(UInt32)
}

public class TrackData {
    var name: String
    var instrument: Int64
    var velocity: Int64
    var elements: ArrayList<MusicElement>

    init(name: String) {
        this.name = name
        this.instrument = -1
        this.velocity = -1
        this.elements = ArrayList<MusicElement>()
    }
}

public class ScoreData {
    public var tempo: Int64
    public var tracks: ArrayList<TrackData>

    public init() {
        this.tempo = 120
        this.tracks = ArrayList<TrackData>()
    }
}

// 辅助结构代替元组
class NumberResult {
    var value: Int64
    var newPos: Int64
    init(value: Int64, newPos: Int64) {
        this.value = value
        this.newPos = newPos
    }
}

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

class ChordParseResult {
    var chord: ChordInfo
    var newPos: Int64
    init(chord: ChordInfo, newPos: Int64) {
        this.chord = chord
        this.newPos = newPos
    }
}

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

// 乐器名 → GM 编号
func instrumentNumber(name: String): Int64 {
    let lower = name.toAsciiLower()
    if (lower == "piano") { return 0 }
    if (lower == "bright_piano") { return 1 }
    if (lower == "electric_piano") { return 4 }
    if (lower == "music_box") { return 10 }
    if (lower == "xylophone") { return 13 }
    if (lower == "harmonica") { return 22 }
    if (lower == "guitar") { return 24 }
    if (lower == "acoustic_guitar") { return 25 }
    if (lower == "steel_guitar") { return 26 }
    if (lower == "overdriven_guitar") { return 29 }
    if (lower == "bass") { return 33 }
    if (lower == "electric_bass") { return 34 }
    if (lower == "violin") { return 40 }
    if (lower == "viola") { return 41 }
    if (lower == "cello") { return 42 }
    if (lower == "harp") { return 46 }
    if (lower == "strings") { return 48 }
    if (lower == "ensemble") { return 49 }
    if (lower == "voice") { return 54 }
    if (lower == "trumpet") { return 56 }
    if (lower == "trombone") { return 57 }
    if (lower == "horn") { return 60 }
    if (lower == "saxophone") { return 65 }
    if (lower == "oboe") { return 68 }
    if (lower == "clarinet") { return 71 }
    if (lower == "flute") { return 73 }
    if (lower == "recorder") { return 74 }
    return 0
}

// 时值 → ticks (480 ticks/四分音符)
func durationToTicks(duration: Int64): UInt32 {
    if (duration <= 0) { return 480 }
    UInt32(480 * 4 / duration)
}

func isNoteName(ch: Rune): Bool {
    ch == r'A' || ch == r'B' || ch == r'C' || ch == r'D' || ch == r'E' || ch == r'F' || ch == r'G'
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
        return NumberResult(4, i)
    }
    NumberResult(num, i)
}

func parseNoteToken(runes: Array<Rune>, startPos: Int64, size: Int64): NoteTokenResult {
    var i = startPos
    let base = basePitch(runes[i])
    if (base < 0) {
        return NoteTokenResult(-1, 0, i + 1)
    }
    i++

    var offset: Int64 = 0
    if (i < size && runes[i] == r'#') {
        offset = 1
        i++
    } else if (i < size && runes[i] == r'b') {
        offset = -1
        i++
    }

    if (i >= size || !isDigitRune(runes[i])) {
        return NoteTokenResult(-1, 0, i)
    }
    let octave = runeToDigit(runes[i])
    i++

    let pitch = (octave + 1) * 12 + base + offset

    while (i < size && isSpaceRune(runes[i])) {
        i++
    }

    let durResult = readNumber(runes, i, size)
    i = durResult.newPos
    let ticks = Int64(durationToTicks(durResult.value))

    NoteTokenResult(pitch, ticks, i)
}

func parseChordContent(runes: Array<Rune>, startPos: Int64, size: Int64): ChordParseResult {
    var i = startPos
    let pitches = ArrayList<UInt8>()

    while (i < size && runes[i] != r']') {
        while (i < size && runes[i] != r']' && isSpaceRune(runes[i])) {
            i++
        }
        if (i >= size || runes[i] == r']') { break }

        if (isNoteName(runes[i])) {
            let base = basePitch(runes[i])
            i++

            var offset: Int64 = 0
            if (i < size && runes[i] == r'#') {
                offset = 1
                i++
            } else if (i < size && runes[i] == r'b') {
                offset = -1
                i++
            }

            if (i < size && isDigitRune(runes[i])) {
                let octave = runeToDigit(runes[i])
                i++
                let pitch = (octave + 1) * 12 + base + offset
                pitches.add(UInt8(pitch))
            }
        } else {
            i++
        }
    }

    if (i < size && runes[i] == r']') { i++ }

    while (i < size && isSpaceRune(runes[i])) { i++ }

    let durResult = readNumber(runes, i, size)
    i = durResult.newPos
    let ticks = durationToTicks(durResult.value)

    ChordParseResult(ChordInfo(pitches, ticks), i)
}

// 去除行内注释
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

// 按空白分割
func splitWhitespace(s: String): ArrayList<String> {
    let result = ArrayList<String>()
    var current = StringBuilder()
    var inWord = false
    let runes = s.toRuneArray()
    for (ch in runes) {
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
    if (inWord) {
        result.add(current.toString())
    }
    result
}

// 解析一行音符
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
            let chordResult = parseChordContent(runes, i, size)
            track.elements.add(MusicElement.Chord(chordResult.chord))
            i = chordResult.newPos
            continue
        }

        // 休止符
        if (runes[i] == r'R') {
            i++
            while (i < size && isSpaceRune(runes[i])) { i++ }
            let durResult = readNumber(runes, i, size)
            i = durResult.newPos
            let ticks = durationToTicks(durResult.value)
            track.elements.add(MusicElement.Rest(ticks))
            continue
        }

        // 音符
        if (isNoteName(runes[i])) {
            let noteResult = parseNoteToken(runes, i, size)
            if (noteResult.pitch >= 0) {
                track.elements.add(MusicElement.SingleNote(NoteInfo(UInt8(noteResult.pitch), UInt32(noteResult.ticks))))
            }
            i = noteResult.newPos
            continue
        }

        i++
    }
}

// 解析文本乐谱
public func parseScore(input: String): ScoreData {
    let score = ScoreData()
    var currentTrack = TrackData("default")
    var hasExplicitTrack = false

    let lines = input.split("\n")

    for (line in lines) {
        let stripped = stripComment(line).trimAscii()
        if (stripped.isEmpty()) { continue }

        if (stripped.startsWith("TEMPO")) {
            let parts = splitWhitespace(stripped)
            if (parts.size >= 2) {
                try {
                    score.tempo = Int64.parse(parts[1])
                } catch (_: Exception) {}
            }
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
            let parts = splitWhitespace(stripped)
            if (parts.size >= 2) {
                try {
                    currentTrack.velocity = Int64.parse(parts[1])
                } catch (_: Exception) {}
            }
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
