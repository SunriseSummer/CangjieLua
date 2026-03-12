package midi

import std.collection.*
import std.fs.*

// ============================================================
// MIDI 音乐生成器 — 入口
// ============================================================

// 处理单个 midi 源文件，生成同目录下的 .mid 文件
func processFile(srcPath: Path): Unit {
    let bytes = File.readFrom(srcPath)
    let input = String.fromUtf8(bytes)
    let data = generate(input)
    let parent = srcPath.parent.toString()
    let baseName = srcPath.fileNameWithoutExtension
    let outPath = Path(parent).join("${baseName}.mid")
    saveMidiFile(outPath.toString(), data)
    println("  ✓ ${srcPath} -> ${outPath}")
}

// 处理路径：文件则生成单个 .mid，目录则生成目录下所有 .txt 对应的 .mid
func process(path: String): Unit {
    let p = Path(path)
    if (!exists(p)) {
        println("错误: 路径不存在: ${path}")
        return
    }
    let info = FileInfo(p)
    if (info.isDirectory()) {
        println("处理目录: ${path}")
        let entries = Directory.readFrom(p)
        var count: Int64 = 0
        for (entry in entries) {
            if (entry.name.endsWith(".txt")) {
                try {
                    processFile(p.join(entry.name))
                    count++
                } catch (e: Exception) {
                    println("  ✗ ${entry.name}: ${e}")
                }
            }
        }
        println("完成: ${count} 个文件已生成")
    } else {
        println("处理文件: ${path}")
        try {
            processFile(p)
        } catch (e: Exception) {
            println("  ✗ ${path}: ${e}")
        }
    }
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
    if (trackCount != 3) {
        println("  ERROR: MTrk count: expected 3, got ${trackCount}")
        return false
    }
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
main(args: Array<String>): Int64 {
    if (args.size > 0) {
        for (arg in args) {
            process(arg)
        }
        return 0
    }

    println("═══════════════════════════════════════")
    println("  🎵 MIDI 音乐生成器 — 测试套件")
    println("═══════════════════════════════════════")
    println()

    // 创建 tests 目录
    try {
        Directory.create(Path("tests"))
    } catch (_: Exception) {}

    print("Test: 🌟 小星星变奏曲 — 三轨完整编曲 [20分] ... ")
    let passed = test10_TwinkleVariation()
    if (passed) {
        println("PASS ✓")
    } else {
        println("FAIL ✗")
    }

    println()
    println("═══════════════════════════════════════")
    if (passed) {
        println("  结果: 1 通过, 0 失败")
        println("═══════════════════════════════════════")
        println("\n🎉 测试通过！MIDI 文件保存在 tests/ 目录下。")
        return 0
    } else {
        println("  结果: 0 通过, 1 失败")
        println("═══════════════════════════════════════")
        return 1
    }
}
