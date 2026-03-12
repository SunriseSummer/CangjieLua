package midi.encoder

import std.collection.*

// ============================================================
// MIDI 事件类型定义与底层编码
// ============================================================

// MIDI 事件种类
public enum MidiEventKind {
    | NoteOn
    | NoteOff
    | ProgramChange
    | ControlChange
    | PitchBendEvent
    | SetTempo
    | EndOfTrack
}

// MIDI 事件
public class MidiEvent {
    public var kind: MidiEventKind
    public var channel: UInt8
    public var data1: UInt8
    public var data2: UInt8
    public var data3: UInt8

    public init(kind: MidiEventKind, channel: UInt8,
                data1: UInt8, data2: UInt8, data3: UInt8) {
        this.kind = kind
        this.channel = channel
        this.data1 = data1
        this.data2 = data2
        this.data3 = data3
    }

    public static func noteOn(channel: UInt8, pitch: UInt8, velocity: UInt8): MidiEvent {
        MidiEvent(MidiEventKind.NoteOn, channel, pitch, velocity, 0)
    }
    public static func noteOff(channel: UInt8, pitch: UInt8): MidiEvent {
        MidiEvent(MidiEventKind.NoteOff, channel, pitch, 0, 0)
    }
    public static func programChange(channel: UInt8, program: UInt8): MidiEvent {
        MidiEvent(MidiEventKind.ProgramChange, channel, program, 0, 0)
    }
    public static func controlChange(channel: UInt8, ctrl: UInt8, val2: UInt8): MidiEvent {
        MidiEvent(MidiEventKind.ControlChange, channel, ctrl, val2, 0)
    }
    public static func pitchBend(channel: UInt8, lsb: UInt8, msb: UInt8): MidiEvent {
        MidiEvent(MidiEventKind.PitchBendEvent, channel, lsb, msb, 0)
    }
    public static func setTempo(microsecondsPerBeat: UInt32): MidiEvent {
        MidiEvent(MidiEventKind.SetTempo, 0,
                  UInt8((microsecondsPerBeat >> 16) & 0xFF),
                  UInt8((microsecondsPerBeat >> 8) & 0xFF),
                  UInt8(microsecondsPerBeat & 0xFF))
    }
    public static func endOfTrack(): MidiEvent {
        MidiEvent(MidiEventKind.EndOfTrack, 0, 0, 0, 0)
    }
}

// 带时间偏移的 MIDI 事件
public class TimedEvent {
    public var deltaTime: UInt32
    public var event: MidiEvent

    public init(deltaTime: UInt32, event: MidiEvent) {
        this.deltaTime = deltaTime
        this.event = event
    }
}

// ── 底层编码工具 ──

// VLQ（可变长度数值）编码
public func encodeVLQ(value: UInt32): ArrayList<UInt8> {
    let result = ArrayList<UInt8>()
    if (value == 0) {
        result.add(0)
        return result
    }
    var v = value
    let temp = ArrayList<UInt8>()
    while (v > 0) {
        temp.add(UInt8(v & 0x7F))
        v = v >> 7
    }
    // 反转输出，高位字节设置 continuation bit
    var i = Int64(temp.size) - 1
    while (i >= 0) {
        var b = temp[i]
        if (i > 0) { b = b | 0x80 }
        result.add(b)
        i--
    }
    result
}

// 大端写入 UInt16
func writeUInt16BE(buf: ArrayList<UInt8>, value: UInt16): Unit {
    buf.add(UInt8((value >> 8) & 0xFF))
    buf.add(UInt8(value & 0xFF))
}

// 大端写入 UInt32
func writeUInt32BE(buf: ArrayList<UInt8>, value: UInt32): Unit {
    buf.add(UInt8((value >> 24) & 0xFF))
    buf.add(UInt8((value >> 16) & 0xFF))
    buf.add(UInt8((value >> 8) & 0xFF))
    buf.add(UInt8(value & 0xFF))
}

// 将单个 MidiEvent 编码为字节序列
func encodeEvent(event: MidiEvent): ArrayList<UInt8> {
    let result = ArrayList<UInt8>()
    match (event.kind) {
        case MidiEventKind.NoteOn =>
            result.add(0x90 | event.channel)
            result.add(event.data1)
            result.add(event.data2)
        case MidiEventKind.NoteOff =>
            result.add(0x80 | event.channel)
            result.add(event.data1)
            result.add(event.data2)
        case MidiEventKind.ProgramChange =>
            result.add(0xC0 | event.channel)
            result.add(event.data1)
        case MidiEventKind.ControlChange =>
            result.add(0xB0 | event.channel)
            result.add(event.data1)
            result.add(event.data2)
        case MidiEventKind.PitchBendEvent =>
            result.add(0xE0 | event.channel)
            result.add(event.data1)
            result.add(event.data2)
        case MidiEventKind.SetTempo =>
            result.add(0xFF); result.add(0x51); result.add(0x03)
            result.add(event.data1)
            result.add(event.data2)
            result.add(event.data3)
        case MidiEventKind.EndOfTrack =>
            result.add(0xFF); result.add(0x2F); result.add(0x00)
    }
    result
}
