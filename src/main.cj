package cangjie_lua

import std.fs.*

private func readSourceFile(path: String): ?String {
    try {
        let bytes = File.readFrom(Path(path))
        return String.fromUtf8(bytes)
    } catch (_: Exception) {
        return None
    }
}

private func emitBytecodeBytes(path: String): Int64 {
    let source = match (readSourceFile(path)) {
        case Some(v) => v
        case None =>
            println("Failed to read source file: ${path}")
            return 1
    }

    let engine = CangjieLua()
    let bytecode = match (engine.compileToBytecode(source)) {
        case Some(v) => v
        case None =>
            let message = if (let Some(err) <- engine.error) {
                err.toDisplayString()
            } else {
                "unknown compile error"
            }
            println(message)
            return 1
    }

    for (i in 0..bytecode.size) {
        if (i > 0) {
            print(" ")
        }
        print("${bytecode[i]}")
    }
    println()
    return 0
}

// 程序入口：支持指定单个测试文件、批量运行 tests/ 目录，或输出字节码
main(args: Array<String>): Int64 {
    if (args.size >= 2 && args[0] == "--emit-bytecode-bytes") {
        return emitBytecodeBytes(args[1])
    }

    let runner = TestRunner()
    if (args.size > 0) {
        runner.runTestFile(args[0])
    } else {
        runner.runAllTestFiles("./tests")
    }
    return runner.failed
}
