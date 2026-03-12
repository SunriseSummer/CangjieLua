package midi.encoder

import std.collection.*
import std.convert.*

// MIDI 可读事件格式 — 各事件类型的编码实现（入口见 readable_encoder.cj）

// 在事件参数列表中查找 "CH" 关键字后的通道号
func findChannel(parts: ArrayList<String>): UInt8 {
    var i: Int64 = 0
    while (i < parts.size - 1) {
        if (parts[i] == "CH") {
            try { return UInt8.parse(parts[i + 1]) } catch (_: Exception) {}
        }
        i++
    }
    return 0
}

// 写入通道事件状态字节（Running Status 模式下省略重复状态字节）
func writeChannelStatus(td: ArrayList<UInt8>, status: UInt8,
                        useRS: Bool, lastStatus: UInt8): Unit {
    if (useRS && status == lastStatus) {
        // Running Status 模式：省略重复的状态字节以节省空间
    } else {
        td.add(status)
    }
}

// 编码 Note On 事件
func encodeNoteOn(td: ArrayList<UInt8>, parts: ArrayList<String>,
                  useRS: Bool, lastStatus: UInt8): UInt8 {
    if (parts.size < 4) { return lastStatus }
    let pitch = noteNameToMidi(parts[2])
    if (pitch < 0) { return lastStatus }
    var vel: UInt8 = 0
    try { vel = UInt8.parse(parts[3]) } catch (_: Exception) {}
    let ch = findChannel(parts)
    let status: UInt8 = 0x90 | ch
    writeChannelStatus(td, status, useRS, lastStatus)
    td.add(UInt8(pitch))
    td.add(vel)
    status
}

// 编码 Note Off 事件
func encodeNoteOff(td: ArrayList<UInt8>, parts: ArrayList<String>,
                   useRS: Bool, lastStatus: UInt8): UInt8 {
    if (parts.size < 4) { return lastStatus }
    let pitch = noteNameToMidi(parts[2])
    if (pitch < 0) { return lastStatus }
    var vel: UInt8 = 0
    try { vel = UInt8.parse(parts[3]) } catch (_: Exception) {}
    let ch = findChannel(parts)
    let status: UInt8 = 0x80 | ch
    writeChannelStatus(td, status, useRS, lastStatus)
    td.add(UInt8(pitch))
    td.add(vel)
    status
}

// 编码 Program Change 事件
func encodeProgram(td: ArrayList<UInt8>, parts: ArrayList<String>,
                   useRS: Bool, lastStatus: UInt8): UInt8 {
    if (parts.size < 3) { return lastStatus }
    var prog: UInt8 = 0
    try { prog = UInt8.parse(parts[2]) } catch (_: Exception) {}
    let ch = findChannel(parts)
    let status: UInt8 = 0xC0 | ch
    writeChannelStatus(td, status, useRS, lastStatus)
    td.add(prog)
    status
}

// 编码 Control Change 事件
func encodeCC(td: ArrayList<UInt8>, parts: ArrayList<String>,
              useRS: Bool, lastStatus: UInt8): UInt8 {
    if (parts.size < 4) { return lastStatus }
    var ctrl: UInt8 = 0
    var val2: UInt8 = 0
    try { ctrl = UInt8.parse(parts[2]) } catch (_: Exception) {}
    try { val2 = UInt8.parse(parts[3]) } catch (_: Exception) {}
    let ch = findChannel(parts)
    let status: UInt8 = 0xB0 | ch
    writeChannelStatus(td, status, useRS, lastStatus)
    td.add(ctrl)
    td.add(val2)
    status
}

// 编码 Channel Pressure 事件
func encodeChanPressure(td: ArrayList<UInt8>, parts: ArrayList<String>,
                        useRS: Bool, lastStatus: UInt8): UInt8 {
    if (parts.size < 3) { return lastStatus }
    var pressure: UInt8 = 0
    try { pressure = UInt8.parse(parts[2]) } catch (_: Exception) {}
    let ch = findChannel(parts)
    let status: UInt8 = 0xD0 | ch
    writeChannelStatus(td, status, useRS, lastStatus)
    td.add(pressure)
    status
}

// 编码 Polyphonic Aftertouch 事件
func encodeAftertouch(td: ArrayList<UInt8>, parts: ArrayList<String>,
                      useRS: Bool, lastStatus: UInt8): UInt8 {
    if (parts.size < 4) { return lastStatus }
    let pitch = noteNameToMidi(parts[2])
    if (pitch < 0) { return lastStatus }
    var pressure: UInt8 = 0
    try { pressure = UInt8.parse(parts[3]) } catch (_: Exception) {}
    let ch = findChannel(parts)
    let status: UInt8 = 0xA0 | ch
    writeChannelStatus(td, status, useRS, lastStatus)
    td.add(UInt8(pitch))
    td.add(pressure)
    status
}

// 编码 Pitch Bend 事件
func encodePitchBend(td: ArrayList<UInt8>, parts: ArrayList<String>,
                     useRS: Bool, lastStatus: UInt8): UInt8 {
    if (parts.size < 4) { return lastStatus }
    var lsb: UInt8 = 0
    var msb: UInt8 = 0
    try { lsb = UInt8.parse(parts[2]) } catch (_: Exception) {}
    try { msb = UInt8.parse(parts[3]) } catch (_: Exception) {}
    let ch = findChannel(parts)
    let status: UInt8 = 0xE0 | ch
    writeChannelStatus(td, status, useRS, lastStatus)
    td.add(lsb)
    td.add(msb)
    status
}

// 编码 Meta/SysEx 类事件，返回新的 Running Status 状态字节
func encodeMetaOrSysex(td: ArrayList<UInt8>, parts: ArrayList<String>,
                       eventType: String, lastStatus: UInt8): UInt8 {
    if (eventType == "SET_TEMPO") {
        // 速度设置事件：SET_TEMPO <微秒/拍>
        if (parts.size < 3) { return lastStatus }
        var micro: UInt32 = 500000
        try { micro = UInt32.parse(parts[2]) } catch (_: Exception) {}
        td.add(0xFF); td.add(0x51); td.add(0x03)
        td.add(UInt8((micro >> 16) & 0xFF))
        td.add(UInt8((micro >> 8) & 0xFF))
        td.add(UInt8(micro & 0xFF))
        return 0

    } else if (eventType == "END_TRACK") {
        // 轨道结束标记
        td.add(0xFF); td.add(0x2F); td.add(0x00)
        return 0

    } else if (eventType == "META") {
        // 通用 Meta 事件：META <类型十六进制> <数据十六进制...>
        if (parts.size < 3) { return lastStatus }
        let metaType = parseHexByte(parts[2])
        let dataLen = parts.size - 3
        td.add(0xFF)
        td.add(metaType)
        let lenVLQ = encodeVLQ(UInt32(dataLen))
        for (b in lenVLQ) { td.add(b) }
        var di: Int64 = 3
        while (di < parts.size) {
            td.add(parseHexByte(parts[di]))
            di++
        }
        return 0

    } else if (eventType == "SYSEX") {
        // 系统独占消息：SYSEX <状态十六进制> <数据十六进制...>
        if (parts.size < 3) { return lastStatus }
        td.add(parseHexByte(parts[2]))
        let dataLen = parts.size - 3
        let lenVLQ = encodeVLQ(UInt32(dataLen))
        for (b in lenVLQ) { td.add(b) }
        var si: Int64 = 3
        while (si < parts.size) {
            td.add(parseHexByte(parts[si]))
            si++
        }
        return 0

    } else if (eventType == "CH_EVENT") {
        // 未识别的通道事件（原样输出十六进制字节）
        if (parts.size < 3) { return lastStatus }
        var pi: Int64 = 2
        while (pi < parts.size) {
            if (parts[pi] == "CH") { break }
            td.add(parseHexByte(parts[pi]))
            pi++
        }
        return 0
    }

    lastStatus
}
