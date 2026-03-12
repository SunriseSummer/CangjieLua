package midi.decoder

import std.collection.*
import midi.core.*

// ============================================================
// MIDI 乐谱格式反编译器：.mid 二进制 → 乐谱记谱格式
// 改进：IOI 时值、时值舍入、力度分组、休止符吸收、行内排列
// ============================================================

// ── 标准时值表（TPQ=480 基准） ──

let STANDARD_DURATIONS: Array<(Int64, String)> = [
    (1920, "1"), (960, "2"), (480, "4"), (240, "8"), (120, "16"), (60, "32")
]
let DOTTED_DURATIONS: Array<(Int64, String)> = [
    (2880, "1."), (1440, "2."), (720, "4."), (360, "8."), (180, "16."), (90, "32.")
]

let VELOCITY_THRESHOLD: Int64 = 15

// ── 时值转换（带 15% 舍入容差） ──

func ticksToScoreDuration(ticks: UInt32, tpq: Int64): String {
    let scaled: Int64 = Int64(ticks) * 480 / tpq

    // Exact match on standard durations
    for (pair in STANDARD_DURATIONS) {
        if (scaled == pair[0]) { return pair[1] }
    }
    for (pair in DOTTED_DURATIONS) {
        if (scaled == pair[0]) { return pair[1] }
    }

    // Fuzzy match: within 15% of a standard duration
    var bestName = ""
    var bestDist: Int64 = Int64.Max

    for (pair in STANDARD_DURATIONS) {
        let diff = if (scaled > pair[0]) { scaled - pair[0] } else { pair[0] - scaled }
        let threshold = pair[0] * 15 / 100
        if (diff <= threshold && diff < bestDist) {
            bestDist = diff
            bestName = pair[1]
        }
    }
    for (pair in DOTTED_DURATIONS) {
        let diff = if (scaled > pair[0]) { scaled - pair[0] } else { pair[0] - scaled }
        let threshold = pair[0] * 15 / 100
        if (diff <= threshold && diff < bestDist) {
            bestDist = diff
            bestName = pair[1]
        }
    }

    if (!bestName.isEmpty()) { return bestName }

    "T${scaled}"
}

// ── 行内音符收集器 ──

// Collects sequential single notes and flushes them as space-separated lines.
class InlineCollector {
    var parts: ArrayList<String> = ArrayList<String>()
    var count: Int64 = 0
    var sb: StringBuilder

    init(sb: StringBuilder) {
        this.sb = sb
    }

    func flush(): Unit {
        if (parts.size > 0) {
            let joined = StringBuilder()
            var fi: Int64 = 0
            while (fi < parts.size) {
                if (fi > 0) { joined.append("  ") }
                joined.append(parts[fi])
                fi++
            }
            sb.append("${joined}\n")
            parts.clear()
            count = 0
        }
    }

    func add(text: String): Unit {
        parts.add(text)
        count++
        if (count >= 8) { flush() }
    }
}

// Format a single note as "C4 4"
func formatNote(note: PairedNote, tpq: Int64): String {
    let dur = ticksToScoreDuration(note.durationTicks, tpq)
    let name = pitchToName(note.pitch)
    "${name} ${dur}"
}

// Format a chord as "[C3 E3 G3] 2"
func formatChord(chordNotes: ArrayList<PairedNote>, tpq: Int64): String {
    let dur = ticksToScoreDuration(chordNotes[0].durationTicks, tpq)
    let csb = StringBuilder()
    csb.append("[")
    var first = true
    for (n in chordNotes) {
        if (!first) { csb.append(" ") }
        csb.append(pitchToName(n.pitch))
        first = false
    }
    csb.append("] ${dur}")
    csb.toString()
}

// ── 主反编译函数 ──

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
