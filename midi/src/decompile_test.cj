package midi

import std.fs.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 反编译回环测试（乐谱 → MIDI → 可读文本 → MIDI 二进制一致）
// ============================================================

@Test
class DecompileTests {
    // ── 乐谱反编译回环 ──
    @TestCase
    func decompileRoundTrip() {
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

        let decompiled = decompile(midi1)
        @Assert(decompiled.startsWith("MIDI"))

        let midi2 = generate(decompiled)
        @Expect(midi1.size, midi2.size)
        verifyBinaryIdentical(midi1, midi2)
    }

    // ── 外部 test.mid 二进制回环 ──
    @TestCase
    func decompileExternalTest1() {
        verifyExternalMid("testcase/test.mid")
    }

    // ── 外部 test2.mid 二进制回环 ──
    @TestCase
    func decompileExternalTest2() {
        verifyExternalMid("testcase/test2.mid")
    }

    // ── 外部 test3.mid 二进制回环 ──
    @TestCase
    func decompileExternalTest3() {
        verifyExternalMid("testcase/test3.mid")
    }

    // ── 速度精度保留 ──
    @TestCase
    func tempoRoundingPrecision() {
        let midPath = Path("testcase/test.mid")
        if (!exists(midPath)) { return }

        let data = File.readFrom(midPath)
        let text = decompile(data)
        @Assert(text.startsWith("MIDI"))
        @Assert(text.contains("SET_TEMPO 857142"))
        let regen = generate(text)
        verifyBinaryIdentical(data, regen)
    }
}
