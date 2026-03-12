package midi.decoder

import std.collection.*
import midi.core.*

// ============================================================
// MIDI 乐谱格式反编译器：.mid 二进制 → 乐谱记谱格式（对称友好）
// ============================================================

// ── 内部事件表示 ──

// 解码后的原始事件（带绝对 tick 位置）
class DecodedEvent {
    var absTick: UInt32       // 绝对 tick 位置
    var eventType: UInt8      // 事件类型 (0x90=NoteOn, 0x80=NoteOff, 0xC0=Program, ...)
    var channel: UInt8        // MIDI 通道
    var data1: UInt8          // 数据字节 1
    var data2: UInt8          // 数据字节 2
    var metaType: UInt8       // Meta 事件类型 (仅 0xFF 事件)
    var metaData: Array<UInt8> // Meta 事件数据

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

// 已配对的音符（ON+OFF → 完整音符）
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

// 乐谱行：用于排列输出
enum ScoreLine {
    | NoteLine(PairedNote)
    | RestLine(UInt32)
    | ChordLine(ArrayList<PairedNote>)
    | TempoLine(Int64)
    | TempoAtLine(UInt32, Int64)
    | InstrumentLine(String)
    | VelocityLine(Int64)
    | ChannelLine(Int64)
    | CCLine(UInt8, UInt8)
    | PitchBendLine(UInt8, UInt8)
}

// ── 时值转换 ──

// 将 tick 数转换为乐谱时值字符串（基于 TPQ）
// 优先使用标准时值 (1,2,4,8,16,32)，其次附点，最后原始 ticks
func ticksToScoreDuration(ticks: UInt32, tpq: Int64): String {
    // 将 ticks 换算到 TPQ=480 基准
    let scaled: Int64 = Int64(ticks) * 480 / tpq

    // 标准时值: duration_value = 480*4 / ticks
    let standardDurations: Array<(Int64, String)> = [
        (1920, "1"), (960, "2"), (480, "4"), (240, "8"), (120, "16"), (60, "32")
    ]
    for (pair in standardDurations) {
        if (scaled == pair[0]) { return pair[1] }
    }

    // 附点时值: base * 1.5
    let dottedDurations: Array<(Int64, String)> = [
        (2880, "1."), (1440, "2."), (720, "4."), (360, "8."), (180, "16."), (90, "32.")
    ]
    for (pair in dottedDurations) {
        if (scaled == pair[0]) { return pair[1] }
    }

    // 原始 tick 值
    "T${scaled}"
}

// ── 轨道事件解码 ──

// 从 MTrk 二进制数据解码所有事件为 DecodedEvent 列表
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
                // Meta 事件
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
                // SysEx — 跳过（乐谱格式忽略）
                j++
                let sysVLQ = decReadVLQ(data, j, trackEnd)
                let sysLen = Int64(sysVLQ.value)
                j = sysVLQ.newPos + sysLen
                runningStatus = 0

            } else {
                // 通道事件
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
            // Running Status
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

// 将 Note ON/OFF 事件配对为完整音符
func pairNotes(events: ArrayList<DecodedEvent>): ArrayList<PairedNote> {
    let notes = ArrayList<PairedNote>()

    // 待配对音符：(channel << 8 | pitch) → (startTick, velocity)
    let pending = HashMap<Int64, ArrayList<(UInt32, UInt8)>>()

    for (ev in events) {
        let evType = ev.eventType

        if (evType == 0x90 && ev.data2 > 0) {
            // Note On（velocity > 0）
            let key = Int64(ev.channel) * 256 + Int64(ev.data1)
            if (!pending.contains(key)) {
                pending[key] = ArrayList<(UInt32, UInt8)>()
            }
            if (let Some(list) <- pending.get(key)) {
                list.add((ev.absTick, ev.data2))
            }
        } else if (evType == 0x80 || (evType == 0x90 && ev.data2 == 0)) {
            // Note Off
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

    // 按起始时间排序
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

// ── 音符分组（和弦检测） ──

// 将同时开始且时值相同的音符归为和弦
func groupNotesIntoChords(notes: ArrayList<PairedNote>): ArrayList<ScoreLine> {
    let lines = ArrayList<ScoreLine>()
    var currentTick: UInt32 = 0
    var i: Int64 = 0

    while (i < notes.size) {
        let note = notes[i]

        // 插入休止符
        if (note.startTick > currentTick) {
            let gap = note.startTick - currentTick
            lines.add(ScoreLine.RestLine(gap))
            currentTick = note.startTick
        }

        // 查找同时开始的音符
        var j = i + 1
        while (j < notes.size && notes[j].startTick == note.startTick) {
            j++
        }
        let groupSize = j - i

        if (groupSize == 1) {
            // 单音符
            lines.add(ScoreLine.NoteLine(note))
            currentTick = note.startTick + note.durationTicks
        } else {
            // 检查是否所有音符时值相同（可构成和弦）
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
                // 和弦
                let chordNotes = ArrayList<PairedNote>()
                var ci = i
                while (ci < j) {
                    chordNotes.add(notes[ci])
                    ci++
                }
                lines.add(ScoreLine.ChordLine(chordNotes))
                currentTick = note.startTick + note.durationTicks
            } else {
                // 时值不同的同时音符 → 逐个输出
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

// ── 轨道信息提取 ──

// 从事件列表中提取轨道名
func extractTrackName(events: ArrayList<DecodedEvent>): String {
    for (ev in events) {
        if (ev.eventType == 0xFF && ev.metaType == 0x03 && ev.metaData.size > 0) {
            // Meta 03 = Track Name，非法 UTF8 时忽略
            try {
                let name = String.fromUtf8(ev.metaData)
                // 替换空格为下划线（轨道名不含空格）
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

// 从事件列表中提取乐器编号
func extractProgram(events: ArrayList<DecodedEvent>): Int64 {
    for (ev in events) {
        if (ev.eventType == 0xC0) {
            return Int64(ev.data1)
        }
    }
    -1
}

// 从事件列表中提取主要通道
func extractChannel(events: ArrayList<DecodedEvent>): Int64 {
    for (ev in events) {
        let evType = ev.eventType
        if (evType == 0x90 || evType == 0x80 || evType == 0xC0 || evType == 0xB0) {
            return Int64(ev.channel)
        }
    }
    -1
}

// 从事件列表中提取主力度
func extractVelocity(events: ArrayList<DecodedEvent>): Int64 {
    // 统计最常见的力度值
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

// 提取 SET_TEMPO 事件列表（绝对 tick → BPM）
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

// 提取非音符事件（CC、PitchBend 等）的时间线
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

// ── 主反编译函数 ──

// MIDI 文件字节数组 → 乐谱记谱格式文本
public func decompileScore(data: Array<UInt8>): String {
    if (data.size < 14) {
        return "// Error: Invalid MIDI file (too short)\n"
    }
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        return "// Error: Invalid MIDI file (bad MThd)\n"
    }

    let numTracks = Int64(decReadU16(data, 10))
    let tpq = Int64(decReadU16(data, 12))

    // 解码所有轨道的事件
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

    // 收集所有轨道中的 tempo 事件
    let allTempos = ArrayList<(UInt32, Int64)>()
    for (trackEvents in allTrackEvents) {
        let tempos = extractTempoEvents(trackEvents)
        for (t in tempos) { allTempos.add(t) }
    }

    // 按 tick 排序 tempo 事件
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

    // 输出
    let sb = StringBuilder()

    // 全局 TEMPO
    let initialBpm = if (allTempos.size > 0) { allTempos[0][1] } else { Int64(120) }
    sb.append("TEMPO ${initialBpm}\n")

    // TEMPO_AT（后续速度变化，tick 需缩放到 TPQ=480 基准）
    var tci: Int64 = 1
    while (tci < allTempos.size) {
        let tick = allTempos[tci][0]
        let bpm = allTempos[tci][1]
        let scaledTick = UInt32(Int64(tick) * 480 / tpq)
        sb.append("TEMPO_AT ${scaledTick} ${bpm}\n")
        tci++
    }

    // 生成各轨道
    var trackIdx: Int64 = 0
    for (trackEvents in allTrackEvents) {
        // 跳过纯指挥轨（仅含 Meta 事件，无音符）
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

        // 轨道基本信息
        var trackName = extractTrackName(trackEvents)
        if (trackName.isEmpty()) {
            trackName = "track${trackIdx}"
        }

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

        // 配对音符
        let pairedNotes = pairNotes(trackEvents)

        // 提取控制事件
        let controlEvents = extractControlEvents(trackEvents)

        // 音符分组 + 和弦检测
        let noteLines = groupNotesIntoChords(pairedNotes)

        // 收集 CC / PitchBend 事件的 tick 位置
        // 在对应的音符间隙插入
        var ctrlIdx: Int64 = 0
        var currentOutputTick: UInt32 = 0

        for (line in noteLines) {
            // 在当前位置之前插入控制事件
            while (ctrlIdx < controlEvents.size) {
                let ctrlTick = controlEvents[ctrlIdx][0]
                if (ctrlTick > currentOutputTick) { break }
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
                    let dur = ticksToScoreDuration(note.durationTicks, tpq)
                    let noteName = pitchToName(note.pitch)
                    // 力度与轨道主力度不同时标注
                    if (Int64(note.velocity) != mainVelocity) {
                        sb.append("VELOCITY ${note.velocity}\n")
                    }
                    sb.append("${noteName} ${dur}\n")
                    currentOutputTick = note.startTick + note.durationTicks

                case ScoreLine.ChordLine(chordNotes) =>
                    let dur = ticksToScoreDuration(chordNotes[0].durationTicks, tpq)
                    // 力度与轨道主力度不同时标注
                    if (Int64(chordNotes[0].velocity) != mainVelocity) {
                        sb.append("VELOCITY ${chordNotes[0].velocity}\n")
                    }
                    sb.append("[")
                    var first = true
                    for (n in chordNotes) {
                        if (!first) { sb.append(" ") }
                        sb.append(pitchToName(n.pitch))
                        first = false
                    }
                    sb.append("] ${dur}\n")
                    currentOutputTick = chordNotes[0].startTick + chordNotes[0].durationTicks

                case ScoreLine.RestLine(ticks) =>
                    let dur = ticksToScoreDuration(ticks, tpq)
                    sb.append("R ${dur}\n")
                    currentOutputTick += ticks

                case _ => ()
            }
        }

        // 输出剩余的控制事件
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
