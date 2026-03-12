package midi.encoder

import std.collection.*
import std.convert.*
import midi.core.*

// ============================================================
// MIDI 编码器：ScoreData → MIDI 二进制 / MIDI 可读文本 → MIDI 二进制
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

// ── 音名解析工具 ──

// 音名基础值: C=0, D=2, E=4, F=5, G=7, A=9, B=11
func encBasePitch(noteRune: Rune): Int64 {
    if (noteRune == r'C') { return 0 }
    if (noteRune == r'D') { return 2 }
    if (noteRune == r'E') { return 4 }
    if (noteRune == r'F') { return 5 }
    if (noteRune == r'G') { return 7 }
    if (noteRune == r'A') { return 9 }
    if (noteRune == r'B') { return 11 }
    return -1
}

// 音名字符串 → MIDI 音高 (如 "C4" → 60, "C#4" → 61, "Db4" → 61)
func noteNameToMidi(name: String): Int64 {
    let runes = name.toRuneArray()
    if (runes.size < 2) { return -1 }
    let base = encBasePitch(runes[0])
    if (base < 0) { return -1 }
    var i: Int64 = 1
    var accidental: Int64 = 0
    if (i < runes.size && runes[i] == r'#') { accidental = 1; i++ }
    else if (i < runes.size && runes[i] == r'b') { accidental = -1; i++ }
    // 读取八度数字（可能为负数如 C-1）
    var neg = false
    if (i < runes.size && runes[i] == r'-') { neg = true; i++ }
    if (i >= runes.size) { return -1 }
    var octave: Int64 = 0
    while (i < runes.size && runes[i] >= r'0' && runes[i] <= r'9') {
        octave = octave * 10 + (runes[i].position() - r'0'.position())
        i++
    }
    if (neg) { octave = -octave }
    (octave + 1) * 12 + base + accidental
}

// ── 格式检测 ──

// 判断输入是否为 MIDI_RAW 格式（旧格式，向后兼容）
func isMidiRawFormat(input: String): Bool {
    input.trimAscii().startsWith("MIDI_RAW")
}

// 判断输入是否为 MIDI 可读格式（新格式）
func isMidiReadableFormat(input: String): Bool {
    let trimmed = input.trimAscii()
    // "MIDI\n" 但不是 "MIDI_RAW"
    trimmed.startsWith("MIDI") && !trimmed.startsWith("MIDI_RAW")
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

// ── MIDI_RAW 格式编码器（向后兼容） ──

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

// ── MIDI 可读格式编码器 ──

// 查找 "CH" 关键字后的通道号
func findChannel(parts: ArrayList<String>): UInt8 {
    var i: Int64 = 0
    while (i < parts.size - 1) {
        if (parts[i] == "CH") {
            try { return UInt8.parse(parts[i + 1]) } catch (_: Exception) {}
        }
        i++
    }
    return 0
}

// 编码单个可读事件行到轨道字节流（带 Running Status 支持）
func encodeReadableEvent(td: ArrayList<UInt8>, parts: ArrayList<String>,
                         delta: UInt32, useRS: Bool,
                         lastStatus: UInt8): UInt8 {
    // 写入 VLQ delta time
    let vlqBytes = encodeVLQ(delta)
    for (b in vlqBytes) { td.add(b) }

    let eventType = parts[1]
    var newLastStatus = lastStatus

    if (eventType == "ON") {
        // ON <note_name> <velocity> CH <channel>
        if (parts.size < 4) { return lastStatus }
        let pitch = noteNameToMidi(parts[2])
        if (pitch < 0) { return lastStatus }
        var vel: UInt8 = 0
        try { vel = UInt8.parse(parts[3]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0x90 | ch
        if (useRS && status == lastStatus) {
            // Running Status: 省略 status 字节
        } else {
            td.add(status)
        }
        td.add(UInt8(pitch))
        td.add(vel)
        newLastStatus = status

    } else if (eventType == "OFF") {
        // OFF <note_name> <velocity> CH <channel>
        if (parts.size < 4) { return lastStatus }
        let pitch = noteNameToMidi(parts[2])
        if (pitch < 0) { return lastStatus }
        var vel: UInt8 = 0
        try { vel = UInt8.parse(parts[3]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0x80 | ch
        if (useRS && status == lastStatus) {
            // Running Status
        } else {
            td.add(status)
        }
        td.add(UInt8(pitch))
        td.add(vel)
        newLastStatus = status

    } else if (eventType == "PROGRAM") {
        // PROGRAM <number> CH <channel>
        if (parts.size < 3) { return lastStatus }
        var prog: UInt8 = 0
        try { prog = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xC0 | ch
        if (useRS && status == lastStatus) {
            // Running Status
        } else {
            td.add(status)
        }
        td.add(prog)
        newLastStatus = status

    } else if (eventType == "CC") {
        // CC <ctrl> <val> CH <channel>
        if (parts.size < 4) { return lastStatus }
        var ctrl: UInt8 = 0
        var val2: UInt8 = 0
        try { ctrl = UInt8.parse(parts[2]) } catch (_: Exception) {}
        try { val2 = UInt8.parse(parts[3]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xB0 | ch
        if (useRS && status == lastStatus) {
            // Running Status
        } else {
            td.add(status)
        }
        td.add(ctrl)
        td.add(val2)
        newLastStatus = status

    } else if (eventType == "CHAN_PRESSURE") {
        // CHAN_PRESSURE <value> CH <channel>
        if (parts.size < 3) { return lastStatus }
        var pressure: UInt8 = 0
        try { pressure = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xD0 | ch
        if (useRS && status == lastStatus) {
            // Running Status
        } else {
            td.add(status)
        }
        td.add(pressure)
        newLastStatus = status

    } else if (eventType == "AFTERTOUCH") {
        // AFTERTOUCH <note_name> <pressure> CH <channel>
        if (parts.size < 4) { return lastStatus }
        let pitch = noteNameToMidi(parts[2])
        if (pitch < 0) { return lastStatus }
        var pressure: UInt8 = 0
        try { pressure = UInt8.parse(parts[3]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xA0 | ch
        if (useRS && status == lastStatus) {
            // Running Status
        } else {
            td.add(status)
        }
        td.add(UInt8(pitch))
        td.add(pressure)
        newLastStatus = status

    } else if (eventType == "PITCH_BEND") {
        // PITCH_BEND <lsb> <msb> CH <channel>
        if (parts.size < 4) { return lastStatus }
        var lsb: UInt8 = 0
        var msb: UInt8 = 0
        try { lsb = UInt8.parse(parts[2]) } catch (_: Exception) {}
        try { msb = UInt8.parse(parts[3]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xE0 | ch
        if (useRS && status == lastStatus) {
            // Running Status
        } else {
            td.add(status)
        }
        td.add(lsb)
        td.add(msb)
        newLastStatus = status

    } else if (eventType == "SET_TEMPO") {
        // SET_TEMPO <microseconds>
        if (parts.size < 3) { return lastStatus }
        var micro: UInt32 = 500000
        try { micro = UInt32.parse(parts[2]) } catch (_: Exception) {}
        td.add(0xFF); td.add(0x51); td.add(0x03)
        td.add(UInt8((micro >> 16) & 0xFF))
        td.add(UInt8((micro >> 8) & 0xFF))
        td.add(UInt8(micro & 0xFF))
        newLastStatus = 0  // Meta 事件重置 Running Status

    } else if (eventType == "END_TRACK") {
        // END_TRACK
        td.add(0xFF); td.add(0x2F); td.add(0x00)
        newLastStatus = 0

    } else if (eventType == "META") {
        // META <type_hex> <data_hex...>
        if (parts.size < 3) { return lastStatus }
        let metaType = parseHexByte(parts[2])
        let dataLen = parts.size - 3
        td.add(0xFF)
        td.add(metaType)
        // VLQ 编码 data 长度
        let lenVLQ = encodeVLQ(UInt32(dataLen))
        for (b in lenVLQ) { td.add(b) }
        // 数据字节
        var di: Int64 = 3
        while (di < parts.size) {
            td.add(parseHexByte(parts[di]))
            di++
        }
        newLastStatus = 0

    } else if (eventType == "SYSEX") {
        // SYSEX <status_hex> <data_hex...>
        if (parts.size < 3) { return lastStatus }
        td.add(parseHexByte(parts[2]))  // F0 or F7
        let dataLen = parts.size - 3
        let lenVLQ = encodeVLQ(UInt32(dataLen))
        for (b in lenVLQ) { td.add(b) }
        var si: Int64 = 3
        while (si < parts.size) {
            td.add(parseHexByte(parts[si]))
            si++
        }
        newLastStatus = 0

    } else if (eventType == "CH_EVENT") {
        // CH_EVENT <status_hex> <data_hex...>
        if (parts.size < 3) { return lastStatus }
        var pi: Int64 = 2
        while (pi < parts.size) {
            if (parts[pi] == "CH") { break }
            td.add(parseHexByte(parts[pi]))
            pi++
        }
        newLastStatus = 0
    }

    newLastStatus
}

// 解析 MIDI 可读格式文本 → MIDI 二进制
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

        if (trimmed == "RUNNING_STATUS ON") {
            useRS = true
            continue
        }
        if (trimmed == "RUNNING_STATUS OFF") {
            useRS = false
            continue
        }

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
                // 解析 delta time
                var delta: UInt32 = 0
                try { delta = UInt32.parse(parts[0]) } catch (_: Exception) { continue }
                lastStatus = encodeReadableEvent(td, parts, delta, useRS, lastStatus)
            }
        }
    }

    let trackCount = trackDataList.size

    // 组装 MThd + MTrk 块
    let result = ArrayList<UInt8>()
    result.add(0x4D); result.add(0x54); result.add(0x68); result.add(0x64)
    writeUInt32BE(result, 6)
    writeUInt16BE(result, format)
    writeUInt16BE(result, UInt16(trackCount))
    writeUInt16BE(result, tpq)

    for (td in trackDataList) {
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
// 自动检测三种输入格式：
//   1. MIDI 可读事件格式（无损，以 "MIDI" 开头，含人类可读事件名和音名）
//   2. MIDI_RAW 格式（旧版无损格式，以 "MIDI_RAW" 开头，向后兼容）
//   3. 乐谱记谱格式（人类友好的音乐记谱法）
public func generate(input: String): Array<UInt8> {
    // 检测 MIDI_RAW 格式（需先于 MIDI 可读格式检测，因 MIDI_RAW 也以 MIDI 开头）
    if (isMidiRawFormat(input)) {
        return generateRaw(input)
    }

    // 检测 MIDI 可读事件格式
    if (isMidiReadableFormat(input)) {
        return generateReadable(input)
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
