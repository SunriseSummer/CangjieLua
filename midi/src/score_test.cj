package midi

import std.collection.*
import midi.core.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 乐谱格式编码测试
// ============================================================

// 乐谱格式编码测试：验证高级音乐记谱语法正确编码为 MIDI 二进制
@Test
class ScoreTests {
    // ── 三轨完整编曲 ──
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

    // ── VELOCITY 力度控制 ──
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

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 扩展乐器 ──
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

        let text = decompileReadable(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── GM 乐器映射完整性 ──
    @TestCase
    func gmInstrumentMapping() {
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
        @Expect(instrumentNumber("steel_guitar"), 25)
        @Expect(instrumentNumber("french_horn"), 60)
        @Expect(instrumentNumber("alto_sax"), 65)
        @Expect(instrumentNumber("acoustic_grand_piano"), 0)
        @Expect(instrumentNumber("unknown"), 0)
        @Expect(GM_INSTRUMENTS.size, 128)
        @Expect(programToInstrument(0), "piano")
        @Expect(programToInstrument(58), "tuba")
        @Expect(programToInstrument(127), "gunshot")
        @Expect(programToInstrument(200), "piano")
    }

}
