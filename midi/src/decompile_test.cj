package midi

import std.fs.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 反编译回环测试
// 重点验证：.mid → 可读文本 → .mid 二进制完全一致
// ============================================================

// 反编译回环测试：验证 .mid → 可读文本 → .mid 二进制完全一致
@Test
class DecompileTests {
    // ── 乐谱格式 → MIDI → 可读文本 → MIDI 回环 ──
    @TestCase
    func scoreRoundTrip() {
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

        // 第一次反编译 + 重编码
        let text1 = decompile(midi1)
        @Assert(text1.startsWith("MIDI"))
        let midi2 = generate(text1)
        @Expect(midi1.size, midi2.size)
        verifyBinaryIdentical(midi1, midi2)

        // 第二次反编译 + 重编码（双重回环，验证格式稳定性）
        let text2 = decompile(midi2)
        @Expect(text1, text2)
        let midi3 = generate(text2)
        verifyBinaryIdentical(midi1, midi3)
    }

    // ── test.mid: 3 轨道钢琴曲（Format 1, TPQ 480, 无 Running Status） ──
    @TestCase
    func externalTest1() {
        let data = loadTestMid("testcase/test.mid")

        // 验证文件头
        @Assert(countTracks(data), 3)

        // 反编译
        let text = decompile(data)
        @Assert(text.startsWith("MIDI"))
        // 不使用 Running Status
        @Assert(!text.contains("RUNNING_STATUS ON"))
        // 包含 SET_TEMPO（857142 微秒 ≈ 70 BPM）
        @Assert(text.contains("SET_TEMPO 857142"))
        // 包含 Note On/Off 事件（使用音名而非十六进制）
        @Assert(text.contains("ON "))
        @Assert(text.contains("OFF "))
        // 包含 Program Change
        @Assert(text.contains("PROGRAM "))
        // 包含 META 事件（轨道名等）
        @Assert(text.contains("META 03"))

        // 重编码 → 二进制完全一致
        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)

        // 双重回环
        let text2 = decompile(regen)
        @Expect(text, text2)
    }

    // ── test2.mid: 4 轨道曲目（Format 1, TPQ 480, 184 个速度变化, 大量 CC） ──
    @TestCase
    func externalTest2() {
        let data = loadTestMid("testcase/test2.mid")

        @Assert(countTracks(data), 4)

        let text = decompile(data)
        @Assert(text.startsWith("MIDI"))
        @Assert(!text.contains("RUNNING_STATUS ON"))
        // 包含多个速度变化
        @Assert(text.contains("SET_TEMPO "))
        // 包含 CC 事件（控制器变化）
        @Assert(text.contains("CC "))
        // 包含 META 事件
        @Assert(text.contains("META "))

        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)

        let text2 = decompile(regen)
        @Expect(text, text2)
    }

    // ── test3.mid: 6 轨道曲目（Format 1, TPQ 120, Running Status） ──
    @TestCase
    func externalTest3() {
        let data = loadTestMid("testcase/test3.mid")

        @Assert(countTracks(data), 6)

        let text = decompile(data)
        @Assert(text.startsWith("MIDI"))
        // 使用 Running Status
        @Assert(text.contains("RUNNING_STATUS ON"))
        // TPQ = 120
        @Assert(text.contains("TPQ 120"))
        // 包含 Note On 事件（使用音名）
        @Assert(text.contains("ON "))
        // 包含 CC 事件
        @Assert(text.contains("CC "))

        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)

        let text2 = decompile(regen)
        @Expect(text, text2)
    }

    // ── 速度精度保留（微秒级无损） ──
    @TestCase
    func tempoMicrosecondPrecision() {
        let data = loadTestMid("testcase/test.mid")

        let text = decompile(data)
        // 857142 微秒 ≈ 70.0 BPM，验证精确保留微秒值
        @Assert(text.contains("SET_TEMPO 857142"))
        let regen = generate(text)
        verifyBinaryIdentical(data, regen)
    }

    // ── 辅助函数: 加载测试 .mid 文件（文件必须存在） ──
    func loadTestMid(midPath: String): Array<UInt8> {
        let p = Path(midPath)
        @Assert(exists(p))
        let data = File.readFrom(p)
        @Assert(data.size >= 14)
        @Assert(data[0], 0x4D)  // 'M'
        @Assert(data[1], 0x54)  // 'T'
        @Assert(data[2], 0x68)  // 'h'
        @Assert(data[3], 0x64)  // 'd'
        data
    }
}
