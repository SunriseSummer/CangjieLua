package midi.decoder

import std.collection.*
import std.fs.*
import midi.core.*

// ============================================================
// MIDI 反编译器：.mid 二进制 → 文本乐谱
// ============================================================

let CHORD_TOLERANCE_DIV: Int64 = 16    // 和弦容差 = TPQ / 此值
let REST_THRESHOLD_DIV: Int64 = 6      // 休止符阈值 = TPQ / 此值
let MAX_NOTES_PER_LINE: Int64 = 4      // 每行最多音符/和弦数
let MAX_INIT_DURATION: UInt32 = 999999 // 和弦最小时值初始值

// ── 轨道文本格式化 ──

// 在指定区间内输出休止符（无速度变化交错，速度变化使用 TEMPO_AT）
func emitGapRest(sb: StringBuilder, gapStart: UInt32, gapEnd: UInt32,
                 tpq: UInt16, notesOnLineRef: ArrayList<Int64>,
                 restThreshold: UInt32): Unit {
    if (gapEnd > gapStart) {
        let restTicks = gapEnd - gapStart
        if (restTicks >= restThreshold) {
            if (notesOnLineRef[0] > 0) { sb.append("  ") }
            sb.append("R ${quantizeDuration(restTicks, tpq)}")
            notesOnLineRef[0]++
            if (notesOnLineRef[0] >= MAX_NOTES_PER_LINE) {
                sb.append("\n")
                notesOnLineRef[0] = 0
            }
        }
    }
}

// 格式化单个轨道的音符序列
func formatNotes(sb: StringBuilder, notes: ArrayList<DecodedNote>,
                 tpq: UInt16): Unit {
    var i: Int64 = 0
    var prevEndTick: UInt32 = 0
    let chordTolerance: UInt32 = UInt32(Int64(tpq) / CHORD_TOLERANCE_DIV)
    let restThreshold: UInt32 = UInt32(Int64(tpq) / REST_THRESHOLD_DIV)

    // 使用 ArrayList 模拟可变引用
    let notesOnLineRef = ArrayList<Int64>()
    notesOnLineRef.add(0)

    while (i < notes.size) {
        // 查找同时开始的音符组（和弦检测）
        var groupEnd = i + 1
        while (groupEnd < notes.size) {
            let diff = if (notes[groupEnd].startTick >= notes[i].startTick) {
                notes[groupEnd].startTick - notes[i].startTick
            } else { UInt32(0) }
            if (diff <= chordTolerance) { groupEnd++ } else { break }
        }

        let groupStart = notes[i].startTick

        // 检测并插入休止符
        if (groupStart > prevEndTick) {
            emitGapRest(sb, prevEndTick, groupStart, tpq, notesOnLineRef, restThreshold)
        }

        // 输出单音或和弦
        if (groupEnd - i == 1) {
            let note = notes[i]
            if (notesOnLineRef[0] > 0) { sb.append("  ") }
            sb.append("${pitchToName(note.pitch)} ${quantizeDuration(note.durationTicks, tpq)}")
            notesOnLineRef[0]++
            let endTick = note.startTick + note.durationTicks
            if (endTick > prevEndTick) { prevEndTick = endTick }
        } else {
            if (notesOnLineRef[0] > 0) { sb.append("  ") }
            sb.append("[")
            var minDur: UInt32 = MAX_INIT_DURATION
            var maxEnd: UInt32 = 0
            var ci = i
            while (ci < groupEnd) {
                if (ci > i) { sb.append(" ") }
                sb.append(pitchToName(notes[ci].pitch))
                if (notes[ci].durationTicks < minDur) { minDur = notes[ci].durationTicks }
                let endTick = notes[ci].startTick + notes[ci].durationTicks
                if (endTick > maxEnd) { maxEnd = endTick }
                ci++
            }
            sb.append("] ${quantizeDuration(minDur, tpq)}")
            notesOnLineRef[0]++
            if (maxEnd > prevEndTick) { prevEndTick = maxEnd }
        }

        if (notesOnLineRef[0] >= MAX_NOTES_PER_LINE) {
            sb.append("\n")
            notesOnLineRef[0] = 0
        }

        i = groupEnd
    }

    if (notesOnLineRef[0] > 0) { sb.append("\n") }
}

// 格式化单个轨道（通道、乐器、力度、音符）
func formatTrack(sb: StringBuilder, track: DecodedTrack,
                 trackIdx: Int64, isMultiTrack: Bool, tpq: UInt16): Unit {
    if (isMultiTrack) {
        sb.append("\nTRACK track${trackIdx + 1}\n")
    }

    // 输出 MIDI 通道（仅非默认情况）
    if (track.channel >= 0) {
        sb.append("CHANNEL ${track.channel}\n")
    }

    let instrName = if (track.instrument >= 0) {
        programToInstrument(track.instrument)
    } else { "piano" }
    sb.append("INSTRUMENT ${instrName}\n")

    if (track.avgVelocity != DEC_DEFAULT_VELOCITY) {
        sb.append("VELOCITY ${track.avgVelocity}\n")
    }

    formatNotes(sb, track.notes, tpq)
}

// ── 反编译主函数 ──

// MIDI 文件字节数组 → 文本乐谱
public func decompile(data: Array<UInt8>): String {
    if (data.size < 14) {
        return "// Error: Invalid MIDI file (too short)\n"
    }
    // 验证 MThd 签名
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        return "// Error: Invalid MIDI file (bad MThd)\n"
    }

    let numTracks = Int64(decReadU16(data, 10))
    let tpq = decReadU16(data, 12)

    // 解码所有轨道，收集速度变化
    let allTempoChanges = ArrayList<DecodedTempoChange>()
    let decodedTracks = ArrayList<DecodedTrack>()
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

        let result = decodeTrackData(data, trackStart, trackEnd, tpq)
        // 收集所有速度变化
        for (tc in result.tempoChanges) {
            allTempoChanges.add(tc)
        }
        if (result.track.notes.size > 0) { decodedTracks.add(result.track) }

        pos = trackEnd
        ti++
    }

    // 按 tick 排序速度变化
    sortTempoChanges(allTempoChanges)

    // 确定初始速度
    let firstTempoBPM: Int64 = if (allTempoChanges.size > 0) {
        allTempoChanges[0].bpm
    } else { Int64(120) }

    // 生成文本输出
    let sb = StringBuilder()
    sb.append("TEMPO ${firstTempoBPM}\n")

    // 输出所有速度变化（使用绝对 tick 位置，缩放到 TPQ=480）
    for (tc in allTempoChanges) {
        // 跳过初始速度（已在 TEMPO 行输出）
        if (tc.tick == 0 && tc.bpm == firstTempoBPM) { continue }
        let scaledTick = scaleTicks(tc.tick, tpq)
        sb.append("TEMPO_AT ${scaledTick} ${tc.bpm}\n")
    }

    let isMultiTrack = decodedTracks.size > 1
    var trackIdx: Int64 = 0
    while (trackIdx < decodedTracks.size) {
        formatTrack(sb, decodedTracks[trackIdx], trackIdx, isMultiTrack, tpq)
        trackIdx++
    }

    sb.toString()
}

// 反编译 .mid 文件为文本乐谱
public func decompileToString(midPath: String): String {
    let data = File.readFrom(Path(midPath))
    decompile(data)
}
