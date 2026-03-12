package midi

import std.collection.*
import std.fs.*
import midi.core.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// MIDI 音乐生成器 — 单元测试 (std.unittest)
// ============================================================

@Test
class MidiTests {
    // ── 测试 1: 三轨完整编曲 ──
    @TestCase
    func twinkleVariation() {
        let input =
            "TEMPO 108\n" +
            "\n" +
            "TRACK melody\n" +
            "INSTRUMENT piano\n" +
            "C4 4  C4 4  G4 4  G4 4\n" +
            "A4 4  A4 4  G4 2\n" +
            "F4 4  F4 4  E4 4  E4 4\n" +
            "D4 4  D4 4  C4 2\n" +
            "G4 4  G4 4  F4 4  F4 4\n" +
            "E4 4  E4 4  D4 2\n" +
            "G4 8  G4 8  G4 8  F#4 8  F4 4  F4 4\n" +
            "E4 4  E4 4  D4 2\n" +
            "C4 4  C4 4  G4 4  G4 4\n" +
            "A4 4  A4 4  G4 2\n" +
            "F4 4  F4 4  E4 4  E4 4\n" +
            "D4 4  D4 4  C4 2\n" +
            "\n" +
            "TRACK harmony\n" +
            "INSTRUMENT strings\n" +
            "[C3 E3 G3] 2  [C3 E3 G3] 2\n" +
            "[F3 A3 C4] 2  [C3 E3 G3] 2\n" +
            "[F3 A3 C4] 2  [C3 E3 G3] 2\n" +
            "[G3 B3 D4] 2  [C3 E3 G3] 2\n" +
            "[C3 E3 G3] 2  [G3 B3 D4] 2\n" +
            "[A3 C4 E4] 2  [G3 B3 D4] 2\n" +
            "[C3 E3 G3] 2  [G3 B3 D4] 2\n" +
            "[A3 C4 E4] 2  [G3 B3 D4] 2\n" +
            "[C3 E3 G3] 2  [C3 E3 G3] 2\n" +
            "[F3 A3 C4] 2  [C3 E3 G3] 2\n" +
            "[F3 A3 C4] 2  [C3 E3 G3] 2\n" +
            "[G3 B3 D4] 2  [C3 E3 G3] 2\n" +
            "\n" +
            "TRACK bass\n" +
            "INSTRUMENT bass\n" +
            "C2 2  E2 2\n" +
            "F2 2  C2 2\n" +
            "F2 2  C2 2\n" +
            "G2 2  C2 2\n" +
            "C2 2  G2 2\n" +
            "A2 2  G2 2\n" +
            "C2 2  G2 2\n" +
            "A2 2  G2 2\n" +
            "C2 2  E2 2\n" +
            "F2 2  C2 2\n" +
            "F2 2  C2 2\n" +
            "G2 2  C2 2"
        let data = generate(input)

        @Assert(verifyMThd(data, 1, 3))
        @Assert(countTracks(data), 3)

        let programs = extractProgramChanges(data)
        @Assert(programs.size >= 3)
        @Expect(programs[0], 0)   // piano
        @Expect(programs[1], 48)  // strings
        @Expect(programs[2], 33)  // bass

        @Assert(verifyTempo(data, 108))

        let pitches = extractNoteOnPitches(data)
        var foundFSharp = false
        for (p in pitches) {
            if (p == 66) { foundFSharp = true; break }
        }
        @Assert(foundFSharp)
    }

    // ── 测试 2: 反编译回环 ──
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
        @Assert(decompiled.contains("TEMPO"))
        @Assert(decompiled.contains("INSTRUMENT"))

        let midi2 = generate(decompiled)
        @Assert(verifyMThd(midi2, 1, 3))
        @Expect(countTracks(midi1), countTracks(midi2))
        @Assert(verifyTempo(midi2, 120))

        let p1 = extractNoteOnPitches(midi1)
        let p2 = extractNoteOnPitches(midi2)
        @Expect(p1.size, p2.size)

        let prog1 = extractProgramChanges(midi1)
        let prog2 = extractProgramChanges(midi2)
        @Expect(prog1.size, prog2.size)
    }

    // ── 测试 3: VELOCITY ──
    @TestCase
    func velocityControl() {
        let input =
            "TEMPO 100\n" +
            "INSTRUMENT piano\n" +
            "VELOCITY 100\n" +
            "C4 4  D4 4  E4 4  F4 4\n"

        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))

        var foundVel100 = false
        var i: Int64 = 14
        while (i + 2 < data.size) {
            if ((data[i] & 0xF0) == 0x90 && data[i + 2] == 100) {
                foundVel100 = true
                break
            }
            i++
        }
        @Assert(foundVel100)

        let text = decompile(data)
        @Assert(text.contains("VELOCITY"))
    }

    // ── 测试 4: 扩展乐器（含 GM 新增音色） ──
    @TestCase
    func extendedInstruments() {
        let input =
            "TEMPO 90\n" +
            "\n" +
            "TRACK t1\n" +
            "INSTRUMENT harmonica\n" +
            "C4 4  E4 4  G4 4  C5 4\n" +
            "\n" +
            "TRACK t2\n" +
            "INSTRUMENT tuba\n" +
            "C3 2  G3 2\n" +
            "\n" +
            "TRACK t3\n" +
            "INSTRUMENT cello\n" +
            "C2 1\n"

        let data = generate(input)
        @Assert(verifyMThd(data, 1, 3))

        let programs = extractProgramChanges(data)
        @Assert(programs.size >= 3)
        @Expect(programs[0], 22)  // harmonica
        @Expect(programs[1], 58)  // tuba
        @Expect(programs[2], 42)  // cello

        // 反编译后乐器名应保持一致
        let text = decompile(data)
        @Assert(text.contains("harmonica"))
        @Assert(text.contains("tuba"))
        @Assert(text.contains("cello"))
    }

    // ── 测试 5: GM 乐器映射完整性 ──
    @TestCase
    func gmInstrumentMapping() {
        // 验证各 GM 乐器族代表乐器的编号映射
        @Expect(instrumentNumber("piano"), 0)
        @Expect(instrumentNumber("harpsichord"), 6)
        @Expect(instrumentNumber("glockenspiel"), 9)
        @Expect(instrumentNumber("church_organ"), 19)
        @Expect(instrumentNumber("guitar"), 24)
        @Expect(instrumentNumber("bass"), 33)
        @Expect(instrumentNumber("violin"), 40)
        @Expect(instrumentNumber("trumpet"), 56)
        @Expect(instrumentNumber("tuba"), 58)
        @Expect(instrumentNumber("saxophone"), 65)
        @Expect(instrumentNumber("flute"), 73)
        @Expect(instrumentNumber("sitar"), 104)
        @Expect(instrumentNumber("steel_drums"), 114)
        @Expect(instrumentNumber("gunshot"), 127)

        // 验证常用别名
        @Expect(instrumentNumber("steel_guitar"), 25)
        @Expect(instrumentNumber("french_horn"), 60)
        @Expect(instrumentNumber("alto_sax"), 65)
        @Expect(instrumentNumber("acoustic_grand_piano"), 0)

        // 未知乐器返回 0 (piano)
        @Expect(instrumentNumber("unknown"), 0)

        // 验证 GM 数组完整性（128 项）
        @Expect(GM_INSTRUMENTS.size, 128)

        // 验证反向映射
        @Expect(programToInstrument(0), "piano")
        @Expect(programToInstrument(58), "tuba")
        @Expect(programToInstrument(127), "gunshot")
        @Expect(programToInstrument(200), "piano")  // 越界返回默认值
    }

    // ── 测试 6: 反编译外部 test.mid ──
    @TestCase
    func decompileExternalTest1() {
        verifyExternalMid("testcase/test.mid")
    }

    // ── 测试 7: 反编译外部 test2.mid ──
    @TestCase
    func decompileExternalTest2() {
        verifyExternalMid("testcase/test2.mid")
    }

    // ── 测试 8: 反编译外部 test3.mid ──
    @TestCase
    func decompileExternalTest3() {
        verifyExternalMid("testcase/test3.mid")
    }

    // 辅助: 验证外部 .mid 文件反编译
    func verifyExternalMid(midPath: String) {
        let p = Path(midPath)
        if (!exists(p)) {
            return  // 文件不存在时跳过（CI 中可能无下载）
        }

        let data = File.readFrom(p)
        @Assert(data.size >= 14)
        @Assert(data[0], 0x4D)  // 'M'
        @Assert(data[1], 0x54)  // 'T'
        @Assert(data[2], 0x68)  // 'h'
        @Assert(data[3], 0x64)  // 'd'

        let text = decompile(data)
        @Assert(!text.startsWith("// Error"))
        @Assert(text.contains("TEMPO"))
        @Assert(text.contains("INSTRUMENT"))

        let regen = generate(text)
        @Assert(regen.size >= 14)
        @Assert(countTracks(regen) > 0)
    }
}
