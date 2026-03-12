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
    // ── 测试 1: 三轨完整编曲（乐谱格式编码） ──
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

    // ── 测试 2: 反编译回环（二进制完全一致） ──
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

        // 反编译应输出 MIDI_RAW 格式
        let decompiled = decompile(midi1)
        @Assert(decompiled.startsWith("MIDI_RAW"))

        // 重新编码应产生二进制完全一致的输出
        let midi2 = generate(decompiled)
        @Expect(midi1.size, midi2.size)
        verifyBinaryIdentical(midi1, midi2)
    }

    // ── 测试 3: VELOCITY（乐谱格式编码） ──
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

        // 反编译后重新编码应二进制一致
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 测试 4: 扩展乐器（乐谱格式编码 + 二进制回环） ──
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

        // 反编译后重新编码应二进制一致
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
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

    // ── 测试 6: 外部 test.mid 二进制回环 ──
    @TestCase
    func decompileExternalTest1() {
        verifyExternalMid("testcase/test.mid")
    }

    // ── 测试 7: 外部 test2.mid 二进制回环 ──
    @TestCase
    func decompileExternalTest2() {
        verifyExternalMid("testcase/test2.mid")
    }

    // ── 测试 8: 外部 test3.mid 二进制回环 ──
    @TestCase
    func decompileExternalTest3() {
        verifyExternalMid("testcase/test3.mid")
    }

    // ── 测试 9: 附点音符（乐谱格式编码 + 二进制回环） ──
    @TestCase
    func dottedNoteDurations() {
        let input =
            "TEMPO 120\n" +
            "INSTRUMENT piano\n" +
            "C4 4.  D4 8.  E4 2.  F4 16.\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))

        // 反编译后重新编码应二进制一致
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 测试 10: 原始 tick 时值（乐谱格式编码 + 二进制回环） ──
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

        // 反编译后重新编码应二进制一致
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 测试 11: CHANNEL 指令（乐谱格式编码 + 二进制回环） ──
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

        // 反编译后重新编码应二进制一致
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 测试 12: TEMPO_AT 绝对速度变化（乐谱格式编码 + 二进制回环） ──
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
        // 应有速度轨道 + 音符轨道 = 2 轨道
        @Assert(verifyMThd(data, 1, 2))
        @Assert(countTracks(data), 2)
        @Assert(verifyTempo(data, 120))

        // 反编译后重新编码应二进制一致
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 测试 13: 速度精度保留（反编译保留原始微秒值） ──
    @TestCase
    func tempoRoundingPrecision() {
        // 原始文件 test.mid 的速度为 857142 微秒 (≈70.0 BPM)
        // MIDI_RAW 格式保留原始十六进制字节 0D 15 86 = 857478? No: 0x0D1586 = 857478
        // Wait: 857142 = 0x0D1506 → bytes: 0D 15 06
        // Actually: 857142 decimal = 0xD1506 hex → bytes: 0D 15 06
        let midPath = Path("testcase/test.mid")
        if (!exists(midPath)) { return }

        let data = File.readFrom(midPath)
        let text = decompile(data)
        // MIDI_RAW 格式应包含 SetTempo 的原始字节
        @Assert(text.startsWith("MIDI_RAW"))
        // 反编译后重新编码应二进制一致
        let regen = generate(text)
        verifyBinaryIdentical(data, regen)
    }

    // ── 辅助函数: 验证两个字节数组二进制完全一致 ──
    func verifyBinaryIdentical(a: Array<UInt8>, b: Array<UInt8>) {
        @Expect(a.size, b.size)
        var i: Int64 = 0
        while (i < a.size && i < b.size) {
            if (a[i] != b[i]) {
                println("  BINARY DIFF at byte ${i}: expected ${a[i]}, got ${b[i]}")
                @Assert(false)
                return
            }
            i++
        }
    }

    // ── 辅助函数: 验证外部 .mid 文件的反编译+重编码二进制一致性 ──
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
        @Assert(text.startsWith("MIDI_RAW"))

        // 重新编码应产生二进制完全一致的输出
        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)
    }
}
