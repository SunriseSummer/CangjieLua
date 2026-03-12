package midi.encoder

import std.collection.*
import midi.core.*

// ============================================================
// MIDI 编码器：ScoreData → MIDI 二进制
// ============================================================

let TICKS_PER_QUARTER: UInt16 = 480   // 每四分音符 tick 数
let DEFAULT_VELOCITY: UInt8 = 80      // 默认音符力度

// 将一条轨道的音乐元素转换为 MIDI 事件序列
func buildTrackEvents(trackData: TrackData, tempo: Int64,
                      channel: UInt8): ArrayList<TimedEvent> {
    let events = ArrayList<TimedEvent>()
    var pendingDelta: UInt32 = 0

    // 确定力度：优先使用轨道设定值
    let velocity: UInt8 = if (trackData.velocity > 0 && trackData.velocity <= 127) {
        UInt8(trackData.velocity)
    } else {
        DEFAULT_VELOCITY
    }

    // 首轨道写入 Set Tempo 事件
    if (channel == 0) {
        events.add(TimedEvent(0, MidiEvent.setTempo(UInt32(60000000 / tempo))))
    }

    // 写入 Program Change（乐器选择）
    if (trackData.instrument >= 0) {
        events.add(TimedEvent(0, MidiEvent.programChange(channel, UInt8(trackData.instrument))))
    }

    // 逐个处理音乐元素
    for (element in trackData.elements) {
        match (element) {
            case MusicElement.SingleNote(note) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.noteOn(channel, note.pitch, velocity)))
                pendingDelta = 0
                events.add(TimedEvent(note.durationTicks, MidiEvent.noteOff(channel, note.pitch)))

            case MusicElement.Chord(chord) =>
                // 和弦：所有音同时 NoteOn，同时 NoteOff
                var first = true
                for (pitch in chord.pitches) {
                    let delta = if (first) { pendingDelta } else { UInt32(0) }
                    events.add(TimedEvent(delta, MidiEvent.noteOn(channel, pitch, velocity)))
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
    // MTrk 标识
    result.add(0x4D); result.add(0x54); result.add(0x72); result.add(0x6B)
    writeUInt32BE(result, UInt32(trackData.size))
    for (b in trackData) { result.add(b) }
    result
}

// 核心入口：文本乐谱 → MIDI 文件字节数组
public func generate(input: String): Array<UInt8> {
    let score = parseScore(input)
    let trackCount = score.tracks.size
    let format: UInt16 = if (trackCount <= 1) { 0 } else { 1 }

    // 逐轨道编码
    let encodedTracks = ArrayList<ArrayList<UInt8>>()
    var channelIdx: UInt8 = 0
    for (td in score.tracks) {
        encodedTracks.add(encodeTrackChunk(buildTrackEvents(td, score.tempo, channelIdx)))
        channelIdx++
        if (channelIdx == 9) { channelIdx = 10 }  // 跳过打击乐通道
    }

    // 组装 MThd + MTrk 块
    let result = ArrayList<UInt8>()
    // MThd 标识
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
