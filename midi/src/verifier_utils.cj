package midi

import std.collection.*

// ============================================================
// MIDI 验证工具 — 内部辅助函数
// 十六进制转换、VLQ 解析、轨道事件提取
// 公共验证接口见 verifier.cj
// ============================================================

// ── 十六进制工具 ──

// 将半字节（0-15）转换为对应的十六进制字符
func hexChar(nibble: UInt8): Rune {
    if (nibble < 10) {
        Rune(UInt32(r'0') + UInt32(nibble))
    } else {
        Rune(UInt32(r'A') + UInt32(nibble) - 10)
    }
}

// ── VLQ（可变长度值）解析 ──

// 读取可变长度值（VLQ），返回 (解析值, 消耗字节数) 元组
// MIDI 文件中 delta-time 和 Meta 事件长度均使用此编码
func readVLQAt(data: Array<UInt8>, pos: Int64, size: Int64): (UInt32, Int64) {
    var value: UInt32 = 0
    var i = pos
    while (i < size) {
        let b = data[i]
        value = (value << 7) | UInt32(b & 0x7F)
        i++
        if ((b & 0x80) == 0) {
            break
        }
    }
    return (value, i - pos)
}

// ── 轨道事件解析 ──

// 轨道事件解析结果：存储从轨道中提取的 NoteOn 音高和 Program Change 值
class TrackParseResult {
    var noteOnPitches: ArrayList<UInt8>
    var programChanges: ArrayList<UInt8>

    init() {
        this.noteOnPitches = ArrayList<UInt8>()
        this.programChanges = ArrayList<UInt8>()
    }
}

// 解析轨道内的 MIDI 事件，提取 NoteOn 音高和 Program Change 音色号
// 用于验证编码后的 MIDI 文件内容是否正确
// 支持 Running Status：当数据字节（< 0x80）出现时复用上一个状态字节
func parseTrackEvents(data: Array<UInt8>, trackStart: Int64, trackEnd: Int64): TrackParseResult {
    let result = TrackParseResult()
    var j = trackStart
    let size = data.size
    var runningStatus: UInt8 = 0

    while (j < trackEnd && j < size) {
        // 读取 delta-time (VLQ)
        let vlqResult = readVLQAt(data, j, if (trackEnd < size) { trackEnd } else { size })
        j += vlqResult[1]

        if (j >= trackEnd || j >= size) { break }

        let firstByte = data[j]

        if (firstByte >= 0x80) {
            if (firstByte == 0xFF) {
                // Meta 事件：跳过类型字节和 VLQ 长度数据
                j++
                if (j >= trackEnd) { break }
                j++ // meta type
                if (j >= trackEnd) { break }
                let metaVlq = readVLQAt(data, j, if (trackEnd < size) { trackEnd } else { size })
                let metaLen = Int64(metaVlq[0])
                j += metaVlq[1] + metaLen
                runningStatus = 0
            } else if (firstByte == 0xF0 || firstByte == 0xF7) {
                // SysEx 事件：跳过数据
                j++
                let sysVlq = readVLQAt(data, j, if (trackEnd < size) { trackEnd } else { size })
                let sysLen = Int64(sysVlq[0])
                j += sysVlq[1] + sysLen
                runningStatus = 0
            } else {
                // 通道事件
                let eventType = firstByte & 0xF0
                runningStatus = firstByte
                j++
                if (eventType == 0xC0 || eventType == 0xD0) {
                    if (eventType == 0xC0 && j < size) {
                        result.programChanges.add(data[j])
                    }
                    j += 1
                } else {
                    if (j + 1 < size) {
                        if (eventType == 0x90 && data[j + 1] > 0) {
                            result.noteOnPitches.add(data[j])
                        }
                    }
                    j += 2
                }
            }
        } else {
            // Running Status：复用上一个状态字节
            let eventType = runningStatus & 0xF0
            if (eventType == 0xC0 || eventType == 0xD0) {
                if (eventType == 0xC0) {
                    result.programChanges.add(data[j])
                }
                j += 1
            } else {
                if (j + 1 < size) {
                    if (eventType == 0x90 && data[j + 1] > 0) {
                        result.noteOnPitches.add(data[j])
                    }
                }
                j += 2
            }
        }

        if (j > trackEnd) { j = trackEnd }
    }

    result
}
