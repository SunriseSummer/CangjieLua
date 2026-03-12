package midi

import std.collection.*

// ============================================================
// MIDI 二进制编码器
// ============================================================

let TICKS_PER_QUARTER: UInt16 = 480
let DEFAULT_VELOCITY: UInt8 = 80

// VLQ 编码
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
    var i = Int64(temp.size) - 1
    while (i >= 0) {
        var b = temp[i]
        if (i > 0) {
            b = b | 0x80
        }
        result.add(b)
        i--
    }
    result
}

func writeUInt16BE(buf: ArrayList<UInt8>, value: UInt16): Unit {
    buf.add(UInt8((value >> 8) & 0xFF))
    buf.add(UInt8(value & 0xFF))
}

func writeUInt32BE(buf: ArrayList<UInt8>, value: UInt32): Unit {
    buf.add(UInt8((value >> 24) & 0xFF))
    buf.add(UInt8((value >> 16) & 0xFF))
    buf.add(UInt8((value >> 8) & 0xFF))
    buf.add(UInt8(value & 0xFF))
}

func buildTrackEvents(trackData: TrackData, tempo: Int64, channel: UInt8): ArrayList<TimedEvent> {
    let events = ArrayList<TimedEvent>()
    var pendingDelta: UInt32 = 0

    let velocity: UInt8 = if (trackData.velocity > 0 && trackData.velocity <= 127) {
        UInt8(trackData.velocity)
    } else {
        DEFAULT_VELOCITY
    }

    if (channel == 0) {
        let microsecondsPerBeat = UInt32(60000000 / tempo)
        events.add(TimedEvent(0, MidiEvent.setTempo(microsecondsPerBeat)))
    }

    if (trackData.instrument >= 0) {
        events.add(TimedEvent(0, MidiEvent.programChange(channel, UInt8(trackData.instrument))))
    }

    for (element in trackData.elements) {
        match (element) {
            case MusicElement.SingleNote(note) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.noteOn(channel, note.pitch, velocity)))
                pendingDelta = 0
                events.add(TimedEvent(note.durationTicks, MidiEvent.noteOff(channel, note.pitch)))

            case MusicElement.Chord(chord) =>
                var first = true
                for (pitch in chord.pitches) {
                    if (first) {
                        events.add(TimedEvent(pendingDelta, MidiEvent.noteOn(channel, pitch, velocity)))
                        pendingDelta = 0
                        first = false
                    } else {
                        events.add(TimedEvent(0, MidiEvent.noteOn(channel, pitch, velocity)))
                    }
                }
                var firstOff = true
                for (pitch in chord.pitches) {
                    if (firstOff) {
                        events.add(TimedEvent(chord.durationTicks, MidiEvent.noteOff(channel, pitch)))
                        firstOff = false
                    } else {
                        events.add(TimedEvent(0, MidiEvent.noteOff(channel, pitch)))
                    }
                }

            case MusicElement.Rest(ticks) =>
                pendingDelta += ticks
        }
    }

    events.add(TimedEvent(pendingDelta, MidiEvent.endOfTrack()))
    events
}

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
        case MidiEventKind.SetTempo =>
            result.add(0xFF)
            result.add(0x51)
            result.add(0x03)
            result.add(event.data1)
            result.add(event.data2)
            result.add(event.data3)
        case MidiEventKind.EndOfTrack =>
            result.add(0xFF)
            result.add(0x2F)
            result.add(0x00)
    }
    result
}

func encodeTrackChunk(events: ArrayList<TimedEvent>): ArrayList<UInt8> {
    let trackData = ArrayList<UInt8>()
    for (timedEvent in events) {
        let vlq = encodeVLQ(timedEvent.deltaTime)
        for (b in vlq) { trackData.add(b) }
        let eventBytes = encodeEvent(timedEvent.event)
        for (b in eventBytes) { trackData.add(b) }
    }

    let result = ArrayList<UInt8>()
    // "MTrk"
    result.add(0x4D)
    result.add(0x54)
    result.add(0x72)
    result.add(0x6B)
    writeUInt32BE(result, UInt32(trackData.size))
    for (b in trackData) { result.add(b) }
    result
}

// 核心函数：文本乐谱 → MIDI 文件字节数组
public func generate(input: String): Array<UInt8> {
    let score = parseScore(input)
    let trackCount = score.tracks.size

    let format: UInt16 = if (trackCount <= 1) { 0 } else { 1 }

    let encodedTracks = ArrayList<ArrayList<UInt8>>()
    var channelIdx: UInt8 = 0
    for (trackData in score.tracks) {
        let events = buildTrackEvents(trackData, score.tempo, channelIdx)
        let encoded = encodeTrackChunk(events)
        encodedTracks.add(encoded)
        channelIdx++
        if (channelIdx == 9) { channelIdx = 10 }
    }

    let result = ArrayList<UInt8>()

    // MThd (14 bytes)
    result.add(0x4D)
    result.add(0x54)
    result.add(0x68)
    result.add(0x64)
    writeUInt32BE(result, 6)
    writeUInt16BE(result, format)
    writeUInt16BE(result, UInt16(trackCount))
    writeUInt16BE(result, TICKS_PER_QUARTER)

    for (track in encodedTracks) {
        for (b in track) { result.add(b) }
    }

    result.toArray()
}
