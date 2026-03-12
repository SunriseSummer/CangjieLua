package midi.encoder

import std.collection.*
import std.convert.*
import midi.core.*

// ============================================================
// MIDI 编码器：ScoreData → MIDI 二进制 / MIDI_RAW 文本 → MIDI 二进制
// ============================================================

let TICKS_PER_QUARTER: UInt16 = 480   // 每四分音符 tick 数
let DEFAULT_VELOCITY: UInt8 = 80      // 默认音符力度

// ── 十六进制解析工具 ──

// 单个十六进制字符 → 数值 (0-15)，无效返回 -1
func hexCharValue(ch: Rune): Int64 {
    if (ch >= r'0' && ch <= r'9') { return ch.position() - r'0'.position() }
    if (ch >= r'A' && ch <= r'F') { return ch.position() - r'A'.position() + 10 }
    if (ch >= r'a' && ch <= r'f') { return ch.position() - r'a'.position() + 10 }
    return -1
}

// 两位十六进制字符串 → UInt8
func parseHexByte(s: String): UInt8 {
    let runes = s.toRuneArray()
    if (runes.size != 2) { return 0 }
    let hi = hexCharValue(runes[0])
    let lo = hexCharValue(runes[1])
    if (hi < 0 || lo < 0) { return 0 }
    UInt8(hi * 16 + lo)
}

// ── MIDI_RAW 格式编码器 ──

// 判断输入是否为 MIDI_RAW 格式
func isMidiRawFormat(input: String): Bool {
    input.trimAscii().startsWith("MIDI_RAW")
}

// 按空白分割字符串
func splitByWhitespace(s: String): ArrayList<String> {
    let result = ArrayList<String>()
    var current = StringBuilder()
    var inWord = false
    for (ch in s.toRuneArray()) {
        if (ch == r' ' || ch == r'\t') {
            if (inWord) {
                result.add(current.toString())
                current = StringBuilder()
                inWord = false
            }
        } else {
            current.append(ch)
            inWord = true
        }
    }
    if (inWord) { result.add(current.toString()) }
    result
}

// 解析 MIDI_RAW 格式文本 → MIDI 二进制
func generateRaw(input: String): Array<UInt8> {
    var tpq: UInt16 = 480
    var format: UInt16 = 0
    let trackDataList = ArrayList<ArrayList<UInt8>>()
    var currentTrack: ?ArrayList<UInt8> = None
    var inTrack = false

    for (line in input.split("\n")) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty() || trimmed.startsWith("//")) { continue }

        if (trimmed == "MIDI_RAW") { continue }

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

        if (trimmed == "TRACK") {
            currentTrack = ArrayList<UInt8>()
            inTrack = true
            continue
        }

        if (trimmed == "TRACK_END") {
            if (let Some(td) <- currentTrack) {
                trackDataList.add(td)
            }
            currentTrack = None
            inTrack = false
            continue
        }

        // 轨道内的事件行: <delta_decimal> <hex_byte1> <hex_byte2> ...
        if (inTrack) {
            if (let Some(td) <- currentTrack) {
                let parts = splitByWhitespace(trimmed)
                if (parts.size < 2) { continue }
                // 解析 delta time
                var delta: UInt32 = 0
                try { delta = UInt32.parse(parts[0]) } catch (_: Exception) { continue }
                // VLQ 编码 delta time 并写入
                let vlqBytes = encodeVLQ(delta)
                for (b in vlqBytes) { td.add(b) }
                // 解析并写入事件的十六进制字节
                var pi: Int64 = 1
                while (pi < parts.size) {
                    td.add(parseHexByte(parts[pi]))
                    pi++
                }
            }
        }
    }

    let trackCount = trackDataList.size

    // 组装 MThd + MTrk 块
    let result = ArrayList<UInt8>()
    // MThd 标识
    result.add(0x4D); result.add(0x54); result.add(0x68); result.add(0x64)
    writeUInt32BE(result, 6)
    writeUInt16BE(result, format)
    writeUInt16BE(result, UInt16(trackCount))
    writeUInt16BE(result, tpq)

    for (td in trackDataList) {
        // MTrk 标识
        result.add(0x4D); result.add(0x54); result.add(0x72); result.add(0x6B)
        writeUInt32BE(result, UInt32(td.size))
        for (b in td) { result.add(b) }
    }

    result.toArray()
}

// ── 乐谱格式编码器（原有功能） ──

// 将一条轨道的音乐元素转换为 MIDI 事件序列
func buildTrackEvents(trackData: TrackData, tempo: Int64,
                       channel: UInt8, isFirstTrack: Bool): ArrayList<TimedEvent> {
    let events = ArrayList<TimedEvent>()
    var pendingDelta: UInt32 = 0

    // 确定力度：优先使用轨道设定值
    let velocity: UInt8 = if (trackData.velocity > 0 && trackData.velocity <= 127) {
        UInt8(trackData.velocity)
    } else {
        DEFAULT_VELOCITY
    }

    // 首轨道写入 Set Tempo 事件
    if (isFirstTrack) {
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

            case MusicElement.TempoChange(bpm) =>
                // 内联速度变化
                events.add(TimedEvent(pendingDelta, MidiEvent.setTempo(UInt32(60000000 / bpm))))
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
    // MTrk 标识
    result.add(0x4D); result.add(0x54); result.add(0x72); result.add(0x6B)
    writeUInt32BE(result, UInt32(trackData.size))
    for (b in trackData) { result.add(b) }
    result
}

// 核心入口：文本乐谱 → MIDI 文件字节数组
// 自动检测 MIDI_RAW 格式（无损原始事件）和乐谱格式（人类可读记谱法）
public func generate(input: String): Array<UInt8> {
    // 检测 MIDI_RAW 格式
    if (isMidiRawFormat(input)) {
        return generateRaw(input)
    }

    let score = parseScore(input)

    // 逐轨道编码
    let encodedTracks = ArrayList<ArrayList<UInt8>>()

    // 如果有 TEMPO_AT 速度变化，创建专用速度轨道
    if (score.tempoChanges.size > 0) {
        let tempoEvents = ArrayList<TimedEvent>()
        // 初始速度
        tempoEvents.add(TimedEvent(0, MidiEvent.setTempo(UInt32(60000000 / score.tempo))))
        // 按 tick 排序速度变化
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
        // 使用绝对 tick 位置计算 delta time
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
    var isFirst = score.tempoChanges.size == 0  // 无 TEMPO_AT 时首轨道写入初始速度
    for (td in score.tracks) {
        // 确定 MIDI 通道：优先使用显式指定值
        let ch: UInt8 = if (td.channel >= 0 && td.channel <= 15) {
            UInt8(td.channel)
        } else {
            let assigned = channelIdx
            channelIdx++
            if (channelIdx == 9) { channelIdx = 10 }  // 跳过打击乐通道
            assigned
        }
        encodedTracks.add(encodeTrackChunk(buildTrackEvents(td, score.tempo, ch, isFirst)))
        isFirst = false
    }

    let trackCount = encodedTracks.size
    let format: UInt16 = if (trackCount <= 1) { 0 } else { 1 }

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
