package midi.encoder

import std.collection.*
import midi.core.*

// ============================================================
// 乐谱格式编码器：ScoreData → MIDI 二进制
// ============================================================

// 将一条轨道的音乐元素转换为 MIDI 事件序列
func buildTrackEvents(trackData: TrackData, tempo: Int64,
                       channel: UInt8, isFirstTrack: Bool): ArrayList<TimedEvent> {
    let events = ArrayList<TimedEvent>()
    var pendingDelta: UInt32 = 0

    let velocity: UInt8 = if (trackData.velocity > 0 && trackData.velocity <= 127) {
        UInt8(trackData.velocity)
    } else {
        DEFAULT_VELOCITY
    }

    if (isFirstTrack) {
        events.add(TimedEvent(0, MidiEvent.setTempo(UInt32(60000000 / tempo))))
    }

    if (trackData.instrument >= 0) {
        events.add(TimedEvent(0, MidiEvent.programChange(channel, UInt8(trackData.instrument))))
    }

    for (element in trackData.elements) {
        match (element) {
            case MusicElement.SingleNote(note) =>
                let noteVel: UInt8 = if (note.velocity > 0) { UInt8(note.velocity) } else { velocity }
                events.add(TimedEvent(pendingDelta, MidiEvent.noteOn(channel, note.pitch, noteVel)))
                pendingDelta = 0
                events.add(TimedEvent(note.durationTicks, MidiEvent.noteOff(channel, note.pitch)))

            case MusicElement.Chord(chord) =>
                let chordVel: UInt8 = if (chord.velocity > 0) { UInt8(chord.velocity) } else { velocity }
                var first = true
                for (pitch in chord.pitches) {
                    let delta = if (first) { pendingDelta } else { UInt32(0) }
                    events.add(TimedEvent(delta, MidiEvent.noteOn(channel, pitch, chordVel)))
                    if (first) { pendingDelta = 0; first = false }
                }
                var firstOff = true
                for (pitch in chord.pitches) {
                    let delta = if (firstOff) { chord.durationTicks } else { UInt32(0) }
                    events.add(TimedEvent(delta, MidiEvent.noteOff(channel, pitch)))
                    firstOff = false
                }

            case MusicElement.Rest(ticks) =>
                pendingDelta += ticks

            case MusicElement.TempoChange(bpm) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.setTempo(UInt32(60000000 / bpm))))
                pendingDelta = 0

            case MusicElement.CC(info) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.controlChange(channel, info.controller, info.value)))
                pendingDelta = 0

            case MusicElement.PitchBend(info) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.pitchBend(channel, info.lsb, info.msb)))
                pendingDelta = 0
        }
    }

    events.add(TimedEvent(pendingDelta, MidiEvent.endOfTrack()))
    events
}

// 将事件序列编码为 MTrk 块
func encodeTrackChunk(events: ArrayList<TimedEvent>): ArrayList<UInt8> {
    let trackData = ArrayList<UInt8>()
    for (te in events) {
        for (b in encodeVLQ(te.deltaTime)) { trackData.add(b) }
        for (b in encodeEvent(te.event)) { trackData.add(b) }
    }

    let result = ArrayList<UInt8>()
    result.add(0x4D); result.add(0x54); result.add(0x72); result.add(0x6B)
    writeUInt32BE(result, UInt32(trackData.size))
    for (b in trackData) { result.add(b) }
    result
}

// 乐谱格式编码：解析乐谱文本 → MIDI 二进制
func generateScore(input: String): Array<UInt8> {
    let score = parseScore(input)
    let encodedTracks = ArrayList<ArrayList<UInt8>>()

    if (score.tempoChanges.size > 0) {
        let tempoEvents = ArrayList<TimedEvent>()
        tempoEvents.add(TimedEvent(0, MidiEvent.setTempo(UInt32(60000000 / score.tempo))))
        let sorted = ArrayList<TempoEntry>()
        for (tc in score.tempoChanges) { sorted.add(tc) }
        var si: Int64 = 1
        while (si < sorted.size) {
            let key = sorted[si]
            var sj = si - 1
            while (sj >= 0 && sorted[sj].tick > key.tick) {
                sorted[sj + 1] = sorted[sj]
                sj--
            }
            sorted[sj + 1] = key
            si++
        }
        var prevTick: UInt32 = 0
        for (tc in sorted) {
            let delta = if (tc.tick > prevTick) { tc.tick - prevTick } else { UInt32(0) }
            tempoEvents.add(TimedEvent(delta, MidiEvent.setTempo(UInt32(60000000 / tc.bpm))))
            prevTick = tc.tick
        }
        tempoEvents.add(TimedEvent(0, MidiEvent.endOfTrack()))
        encodedTracks.add(encodeTrackChunk(tempoEvents))
    }

    var channelIdx: UInt8 = 0
    var isFirst = score.tempoChanges.size == 0
    for (td in score.tracks) {
        let ch: UInt8 = if (td.channel >= 0 && td.channel <= 15) {
            UInt8(td.channel)
        } else {
            let assigned = channelIdx
            channelIdx++
            if (channelIdx == 9) { channelIdx = 10 }
            assigned
        }
        encodedTracks.add(encodeTrackChunk(buildTrackEvents(td, score.tempo, ch, isFirst)))
        isFirst = false
    }

    let trackCount = encodedTracks.size
    let format: UInt16 = if (trackCount <= 1) { 0 } else { 1 }

    let result = ArrayList<UInt8>()
    result.add(0x4D); result.add(0x54); result.add(0x68); result.add(0x64)
    writeUInt32BE(result, 6)
    writeUInt16BE(result, format)
    writeUInt16BE(result, UInt16(trackCount))
    writeUInt16BE(result, TICKS_PER_QUARTER)

    for (track in encodedTracks) {
        for (b in track) { result.add(b) }
    }

    result.toArray()
}

// ============================================================
// 核心入口：文本 → MIDI 文件字节数组
// 自动检测两种输入格式：
//   1. MIDI 可读事件格式（无损，人类可读事件名和音名）
//   2. 乐谱记谱格式（人类友好的音乐记谱法）
// ============================================================

public func generate(input: String): Array<UInt8> {
    if (isMidiReadableFormat(input)) {
        return generateReadable(input)
    }
    generateScore(input)
}
