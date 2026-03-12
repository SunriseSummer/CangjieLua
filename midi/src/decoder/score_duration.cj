package midi.decoder

import std.collection.*

// ============================================================
// MIDI 乐谱时值转换 — 标准时值表、时值匹配、行内音符收集器
// 主反编译函数见 score_decoder.cj
// ============================================================

// ── 标准时值表（TPQ=480 基准） ──

// 基本时值：全音符(1920) → 三十二分音符(60)
let STANDARD_DURATIONS: Array<(Int64, String)> = [
    (1920, "1"), (960, "2"), (480, "4"), (240, "8"), (120, "16"), (60, "32")
]

// 附点时值：基本时值 × 1.5
let DOTTED_DURATIONS: Array<(Int64, String)> = [
    (2880, "1."), (1440, "2."), (720, "4."), (360, "8."), (180, "16."), (90, "32.")
]

// 力度分组阈值：力度差异超过此值时输出新的 VELOCITY 指令
let VELOCITY_THRESHOLD: Int64 = 15

// ── 时值转换（带 15% 舍入容差） ──

// 将 MIDI tick 数转换为乐谱时值标记
// 先精确匹配标准/附点时值，再尝试 15% 模糊匹配，最后返回原始 tick 值
func ticksToScoreDuration(ticks: UInt32, tpq: Int64): String {
    let scaled: Int64 = Int64(ticks) * 480 / tpq

    // 精确匹配标准时值
    for (pair in STANDARD_DURATIONS) {
        if (scaled == pair[0]) { return pair[1] }
    }
    for (pair in DOTTED_DURATIONS) {
        if (scaled == pair[0]) { return pair[1] }
    }

    // 模糊匹配：在 15% 容差范围内找最近的标准时值
    var bestName = ""
    var bestDist: Int64 = Int64.Max

    for (pair in STANDARD_DURATIONS) {
        let diff = if (scaled > pair[0]) { scaled - pair[0] } else { pair[0] - scaled }
        let threshold = pair[0] * 15 / 100
        if (diff <= threshold && diff < bestDist) {
            bestDist = diff
            bestName = pair[1]
        }
    }
    for (pair in DOTTED_DURATIONS) {
        let diff = if (scaled > pair[0]) { scaled - pair[0] } else { pair[0] - scaled }
        let threshold = pair[0] * 15 / 100
        if (diff <= threshold && diff < bestDist) {
            bestDist = diff
            bestName = pair[1]
        }
    }

    if (!bestName.isEmpty()) { return bestName }

    // 无法匹配标准时值，返回原始 tick 值（如 "T216"）
    "T${scaled}"
}

// ── 行内音符收集器 ──

// 将连续的单音符收集后以空格分隔输出为一行
// 每行最多 8 个音符，超过自动换行
class InlineCollector {
    var parts: ArrayList<String> = ArrayList<String>()
    var count: Int64 = 0
    var sb: StringBuilder

    init(sb: StringBuilder) {
        this.sb = sb
    }

    // 将缓冲的音符文本刷新输出为一行
    func flush(): Unit {
        if (parts.size > 0) {
            let joined = StringBuilder()
            var fi: Int64 = 0
            while (fi < parts.size) {
                if (fi > 0) { joined.append("  ") }
                joined.append(parts[fi])
                fi++
            }
            sb.append("${joined}\n")
            parts.clear()
            count = 0
        }
    }

    // 添加一个音符文本，满 8 个自动刷新
    func add(text: String): Unit {
        parts.add(text)
        count++
        if (count >= 8) { flush() }
    }
}

// 格式化单个音符为 "C4 4" 形式
func formatNote(note: PairedNote, tpq: Int64): String {
    let dur = ticksToScoreDuration(note.durationTicks, tpq)
    let name = pitchToName(note.pitch)
    "${name} ${dur}"
}

// 格式化和弦为 "[C3 E3 G3] 2" 形式
func formatChord(chordNotes: ArrayList<PairedNote>, tpq: Int64): String {
    let dur = ticksToScoreDuration(chordNotes[0].durationTicks, tpq)
    let csb = StringBuilder()
    csb.append("[")
    var first = true
    for (n in chordNotes) {
        if (!first) { csb.append(" ") }
        csb.append(pitchToName(n.pitch))
        first = false
    }
    csb.append("] ${dur}")
    csb.toString()
}
