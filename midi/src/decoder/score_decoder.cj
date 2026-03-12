package midi.decoder

import std.collection.*
import midi.core.*

// ============================================================
// MIDI 乐谱格式反编译器：.mid 二进制 → 乐谱记谱格式
// 时值转换与行内收集器见 score_duration.cj
// 事件解码与音符配对见 score_analysis.cj
// 和弦检测与元数据提取见 score_grouping.cj
// ============================================================

// ── 主反编译函数 ──

// 将 MIDI 二进制数据反编译为乐谱记谱格式文本
// 流程：解码轨道事件 → 提取元数据 → 配对音符 → 分组输出
public func decompileScore(data: Array<UInt8>): String {
    if (data.size < 14) {
        return "// Error: Invalid MIDI file (too short)\n"
    }
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        return "// Error: Invalid MIDI file (bad MThd)\n"
    }

    let numTracks = Int64(decReadU16(data, 10))
    let tpq = Int64(decReadU16(data, 12))

    // Decode all track events
    let allTrackEvents = ArrayList<ArrayList<DecodedEvent>>()
    var pos: Int64 = 14
    var ti: Int64 = 0
    while (ti < numTracks) {
        if (pos + 8 > data.size) { break }
        if (data[pos] != 0x4D || data[pos + 1] != 0x54 ||
            data[pos + 2] != 0x72 || data[pos + 3] != 0x6B) { break }
        let trackLen = Int64(decReadU32(data, pos + 4))
        let trackStart = pos + 8
        let trackEnd = trackStart + trackLen
        allTrackEvents.add(decodeTrackEvents(data, trackStart, trackEnd))
        pos = trackEnd
        ti++
    }

    // Collect and sort tempo events across all tracks
    let allTempos = ArrayList<(UInt32, Int64)>()
    for (trackEvents in allTrackEvents) {
        let tempos = extractTempoEvents(trackEvents)
        for (t in tempos) { allTempos.add(t) }
    }
    var si: Int64 = 1
    while (si < allTempos.size) {
        let key = allTempos[si]
        var sj = si - 1
        while (sj >= 0 && allTempos[sj][0] > key[0]) {
            allTempos[sj + 1] = allTempos[sj]
            sj--
        }
        allTempos[sj + 1] = key
        si++
    }

    let sb = StringBuilder()

    // Global TEMPO
    let initialBpm = if (allTempos.size > 0) { allTempos[0][1] } else { Int64(120) }
    sb.append("TEMPO ${initialBpm}\n")

    // TEMPO_AT for subsequent tempo changes
    var tci: Int64 = 1
    while (tci < allTempos.size) {
        let tick = allTempos[tci][0]
        let bpm = allTempos[tci][1]
        let scaledTick = UInt32(Int64(tick) * 480 / tpq)
        sb.append("TEMPO_AT ${scaledTick} ${bpm}\n")
        tci++
    }

    // Generate each track
    var trackIdx: Int64 = 0
    for (trackEvents in allTrackEvents) {
        // Skip conductor-only tracks (no notes, no channel events)
        var hasNotes = false
        var hasChannelEvents = false
        for (ev in trackEvents) {
            if (ev.eventType == 0x90 && ev.data2 > 0) { hasNotes = true; break }
            if (ev.eventType == 0xC0 || ev.eventType == 0xB0 || ev.eventType == 0xE0) {
                hasChannelEvents = true
            }
        }
        if (!hasNotes && !hasChannelEvents) {
            trackIdx++
            continue
        }

        // Track metadata
        var trackName = extractTrackName(trackEvents)
        if (trackName.isEmpty()) { trackName = "track${trackIdx}" }

        let program = extractProgram(trackEvents)
        let channel = extractChannel(trackEvents)
        let mainVelocity = extractVelocity(trackEvents)

        sb.append("\nTRACK ${trackName}\n")
        if (program >= 0) {
            sb.append("INSTRUMENT ${programToInstrument(program)}\n")
        }
        if (mainVelocity != 80) {
            sb.append("VELOCITY ${mainVelocity}\n")
        }
        if (channel >= 0) {
            sb.append("CHANNEL ${channel}\n")
        }

        // Pair notes and apply IOI-based durations
        let pairedNotes = pairNotes(trackEvents)
        applyIOIDurations(pairedNotes)

        let controlEvents = extractControlEvents(trackEvents)
        let noteLines = groupNotesIntoChords(pairedNotes, tpq)

        // Output with velocity grouping and inline notes
        var ctrlIdx: Int64 = 0
        var currentOutputTick: UInt32 = 0
        var activeVelocity: Int64 = mainVelocity
        let collector = InlineCollector(sb)

        for (line in noteLines) {
            // Insert control events at current position
            while (ctrlIdx < controlEvents.size) {
                let ctrlTick = controlEvents[ctrlIdx][0]
                if (ctrlTick > currentOutputTick) { break }
                collector.flush()
                let ctrlEv = controlEvents[ctrlIdx][1]
                if (ctrlEv.eventType == 0xB0) {
                    sb.append("CC ${ctrlEv.data1} ${ctrlEv.data2}\n")
                } else if (ctrlEv.eventType == 0xE0) {
                    sb.append("PITCH_BEND ${ctrlEv.data1} ${ctrlEv.data2}\n")
                }
                ctrlIdx++
            }

            match (line) {
                case ScoreLine.NoteLine(note) =>
                    let noteVel = Int64(note.velocity)
                    let velDiff = if (noteVel > activeVelocity) { noteVel - activeVelocity } else { activeVelocity - noteVel }
                    if (velDiff >= VELOCITY_THRESHOLD) {
                        collector.flush()
                        sb.append("VELOCITY ${noteVel}\n")
                        activeVelocity = noteVel
                    }
                    collector.add(formatNote(note, tpq))
                    currentOutputTick = note.startTick + note.durationTicks

                case ScoreLine.ChordLine(chordNotes) =>
                    let noteVel = Int64(chordNotes[0].velocity)
                    let velDiff = if (noteVel > activeVelocity) { noteVel - activeVelocity } else { activeVelocity - noteVel }
                    if (velDiff >= VELOCITY_THRESHOLD) {
                        collector.flush()
                        sb.append("VELOCITY ${noteVel}\n")
                        activeVelocity = noteVel
                    }
                    collector.flush()
                    sb.append("${formatChord(chordNotes, tpq)}\n")
                    currentOutputTick = chordNotes[0].startTick + chordNotes[0].durationTicks

                case ScoreLine.RestLine(ticks) =>
                    collector.flush()
                    let dur = ticksToScoreDuration(ticks, tpq)
                    sb.append("R ${dur}\n")
                    currentOutputTick += ticks
            }
        }

        collector.flush()

        // Output remaining control events
        while (ctrlIdx < controlEvents.size) {
            let ctrlEv = controlEvents[ctrlIdx][1]
            if (ctrlEv.eventType == 0xB0) {
                sb.append("CC ${ctrlEv.data1} ${ctrlEv.data2}\n")
            } else if (ctrlEv.eventType == 0xE0) {
                sb.append("PITCH_BEND ${ctrlEv.data1} ${ctrlEv.data2}\n")
            }
            ctrlIdx++
        }

        trackIdx++
    }

    sb.toString()
}
