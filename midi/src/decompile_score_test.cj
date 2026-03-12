package midi

import std.fs.*
import std.collection.*
import midi.core.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 反编译测试（乐谱格式）— 乐谱回环、外部文件乐谱解码
// 可读格式回环测试见 decompile_test.cj
// ============================================================

@Test
class DecompileScoreTests {
    // ── 乐谱格式回环：乐谱 → MIDI → 乐谱 → MIDI 音乐内容一致 ──
    @TestCase
    func scoreFormatRoundTrip() {
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

        // 反编译为乐谱格式
        let scoreText = decompile(midi1)
        @Assert(scoreText.contains("TEMPO 120"))
        @Assert(scoreText.contains("TRACK"))
        @Assert(scoreText.contains("INSTRUMENT guitar"))
        @Assert(scoreText.contains("INSTRUMENT strings"))
        @Assert(scoreText.contains("INSTRUMENT bass"))

        // 重编码
        let midi2 = generate(scoreText)

        // 验证音符一致
        let pitches1 = extractNoteOnPitches(midi1)
        let pitches2 = extractNoteOnPitches(midi2)
        @Expect(pitches1.size, pitches2.size)

        // 验证乐器一致
        let programs1 = extractProgramChanges(midi1)
        let programs2 = extractProgramChanges(midi2)
        @Expect(programs1.size, programs2.size)
        var pi: Int64 = 0
        while (pi < programs1.size && pi < programs2.size) {
            @Expect(programs1[pi], programs2[pi])
            pi++
        }

        // 验证 tempo 一致
        @Assert(verifyTempo(midi2, 120))
    }

    // ── test.mid: 乐谱格式解码 ──
    @TestCase
    func externalTest1Score() {
        let data = loadTestMid("testcase/binary/test.mid")
        @Assert(countTracks(data), 3)

        let text = decompile(data)
        @Assert(text.contains("TEMPO "))
        @Assert(text.contains("TRACK"))
        @Assert(text.contains("INSTRUMENT"))

        let regen = generate(text)
        @Assert(verifyMThd(regen, 1, UInt16(countTracks(regen))))

        let pitches1 = extractNoteOnPitches(data)
        let pitches2 = extractNoteOnPitches(regen)
        @Assert(pitches2.size > 0)
        verifyPitchSetOverlap(pitches1, pitches2)
    }

    // ── test2.mid: 乐谱格式解码 ──
    @TestCase
    func externalTest2Score() {
        let data = loadTestMid("testcase/binary/test2.mid")
        @Assert(countTracks(data), 4)

        let text = decompile(data)
        @Assert(text.contains("TEMPO "))
        @Assert(text.contains("TRACK"))
        @Assert(text.contains("CC "))

        let regen = generate(text)
        let pitches1 = extractNoteOnPitches(data)
        let pitches2 = extractNoteOnPitches(regen)
        @Assert(pitches2.size > 0)
        verifyPitchSetOverlap(pitches1, pitches2)
    }

    // ── test3.mid: 乐谱格式解码 ──
    @TestCase
    func externalTest3Score() {
        let data = loadTestMid("testcase/binary/test3.mid")
        @Assert(countTracks(data), 6)

        let text = decompile(data)
        @Assert(text.contains("TEMPO "))
        @Assert(text.contains("TRACK"))

        let regen = generate(text)
        let pitches1 = extractNoteOnPitches(data)
        let pitches2 = extractNoteOnPitches(regen)
        @Assert(pitches2.size > 0)
        verifyPitchSetOverlap(pitches1, pitches2)
    }

    // ── 乐谱格式 tempo 保留（BPM 级） ──
    @TestCase
    func tempoScoreFormat() {
        let data = loadTestMid("testcase/binary/test.mid")

        let text = decompile(data)
        // 857142 微秒 ≈ 70 BPM
        @Assert(text.contains("TEMPO 70"))

        let regen = generate(text)
        @Assert(verifyTempo(regen, 70))
    }

    // ── 乐谱格式编解码对称性 ──
    @TestCase
    func scoreSymmetry() {
        let input =
            "TEMPO 100\n" +
            "\nTRACK melody\n" +
            "INSTRUMENT piano\n" +
            "C4 4  D4 4  E4 4  F4 4\n" +
            "G4 2  A4 2\n"

        let midi1 = generate(input)
        let scoreText = decompile(midi1)

        @Assert(scoreText.contains("TEMPO 100"))
        @Assert(scoreText.contains("INSTRUMENT piano"))
        @Assert(scoreText.contains("C4"))
        @Assert(scoreText.contains("D4"))
        @Assert(scoreText.contains("G4"))

        let midi2 = generate(scoreText)
        let pitches1 = extractNoteOnPitches(midi1)
        let pitches2 = extractNoteOnPitches(midi2)
        @Expect(pitches1.size, pitches2.size)
    }

    // ── testcase/source 目录编解码测试 ──
    @TestCase
    func sourceFilesRoundTrip() {
        let sourceDir = Path("testcase/source")
        if (!exists(sourceDir)) { return }
        let entries = Directory.readFrom(sourceDir)
        var count: Int64 = 0
        for (entry in entries) {
            if (!entry.name.endsWith(".txt")) { continue }
            let bytes = File.readFrom(sourceDir.join(entry.name))
            let input = String.fromUtf8(bytes)
            let midi1 = generate(input)
            @Assert(midi1.size >= 14)

            let scoreText = decompile(midi1)
            @Assert(scoreText.contains("TEMPO"))
            let midi2 = generate(scoreText)
            @Assert(midi2.size >= 14)

            let pitches1 = extractNoteOnPitches(midi1)
            let pitches2 = extractNoteOnPitches(midi2)
            @Assert(pitches2.size > 0)

            count++
        }
        @Assert(count >= 20)
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

    // 验证两组音高有足够的重叠
    func verifyPitchSetOverlap(a: ArrayList<UInt8>, b: ArrayList<UInt8>) {
        let setA = HashSet<UInt8>(a)
        let setB = HashSet<UInt8>(b)
        var overlap: Int64 = 0
        for (p in setA) {
            if (setB.contains(p)) { overlap++ }
        }
        let minSize = if (setA.size < setB.size) { setA.size } else { setB.size }
        if (minSize > 0) {
            @Assert(overlap * 2 >= minSize)
        }
    }
}
