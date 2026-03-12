package midi.encoder

import std.collection.*
import std.convert.*

// ============================================================
// MIDI 可读事件格式编码器
// 将人类可读的事件文本（音名、命名事件类型）编码为 MIDI 二进制
// 支持 Running Status 自动处理
// ============================================================

// 查找 "CH" 关键字后的通道号
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

// 写入通道事件状态字节（处理 Running Status）
func writeChannelStatus(td: ArrayList<UInt8>, status: UInt8,
                        useRS: Bool, lastStatus: UInt8): Unit {
    if (useRS && status == lastStatus) {
        // Running Status: 省略 status 字节
    } else {
        td.add(status)
    }
}

// 编码单个可读事件行到轨道字节流（带 Running Status 支持）
func encodeReadableEvent(td: ArrayList<UInt8>, parts: ArrayList<String>,
                         delta: UInt32, useRS: Bool,
                         lastStatus: UInt8): UInt8 {
    let vlqBytes = encodeVLQ(delta)
    for (b in vlqBytes) { td.add(b) }

    let eventType = parts[1]
    var newLastStatus = lastStatus

    if (eventType == "ON") {
        // ON <note_name> <velocity> CH <channel>
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
        newLastStatus = status

    } else if (eventType == "OFF") {
        // OFF <note_name> <velocity> CH <channel>
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
        newLastStatus = status

    } else if (eventType == "PROGRAM") {
        // PROGRAM <number> CH <channel>
        if (parts.size < 3) { return lastStatus }
        var prog: UInt8 = 0
        try { prog = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xC0 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(prog)
        newLastStatus = status

    } else if (eventType == "CC") {
        // CC <ctrl> <val> CH <channel>
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
        newLastStatus = status

    } else if (eventType == "CHAN_PRESSURE") {
        // CHAN_PRESSURE <value> CH <channel>
        if (parts.size < 3) { return lastStatus }
        var pressure: UInt8 = 0
        try { pressure = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xD0 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(pressure)
        newLastStatus = status

    } else if (eventType == "AFTERTOUCH") {
        // AFTERTOUCH <note_name> <pressure> CH <channel>
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
        newLastStatus = status

    } else if (eventType == "PITCH_BEND") {
        // PITCH_BEND <lsb> <msb> CH <channel>
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
        newLastStatus = status

    } else if (eventType == "SET_TEMPO") {
        // SET_TEMPO <microseconds>
        if (parts.size < 3) { return lastStatus }
        var micro: UInt32 = 500000
        try { micro = UInt32.parse(parts[2]) } catch (_: Exception) {}
        td.add(0xFF); td.add(0x51); td.add(0x03)
        td.add(UInt8((micro >> 16) & 0xFF))
        td.add(UInt8((micro >> 8) & 0xFF))
        td.add(UInt8(micro & 0xFF))
        newLastStatus = 0

    } else if (eventType == "END_TRACK") {
        td.add(0xFF); td.add(0x2F); td.add(0x00)
        newLastStatus = 0

    } else if (eventType == "META") {
        // META <type_hex> <data_hex...>
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
        newLastStatus = 0

    } else if (eventType == "SYSEX") {
        // SYSEX <status_hex> <data_hex...>
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
        newLastStatus = 0

    } else if (eventType == "CH_EVENT") {
        // CH_EVENT <status_hex> <data_hex...>
        if (parts.size < 3) { return lastStatus }
        var pi: Int64 = 2
        while (pi < parts.size) {
            if (parts[pi] == "CH") { break }
            td.add(parseHexByte(parts[pi]))
            pi++
        }
        newLastStatus = 0
    }

    newLastStatus
}

// 解析 MIDI 可读格式文本 → MIDI 二进制
func generateReadable(input: String): Array<UInt8> {
    var tpq: UInt16 = 480
    var format: UInt16 = 0
    var useRS = false
    let trackDataList = ArrayList<ArrayList<UInt8>>()
    var currentTrack: ?ArrayList<UInt8> = None
    var inTrack = false
    var lastStatus: UInt8 = 0

    for (line in input.split("\n")) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty() || trimmed.startsWith("//")) { continue }

        if (trimmed == "MIDI") { continue }

        if (trimmed.startsWith("TPQ ")) {
            let parts = splitByWhitespace(trimmed)
            if (parts.size >= 2) {
                try { tpq = UInt16.parse(parts[1]) } catch (_: Exception) {}
            }
            continue
        }

        if (trimmed.startsWith("FORMAT ")) {
            let parts = splitByWhitespace(trimmed)
            if (parts.size >= 2) {
                try { format = UInt16.parse(parts[1]) } catch (_: Exception) {}
            }
            continue
        }

        if (trimmed == "RUNNING_STATUS ON") { useRS = true; continue }
        if (trimmed == "RUNNING_STATUS OFF") { useRS = false; continue }

        if (trimmed == "TRACK") {
            currentTrack = ArrayList<UInt8>()
            inTrack = true
            lastStatus = 0
            continue
        }

        if (trimmed == "TRACK_END") {
            if (let Some(td) <- currentTrack) {
                trackDataList.add(td)
            }
            currentTrack = None
            inTrack = false
            lastStatus = 0
            continue
        }

        // 轨道内的事件行: <delta> <event_type> <params...>
        if (inTrack) {
            if (let Some(td) <- currentTrack) {
                let parts = splitByWhitespace(trimmed)
                if (parts.size < 2) { continue }
                var delta: UInt32 = 0
                try { delta = UInt32.parse(parts[0]) } catch (_: Exception) { continue }
                lastStatus = encodeReadableEvent(td, parts, delta, useRS, lastStatus)
            }
        }
    }

    assembleMidiFile(trackDataList, format, tpq)
}
