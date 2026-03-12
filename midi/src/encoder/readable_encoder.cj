package midi.encoder

import std.collection.*
import std.convert.*

// ============================================================
// MIDI 可读事件格式编码器
// 将人类可读的事件文本（音名、命名事件类型）编码为 MIDI 二进制
// 各事件类型编码实现见 readable_events.cj
// ============================================================

// 编码单个可读事件行为 MIDI 二进制字节流
// 支持的事件类型：ON/OFF/PROGRAM/CC/CHAN_PRESSURE/AFTERTOUCH/
//   PITCH_BEND/SET_TEMPO/END_TRACK/META/SYSEX/CH_EVENT
// 返回新的 Running Status 状态字节
func encodeReadableEvent(td: ArrayList<UInt8>, parts: ArrayList<String>,
                         delta: UInt32, useRS: Bool,
                         lastStatus: UInt8): UInt8 {
    let vlqBytes = encodeVLQ(delta)
    for (b in vlqBytes) { td.add(b) }

    let eventType = parts[1]

    // 通道事件：分发到具体的编码函数
    if (eventType == "ON") {
        return encodeNoteOn(td, parts, useRS, lastStatus)
    } else if (eventType == "OFF") {
        return encodeNoteOff(td, parts, useRS, lastStatus)
    } else if (eventType == "PROGRAM") {
        return encodeProgram(td, parts, useRS, lastStatus)
    } else if (eventType == "CC") {
        return encodeCC(td, parts, useRS, lastStatus)
    } else if (eventType == "CHAN_PRESSURE") {
        return encodeChanPressure(td, parts, useRS, lastStatus)
    } else if (eventType == "AFTERTOUCH") {
        return encodeAftertouch(td, parts, useRS, lastStatus)
    } else if (eventType == "PITCH_BEND") {
        return encodePitchBend(td, parts, useRS, lastStatus)
    }

    // Meta/SysEx/其他事件
    encodeMetaOrSysex(td, parts, eventType, lastStatus)
}

// ── 主入口：解析可读格式文本 → MIDI 二进制 ──

// 解析 MIDI 可读格式文本 → MIDI 二进制字节数组
// 读取头部信息（TPQ、FORMAT、RUNNING_STATUS），逐轨道编码事件
// 最后组装为完整的 MIDI 文件
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
