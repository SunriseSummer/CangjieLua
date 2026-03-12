package midi.decoder

// ============================================================
// 音高与时值转换工具
// ============================================================

// 音名查找表
let NOTE_NAMES: Array<String> = [
    "C", "C#", "D", "D#", "E", "F",
    "F#", "G", "G#", "A", "A#", "B"
]

// MIDI 音高 → 音名字符串（如 60 → "C4"）
func pitchToName(pitch: UInt8): String {
    let p = Int64(pitch)
    let noteIdx = p % 12
    let octave = p / 12 - 1
    "${NOTE_NAMES[noteIdx]}${octave}"
}

// 缩放 tick 数到 TPQ=480 的等效值
func scaleTicks(ticks: UInt32, tpq: UInt16): UInt32 {
    if (tpq == 480) { return ticks }
    UInt32(Int64(ticks) * 480 / Int64(tpq))
}

// Ticks → 最接近的标准时值字符串（支持附点和原始 tick）
func quantizeDuration(ticks: UInt32, tpq: UInt16): String {
    let tpqI = Int64(tpq)
    let ticksI = Int64(ticks)
    if (ticksI <= 0) { return "4" }

    // 标准时值及附点时值对应的 tick 数
    let standards: Array<(Int64, Int64)> = [
        (1,   tpqI * 4),           // 全音符
        (-1,  tpqI * 6),           // 附点全音符
        (2,   tpqI * 2),           // 二分音符
        (-2,  tpqI * 3),           // 附点二分音符
        (4,   tpqI),               // 四分音符
        (-4,  tpqI * 3 / 2),       // 附点四分音符
        (8,   tpqI / 2),           // 八分音符
        (-8,  tpqI * 3 / 4),       // 附点八分音符
        (16,  tpqI / 4),           // 十六分音符
        (-16, tpqI * 3 / 8),       // 附点十六分音符
        (32,  tpqI / 8)            // 三十二分音符
    ]

    var minDiff: Int64 = tpqI * 8 + 1
    var bestDur: Int64 = 4
    for (pair in standards) {
        let dur = pair[0]
        let tv = pair[1]
        if (tv > 0) {
            let diff = if (ticksI > tv) { ticksI - tv } else { tv - ticksI }
            if (diff < minDiff) {
                minDiff = diff
                bestDur = dur
            }
        }
    }

    // 如果最佳匹配误差超过阈值，使用原始 tick 值（缩放到 TPQ=480）
    let bestTicks = if (bestDur < 0) {
        let base = tpqI * 4 / (-bestDur)
        base * 3 / 2
    } else {
        tpqI * 4 / bestDur
    }
    let errorPct = if (bestTicks > 0) { minDiff * 100 / bestTicks } else { Int64(100) }

    if (errorPct > 5) {
        // 误差过大，输出原始 tick 值（缩放到 TPQ=480）
        let scaled = scaleTicks(ticks, tpq)
        "T${scaled}"
    } else if (bestDur < 0) {
        "${-bestDur}."
    } else {
        "${bestDur}"
    }
}
