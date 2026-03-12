package midi

import std.fs.*
import std.collection.*
import midi.core.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 反编译测试（可读格式）— 可读文本回环、速度精度保留
// 乐谱格式回环测试见 decompile_score_test.cj
// ============================================================

@Test
class DecompileTests {
    // ── 可读格式：乐谱 → MIDI → 可读文本 → MIDI 无损回环 ──
    @TestCase
    func readableRoundTrip() {
        let input =
            "TEMPO 120\n" +
            "\n" +
            "TRACK melody\n" +
            "INSTRUMENT guitar\n" +
            "C4 4  D4 4  E4 8  E4 8  F4 4\n" +
            "G4 2  R 4  A4 4\n" +
            "B4 4  C5 1\n" +
            "\n" +
            "TRACK chords\n" +
            "INSTRUMENT strings\n" +
            "[C3 E3 G3] 2  [F3 A3 C4] 2\n" +
            "[G3 B3 D4] 2  [C3 E3 G3] 2\n" +
            "\n" +
            "TRACK bass\n" +
            "INSTRUMENT bass\n" +
            "C2 2  F2 2\n" +
            "G2 2  C2 2"

        let midi1 = generate(input)
        @Assert(verifyMThd(midi1, 1, 3))

        // 可读格式无损回环
        let text1 = decompileReadable(midi1)
        @Assert(text1.startsWith("MIDI"))
        let midi2 = generate(text1)
        @Expect(midi1.size, midi2.size)
        verifyBinaryIdentical(midi1, midi2)

        let text2 = decompileReadable(midi2)
        @Expect(text1, text2)
    }

    // ── test.mid: 可读格式无损回环 ──
    @TestCase
    func externalTest1Readable() {
        let data = loadTestMid("testcase/binary/test.mid")
        @Assert(countTracks(data), 3)

        let text = decompileReadable(data)
        @Assert(text.startsWith("MIDI"))
        @Assert(text.contains("SET_TEMPO 857142"))
        @Assert(text.contains("ON "))
        @Assert(text.contains("OFF "))

        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)

        let text2 = decompileReadable(regen)
        @Expect(text, text2)
    }

    // ── test2.mid: 可读格式无损回环 ──
    @TestCase
    func externalTest2Readable() {
        let data = loadTestMid("testcase/binary/test2.mid")
        @Assert(countTracks(data), 4)

        let text = decompileReadable(data)
        @Assert(text.startsWith("MIDI"))
        @Assert(text.contains("SET_TEMPO "))
        @Assert(text.contains("CC "))

        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)
    }

    // ── test3.mid: 可读格式无损回环 ──
    @TestCase
    func externalTest3Readable() {
        let data = loadTestMid("testcase/binary/test3.mid")
        @Assert(countTracks(data), 6)

        let text = decompileReadable(data)
        @Assert(text.startsWith("MIDI"))
        @Assert(text.contains("RUNNING_STATUS ON"))
        @Assert(text.contains("TPQ 120"))

        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)
    }

    // ── 速度精度保留（可读格式微秒级无损） ──
    @TestCase
    func tempoMicrosecondPrecision() {
        let data = loadTestMid("testcase/binary/test.mid")

        let text = decompileReadable(data)
        @Assert(text.contains("SET_TEMPO 857142"))
        let regen = generate(text)
        verifyBinaryIdentical(data, regen)
    }

    // ── 辅助函数 ──

    func loadTestMid(midPath: String): Array<UInt8> {
        let p = Path(midPath)
        @Assert(exists(p))
        let data = File.readFrom(p)
        @Assert(data.size >= 14)
        @Assert(data[0], 0x4D)
        @Assert(data[1], 0x54)
        @Assert(data[2], 0x68)
        @Assert(data[3], 0x64)
        data
    }
}
