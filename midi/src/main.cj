package midi

import std.collection.*
import std.fs.*
import midi.encoder.*
import midi.decoder.*

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

func printUsage(): Unit {
    println("用法: midi [选项] [路径...]")
    println()
    println("选项:")
    println("  -d, --decompile    反编译 .mid 文件为文本乐谱")
    println("  -h, --help         显示帮助信息")
    println()
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

    if (paths.size == 0) {
        printUsage()
        return 0
    }

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
