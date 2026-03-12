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

// Ticks → 最接近的标准时值 (1, 2, 4, 8, 16, 32)
func quantizeDuration(ticks: UInt32, tpq: UInt16): Int64 {
    let tpqI = Int64(tpq)
    let ticksI = Int64(ticks)
    if (ticksI <= 0) { return 4 }

    // 标准时值对应的 tick 数
    let standards: Array<(Int64, Int64)> = [
        (1,  tpqI * 4),       // 全音符
        (2,  tpqI * 2),       // 二分音符
        (4,  tpqI),           // 四分音符
        (8,  tpqI / 2),       // 八分音符
        (16, tpqI / 4),       // 十六分音符
        (32, tpqI / 8)        // 三十二分音符
    ]

    var minDiff: Int64 = tpqI * 8 + 1   // 大于所有可能差值
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
    bestDur
}
