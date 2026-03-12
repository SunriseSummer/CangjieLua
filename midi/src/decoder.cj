package midi

import std.collection.*
import std.fs.*

// ============================================================
// MIDI 反编译器：.mid 二进制 → 文本乐谱
// ============================================================

let DEC_DEFAULT_VELOCITY: Int64 = 80     // 默认力度 (与 encoder 一致)
let CHORD_TOLERANCE_DIV: Int64 = 16      // 和弦容差 = TPQ / 此值
let REST_THRESHOLD_DIV: Int64 = 6        // 休止符阈值 = TPQ / 此值
let MAX_NOTES_PER_LINE: Int64 = 4        // 每行最多音符/和弦数
let MAX_INIT_DURATION: UInt32 = 999999   // 和弦最小时值初始值

// 读取大端 UInt16
func decReadU16(data: Array<UInt8>, pos: Int64): UInt16 {
    UInt16(data[pos]) << 8 | UInt16(data[pos + 1])
}

// 读取大端 UInt32
func decReadU32(data: Array<UInt8>, pos: Int64): UInt32 {
    UInt32(data[pos]) << 24 | UInt32(data[pos + 1]) << 16 |
        UInt32(data[pos + 2]) << 8 | UInt32(data[pos + 3])
}

// VLQ 读取结果
class DecVLQ {
    var value: UInt32
    var newPos: Int64
    init(value: UInt32, newPos: Int64) {
        this.value = value
        this.newPos = newPos
    }
}

// 读取 VLQ
func decReadVLQ(data: Array<UInt8>, pos: Int64, end: Int64): DecVLQ {
    var value: UInt32 = 0
    var i = pos
    while (i < end) {
        let b = data[i]
        value = (value << 7) | UInt32(b & 0x7F)
        i++
        if ((b & 0x80) == 0) {
            break
        }
    }
    DecVLQ(value, i)
}

// 待配对的 NoteOn
class PendingNote {
    var pitch: UInt8
    var startTick: UInt32
    var velocity: UInt8
    init(pitch: UInt8, startTick: UInt32, velocity: UInt8) {
        this.pitch = pitch
        this.startTick = startTick
        this.velocity = velocity
    }
}

// 解码后的音符
class DecodedNote {
    var pitch: UInt8
    var startTick: UInt32
    var durationTicks: UInt32
    var velocity: UInt8

    init(pitch: UInt8, startTick: UInt32, durationTicks: UInt32, velocity: UInt8) {
        this.pitch = pitch
        this.startTick = startTick
        this.durationTicks = durationTicks
        this.velocity = velocity
    }
}

// 解码后的轨道
class DecodedTrack {
    var instrument: Int64
    var notes: ArrayList<DecodedNote>
    var avgVelocity: Int64

    init() {
        this.instrument = -1
        this.notes = ArrayList<DecodedNote>()
        this.avgVelocity = 80
    }
}

// MIDI 音高 → 音名字符串
func pitchToName(pitch: UInt8): String {
    let p = Int64(pitch)
    let noteIdx = p % 12
    let octave = p / 12 - 1
    let name = if (noteIdx == 0) { "C" }
        else if (noteIdx == 1) { "C#" }
        else if (noteIdx == 2) { "D" }
        else if (noteIdx == 3) { "D#" }
        else if (noteIdx == 4) { "E" }
        else if (noteIdx == 5) { "F" }
        else if (noteIdx == 6) { "F#" }
        else if (noteIdx == 7) { "G" }
        else if (noteIdx == 8) { "G#" }
        else if (noteIdx == 9) { "A" }
        else if (noteIdx == 10) { "A#" }
        else { "B" }
    "${name}${octave}"
}

// GM 编号 → 乐器名
func programToInstrument(program: Int64): String {
    if (program == 0) { return "piano" }
    if (program == 1) { return "bright_piano" }
    if (program == 4) { return "electric_piano" }
    if (program == 10) { return "music_box" }
    if (program == 13) { return "xylophone" }
    if (program == 22) { return "harmonica" }
    if (program == 24) { return "guitar" }
    if (program == 25) { return "acoustic_guitar" }
    if (program == 26) { return "steel_guitar" }
    if (program == 29) { return "overdriven_guitar" }
    if (program == 33) { return "bass" }
    if (program == 34) { return "electric_bass" }
    if (program == 40) { return "violin" }
    if (program == 41) { return "viola" }
    if (program == 42) { return "cello" }
    if (program == 46) { return "harp" }
    if (program == 48) { return "strings" }
    if (program == 49) { return "ensemble" }
    if (program == 54) { return "voice" }
    if (program == 56) { return "trumpet" }
    if (program == 57) { return "trombone" }
    if (program == 60) { return "horn" }
    if (program == 65) { return "saxophone" }
    if (program == 68) { return "oboe" }
    if (program == 71) { return "clarinet" }
    if (program == 73) { return "flute" }
    if (program == 74) { return "recorder" }
    return "piano"
}

// Ticks → 标准时值 (1, 2, 4, 8, 16, 32)
func quantizeDuration(ticks: UInt32, tpq: UInt16): Int64 {
    let tpqI = Int64(tpq)
    let ticksI = Int64(ticks)
    if (ticksI <= 0) { return 4 }

    let s0 = tpqI * 4        // whole (1)
    let s1 = tpqI * 2        // half (2)
    let s2 = tpqI            // quarter (4)
    let s3 = tpqI / 2        // eighth (8)
    let s4 = tpqI / 4        // sixteenth (16)
    let s5 = tpqI / 8        // thirty-second (32)

    let d0 = if (ticksI > s0) { ticksI - s0 } else { s0 - ticksI }
    let d1 = if (ticksI > s1) { ticksI - s1 } else { s1 - ticksI }
    let d2 = if (ticksI > s2) { ticksI - s2 } else { s2 - ticksI }
    let d3 = if (ticksI > s3) { ticksI - s3 } else { s3 - ticksI }
    let d4 = if (ticksI > s4) { ticksI - s4 } else { s4 - ticksI }
    let d5 = if (s5 > 0) {
        if (ticksI > s5) { ticksI - s5 } else { s5 - ticksI }
    } else { ticksI + 9999 }

    var minDiff = d0
    var dur: Int64 = 1
    if (d1 < minDiff) { minDiff = d1; dur = 2 }
    if (d2 < minDiff) { minDiff = d2; dur = 4 }
    if (d3 < minDiff) { minDiff = d3; dur = 8 }
    if (d4 < minDiff) { minDiff = d4; dur = 16 }
    if (d5 < minDiff) { minDiff = d5; dur = 32 }
    dur
}

// 完成未关闭的音符 (NoteOn without NoteOff)
func flushPending(pending: ArrayList<PendingNote>, notes: ArrayList<DecodedNote>,
                  absTime: UInt32, tpq: UInt16): Unit {
    let defaultDur = UInt32(tpq)
    while (pending.size > 0) {
        let p = pending[0]
        pending.remove(at: 0)
        let dur = if (absTime > p.startTick) { absTime - p.startTick } else { defaultDur }
        notes.add(DecodedNote(p.pitch, p.startTick, dur, p.velocity))
    }
}

// 解析单个轨道的事件
func decodeTrackData(data: Array<UInt8>, trackStart: Int64, trackEnd: Int64,
                     tpq: UInt16): (DecodedTrack, Int64) {
    let track = DecodedTrack()
    var tempoBPM: Int64 = 0
    var j = trackStart
    var absTime: UInt32 = 0
    var runningStatus: UInt8 = 0
    let pending = ArrayList<PendingNote>()
    var totalVel: Int64 = 0
    var velCount: Int64 = 0

    while (j < trackEnd && j < data.size) {
        let vlq = decReadVLQ(data, j, trackEnd)
        absTime += vlq.value
        j = vlq.newPos

        if (j >= trackEnd) { break }

        var status = data[j]
        if (status >= 0x80) {
            runningStatus = status
            j++
        } else {
            status = runningStatus
        }

        let eventType = status & 0xF0

        if (eventType == 0x90) {
            if (j + 1 < trackEnd) {
                let pitch = data[j]
                let vel = data[j + 1]
                j += 2
                if (vel > 0) {
                    pending.add(PendingNote(pitch, absTime, vel))
                    totalVel += Int64(vel)
                    velCount++
                } else {
                    // velocity 0 = NoteOff
                    var fi: Int64 = 0
                    while (fi < pending.size) {
                        if (pending[fi].pitch == pitch) {
                            let pn = pending[fi]
                            pending.remove(at: fi)
                            let dur = if (absTime > pn.startTick) { absTime - pn.startTick } else { UInt32(1) }
                            track.notes.add(DecodedNote(pitch, pn.startTick, dur, pn.velocity))
                            break
                        }
                        fi++
                    }
                }
            } else { j = trackEnd }
        } else if (eventType == 0x80) {
            if (j + 1 < trackEnd) {
                let pitch = data[j]
                j += 2
                var fi: Int64 = 0
                while (fi < pending.size) {
                    if (pending[fi].pitch == pitch) {
                        let pn = pending[fi]
                        pending.remove(at: fi)
                        let dur = if (absTime > pn.startTick) { absTime - pn.startTick } else { UInt32(1) }
                        track.notes.add(DecodedNote(pitch, pn.startTick, dur, pn.velocity))
                        break
                    }
                    fi++
                }
            } else { j = trackEnd }
        } else if (eventType == 0xC0) {
            if (j < trackEnd) {
                track.instrument = Int64(data[j])
                j++
            }
        } else if (eventType == 0xB0 || eventType == 0xA0 || eventType == 0xE0) {
            j += 2
        } else if (eventType == 0xD0) {
            j++
        } else if (status == 0xFF) {
            if (j < trackEnd) {
                let metaType = data[j]
                j++
                let metaVLQ = decReadVLQ(data, j, trackEnd)
                let metaLen = Int64(metaVLQ.value)
                j = metaVLQ.newPos

                if (metaType == 0x51 && metaLen == 3 && j + 2 < trackEnd) {
                    let microPerBeat = UInt32(data[j]) << 16 | UInt32(data[j + 1]) << 8 | UInt32(data[j + 2])
                    if (microPerBeat > 0) {
                        tempoBPM = 60000000 / Int64(microPerBeat)
                    }
                }
                j += metaLen
            }
            runningStatus = 0
        } else if (status == 0xF0 || status == 0xF7) {
            let sysVLQ = decReadVLQ(data, j, trackEnd)
            j = sysVLQ.newPos + Int64(sysVLQ.value)
            runningStatus = 0
        } else {
            j++
        }
    }

    // 处理未关闭的音符
    flushPending(pending, track.notes, absTime, tpq)

    // 计算平均力度
    if (velCount > 0) {
        track.avgVelocity = totalVel / velCount
    }

    // 按起始时间排序（插入排序）
    var si: Int64 = 1
    while (si < track.notes.size) {
        let key = track.notes[si]
        var sj = si - 1
        while (sj >= 0) {
            let curr = track.notes[sj]
            if (curr.startTick > key.startTick ||
                (curr.startTick == key.startTick && curr.pitch > key.pitch)) {
                track.notes[sj + 1] = curr
                sj--
            } else {
                break
            }
        }
        track.notes[sj + 1] = key
        si++
    }

    (track, tempoBPM)
}

// 核心函数：MIDI 文件字节数组 → 文本乐谱
public func decompile(data: Array<UInt8>): String {
    if (data.size < 14) {
        return "// Error: Invalid MIDI file (too short)\n"
    }

    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        return "// Error: Invalid MIDI file (bad MThd)\n"
    }

    let numTracks = Int64(decReadU16(data, 10))
    let tpq = decReadU16(data, 12)

    var tempoBPM: Int64 = 120
    let decodedTracks = ArrayList<DecodedTrack>()

    var pos: Int64 = 14
    var ti: Int64 = 0
    while (ti < numTracks) {
        if (pos + 8 > data.size) { break }
        if (data[pos] != 0x4D || data[pos + 1] != 0x54 ||
            data[pos + 2] != 0x72 || data[pos + 3] != 0x6B) {
            break
        }

        let trackLen = Int64(decReadU32(data, pos + 4))
        let trackStart = pos + 8
        let trackEnd = trackStart + trackLen

        let result = decodeTrackData(data, trackStart, trackEnd, tpq)
        let track = result[0]
        let trackTempo = result[1]

        if (trackTempo > 0) {
            tempoBPM = trackTempo
        }

        if (track.notes.size > 0) {
            decodedTracks.add(track)
        }

        pos = trackEnd
        ti++
    }

    let sb = StringBuilder()
    sb.append("TEMPO ${tempoBPM}\n")

    let isMultiTrack = decodedTracks.size > 1

    var trackIdx: Int64 = 0
    while (trackIdx < decodedTracks.size) {
        let track = decodedTracks[trackIdx]

        if (isMultiTrack) {
            sb.append("\nTRACK track${trackIdx + 1}\n")
        }

        let instrName = if (track.instrument >= 0) {
            programToInstrument(track.instrument)
        } else { "piano" }
        sb.append("INSTRUMENT ${instrName}\n")

        if (track.avgVelocity != DEC_DEFAULT_VELOCITY) {
            sb.append("VELOCITY ${track.avgVelocity}\n")
        }

        // 生成音符行
        let notes = track.notes
        var i: Int64 = 0
        var prevEndTick: UInt32 = 0
        var notesOnLine: Int64 = 0
        let chordTolerance: UInt32 = UInt32(Int64(tpq) / CHORD_TOLERANCE_DIV)
        let restThreshold: UInt32 = UInt32(Int64(tpq) / REST_THRESHOLD_DIV)

        while (i < notes.size) {
            // 找同时开始的音符组（和弦）
            var groupEnd = i + 1
            while (groupEnd < notes.size) {
                let geTick = notes[groupEnd].startTick
                let iTick = notes[i].startTick
                let diff = if (geTick >= iTick) { geTick - iTick } else { UInt32(0) }
                if (diff <= chordTolerance) {
                    groupEnd++
                } else {
                    break
                }
            }

            let groupStart = notes[i].startTick

            // 检测休止符
            if (groupStart > prevEndTick) {
                let gap = groupStart - prevEndTick
                if (gap >= restThreshold) {
                    let restDur = quantizeDuration(gap, tpq)
                    if (notesOnLine > 0) {
                        sb.append("  ")
                    }
                    sb.append("R ${restDur}")
                    notesOnLine++
                    if (notesOnLine >= MAX_NOTES_PER_LINE) {
                        sb.append("\n")
                        notesOnLine = 0
                    }
                }
            }

            if (groupEnd - i == 1) {
                // 单音符
                let note = notes[i]
                let dur = quantizeDuration(note.durationTicks, tpq)
                if (notesOnLine > 0) {
                    sb.append("  ")
                }
                sb.append("${pitchToName(note.pitch)} ${dur}")
                notesOnLine++

                let endTick = note.startTick + note.durationTicks
                if (endTick > prevEndTick) { prevEndTick = endTick }
            } else {
                // 和弦
                if (notesOnLine > 0) {
                    sb.append("  ")
                }
                sb.append("[")
                var minDur: UInt32 = MAX_INIT_DURATION
                var maxEnd: UInt32 = 0
                var ci = i
                while (ci < groupEnd) {
                    if (ci > i) { sb.append(" ") }
                    sb.append(pitchToName(notes[ci].pitch))
                    if (notes[ci].durationTicks < minDur) {
                        minDur = notes[ci].durationTicks
                    }
                    let endTick = notes[ci].startTick + notes[ci].durationTicks
                    if (endTick > maxEnd) { maxEnd = endTick }
                    ci++
                }
                let dur = quantizeDuration(minDur, tpq)
                sb.append("] ${dur}")
                notesOnLine++

                if (maxEnd > prevEndTick) { prevEndTick = maxEnd }
            }

            if (notesOnLine >= MAX_NOTES_PER_LINE) {
                sb.append("\n")
                notesOnLine = 0
            }

            i = groupEnd
        }

        if (notesOnLine > 0) {
            sb.append("\n")
        }

        trackIdx++
    }

    sb.toString()
}

// 反编译 .mid 文件
public func decompileToString(midPath: String): String {
    let data = File.readFrom(Path(midPath))
    decompile(data)
}
