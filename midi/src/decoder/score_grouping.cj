package midi.decoder

import std.collection.*

// ============================================================
// MIDI 乐谱分析 — 和弦检测、休止符插入、轨道元数据提取
// 事件解码与音符配对逻辑见 score_analysis.cj
// ============================================================

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

        // 间隔超过阈值时插入休止符
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
            // 单个音符，直接作为 NoteLine
            lines.add(ScoreLine.NoteLine(note))
            currentTick = note.startTick + note.durationTicks
        } else {
            // 多个音符：检查时值是否一致（和弦判定）
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
                // 时值相同：合并为和弦
                let chordNotes = ArrayList<PairedNote>()
                var ci = i
                while (ci < j) {
                    chordNotes.add(notes[ci])
                    ci++
                }
                lines.add(ScoreLine.ChordLine(chordNotes))
                currentTick = note.startTick + note.durationTicks
            } else {
                // 时值不同：拆分为独立音符行
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
// 返回 (绝对tick位置, 事件) 元组列表，用于乐谱输出时穿插控制器信息
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
