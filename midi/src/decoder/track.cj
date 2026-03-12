package midi.decoder

import std.collection.*

// ============================================================
// MIDI 轨道解码：二进制事件 → DecodedTrack
// ============================================================

let DEC_DEFAULT_VELOCITY: Int64 = 80   // 默认力度（与编码器一致）

// ── NoteOn/NoteOff 配对辅助 ──

// 关闭匹配音高的 PendingNote，生成 DecodedNote
func closePendingNote(pending: ArrayList<PendingNote>,
                      notes: ArrayList<DecodedNote>,
                      pitch: UInt8, absTime: UInt32): Unit {
    var i: Int64 = 0
    while (i < pending.size) {
        if (pending[i].pitch == pitch) {
            let pn = pending[i]
            pending.remove(at: i)
            let dur = if (absTime > pn.startTick) { absTime - pn.startTick } else { UInt32(1) }
            notes.add(DecodedNote(pitch, pn.startTick, dur, pn.velocity))
            return
        }
        i++
    }
}

// 完成所有未关闭的音符（文件结束时调用）
func flushPending(pending: ArrayList<PendingNote>,
                  notes: ArrayList<DecodedNote>,
                  absTime: UInt32, tpq: UInt16): Unit {
    let defaultDur = UInt32(tpq)
    while (pending.size > 0) {
        let p = pending[0]
        pending.remove(at: 0)
        let dur = if (absTime > p.startTick) { absTime - p.startTick } else { defaultDur }
        notes.add(DecodedNote(p.pitch, p.startTick, dur, p.velocity))
    }
}

// ── 音符排序 ──

// 按起始时间、音高排序（插入排序，适合中小规模数据）
func sortNotes(notes: ArrayList<DecodedNote>): Unit {
    var i: Int64 = 1
    while (i < notes.size) {
        let key = notes[i]
        var j = i - 1
        while (j >= 0) {
            let curr = notes[j]
            if (curr.startTick > key.startTick ||
                (curr.startTick == key.startTick && curr.pitch > key.pitch)) {
                notes[j + 1] = curr
                j--
            } else {
                break
            }
        }
        notes[j + 1] = key
        i++
    }
}

// ── 轨道解码主函数 ──

// 解析单个 MTrk 的二进制事件，返回 (解码轨道, tempo BPM)
func decodeTrackData(data: Array<UInt8>, trackStart: Int64,
                     trackEnd: Int64, tpq: UInt16): (DecodedTrack, Int64) {
    let track = DecodedTrack()
    var tempoBPM: Int64 = 0
    var j = trackStart
    var absTime: UInt32 = 0
    var runningStatus: UInt8 = 0
    let pending = ArrayList<PendingNote>()
    var totalVel: Int64 = 0
    var velCount: Int64 = 0

    while (j < trackEnd && j < data.size) {
        // 读取 delta-time
        let vlq = decReadVLQ(data, j, trackEnd)
        absTime += vlq.value
        j = vlq.newPos
        if (j >= trackEnd) { break }

        // Running Status 处理
        var status = data[j]
        if (status >= 0x80) {
            runningStatus = status
            j++
        } else {
            status = runningStatus
        }

        let eventType = status & 0xF0

        // NoteOn (0x90)
        if (eventType == 0x90 && j + 1 < trackEnd) {
            let pitch = data[j]
            let vel = data[j + 1]
            j += 2
            if (vel > 0) {
                pending.add(PendingNote(pitch, absTime, vel))
                totalVel += Int64(vel)
                velCount++
            } else {
                // velocity 0 视为 NoteOff
                closePendingNote(pending, track.notes, pitch, absTime)
            }
        }
        // NoteOff (0x80)
        else if (eventType == 0x80 && j + 1 < trackEnd) {
            closePendingNote(pending, track.notes, data[j], absTime)
            j += 2
        }
        // Program Change (0xC0)
        else if (eventType == 0xC0 && j < trackEnd) {
            track.instrument = Int64(data[j])
            j++
        }
        // Meta Event (0xFF)
        else if (status == 0xFF && j < trackEnd) {
            let metaType = data[j]
            j++
            let metaVLQ = decReadVLQ(data, j, trackEnd)
            let metaLen = Int64(metaVLQ.value)
            j = metaVLQ.newPos
            // Set Tempo (FF 51 03)
            if (metaType == 0x51 && metaLen == 3 && j + 2 < trackEnd) {
                let micro = UInt32(data[j]) << 16 | UInt32(data[j + 1]) << 8 | UInt32(data[j + 2])
                if (micro > 0) { tempoBPM = 60000000 / Int64(micro) }
            }
            j += metaLen
            runningStatus = 0
        }
        // SysEx (F0/F7)
        else if (status == 0xF0 || status == 0xF7) {
            let sysVLQ = decReadVLQ(data, j, trackEnd)
            j = sysVLQ.newPos + Int64(sysVLQ.value)
            runningStatus = 0
        }
        // 其他 Channel Voice 消息（Control Change 等，跳过数据字节）
        else if (eventType == 0xB0 || eventType == 0xA0 || eventType == 0xE0) {
            j += 2
        }
        else if (eventType == 0xD0) {
            j++
        }
        else {
            j++
        }
    }

    flushPending(pending, track.notes, absTime, tpq)

    // 计算平均力度
    if (velCount > 0) { track.avgVelocity = totalVel / velCount }

    sortNotes(track.notes)

    (track, tempoBPM)
}
