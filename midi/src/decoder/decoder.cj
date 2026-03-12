package midi.decoder

import std.fs.*

// ============================================================
// MIDI 反编译器 — 公共入口函数
// 可读格式解码逻辑见 readable_decoder.cj
// 乐谱格式解码逻辑见 score_decoder.cj
// ============================================================

// ── 反编译主函数 ──

// MIDI 文件字节数组 → 可读事件文本（无损格式）
// 保留所有 MIDI 事件，使用人类可读的事件名和音名
// 确保重新编码后二进制完全一致
public func decompileReadable(data: Array<UInt8>): String {
    if (data.size < 14) {
        return "// Error: Invalid MIDI file (too short)\n"
    }
    // 验证 MThd 头部签名
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        return "// Error: Invalid MIDI file (bad MThd)\n"
    }

    let format = Int64(decReadU16(data, 8))
    let numTracks = Int64(decReadU16(data, 10))
    let tpq = Int64(decReadU16(data, 12))

    // 检测是否使用了 Running Status 压缩
    let useRS = detectRunningStatus(data, 14, numTracks)

    let sb = StringBuilder()
    sb.append("MIDI\n")
    sb.append("TPQ ${tpq}\n")
    sb.append("FORMAT ${format}\n")
    if (useRS) {
        sb.append("RUNNING_STATUS ON\n")
    }

    // 逐轨道解码为可读文本
    var pos: Int64 = 14
    var ti: Int64 = 0
    while (ti < numTracks) {
        if (pos + 8 > data.size) { break }
        // 验证 MTrk 标记
        if (data[pos] != 0x4D || data[pos + 1] != 0x54 ||
            data[pos + 2] != 0x72 || data[pos + 3] != 0x6B) { break }

        let trackLen = Int64(decReadU32(data, pos + 4))
        let trackStart = pos + 8
        let trackEnd = trackStart + trackLen

        sb.append("\nTRACK\n")
        decodeTrackReadable(sb, data, trackStart, trackEnd)
        sb.append("TRACK_END\n")

        pos = trackEnd
        ti++
    }

    sb.toString()
}

// 反编译 MIDI 字节数组 → 乐谱记谱格式文本（用户友好）
public func decompile(data: Array<UInt8>): String {
    decompileScore(data)
}

// 从文件路径读取 .mid 文件并反编译为乐谱文本
public func decompileToString(midPath: String): String {
    let data = File.readFrom(Path(midPath))
    decompile(data)
}

// 从文件路径读取 .mid 文件并反编译为可读事件格式文本（无损）
public func decompileReadableToString(midPath: String): String {
    let data = File.readFrom(Path(midPath))
    decompileReadable(data)
}
