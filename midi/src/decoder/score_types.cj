package midi.decoder

import std.collection.*

// ============================================================
// MIDI 乐谱分析 — 数据类型定义
// 定义解码过程中使用的事件、音符和乐谱行类型
// ============================================================

// ── 解码事件 ──

// 表示从 MIDI 二进制中解码出的单个事件
// 支持通道事件（NoteOn/Off、CC 等）和 Meta 事件（速度、曲名等）
class DecodedEvent {
    var absTick: UInt32      // 事件的绝对 tick 位置
    var eventType: UInt8     // 事件类型（0x80-0xE0 为通道事件，0xFF 为 Meta 事件）
    var channel: UInt8       // MIDI 通道号（0-15）
    var data1: UInt8         // 数据字节1（如音高、控制器编号）
    var data2: UInt8         // 数据字节2（如力度、控制器值）
    var metaType: UInt8      // Meta 事件子类型（如 0x51=速度、0x03=曲名）
    var metaData: Array<UInt8>  // Meta 事件的数据字节

    // 构造通道事件
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

    // 构造 Meta 事件
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

// ── 配对音符 ──

// 表示一个已配对的音符（NoteOn + NoteOff 匹配后的结果）
// 包含音高、力度、通道、起始位置和持续时长
class PairedNote {
    var pitch: UInt8         // MIDI 音高（0-127）
    var velocity: UInt8      // 力度（0-127）
    var channel: UInt8       // MIDI 通道号
    var startTick: UInt32    // 起始 tick 位置
    var durationTicks: UInt32 // 持续 tick 数

    init(pitch: UInt8, velocity: UInt8, channel: UInt8,
         startTick: UInt32, durationTicks: UInt32) {
        this.pitch = pitch
        this.velocity = velocity
        this.channel = channel
        this.startTick = startTick
        this.durationTicks = durationTicks
    }
}

// ── 乐谱行类型 ──

// 表示乐谱输出的一行内容：单音符、休止符或和弦
enum ScoreLine {
    | NoteLine(PairedNote)              // 单个音符
    | RestLine(UInt32)                  // 休止符（持续 tick 数）
    | ChordLine(ArrayList<PairedNote>)  // 和弦（同时发声的多个音符）
}
