package midi.decoder

// ============================================================
// MIDI 可读格式解码器 — 轨道事件解码与通道事件输出
// 十六进制工具与 Running Status 检测见 readable_utils.cj
// ============================================================

// ── 可读轨道事件输出 ──

// 解码单个 MTrk 的二进制事件，将每个事件输出为一行可读文本
// 支持 Meta 事件、SysEx 事件和通道事件（含 Running Status）
func decodeTrackReadable(sb: StringBuilder, data: Array<UInt8>,
                         trackStart: Int64, trackEnd: Int64): Unit {
    var j = trackStart
    var runningStatus: UInt8 = 0

    while (j < trackEnd && j < data.size) {
        // 读取 delta-time
        let vlq = decReadVLQ(data, j, trackEnd)
        let delta = vlq.value
        j = vlq.newPos
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

                if (metaType == 0x51 && metaLen == 3 && j + 2 < trackEnd) {
                    // Set Tempo: 输出微秒值
                    let micro = UInt32(data[j]) << 16 | UInt32(data[j + 1]) << 8 | UInt32(data[j + 2])
                    sb.append("${delta} SET_TEMPO ${micro}\n")
                } else if (metaType == 0x2F) {
                    // End of Track
                    sb.append("${delta} END_TRACK\n")
                } else {
                    // 其他 Meta 事件: META <type_hex> <data_bytes_hex...>
                    sb.append("${delta} META ${byteToHex(metaType)}")
                    var mi: Int64 = 0
                    while (mi < metaLen && j + mi < trackEnd) {
                        sb.append(" ${byteToHex(data[j + mi])}")
                        mi++
                    }
                    sb.append("\n")
                }
                j += metaLen
                // Meta 事件会重置 Running Status
                runningStatus = 0

            } else if (firstByte == 0xF0 || firstByte == 0xF7) {
                // SysEx 事件
                j++
                let sysVLQ = decReadVLQ(data, j, trackEnd)
                let sysLen = Int64(sysVLQ.value)
                j = sysVLQ.newPos
                sb.append("${delta} SYSEX ${byteToHex(firstByte)}")
                var si: Int64 = 0
                while (si < sysLen && j + si < trackEnd) {
                    sb.append(" ${byteToHex(data[j + si])}")
                    si++
                }
                sb.append("\n")
                j += sysLen
                // SysEx 事件会重置 Running Status
                runningStatus = 0

            } else {
                // 通道消息（Voice / Mode）
                let eventType = firstByte & 0xF0
                let channel = firstByte & 0x0F
                runningStatus = firstByte
                j++
                decodeChannelEvent(sb, data, eventType, channel, delta, j, trackEnd)
                if (eventType == 0xC0 || eventType == 0xD0) { j += 1 }
                else { j += 2 }
            }
        } else {
            // Running Status：复用上一个状态字节
            let eventType = runningStatus & 0xF0
            let channel = runningStatus & 0x0F
            decodeChannelEvent(sb, data, eventType, channel, delta, j, trackEnd)
            if (eventType == 0xC0 || eventType == 0xD0) { j += 1 }
            else { j += 2 }
        }

        if (j > trackEnd) { j = trackEnd }
    }
}

// 将通道事件解码为可读文本行并追加到 StringBuilder
// 支持 NoteOn/NoteOff（输出音名）、ProgramChange、CC、PitchBend、Aftertouch 等
func decodeChannelEvent(sb: StringBuilder, data: Array<UInt8>,
                        eventType: UInt8, channel: UInt8,
                        delta: UInt32, dataPos: Int64, trackEnd: Int64): Unit {
    let ch = Int64(channel)
    if (eventType == 0x90 && dataPos + 1 < trackEnd) {
        // Note On：输出音名和力度
        let pitch = data[dataPos]
        let vel = data[dataPos + 1]
        sb.append("${delta} ON ${pitchToName(pitch)} ${vel} CH ${ch}\n")
    } else if (eventType == 0x80 && dataPos + 1 < trackEnd) {
        // Note Off：输出音名和力度
        let pitch = data[dataPos]
        let vel = data[dataPos + 1]
        sb.append("${delta} OFF ${pitchToName(pitch)} ${vel} CH ${ch}\n")
    } else if (eventType == 0xC0 && dataPos < trackEnd) {
        // Program Change：输出音色编号
        let prog = data[dataPos]
        sb.append("${delta} PROGRAM ${prog} CH ${ch}\n")
    } else if (eventType == 0xB0 && dataPos + 1 < trackEnd) {
        // Control Change：输出控制器编号和值
        let ctrl = data[dataPos]
        let val2 = data[dataPos + 1]
        sb.append("${delta} CC ${ctrl} ${val2} CH ${ch}\n")
    } else if (eventType == 0xD0 && dataPos < trackEnd) {
        // Channel Pressure（通道触后）
        let pressure = data[dataPos]
        sb.append("${delta} CHAN_PRESSURE ${pressure} CH ${ch}\n")
    } else if (eventType == 0xA0 && dataPos + 1 < trackEnd) {
        // Polyphonic Aftertouch（多音触后）
        let note = data[dataPos]
        let pressure = data[dataPos + 1]
        sb.append("${delta} AFTERTOUCH ${pitchToName(note)} ${pressure} CH ${ch}\n")
    } else if (eventType == 0xE0 && dataPos + 1 < trackEnd) {
        // Pitch Bend：输出 LSB 和 MSB
        let lsb = data[dataPos]
        let msb = data[dataPos + 1]
        sb.append("${delta} PITCH_BEND ${lsb} ${msb} CH ${ch}\n")
    } else {
        // 未知通道事件，原样输出十六进制数据
        sb.append("${delta} CH_EVENT ${byteToHex(eventType | channel)}")
        if (eventType == 0xC0 || eventType == 0xD0) {
            if (dataPos < trackEnd) { sb.append(" ${byteToHex(data[dataPos])}") }
        } else {
            if (dataPos < trackEnd) { sb.append(" ${byteToHex(data[dataPos])}") }
            if (dataPos + 1 < trackEnd) { sb.append(" ${byteToHex(data[dataPos + 1])}") }
        }
        sb.append("\n")
    }
}
