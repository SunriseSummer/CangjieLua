package midi

import std.collection.*
import std.fs.*

// ============================================================
// MIDI 音乐生成器 — 测试入口
// ============================================================

var totalPassed: Int64 = 0
var totalFailed: Int64 = 0

func runTest(name: String, testFn: () -> Bool): Unit {
    print("Test: ${name} ... ")
    let result = testFn()
    if (result) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }
}

func assertEq(label: String, actual: Int64, expected: Int64): Bool {
    if (actual != expected) {
        println("  ${label}: expected ${expected}, got ${actual}")
        return false
    }
    true
}

func assertArrayEq(label: String, actual: ArrayList<UInt8>, expected: Array<UInt8>): Bool {
    if (Int64(actual.size) != expected.size) {
        println("  ${label}: size mismatch: expected ${expected.size}, got ${actual.size}")
        return false
    }
    for (i in 0..expected.size) {
        if (actual[i] != expected[i]) {
            println("  ${label}: byte ${i} mismatch: expected ${expected[i]}, got ${actual[i]}")
            return false
        }
    }
    true
}

// VLQ 编码单元测试
func testVLQ(): Bool {
    let v0 = encodeVLQ(0)
    if (v0.size != 1 || v0[0] != 0x00) {
        println("  VLQ(0) failed")
        return false
    }
    let v127 = encodeVLQ(127)
    if (v127.size != 1 || v127[0] != 0x7F) {
        println("  VLQ(127) failed")
        return false
    }
    let v128 = encodeVLQ(128)
    if (v128.size != 2 || v128[0] != 0x81 || v128[1] != 0x00) {
        println("  VLQ(128) failed")
        return false
    }
    let v480 = encodeVLQ(480)
    if (v480.size != 2 || v480[0] != 0x83 || v480[1] != 0x60) {
        println("  VLQ(480) failed")
        return false
    }
    let v960 = encodeVLQ(960)
    if (v960.size != 2 || v960[0] != 0x87 || v960[1] != 0x40) {
        println("  VLQ(960) failed")
        return false
    }
    true
}

// 测试 1: 两只老虎（单音）— MIDI 文件头 [5分]
func test1_TwoTigers(): Bool {
    let input = "TEMPO 120\nC4 4"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    let pitches = extractNoteOnPitches(data)
    if (pitches.size < 1) {
        println("  ERROR: No Note On events found")
        return false
    }
    if (pitches[0] != 60) {
        println("  ERROR: Expected C4=60, got ${pitches[0]}")
        return false
    }
    saveMidiFile("tests/test1_two_tigers.mid", data)
    true
}

// 测试 2: 小蜜蜂 — 音高映射 [5分]
func test2_LittleBee(): Bool {
    let input = "TEMPO 120\nG4 4  E4 4  E4 2\nF4 4  D4 4  D4 2\nC4 4  D4 4  E4 4  F4 4\nG4 4  G4 4  G4 2"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    let pitches = extractNoteOnPitches(data)
    let expected: Array<UInt8> = [67, 64, 64, 65, 62, 62, 60, 62, 64, 65, 67, 67, 67]
    if (!assertArrayEq("pitches", pitches, expected)) { return false }
    saveMidiFile("tests/test2_little_bee.mid", data)
    true
}

// 测试 3: 小星星 — 时值变化 [10分]
func test3_TwinkleStar(): Bool {
    let input =
        "TEMPO 120\n" +
        "C4 4  C4 4  G4 4  G4 4\n" +
        "A4 4  A4 4  G4 2\n" +
        "F4 4  F4 4  E4 4  E4 4\n" +
        "D4 4  D4 4  C4 2\n" +
        "G4 4  G4 4  F4 4  F4 4\n" +
        "E4 4  E4 4  D4 2\n" +
        "G4 4  G4 4  F4 4  F4 4\n" +
        "E4 4  E4 4  D4 2\n" +
        "C4 4  C4 4  G4 4  G4 4\n" +
        "A4 4  A4 4  G4 2\n" +
        "F4 4  F4 4  E4 4  E4 4\n" +
        "D4 4  D4 4  C4 2"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    let pitches = extractNoteOnPitches(data)
    if (!assertEq("note count", Int64(pitches.size), 42)) { return false }
    if (!verifyTempo(data, 120)) { return false }
    saveMidiFile("tests/test3_twinkle_star.mid", data)
    true
}

// 测试 4: 欢乐颂 — BPM 速度控制 [10分]
func test4_OdeToJoy(): Bool {
    let input =
        "TEMPO 144\n" +
        "E4 4  E4 4  F4 4  G4 4\n" +
        "G4 4  F4 4  E4 4  D4 4\n" +
        "C4 4  C4 4  D4 4  E4 4\n" +
        "E4 4  D4 8  D4 2\n" +
        "E4 4  E4 4  F4 4  G4 4\n" +
        "G4 4  F4 4  E4 4  D4 4\n" +
        "C4 4  C4 4  D4 4  E4 4\n" +
        "D4 4  C4 8  C4 2"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    if (!verifyTempo(data, 144)) { return false }
    let pitches = extractNoteOnPitches(data)
    if (!assertEq("note count", Int64(pitches.size), 30)) { return false }
    saveMidiFile("tests/test4_ode_to_joy.mid", data)
    true
}

// 测试 5: 茉莉花 — 升降号 [10分]
func test5_JasmineFlower(): Bool {
    let input =
        "TEMPO 96\n" +
        "E4 4  E4 8  F#4 8  G4 4  A4 4\n" +
        "G4 4  E4 8  F#4 8  G4 2\n" +
        "A4 4  G4 4  E4 4  D4 4\n" +
        "E4 8  F#4 8  E4 4  D4 2\n" +
        "E4 4  D4 4  C4 4  D4 4\n" +
        "E4 4  G4 4  A4 2\n" +
        "G4 4  E4 4  D4 4  C4 4\n" +
        "D4 8  Eb4 8  D4 4  C4 2"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    let pitches = extractNoteOnPitches(data)

    var foundFSharp = false
    for (p in pitches) {
        if (p == 66) { foundFSharp = true; break }
    }
    if (!foundFSharp) {
        println("  ERROR: F#4 (66) not found")
        return false
    }

    var foundEFlat = false
    for (p in pitches) {
        if (p == 63) { foundEFlat = true; break }
    }
    if (!foundEFlat) {
        println("  ERROR: Eb4 (63) not found")
        return false
    }
    if (!verifyTempo(data, 96)) { return false }
    saveMidiFile("tests/test5_jasmine.mid", data)
    true
}

// 测试 6: 天空之城 — 休止符 [10分]
func test6_CastleInSky(): Bool {
    let input =
        "TEMPO 80\n" +
        "R 8  A4 8  B4 8  C5 4  B4 8\n" +
        "C5 4  E5 4  B4 2\n" +
        "R 8  E4 8  A4 8  G4 4  E4 8\n" +
        "G4 4  A4 4  R 4  R 4"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    let pitches = extractNoteOnPitches(data)
    if (!assertEq("note count", Int64(pitches.size), 13)) { return false }

    var foundC5 = false
    for (p in pitches) {
        if (p == 72) { foundC5 = true; break }
    }
    if (!foundC5) {
        println("  ERROR: C5 (72) not found")
        return false
    }
    saveMidiFile("tests/test6_castle_in_sky.mid", data)
    true
}

// 测试 7: 卡农 — 乐器选择 [10分]
func test7_Canon(): Bool {
    let input =
        "TEMPO 72\n" +
        "INSTRUMENT violin\n" +
        "F#5 4  E5 4  D5 4  C#5 4\n" +
        "B4 4  A4 4  B4 4  C#5 4\n" +
        "D5 4  C#5 4  B4 4  A4 4\n" +
        "G4 4  F#4 4  G4 4  E4 4"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    let programs = extractProgramChanges(data)
    if (programs.size < 1) {
        println("  ERROR: No Program Change events found")
        return false
    }
    if (programs[0] != 40) {
        println("  ERROR: Expected violin (40), got ${programs[0]}")
        return false
    }
    let pitches = extractNoteOnPitches(data)
    if (pitches.size < 1 || pitches[0] != 78) {
        println("  ERROR: First note should be F#5 (78)")
        return false
    }
    saveMidiFile("tests/test7_canon.mid", data)
    true
}

// 测试 8: 致爱丽丝 — 和弦 [15分]
func test8_FurElise(): Bool {
    let input =
        "TEMPO 132\n" +
        "INSTRUMENT piano\n" +
        "E5 16  D#5 16  E5 16  D#5 16  E5 16  B4 16  D5 16  C5 16\n" +
        "[A2 A3 C4 E4 A4] 4  R 8\n" +
        "E3 8  A3 8  C4 8\n" +
        "[E3 B3 E4 G#4] 4  R 8\n" +
        "E3 8  C4 8  E4 8\n" +
        "[A2 A3 C4 E4 A4] 4"
    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) { return false }
    let pitches = extractNoteOnPitches(data)
    if (Int64(pitches.size) < 20) {
        println("  ERROR: Too few notes, expected ~28, got ${pitches.size}")
        return false
    }

    var foundA2 = false
    for (p in pitches) {
        if (p == 45) { foundA2 = true; break }
    }
    if (!foundA2) {
        println("  ERROR: A2 (45) not found in chord")
        return false
    }

    var foundDSharp = false
    for (p in pitches) {
        if (p == 75) { foundDSharp = true; break }
    }
    if (!foundDSharp) {
        println("  ERROR: D#5 (75) not found")
        return false
    }
    saveMidiFile("tests/test8_fur_elise.mid", data)
    true
}

// 测试 9: 生日快乐 — 多轨道 [15分]
func test9_HappyBirthday(): Bool {
    let input =
        "TEMPO 120\n" +
        "\n" +
        "TRACK melody\n" +
        "INSTRUMENT piano\n" +
        "G4 8  G4 8  A4 4  G4 4\n" +
        "C5 4  B4 2\n" +
        "G4 8  G4 8  A4 4  G4 4\n" +
        "D5 4  C5 2\n" +
        "G4 8  G4 8  G5 4  E5 4\n" +
        "C5 4  B4 4  A4 4\n" +
        "F5 8  F5 8  E5 4  C5 4\n" +
        "D5 4  C5 2\n" +
        "\n" +
        "TRACK bass\n" +
        "INSTRUMENT bass\n" +
        "C3 2  G3 2\n" +
        "C3 2  G3 2\n" +
        "C3 2  E3 2\n" +
        "F3 2  C3 2"
    let data = generate(input)
    if (!verifyMThd(data, 1, 2)) { return false }
    let trackCount = countTracks(data)
    if (!assertEq("MTrk count", trackCount, 2)) { return false }
    let programs = extractProgramChanges(data)
    if (programs.size < 2) {
        println("  ERROR: Expected 2 Program Changes, got ${programs.size}")
        return false
    }
    if (programs[0] != 0) {
        println("  ERROR: Track 1 should be piano (0), got ${programs[0]}")
        return false
    }
    if (programs[1] != 33) {
        println("  ERROR: Track 2 should be bass (33), got ${programs[1]}")
        return false
    }
    saveMidiFile("tests/test9_happy_birthday.mid", data)
    true
}

// 测试 10: 小星星变奏曲 — 三轨完整编曲 [20分]
func test10_TwinkleVariation(): Bool {
    let input =
        "TEMPO 108\n" +
        "\n" +
        "// 轨道1: 钢琴旋律\n" +
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
        "// 轨道2: 弦乐和弦伴奏\n" +
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
        "// 轨道3: 贝斯低音线\n" +
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
    if (!verifyMThd(data, 1, 3)) { return false }
    let trackCount = countTracks(data)
    if (!assertEq("MTrk count", trackCount, 3)) { return false }
    let programs = extractProgramChanges(data)
    if (programs.size < 3) {
        println("  ERROR: Expected 3 Program Changes, got ${programs.size}")
        return false
    }
    if (programs[0] != 0) {
        println("  ERROR: Track 1 should be piano (0), got ${programs[0]}")
        return false
    }
    if (programs[1] != 48) {
        println("  ERROR: Track 2 should be strings (48), got ${programs[1]}")
        return false
    }
    if (programs[2] != 33) {
        println("  ERROR: Track 3 should be bass (33), got ${programs[2]}")
        return false
    }
    if (!verifyTempo(data, 108)) { return false }

    let pitches = extractNoteOnPitches(data)
    var foundFSharp = false
    for (p in pitches) {
        if (p == 66) { foundFSharp = true; break }
    }
    if (!foundFSharp) {
        println("  ERROR: F#4 (66) not found in melody")
        return false
    }
    saveMidiFile("tests/test10_twinkle_variation.mid", data)
    true
}

// 主入口
main(): Int64 {
    println("═══════════════════════════════════════")
    println("  🎵 MIDI 音乐生成器 — 测试套件")
    println("═══════════════════════════════════════")
    println()

    // 创建 tests 目录
    try {
        Directory.create(Path("tests"))
    } catch (_: Exception) {}

    println("── 单元测试 ──")
    runTest("VLQ 编码", testVLQ)
    println()

    println("── 测试用例 ──")
    runTest("1. 🐯 两只老虎（单音）— MIDI 文件头 [5分]", test1_TwoTigers)
    runTest("2. 🐝 小蜜蜂 — 音高映射 [5分]", test2_LittleBee)
    runTest("3. ⭐ 小星星 — 时值变化 [10分]", test3_TwinkleStar)
    runTest("4. 🎉 欢乐颂 — BPM 速度控制 [10分]", test4_OdeToJoy)
    runTest("5. 🌸 茉莉花 — 升降号 [10分]", test5_JasmineFlower)
    runTest("6. 🏰 天空之城 — 休止符 [10分]", test6_CastleInSky)
    runTest("7. 🎻 卡农 — 乐器选择 [10分]", test7_Canon)
    runTest("8. 🎹 致爱丽丝 — 和弦 [15分]", test8_FurElise)
    runTest("9. 🎂 生日快乐 — 多轨道 [15分]", test9_HappyBirthday)
    runTest("10. 🌟 小星星变奏曲 — 三轨完整编曲 [20分]", test10_TwinkleVariation)

    println()
    println("═══════════════════════════════════════")
    println("  结果: ${totalPassed} 通过, ${totalFailed} 失败")
    let scores: Array<Int64> = [5, 5, 10, 10, 10, 10, 10, 15, 15, 20]
    let testsPassed = totalPassed - 1
    var score: Int64 = 0
    for (i in 0..scores.size) {
        if (i < testsPassed) { score += scores[i] }
    }
    println("  得分: ${score} / 110")
    println("═══════════════════════════════════════")

    if (totalFailed == 0) {
        println("\n🎉 全部通过！MIDI 文件保存在 tests/ 目录下。")
    } else {
        println("\nMIDI 文件保存在 tests/ 目录下，可用播放器打开试听。")
    }

    totalFailed
}
