package midi.decoder

import std.collection.*

// ============================================================
// MIDI 乐谱分析 — 事件解码、音符配对、和弦检测、轨道元数据提取
// 数据类型定义见 score_types.cj
// ============================================================

// ── 轨道事件解码 ──

// 将 MIDI 二进制轨道数据解码为 DecodedEvent 列表
// 处理 Meta 事件、SysEx 事件和通道事件（含 Running Status）
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

// 将 NoteOn/NoteOff 事件配对，生成带有起始位置和持续时长的 PairedNote 列表
// 使用 pending 哈希表按 (channel, pitch) 跟踪未关闭的 NoteOn 事件
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

    // 按起始 tick 位置排序（插入排序）
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

// ── 基于 IOI（音符间隔）的时值修正 ──

// 将原始 NoteOff 时值替换为音符间隔（Inter-Onset Interval）
// 对于顺序演奏的音符，时值变为当前音符到下一个音符的时间间隔
// 这样可以自然地吸收小的断奏间隙，使记谱更符合乐谱习惯
func applyIOIDurations(notes: ArrayList<PairedNote>): Unit {
    if (notes.size <= 1) { return }
    var i: Int64 = 0
    while (i < notes.size - 1) {
        let curr = notes[i]
        let next = notes[i + 1]
        if (next.startTick > curr.startTick) {
            let ioi = next.startTick - curr.startTick
            let origEnd = curr.startTick + curr.durationTicks
            // 当下一个音符在当前音符结束前或附近开始时使用 IOI
            // 即音符重叠或间隙相对于音符时值较小时
            let gap = if (next.startTick > origEnd) { next.startTick - origEnd } else { UInt32(0) }
            if (gap < curr.durationTicks / 2) {
                curr.durationTicks = ioi
            }
        }
        i++
    }
}

// ── 和弦检测与休止符插入 ──

// 将配对音符列表组织为乐谱行：单音符、和弦或休止符
// 同一 tick 位置开始且时值相同的多个音符被识别为和弦
// 间隔超过阈值（TPQ/8）的空白被插入为休止符

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

        // 查找同一 tick 位置的所有音符
        var j = i + 1
        while (j < notes.size && notes[j].startTick == note.startTick) {
            j++
        }
        let groupSize = j - i

        if (groupSize == 1) {
            lines.add(ScoreLine.NoteLine(note))
            currentTick = note.startTick + note.durationTicks
        } else {
            // 检查所有音符是否具有相同时值（即为和弦）
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

// 从事件列表中提取轨道名称（Meta 事件类型 0x03）
// 将空格和制表符替换为下划线，使其适合作为标识符使用

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

// 从事件列表中提取音色编号（Program Change 事件，类型 0xC0）
// 返回第一个 Program Change 的音色号，未找到返回 -1
func extractProgram(events: ArrayList<DecodedEvent>): Int64 {
    for (ev in events) {
        if (ev.eventType == 0xC0) {
            return Int64(ev.data1)
        }
    }
    -1
}

// 从事件列表中提取 MIDI 通道号
// 扫描 NoteOn/NoteOff/ProgramChange/CC 事件，返回第一个找到的通道号
func extractChannel(events: ArrayList<DecodedEvent>): Int64 {
    for (ev in events) {
        let evType = ev.eventType
        if (evType == 0x90 || evType == 0x80 || evType == 0xC0 || evType == 0xB0) {
            return Int64(ev.channel)
        }
    }
    -1
}

// 提取所有 NoteOn 事件中出现频率最高的力度值
// 用于确定轨道的默认力度设置
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

// 从事件列表中提取所有速度变化事件（Meta 类型 0x51）
// 返回 (绝对tick位置, BPM) 元组列表
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

// 从事件列表中提取所有控制器事件（CC 和 PitchBend）
// 返回 (绝对tick位置, 事件) 元组列表
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
