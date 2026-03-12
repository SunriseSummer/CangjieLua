package midi

import std.collection.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// MIDI 可读事件格式测试
// ============================================================

@Test
class ReadableFormatTests {
    // ── 手工构造可读格式 ──
    @TestCase
    func readableFormatManual() {
        let input =
            "MIDI\n" +
            "TPQ 480\n" +
            "FORMAT 0\n" +
            "\n" +
            "TRACK\n" +
            "0 SET_TEMPO 500000\n" +
            "0 PROGRAM 0 CH 0\n" +
            "0 ON C4 80 CH 0\n" +
            "480 OFF C4 0 CH 0\n" +
            "0 ON E4 90 CH 0\n" +
            "480 OFF E4 0 CH 0\n" +
            "0 ON G4 100 CH 0\n" +
            "480 OFF G4 0 CH 0\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        @Assert(verifyTempo(data, 120))
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 3)
        @Expect(pitches[0], 60) // C4
        @Expect(pitches[1], 64) // E4
        @Expect(pitches[2], 67) // G4

        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── Running Status 编码 ──
    @TestCase
    func runningStatusEncoding() {
        let input =
            "MIDI\n" +
            "TPQ 480\n" +
            "FORMAT 0\n" +
            "RUNNING_STATUS ON\n" +
            "\n" +
            "TRACK\n" +
            "0 SET_TEMPO 500000\n" +
            "0 PROGRAM 0 CH 0\n" +
            "0 ON C4 80 CH 0\n" +
            "480 ON C4 0 CH 0\n" +
            "0 ON D4 80 CH 0\n" +
            "480 ON D4 0 CH 0\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))

        let text = decompile(data)
        @Assert(text.contains("RUNNING_STATUS ON"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── CC 事件保留 ──
    @TestCase
    func ccEventPreservation() {
        let input =
            "MIDI\n" +
            "TPQ 480\n" +
            "FORMAT 0\n" +
            "\n" +
            "TRACK\n" +
            "0 SET_TEMPO 500000\n" +
            "0 PROGRAM 0 CH 0\n" +
            "0 CC 10 64 CH 0\n" +
            "0 CC 64 127 CH 0\n" +
            "0 ON C4 80 CH 0\n" +
            "480 OFF C4 0 CH 0\n" +
            "0 CC 64 0 CH 0\n" +
            "0 END_TRACK\n" +
            "TRACK_END\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))

        let text = decompile(data)
        @Assert(text.contains("CC 10 64 CH 0"))
        @Assert(text.contains("CC 64 127 CH 0"))
        @Assert(text.contains("CC 64 0 CH 0"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

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

        let text = decompile(data)
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

        let text = decompile(data)
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

        let text = decompile(data)
        @Assert(text.contains("ON C#4"))
        @Assert(text.contains("ON F#4"))
        @Assert(text.contains("ON G#3"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }
}
