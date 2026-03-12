package midi

import std.collection.*
import midi.core.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 乐谱格式编码测试（扩展）— 附点音符、原始tick、通道、速度变化
// 基础测试见 score_test.cj
// ============================================================

@Test
class ScoreExtraTests {
    // ── 附点音符 ──
    @TestCase
    func dottedNoteDurations() {
        let input =
            "TEMPO 120\n" +
            "INSTRUMENT piano\n" +
            "C4 4.  D4 8.  E4 2.  F4 16.\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 原始 tick 时值 ──
    @TestCase
    func rawTickDurations() {
        let input =
            "TEMPO 120\n" +
            "INSTRUMENT piano\n" +
            "C4 T216  D4 T432  R T100  E4 T108\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))

        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 3)

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── CHANNEL 指令 ──
    @TestCase
    func channelPreservation() {
        let input =
            "TEMPO 120\n" +
            "\nTRACK melody\n" +
            "CHANNEL 1\n" +
            "INSTRUMENT bright_piano\n" +
            "C4 4  D4 4\n" +
            "\nTRACK drums\n" +
            "CHANNEL 9\n" +
            "INSTRUMENT piano\n" +
            "C4 32  D4 32\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 2))

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── TEMPO_AT 绝对速度变化 ──
    @TestCase
    func tempoAtAbsolutePositioning() {
        let input =
            "TEMPO 120\n" +
            "TEMPO_AT 480 100\n" +
            "TEMPO_AT 960 140\n" +
            "\nTRACK melody\n" +
            "INSTRUMENT piano\n" +
            "C4 4  D4 4  E4 4  F4 4\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 2))
        @Assert(countTracks(data), 2)
        @Assert(verifyTempo(data, 120))

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 三连音时值 ──
    @TestCase
    func tripletDurations() {
        let input =
            "TEMPO 120\n" +
            "INSTRUMENT piano\n" +
            "C4 4t  D4 4t  E4 4t  F4 8t  G4 8t  A4 8t\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))

        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 6)

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)

        // 三连音回环：乐谱 → MIDI → 乐谱 → MIDI
        let scoreText = decompile(data)
        @Assert(scoreText.contains("4t"))
        @Assert(scoreText.contains("8t"))
        let midi2 = generate(scoreText)
        let pitches2 = extractNoteOnPitches(midi2)
        @Expect(pitches2.size, 6)
    }

    // ── 同时开始不同时值的音符保持为和弦 ──
    @TestCase
    func chordDifferentDurations() {
        // 构造两个同时开始但时值不同的音符
        let input =
            "MIDI\n" +
            "TPQ 480\n" +
            "FORMAT 0\n" +
            "\n" +
            "TRACK\n" +
            "0 SET_TEMPO 500000\n" +
            "0 PROGRAM 0 CH 0\n" +
            "0 ON C4 80 CH 0\n" +
            "0 ON E4 80 CH 0\n" +
            "480 OFF C4 0 CH 0\n" +
            "480 OFF E4 0 CH 0\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n"
        let data = generate(input)

        // 反编译为乐谱格式
        let scoreText = decompile(data)
        // 应该包含和弦表示，而不是拆分为独立音符
        @Assert(scoreText.contains("["))
        @Assert(scoreText.contains("C4"))
        @Assert(scoreText.contains("E4"))

        // 重新编码应保留两个音高
        let regen = generate(scoreText)
        let pitches = extractNoteOnPitches(regen)
        @Expect(pitches.size, 2)
    }
}
