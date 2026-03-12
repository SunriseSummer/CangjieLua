package midi.decoder

import std.collection.*

// ============================================================
// MIDI 乐谱分析 — 事件解码、音符配对、IOI 时值修正
// 和弦检测与轨道元数据提取见 score_grouping.cj
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
                // Meta 事件：读取类型、长度和数据
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
                // SysEx 事件：跳过数据
                j++
                let sysVLQ = decReadVLQ(data, j, trackEnd)
                let sysLen = Int64(sysVLQ.value)
                j = sysVLQ.newPos + sysLen
                runningStatus = 0
            } else {
                // 通道事件：解析状态字节和数据
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
            // Running Status：复用上一个状态字节
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

// 计算给定 tick 数到最接近标准时值的距离
// 标准时值和附点时值基于 TPQ=480 定义
func distToStandardDuration(ticks: UInt32, tpq: Int64): Int64 {
    let scaled: Int64 = Int64(ticks) * 480 / tpq
    // 标准时值表（TPQ=480 基准）
    let allDurations: Array<Int64> = [
        1920, 960, 480, 240, 120, 60,          // 标准时值
        2880, 1440, 720, 360, 180, 90,         // 附点时值
        1280, 640, 320, 160, 80, 40            // 三连音时值
    ]
    var minDist: Int64 = Int64.Max
    for (d in allDurations) {
        let diff = if (scaled > d) { scaled - d } else { d - scaled }
        if (diff < minDist) { minDist = diff }
    }
    minDist
}

// 智能时值修正：仅在 IOI 能产生更接近标准时值的结果时才替换原始时值
// 对于同时开始的音符（和弦成员），保持原始时值不变
// 对于极短的 IOI（<最短标准时值的一半），保持原始时值不变
// 这样既能吸收演奏表情中的微小断奏间隙，又不会破坏原始节奏
func applyIOIDurations(notes: ArrayList<PairedNote>, tpq: Int64): Unit {
    if (notes.size <= 1) { return }
    // 最短标准时值的一半（三十二分音符/2 = 30 ticks at TPQ=480）
    let minIOI = UInt32(30 * tpq / 480)
    var i: Int64 = 0
    while (i < notes.size - 1) {
        let curr = notes[i]
        let next = notes[i + 1]
        // 跳过同时开始的音符（和弦成员）
        if (next.startTick == curr.startTick) {
            i++
            continue
        }
        let ioi = next.startTick - curr.startTick
        // 跳过极短的 IOI
        // 这些通常是快速琶音或装饰音，不应改变前一个音符的时值
        if (ioi < minIOI) {
            i++
            continue
        }
        let origEnd = curr.startTick + curr.durationTicks
        let gap = if (next.startTick > origEnd) { next.startTick - origEnd } else { UInt32(0) }
        // 仅在间隙较小（音符间有短暂断开或轻微重叠）时考虑 IOI 替换
        if (gap < curr.durationTicks / 4) {
            // 比较原始时值和 IOI 哪个更接近标准时值
            let origDist = distToStandardDuration(curr.durationTicks, tpq)
            let ioiDist = distToStandardDuration(ioi, tpq)
            // 仅当 IOI 产生更好的标准时值匹配时才替换
            if (ioiDist < origDist) {
                curr.durationTicks = ioi
            }
        }
        i++
    }
}
