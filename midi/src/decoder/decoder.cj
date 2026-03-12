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

// 在指定区间内输出休止符和速度变化（按 tick 位置交错）
func emitGapWithTempos(sb: StringBuilder, gapStart: UInt32, gapEnd: UInt32,
                       tempoChanges: ArrayList<DecodedTempoChange>,
                       tempoIdxRef: ArrayList<Int64>,
                       tpq: UInt16, notesOnLineRef: ArrayList<Int64>,
                       restThreshold: UInt32): Unit {
    var currentPos = gapStart
    let tidx = tempoIdxRef[0]
    var ti = tidx

    // 检查区间内是否有速度变化
    let hasTemposInGap = ti < tempoChanges.size && tempoChanges[ti].tick < gapEnd

    while (ti < tempoChanges.size && tempoChanges[ti].tick <= gapEnd) {
        let tc = tempoChanges[ti]
        // 输出当前位置到速度变化位置的休止符
        // 有速度变化时使用较低阈值，确保定位准确
        if (tc.tick > currentPos) {
            let restTicks = tc.tick - currentPos
            // 速度变化间的间隔始终保留（即使很小），保证正确的时间位置
            if (notesOnLineRef[0] > 0) { sb.append("  ") }
            sb.append("R ${quantizeDuration(restTicks, tpq)}")
            notesOnLineRef[0]++
            if (notesOnLineRef[0] >= MAX_NOTES_PER_LINE) {
                sb.append("\n")
                notesOnLineRef[0] = 0
            }
            currentPos = tc.tick
        }
        // 输出速度变化
        if (notesOnLineRef[0] > 0) {
            sb.append("\n")
            notesOnLineRef[0] = 0
        }
        sb.append("TEMPO ${tc.bpm}\n")
        ti++
    }
    tempoIdxRef[0] = ti

    // 输出剩余的休止符
    if (gapEnd > currentPos) {
        let restTicks = gapEnd - currentPos
        // 有速度变化时使用较低阈值，无速度变化时使用标准阈值
        let threshold = if (hasTemposInGap) { UInt32(1) } else { restThreshold }
        if (restTicks >= threshold) {
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

// 格式化单个轨道的音符序列（支持内联速度变化）
func formatNotes(sb: StringBuilder, notes: ArrayList<DecodedNote>,
                 tpq: UInt16, tempoChanges: ArrayList<DecodedTempoChange>,
                 firstTempoBPM: Int64): Unit {
    var i: Int64 = 0
    var prevEndTick: UInt32 = 0
    let chordTolerance: UInt32 = UInt32(Int64(tpq) / CHORD_TOLERANCE_DIV)
    let restThreshold: UInt32 = UInt32(Int64(tpq) / REST_THRESHOLD_DIV)

    // 使用 ArrayList 模拟可变引用
    let notesOnLineRef = ArrayList<Int64>()
    notesOnLineRef.add(0)
    let tempoIdxRef = ArrayList<Int64>()
    tempoIdxRef.add(0)

    // 跳过 tick=0 处与初始 BPM 相同的速度变化（已在头部输出）
    while (tempoIdxRef[0] < tempoChanges.size) {
        let tc = tempoChanges[tempoIdxRef[0]]
        if (tc.tick == 0 && tc.bpm == firstTempoBPM) {
            tempoIdxRef[0]++
        } else {
            break
        }
    }

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

        // 在间隙内交错输出休止符和速度变化
        if (groupStart > prevEndTick) {
            emitGapWithTempos(sb, prevEndTick, groupStart, tempoChanges,
                              tempoIdxRef, tpq, notesOnLineRef, restThreshold)
        } else {
            // 即使没有间隙，仍需输出到达此时间点的速度变化
            while (tempoIdxRef[0] < tempoChanges.size && tempoChanges[tempoIdxRef[0]].tick <= groupStart) {
                if (notesOnLineRef[0] > 0) {
                    sb.append("\n")
                    notesOnLineRef[0] = 0
                }
                sb.append("TEMPO ${tempoChanges[tempoIdxRef[0]].bpm}\n")
                tempoIdxRef[0]++
            }
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

    // 输出剩余的速度变化（在所有音符之后）
    while (tempoIdxRef[0] < tempoChanges.size) {
        if (notesOnLineRef[0] > 0) {
            sb.append("\n")
            notesOnLineRef[0] = 0
        }
        sb.append("TEMPO ${tempoChanges[tempoIdxRef[0]].bpm}\n")
        tempoIdxRef[0]++
    }

    if (notesOnLineRef[0] > 0) { sb.append("\n") }
}

// 格式化单个轨道（通道、乐器、力度、音符）
func formatTrack(sb: StringBuilder, track: DecodedTrack,
                 trackIdx: Int64, isMultiTrack: Bool, tpq: UInt16,
                 tempoChanges: ArrayList<DecodedTempoChange>,
                 firstTempoBPM: Int64): Unit {
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

    // 仅第一个含音符的轨道传递速度变化
    let trackTempos = if (trackIdx == 0) { tempoChanges } else { ArrayList<DecodedTempoChange>() }
    formatNotes(sb, track.notes, tpq, trackTempos, firstTempoBPM)
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
    var si: Int64 = 1
    while (si < allTempoChanges.size) {
        let key = allTempoChanges[si]
        var sj = si - 1
        while (sj >= 0 && allTempoChanges[sj].tick > key.tick) {
            allTempoChanges[sj + 1] = allTempoChanges[sj]
            sj--
        }
        allTempoChanges[sj + 1] = key
        si++
    }

    // 确定初始速度
    let firstTempoBPM: Int64 = if (allTempoChanges.size > 0) {
        allTempoChanges[0].bpm
    } else { Int64(120) }

    // 生成文本输出
    let sb = StringBuilder()
    sb.append("TEMPO ${firstTempoBPM}\n")

    let isMultiTrack = decodedTracks.size > 1
    var trackIdx: Int64 = 0
    while (trackIdx < decodedTracks.size) {
        formatTrack(sb, decodedTracks[trackIdx], trackIdx, isMultiTrack, tpq,
                    allTempoChanges, firstTempoBPM)
        trackIdx++
    }

    sb.toString()
}

// 反编译 .mid 文件为文本乐谱
public func decompileToString(midPath: String): String {
    let data = File.readFrom(Path(midPath))
    decompile(data)
}
