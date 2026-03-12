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
}
