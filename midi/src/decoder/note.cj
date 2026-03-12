package midi.decoder

// ============================================================
// 音高转换工具
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
