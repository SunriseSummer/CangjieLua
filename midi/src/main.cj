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

// 反编译单个 .mid 文件，生成同目录下的 .txt 文件
func decompileFile(srcPath: Path): Unit {
    let text = decompileToString(srcPath.toString())
    let parent = srcPath.parent.toString()
    let baseName = srcPath.fileNameWithoutExtension
    let outPath = Path(parent).join("${baseName}_decompiled.txt")
    File.writeTo(outPath, text.toArray())
    println("  ✓ ${srcPath} -> ${outPath}")
}

// 反编译路径：文件则反编译单个 .mid，目录则反编译目录下所有 .mid
func decompileProcess(path: String): Unit {
    let p = Path(path)
    if (!exists(p)) {
        println("错误: 路径不存在: ${path}")
        return
    }
    let info = FileInfo(p)
    if (info.isDirectory()) {
        println("反编译目录: ${path}")
        let entries = Directory.readFrom(p)
        var count: Int64 = 0
        for (entry in entries) {
            if (entry.name.endsWith(".mid")) {
                try {
                    decompileFile(p.join(entry.name))
                    count++
                } catch (e: Exception) {
                    println("  ✗ ${entry.name}: ${e}")
                }
            }
        }
        println("完成: ${count} 个文件已反编译")
    } else {
        println("反编译文件: ${path}")
        try {
            decompileFile(p)
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

// 反编译回环测试：text → MIDI → text → MIDI → 比较
func testDecompileRoundTrip(): Bool {
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

    // 第一次生成
    let midi1 = generate(input)
    if (!verifyMThd(midi1, 1, 3)) {
        println("  ERROR: First generate failed MThd check")
        return false
    }

    // 反编译
    let decompiled = decompile(midi1)
    if (!decompiled.contains("TEMPO")) {
        println("  ERROR: Decompiled text missing TEMPO")
        return false
    }
    if (!decompiled.contains("INSTRUMENT")) {
        println("  ERROR: Decompiled text missing INSTRUMENT")
        return false
    }

    // 第二次生成
    let midi2 = generate(decompiled)
    if (!verifyMThd(midi2, 1, 3)) {
        println("  ERROR: Second generate failed MThd check")
        return false
    }

    // 验证两次结果一致性：轨道数
    let tc1 = countTracks(midi1)
    let tc2 = countTracks(midi2)
    if (tc1 != tc2) {
        println("  ERROR: Track count mismatch: ${tc1} vs ${tc2}")
        return false
    }

    // 验证 tempo
    if (!verifyTempo(midi2, 120)) {
        println("  ERROR: Round-trip tempo mismatch")
        return false
    }

    // 验证音高数量
    let p1 = extractNoteOnPitches(midi1)
    let p2 = extractNoteOnPitches(midi2)
    if (p1.size != p2.size) {
        println("  ERROR: Note count mismatch: ${p1.size} vs ${p2.size}")
        return false
    }

    // 验证乐器
    let prog1 = extractProgramChanges(midi1)
    let prog2 = extractProgramChanges(midi2)
    if (prog1.size != prog2.size) {
        println("  ERROR: Program count mismatch: ${prog1.size} vs ${prog2.size}")
        return false
    }

    saveMidiFile("tests/test_roundtrip.mid", midi2)
    true
}

// 反编译外部 .mid 文件测试
func testDecompileExternal(midPath: String): Bool {
    let p = Path(midPath)
    if (!exists(p)) {
        println("  SKIP: ${midPath} not found")
        return true
    }

    let data = File.readFrom(p)
    if (data.size < 14) {
        println("  ERROR: File too small: ${data.size} bytes")
        return false
    }

    // 检查 MThd 签名
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        println("  ERROR: Invalid MThd signature")
        return false
    }

    // 反编译
    let text = decompile(data)
    if (text.startsWith("// Error")) {
        println("  ERROR: Decompile failed: ${text}")
        return false
    }

    // 验证反编译结果包含基本元素
    if (!text.contains("TEMPO")) {
        println("  ERROR: Missing TEMPO in decompiled output")
        return false
    }
    if (!text.contains("INSTRUMENT")) {
        println("  ERROR: Missing INSTRUMENT in decompiled output")
        return false
    }

    // 重新生成 MIDI 验证
    let regen = generate(text)
    if (regen.size < 14) {
        println("  ERROR: Re-generated MIDI too small: ${regen.size} bytes")
        return false
    }

    // 验证重新生成的 MIDI 有效
    let regenTracks = countTracks(regen)
    if (regenTracks <= 0) {
        println("  ERROR: Re-generated MIDI has no tracks")
        return false
    }

    // 保存反编译结果和重新生成的 MIDI
    let baseName = p.fileNameWithoutExtension
    File.writeTo(Path("tests/${baseName}_decompiled.txt"), text.toArray())
    saveMidiFile("tests/${baseName}_regen.mid", regen)

    // 打印统计信息
    let origNotes = extractNoteOnPitches(data)
    let regenNotes = extractNoteOnPitches(regen)
    println("  原始: ${data.size} bytes, ${origNotes.size} notes")
    println("  反编: ${text.size} chars, 重生成: ${regen.size} bytes, ${regenNotes.size} notes")

    true
}

// VELOCITY 功能测试
func testVelocity(): Bool {
    let input =
        "TEMPO 100\n" +
        "INSTRUMENT piano\n" +
        "VELOCITY 100\n" +
        "C4 4  D4 4  E4 4  F4 4\n"

    let data = generate(input)
    if (!verifyMThd(data, 0, 1)) {
        println("  ERROR: MThd check failed")
        return false
    }

    // 检查生成的 NoteOn 力度是否为 100
    let size = data.size
    var i: Int64 = 14
    var foundVel100 = false
    while (i + 2 < size) {
        if ((data[i] & 0xF0) == 0x90 && data[i + 2] == 100) {
            foundVel100 = true
            break
        }
        i++
    }
    if (!foundVel100) {
        println("  ERROR: Velocity 100 not found in NoteOn events")
        return false
    }

    // 反编译并检查 VELOCITY 指令
    let text = decompile(data)
    if (!text.contains("VELOCITY")) {
        println("  ERROR: Decompiled text should contain VELOCITY")
        return false
    }

    saveMidiFile("tests/test_velocity.mid", data)
    true
}

// 扩展乐器测试
func testExtendedInstruments(): Bool {
    let input =
        "TEMPO 90\n" +
        "\n" +
        "TRACK t1\n" +
        "INSTRUMENT harmonica\n" +
        "C4 4  E4 4  G4 4  C5 4\n" +
        "\n" +
        "TRACK t2\n" +
        "INSTRUMENT steel_guitar\n" +
        "C3 2  G3 2\n" +
        "\n" +
        "TRACK t3\n" +
        "INSTRUMENT cello\n" +
        "C2 1\n"

    let data = generate(input)
    if (!verifyMThd(data, 1, 3)) {
        println("  ERROR: MThd check failed")
        return false
    }

    let programs = extractProgramChanges(data)
    if (programs.size < 3) {
        println("  ERROR: Expected 3 Program Changes, got ${programs.size}")
        return false
    }
    if (programs[0] != 22) {
        println("  ERROR: Track 1 should be harmonica (22), got ${programs[0]}")
        return false
    }
    if (programs[1] != 26) {
        println("  ERROR: Track 2 should be steel_guitar (26), got ${programs[1]}")
        return false
    }
    if (programs[2] != 42) {
        println("  ERROR: Track 3 should be cello (42), got ${programs[2]}")
        return false
    }

    // 反编译验证乐器名还原
    let text = decompile(data)
    if (!text.contains("harmonica")) {
        println("  ERROR: Decompiled text should contain 'harmonica'")
        return false
    }
    if (!text.contains("steel_guitar")) {
        println("  ERROR: Decompiled text should contain 'steel_guitar'")
        return false
    }
    if (!text.contains("cello")) {
        println("  ERROR: Decompiled text should contain 'cello'")
        return false
    }

    saveMidiFile("tests/test_instruments.mid", data)
    true
}

func printUsage(): Unit {
    println("用法: midi [选项] [路径...]")
    println()
    println("选项:")
    println("  -d, --decompile    反编译 .mid 文件为文本乐谱")
    println("  -h, --help         显示帮助信息")
    println()
    println("不带参数运行时执行内置测试套件。")
    println("提供路径时根据模式处理文件或目录:")
    println("  默认模式: 将 .txt 乐谱编译为 .mid 文件")
    println("  反编译模式: 将 .mid 文件反编译为 .txt 乐谱")
}

// 主入口
main(args: Array<String>): Int64 {
    var decompileMode = false
    var showHelp = false
    let paths = ArrayList<String>()

    for (arg in args) {
        if (arg == "--decompile" || arg == "-d") {
            decompileMode = true
        } else if (arg == "--help" || arg == "-h") {
            showHelp = true
        } else {
            paths.add(arg)
        }
    }

    if (showHelp) {
        printUsage()
        return 0
    }

    if (paths.size > 0) {
        if (decompileMode) {
            for (path in paths) {
                decompileProcess(path)
            }
        } else {
            for (path in paths) {
                process(path)
            }
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

    var totalPassed: Int64 = 0
    var totalFailed: Int64 = 0

    // 测试 1: 三轨完整编曲
    print("Test 1: 🌟 小星星变奏曲 — 三轨完整编曲 ... ")
    if (test10_TwinkleVariation()) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }

    // 测试 2: 反编译回环测试
    print("Test 2: 🔄 反编译回环测试 — text→MIDI→text→MIDI ... ")
    if (testDecompileRoundTrip()) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }

    // 测试 3: VELOCITY 功能
    print("Test 3: 🎚  VELOCITY 力度控制 ... ")
    if (testVelocity()) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }

    // 测试 4: 扩展乐器
    print("Test 4: 🎸 扩展乐器支持 ... ")
    if (testExtendedInstruments()) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }

    // 测试 5-7: 外部 .mid 文件反编译
    print("Test 5: 📂 反编译 test.mid ... ")
    if (testDecompileExternal("testcase/test.mid")) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }

    print("Test 6: 📂 反编译 test2.mid ... ")
    if (testDecompileExternal("testcase/test2.mid")) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }

    print("Test 7: 📂 反编译 test3.mid ... ")
    if (testDecompileExternal("testcase/test3.mid")) {
        println("PASS ✓")
        totalPassed++
    } else {
        println("FAIL ✗")
        totalFailed++
    }

    println()
    println("═══════════════════════════════════════")
    if (totalFailed == 0) {
        println("  结果: ${totalPassed} 通过, 0 失败")
        println("═══════════════════════════════════════")
        println("\n🎉 全部测试通过！MIDI 文件保存在 tests/ 目录下。")
        return 0
    } else {
        println("  结果: ${totalPassed} 通过, ${totalFailed} 失败")
        println("═══════════════════════════════════════")
        return 1
    }
}
