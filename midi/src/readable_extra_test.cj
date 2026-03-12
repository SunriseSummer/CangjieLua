package midi

import std.collection.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// MIDI 可读事件格式测试（扩展）— META事件、多通道、升降号
// 基础测试见 readable_test.cj
// ============================================================

@Test
class ReadableExtraTests {
    // ── META 事件保留 ──
    @TestCase
    func metaEventPreservation() {
        let input =
            "MIDI\n" +
            "TPQ 480\n" +
            "FORMAT 1\n" +
            "\n" +
            "TRACK\n" +
            "0 META 03 50 69 61 6E 6F\n" +
            "0 META 58 04 02 18 08\n" +
            "0 META 59 00 00\n" +
            "0 SET_TEMPO 600000\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n" +
            "\n" +
            "TRACK\n" +
            "0 PROGRAM 0 CH 0\n" +
            "0 ON C4 80 CH 0\n" +
            "960 OFF C4 0 CH 0\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 2))
        @Assert(verifyTempo(data, 100))

        let text = decompileReadable(data)
        @Assert(text.contains("META 03 50 69 61 6E 6F"))
        @Assert(text.contains("META 58 04 02 18 08"))
        @Assert(text.contains("SET_TEMPO 600000"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 多通道和多乐器 ──
    @TestCase
    func multiChannelReadable() {
        let input =
            "MIDI\n" +
            "TPQ 480\n" +
            "FORMAT 1\n" +
            "\n" +
            "TRACK\n" +
            "0 SET_TEMPO 500000\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n" +
            "\n" +
            "TRACK\n" +
            "0 PROGRAM 0 CH 0\n" +
            "0 ON C4 80 CH 0\n" +
            "480 OFF C4 0 CH 0\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n" +
            "\n" +
            "TRACK\n" +
            "0 PROGRAM 48 CH 1\n" +
            "0 ON E3 64 CH 1\n" +
            "960 OFF E3 0 CH 1\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 3))
        let programs = extractProgramChanges(data)
        @Expect(programs.size, 2)
        @Expect(programs[0], 0)   // piano
        @Expect(programs[1], 48)  // strings

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 升降号音名 ──
    @TestCase
    func sharpNoteNames() {
        let input =
            "MIDI\n" +
            "TPQ 480\n" +
            "FORMAT 0\n" +
            "\n" +
            "TRACK\n" +
            "0 SET_TEMPO 500000\n" +
            "0 PROGRAM 0 CH 0\n" +
            "0 ON C#4 80 CH 0\n" +
            "240 OFF C#4 0 CH 0\n" +
            "0 ON F#4 80 CH 0\n" +
            "240 OFF F#4 0 CH 0\n" +
            "0 ON G#3 80 CH 0\n" +
            "240 OFF G#3 0 CH 0\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 3)
        @Expect(pitches[0], 61) // C#4
        @Expect(pitches[1], 66) // F#4
        @Expect(pitches[2], 56) // G#3

        let text = decompileReadable(data)
        @Assert(text.contains("ON C#4"))
        @Assert(text.contains("ON F#4"))
        @Assert(text.contains("ON G#3"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }
}
