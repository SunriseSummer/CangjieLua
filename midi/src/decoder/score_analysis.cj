package midi.decoder

import std.collection.*
// ============================================================
// MIDI 乐谱分析：事件解码、音符配对、和弦检测、轨道分析
// ============================================================

// ── 内部事件表示 ──

class DecodedEvent {
    var absTick: UInt32
    var eventType: UInt8
    var channel: UInt8
    var data1: UInt8
    var data2: UInt8
    var metaType: UInt8
    var metaData: Array<UInt8>

    init(absTick: UInt32, eventType: UInt8, channel: UInt8,
         data1: UInt8, data2: UInt8) {
        this.absTick = absTick
        this.eventType = eventType
        this.channel = channel
        this.data1 = data1
        this.data2 = data2
        this.metaType = 0
        this.metaData = Array<UInt8>()
    }

    init(absTick: UInt32, metaType: UInt8, metaData: Array<UInt8>) {
        this.absTick = absTick
        this.eventType = 0xFF
        this.channel = 0
        this.data1 = 0
        this.data2 = 0
        this.metaType = metaType
        this.metaData = metaData
    }
}

class PairedNote {
    var pitch: UInt8
    var velocity: UInt8
    var channel: UInt8
    var startTick: UInt32
    var durationTicks: UInt32

    init(pitch: UInt8, velocity: UInt8, channel: UInt8,
         startTick: UInt32, durationTicks: UInt32) {
        this.pitch = pitch
        this.velocity = velocity
        this.channel = channel
        this.startTick = startTick
        this.durationTicks = durationTicks
    }
}

enum ScoreLine {
    | NoteLine(PairedNote)
    | RestLine(UInt32)
    | ChordLine(ArrayList<PairedNote>)
}

// ── 轨道事件解码 ──

func decodeTrackEvents(data: Array<UInt8>, trackStart: Int64, trackEnd: Int64): ArrayList<DecodedEvent> {
    let events = ArrayList<DecodedEvent>()
    var j = trackStart
    var absTick: UInt32 = 0
    var runningStatus: UInt8 = 0

    while (j < trackEnd && j < data.size) {
        let vlq = decReadVLQ(data, j, trackEnd)
        let delta = vlq.value
        j = vlq.newPos
        absTick += delta
        if (j >= trackEnd) { break }

        let firstByte = data[j]

        if (firstByte >= 0x80) {
            if (firstByte == 0xFF) {
                j++
                if (j >= trackEnd) { break }
                let metaType = data[j]
                j++
                let metaVLQ = decReadVLQ(data, j, trackEnd)
                let metaLen = Int64(metaVLQ.value)
                j = metaVLQ.newPos
                let metaBytes = ArrayList<UInt8>()
                var mi: Int64 = 0
                while (mi < metaLen && j + mi < trackEnd) {
                    metaBytes.add(data[j + mi])
                    mi++
                }
                events.add(DecodedEvent(absTick, metaType, metaBytes.toArray()))
                j += metaLen
                runningStatus = 0
            } else if (firstByte == 0xF0 || firstByte == 0xF7) {
                j++
                let sysVLQ = decReadVLQ(data, j, trackEnd)
                let sysLen = Int64(sysVLQ.value)
                j = sysVLQ.newPos + sysLen
                runningStatus = 0
            } else {
                let eventType = firstByte & 0xF0
                let channel = firstByte & 0x0F
                runningStatus = firstByte
                j++
                if (eventType == 0xC0 || eventType == 0xD0) {
                    if (j < trackEnd) {
                        events.add(DecodedEvent(absTick, eventType, channel, data[j], 0))
                        j += 1
                    }
                } else {
                    if (j + 1 < trackEnd) {
                        events.add(DecodedEvent(absTick, eventType, channel, data[j], data[j + 1]))
                        j += 2
                    }
                }
            }
        } else {
            let eventType = runningStatus & 0xF0
            let channel = runningStatus & 0x0F
            if (eventType == 0xC0 || eventType == 0xD0) {
                events.add(DecodedEvent(absTick, eventType, channel, data[j], 0))
                j += 1
            } else {
                if (j + 1 < trackEnd) {
                    events.add(DecodedEvent(absTick, eventType, channel, data[j], data[j + 1]))
                    j += 2
                }
            }
        }

        if (j > trackEnd) { j = trackEnd }
    }

    events
}

// ── 音符配对 ──

func pairNotes(events: ArrayList<DecodedEvent>): ArrayList<PairedNote> {
    let notes = ArrayList<PairedNote>()
    let pending = HashMap<Int64, ArrayList<(UInt32, UInt8)>>()

    for (ev in events) {
        let evType = ev.eventType
        if (evType == 0x90 && ev.data2 > 0) {
            let key = Int64(ev.channel) * 256 + Int64(ev.data1)
            if (!pending.contains(key)) {
                pending[key] = ArrayList<(UInt32, UInt8)>()
            }
            if (let Some(list) <- pending.get(key)) {
                list.add((ev.absTick, ev.data2))
            }
        } else if (evType == 0x80 || (evType == 0x90 && ev.data2 == 0)) {
            let key = Int64(ev.channel) * 256 + Int64(ev.data1)
            if (let Some(list) <- pending.get(key)) {
                if (list.size > 0) {
                    let entry = list[0]
                    list.remove(at: 0)
                    let startTick = entry[0]
                    let velocity = entry[1]
                    let dur = if (ev.absTick > startTick) { ev.absTick - startTick } else { UInt32(0) }
                    notes.add(PairedNote(ev.data1, velocity, ev.channel, startTick, dur))
                }
            }
        }
    }

    // Sort by startTick
    var si: Int64 = 1
    while (si < notes.size) {
        let key = notes[si]
        var sj = si - 1
        while (sj >= 0 && notes[sj].startTick > key.startTick) {
            notes[sj + 1] = notes[sj]
            sj--
        }
        notes[sj + 1] = key
        si++
    }

    notes
}

// ── IOI-based duration assignment ──

// Replace raw note-off durations with inter-onset intervals.
// For sequential notes, the duration becomes the gap from this note's start
// to the next note's start, naturally absorbing small articulation gaps.
func applyIOIDurations(notes: ArrayList<PairedNote>): Unit {
    if (notes.size <= 1) { return }
    var i: Int64 = 0
    while (i < notes.size - 1) {
        let curr = notes[i]
        let next = notes[i + 1]
        if (next.startTick > curr.startTick) {
            let ioi = next.startTick - curr.startTick
            let origEnd = curr.startTick + curr.durationTicks
            // Use IOI when: the next note starts before or near this note's end,
            // i.e. notes overlap or the gap is small relative to the note duration.
            let gap = if (next.startTick > origEnd) { next.startTick - origEnd } else { UInt32(0) }
            if (gap < curr.durationTicks / 2) {
                curr.durationTicks = ioi
            }
        }
        i++
    }
}

// ── 和弦检测与休止符插入 ──

func groupNotesIntoChords(notes: ArrayList<PairedNote>, tpq: Int64): ArrayList<ScoreLine> {
    let lines = ArrayList<ScoreLine>()
    var currentTick: UInt32 = 0
    var i: Int64 = 0
    let restThreshold = UInt32(tpq / 8)

    while (i < notes.size) {
        let note = notes[i]

        // Insert rest only if gap is significant
        if (note.startTick > currentTick) {
            let gap = note.startTick - currentTick
            if (gap >= restThreshold) {
                lines.add(ScoreLine.RestLine(gap))
            }
            currentTick = note.startTick
        }

        // Find simultaneous notes
        var j = i + 1
        while (j < notes.size && notes[j].startTick == note.startTick) {
            j++
        }
        let groupSize = j - i

        if (groupSize == 1) {
            lines.add(ScoreLine.NoteLine(note))
            currentTick = note.startTick + note.durationTicks
        } else {
            // Check if all notes have same duration (chord)
            var allSameDuration = true
            var ki = i + 1
            while (ki < j) {
                if (notes[ki].durationTicks != note.durationTicks) {
                    allSameDuration = false
                    break
                }
                ki++
            }

            if (allSameDuration) {
                let chordNotes = ArrayList<PairedNote>()
                var ci = i
                while (ci < j) {
                    chordNotes.add(notes[ci])
                    ci++
                }
                lines.add(ScoreLine.ChordLine(chordNotes))
                currentTick = note.startTick + note.durationTicks
            } else {
                var ci = i
                while (ci < j) {
                    lines.add(ScoreLine.NoteLine(notes[ci]))
                    let endTick = notes[ci].startTick + notes[ci].durationTicks
                    if (endTick > currentTick) {
                        currentTick = endTick
                    }
                    ci++
                }
            }
        }

        i = j
    }

    lines
}

// ── 轨道元数据提取 ──

func extractTrackName(events: ArrayList<DecodedEvent>): String {
    for (ev in events) {
        if (ev.eventType == 0xFF && ev.metaType == 0x03 && ev.metaData.size > 0) {
            try {
                let name = String.fromUtf8(ev.metaData)
                let sb = StringBuilder()
                for (ch in name.toRuneArray()) {
                    if (ch == r' ' || ch == r'\t') { sb.append(r'_') }
                    else { sb.append(ch) }
                }
                return sb.toString()
            } catch (_: Exception) {
                return ""
            }
        }
    }
    ""
}

func extractProgram(events: ArrayList<DecodedEvent>): Int64 {
    for (ev in events) {
        if (ev.eventType == 0xC0) {
            return Int64(ev.data1)
        }
    }
    -1
}

func extractChannel(events: ArrayList<DecodedEvent>): Int64 {
    for (ev in events) {
        let evType = ev.eventType
        if (evType == 0x90 || evType == 0x80 || evType == 0xC0 || evType == 0xB0) {
            return Int64(ev.channel)
        }
    }
    -1
}

// Find the most common velocity across all Note On events
func extractVelocity(events: ArrayList<DecodedEvent>): Int64 {
    let velCounts = HashMap<Int64, Int64>()
    for (ev in events) {
        if (ev.eventType == 0x90 && ev.data2 > 0) {
            let v = Int64(ev.data2)
            let count = if (let Some(c) <- velCounts.get(v)) { c } else { Int64(0) }
            velCounts[v] = count + 1
        }
    }
    var maxCount: Int64 = 0
    var mainVel: Int64 = 80
    for ((vel, count) in velCounts) {
        if (count > maxCount) {
            maxCount = count
            mainVel = vel
        }
    }
    mainVel
}

func extractTempoEvents(events: ArrayList<DecodedEvent>): ArrayList<(UInt32, Int64)> {
    let tempos = ArrayList<(UInt32, Int64)>()
    for (ev in events) {
        if (ev.eventType == 0xFF && ev.metaType == 0x51 && ev.metaData.size == 3) {
            let micro = UInt32(ev.metaData[0]) << 16 | UInt32(ev.metaData[1]) << 8 | UInt32(ev.metaData[2])
            let bpm = if (micro > 0) { Int64(60000000 / micro) } else { Int64(120) }
            tempos.add((ev.absTick, bpm))
        }
    }
    tempos
}

func extractControlEvents(events: ArrayList<DecodedEvent>): ArrayList<(UInt32, DecodedEvent)> {
    let controls = ArrayList<(UInt32, DecodedEvent)>()
    for (ev in events) {
        if (ev.eventType == 0xB0) {
            controls.add((ev.absTick, ev))
        } else if (ev.eventType == 0xE0) {
            controls.add((ev.absTick, ev))
        }
    }
    controls
}
