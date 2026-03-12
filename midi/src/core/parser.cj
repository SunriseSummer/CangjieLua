package midi.core

import std.collection.*
import std.convert.*

// ============================================================
// 文本乐谱解析器 — 行解析与主入口
// 辅助类型和工具函数见 parser_utils.cj
// ============================================================

// ── 行解析 ──

// 解析一行音符/和弦/休止符，将解析出的元素添加到轨道中
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

// 处理 TEMPO 指令：从指令参数中读取 BPM 值并设置到乐谱数据
func handleTempo(parts: ArrayList<String>, score: ScoreData): Unit {
    if (parts.size >= 2) {
        try { score.tempo = Int64.parse(parts[1]) } catch (_: Exception) {}
    }
}

// 处理 VELOCITY 指令：从指令参数中读取力度值并设置到当前轨道
func handleVelocity(parts: ArrayList<String>, track: TrackData): Unit {
    if (parts.size >= 2) {
        try { track.velocity = Int64.parse(parts[1]) } catch (_: Exception) {}
    }
}

// ── 主解析函数 ──

// 解析完整的文本乐谱，支持 TEMPO / CHANNEL / INSTRUMENT / VELOCITY / CC / PITCH_BEND / TRACK 等指令
// 返回包含所有轨道和全局设置的 ScoreData 结构
public func parseScore(input: String): ScoreData {
    let score = ScoreData()
    var currentTrack = TrackData("default")
    var hasExplicitTrack = false

    for (line in input.split("\n")) {
        let stripped = stripComment(line).trimAscii()
        if (stripped.isEmpty()) { continue }

        if (stripped.startsWith("TEMPO_AT")) {
            let parts = splitWhitespace(stripped)
            if (parts.size >= 3) {
                try {
                    let tick = UInt32.parse(parts[1])
                    let bpm = Int64.parse(parts[2])
                    score.tempoChanges.add(TempoEntry(tick, bpm))
                } catch (_: Exception) {}
            }
            continue
        }

        if (stripped.startsWith("TEMPO")) {
            let parts = splitWhitespace(stripped)
            if (parts.size >= 2) {
                // 在 TRACK 内部时，TEMPO 始终为内联速度变化
                if (hasExplicitTrack) {
                    try {
                        let bpm = Int64.parse(parts[1])
                        currentTrack.elements.add(MusicElement.TempoChange(bpm))
                    } catch (_: Exception) {}
                } else {
                    handleTempo(parts, score)
                }
            }
            continue
        }

        if (stripped.startsWith("CHANNEL")) {
            let parts = splitWhitespace(stripped)
            if (parts.size >= 2) {
                try { currentTrack.channel = Int64.parse(parts[1]) } catch (_: Exception) {}
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
            handleVelocity(splitWhitespace(stripped), currentTrack)
            continue
        }

        if (stripped.startsWith("CC")) {
            let parts = splitWhitespace(stripped)
            if (parts.size >= 3) {
                try {
                    let ctrl = UInt8.parse(parts[1])
                    let val2 = UInt8.parse(parts[2])
                    currentTrack.elements.add(MusicElement.CC(CCInfo(ctrl, val2)))
                } catch (_: Exception) {}
            }
            continue
        }

        if (stripped.startsWith("PITCH_BEND")) {
            let parts = splitWhitespace(stripped)
            if (parts.size >= 3) {
                try {
                    let lsb = UInt8.parse(parts[1])
                    let msb = UInt8.parse(parts[2])
                    currentTrack.elements.add(MusicElement.PitchBend(PitchBendInfo(lsb, msb)))
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
