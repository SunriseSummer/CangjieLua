package midi

import std.collection.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// MIDI 可读事件格式测试
// ============================================================

// MIDI 可读事件格式测试：验证命名事件和音名的编解码正确性
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

        let text = decompileReadable(data)
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

        let text = decompileReadable(data)
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

        let text = decompileReadable(data)
        @Assert(text.contains("CC 10 64 CH 0"))
        @Assert(text.contains("CC 64 127 CH 0"))
        @Assert(text.contains("CC 64 0 CH 0"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

}
