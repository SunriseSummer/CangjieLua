package midi

import std.collection.*

// ============================================================
// MIDI 事件类型定义
// ============================================================

public enum MidiEventKind {
    | NoteOn
    | NoteOff
    | ProgramChange
    | SetTempo
    | EndOfTrack
}

public class MidiEvent {
    public var kind: MidiEventKind
    public var channel: UInt8
    public var data1: UInt8
    public var data2: UInt8
    public var data3: UInt8

    public init(kind: MidiEventKind, channel: UInt8, data1: UInt8, data2: UInt8, data3: UInt8) {
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

    public static func setTempo(microsecondsPerBeat: UInt32): MidiEvent {
        let b0 = UInt8((microsecondsPerBeat >> 16) & 0xFF)
        let b1 = UInt8((microsecondsPerBeat >> 8) & 0xFF)
        let b2 = UInt8(microsecondsPerBeat & 0xFF)
        MidiEvent(MidiEventKind.SetTempo, 0, b0, b1, b2)
    }

    public static func endOfTrack(): MidiEvent {
        MidiEvent(MidiEventKind.EndOfTrack, 0, 0, 0, 0)
    }
}

public class TimedEvent {
    public var deltaTime: UInt32
    public var event: MidiEvent

    public init(deltaTime: UInt32, event: MidiEvent) {
        this.deltaTime = deltaTime
        this.event = event
    }
}

public class MidiTrack {
    public var name: String
    public var events: ArrayList<TimedEvent>

    public init(name: String) {
        this.name = name
        this.events = ArrayList<TimedEvent>()
    }
}
