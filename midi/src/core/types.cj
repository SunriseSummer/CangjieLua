package midi.core

import std.collection.*

// ============================================================
// 乐谱数据模型 — 文本乐谱解析后的中间表示
// ============================================================

// 单音符信息
public class NoteInfo {
    public var pitch: UInt8           // MIDI 音高 (0-127)
    public var durationTicks: UInt32  // 持续时间（tick 数）
    public var velocity: Int64        // 力度 (1-127)，-1 表示使用轨道默认值

    public init(pitch: UInt8, durationTicks: UInt32) {
        this.pitch = pitch
        this.durationTicks = durationTicks
        this.velocity = -1
    }

    public init(pitch: UInt8, durationTicks: UInt32, velocity: Int64) {
        this.pitch = pitch
        this.durationTicks = durationTicks
        this.velocity = velocity
    }
}

// 和弦信息（多个音符同时发声）
public class ChordInfo {
    public var pitches: ArrayList<UInt8>   // 和弦内各音的 MIDI 音高
    public var durationTicks: UInt32       // 持续时间（tick 数）
    public var velocity: Int64             // 力度 (1-127)，-1 表示使用轨道默认值

    public init(pitches: ArrayList<UInt8>, durationTicks: UInt32) {
        this.pitches = pitches
        this.durationTicks = durationTicks
        this.velocity = -1
    }

    public init(pitches: ArrayList<UInt8>, durationTicks: UInt32, velocity: Int64) {
        this.pitches = pitches
        this.durationTicks = durationTicks
        this.velocity = velocity
    }
}

// 控制器变化信息
public class CCInfo {
    public var controller: UInt8   // 控制器编号 (0-127)
    public var value: UInt8        // 控制器值 (0-127)
    public init(controller: UInt8, value: UInt8) {
        this.controller = controller
        this.value = value
    }
}

// 弯音信息
public class PitchBendInfo {
    public var lsb: UInt8  // 低 7 位
    public var msb: UInt8  // 高 7 位
    public init(lsb: UInt8, msb: UInt8) {
        this.lsb = lsb
        this.msb = msb
    }
}

// 音乐元素：单音、和弦、休止、速度变化及扩展事件
public enum MusicElement {
    | SingleNote(NoteInfo)
    | Chord(ChordInfo)
    | Rest(UInt32)              // 休止时长（tick 数）
    | TempoChange(Int64)        // 内联速度变化（BPM）
    | CC(CCInfo)                // 控制器变化
    | PitchBend(PitchBendInfo)  // 弯音
}

// 轨道数据
public class TrackData {
    public var name: String                       // 轨道名称
    public var instrument: Int64                  // GM 乐器编号，-1 表示未设置
    public var velocity: Int64                    // 力度 (1-127)，-1 表示使用默认值
    public var channel: Int64                     // MIDI 通道，-1 表示自动分配
    public var elements: ArrayList<MusicElement>  // 音乐元素序列

    public init(name: String) {
        this.name = name
        this.instrument = -1
        this.velocity = -1
        this.channel = -1
        this.elements = ArrayList<MusicElement>()
    }
}

// 速度变化条目
public class TempoEntry {
    public var tick: UInt32   // 绝对 tick 位置（TPQ=480 基准）
    public var bpm: Int64     // BPM 速度

    public init(tick: UInt32, bpm: Int64) {
        this.tick = tick
        this.bpm = bpm
    }
}

// 乐谱数据：包含速度和多轨道信息
public class ScoreData {
    public var tempo: Int64                          // 初始 BPM 速度
    public var tempoChanges: ArrayList<TempoEntry>   // 速度变化列表（绝对 tick）
    public var tracks: ArrayList<TrackData>           // 轨道列表

    public init() {
        this.tempo = 120
        this.tempoChanges = ArrayList<TempoEntry>()
        this.tracks = ArrayList<TrackData>()
    }
}
