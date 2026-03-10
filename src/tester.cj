package cangjie_lua

import cangjie_lua.errors.*
import cangjie_lua.runtime.*
import std.collection.*
import std.convert.*
import std.fs.*

// TestRunner：测试执行与断言入口
// 负责读取 .scj 用例，调用 `CangjieLua.run()` 执行，并根据注释进行自动断言
//
// 支持的注释格式：
//   // Expected: 10.0, 20.0, 30.0
//   // ExpectedReturn: 42.0
//   // ExpectError[: message substring]
//
// 若没有期望注释，则仅要求“成功执行且无异常崩溃”
public class TestRunner {
    private static let EPSILON: Float64 = 0.001

    private var passed: Int64 = 0
    private var _failed: Int64 = 0
    private var errors: ArrayList<String> = ArrayList<String>()

    public prop failed: Int64 {
        get() { _failed }
    }

    private func sourceLines(source: String): Array<String> {
        return source.split("\n")
    }

    private func failTest(testName: String, msg: String): Bool {
        _failed++
        errors.add("${testName}: ${msg}")
        println("  [FAIL] ${msg}")
        return false
    }

    private func passTest(note: String): Bool {
        passed++
        if (note.isEmpty()) {
            println("  [PASS]")
        } else {
            println("  [PASS] ${note}")
        }
        return true
    }

    private func engineErrorText(engine: CangjieLua): String {
        return if (let Some(err) <- engine.error) {
            err.toDisplayString()
        } else {
            "unknown error"
        }
    }

    /// 解析 `// Expected:` 注释，返回预期输出列表
    /// 约定：只读取首个匹配行（避免多处声明导致歧义）
    private func parseExpectedOutputs(source: String): ?ArrayList<String> {
        let lines = sourceLines(source)
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.startsWith("// Expected:")) {
                let afterColon = trimmed.removePrefix("// Expected:").trimAscii()
                if (afterColon.isEmpty()) {
                    return None
                }
                let values = ArrayList<String>()
                // 支持逗号分隔和 "then" 分隔
                let normalized = afterColon.replace(" then ", ",")
                let parts = normalized.split(",", removeEmpty: true)
                for (p in parts) {
                    let t = p.trimAscii()
                    if (t.isEmpty()) { continue }
                    // 跳过非数值描述词
                    if (t == "nothing" || t.contains("loop") || t.contains("output") || t.contains("lots") || t.contains("ending")) {
                        return None  // 带描述性文字的 Expected 无法精确校验
                    }
                    values.add(t)
                }
                if (values.size > 0) {
                    return values
                }
                return None
            }
        }
        return None
    }

    /// 解析 `// ExpectedReturn:` 注释（支持 Int64/Float64/Bool）
    /// 约定：只读取首个匹配行
    private func parseExpectedReturn(source: String): ?String {
        let lines = sourceLines(source)
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.startsWith("// ExpectedReturn:")) {
                let afterColon = trimmed.removePrefix("// ExpectedReturn:").trimAscii()
                if (!afterColon.isEmpty()) {
                    return afterColon
                }
                return None
            }
        }
        return None
    }

    /// 解析 `// ExpectError` 注释，返回期望错误信息子串
    /// - `// ExpectError: xxx`：要求错误信息包含 `xxx`
    /// - `// ExpectError`：只要求“出现任意错误”
    /// 同样只读取首个匹配行
    private func parseExpectError(source: String): ?String {
        let lines = sourceLines(source)
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.startsWith("// ExpectError")) {
                let rest = trimmed.removePrefix("// ExpectError").trimAscii()
                if (rest.startsWith(":")) {
                    let msg = rest.removePrefix(":").trimAscii()
                    if (!msg.isEmpty()) {
                        return msg
                    }
                }
                // 无具体信息时返回空串，表示只要求有错误
                return ""
            }
        }
        return None
    }

    private func parseExpectedValue(raw: String): RuntimeValue {
        let t = raw.trimAscii()
        if (t == "true") { return RuntimeValue.BoolValue(true) }
        if (t == "false") { return RuntimeValue.BoolValue(false) }
        if (t == "nil") { return RuntimeValue.NilValue }

        try {
            if (t.contains(".")) {
                return RuntimeValue.FloatValue(Float64.parse(t))
            }
            return RuntimeValue.IntValue(Int64.parse(t))
        } catch (_: Exception) {
            return RuntimeValue.TextValue(t)
        }
    }

    private func runtimeValueEquals(actual: RuntimeValue, expected: RuntimeValue): Bool {
        match (actual) {
            case RuntimeValue.NilValue =>
                match (expected) {
                    case RuntimeValue.NilValue => return true
                    case _ => return false
                }
            case RuntimeValue.BoolValue(a) =>
                match (expected) {
                    case RuntimeValue.BoolValue(e) => return a == e
                    case _ => return false
                }
            case RuntimeValue.IntValue(a) =>
                match (expected) {
                    case RuntimeValue.IntValue(e) => return a == e
                    case RuntimeValue.FloatValue(e) =>
                        let diff = Float64(a) - e
                        let absDiff = if (diff < 0.0) { -diff } else { diff }
                        return absDiff <= EPSILON
                    case _ => return false
                }
            case RuntimeValue.FloatValue(a) =>
                match (expected) {
                    case RuntimeValue.FloatValue(e) =>
                        let diff = a - e
                        let absDiff = if (diff < 0.0) { -diff } else { diff }
                        return absDiff <= EPSILON
                    case RuntimeValue.IntValue(e) =>
                        let diff = a - Float64(e)
                        let absDiff = if (diff < 0.0) { -diff } else { diff }
                        return absDiff <= EPSILON
                    case _ => return false
                }
            case RuntimeValue.TextValue(a) =>
                match (expected) {
                    case RuntimeValue.TextValue(e) => return a == e
                    case _ => return false
                }
        }
    }

    private func verifyExpectedError(testName: String, result: ?RuntimeValue, expectedMsg: String, engine: CangjieLua): ?Bool {
        match (result) {
            case None =>
                let actualMsg = engineErrorText(engine)
                if (!expectedMsg.isEmpty() && !actualMsg.contains(expectedMsg)) {
                    return failTest(testName, "error message mismatch: expected to contain '${expectedMsg}', got '${actualMsg}'")
                }
                println("  Expected error: ${actualMsg}")
                return passTest("(expected error)")
            case Some(_) =>
                return failTest(testName, "Expected error but execution succeeded")
        }
    }

    private func verifyOutputs(testName: String, actual: ArrayList<RuntimeValue>, expected: ArrayList<String>): Bool {
        if (actual.size != expected.size) {
            return failTest(testName, "output count mismatch: expected ${expected.size}, got ${actual.size}")
        }
        for (i in 0..expected.size) {
            let expectedValue = parseExpectedValue(expected[i])
            if (!runtimeValueEquals(actual[i], expectedValue)) {
                return failTest(testName, "output[${i}] mismatch: expected '${runtimeValueToDisplayString(expectedValue)}', got '${runtimeValueToDisplayString(actual[i])}'")
            }
        }
        return true
    }

    private func verifyReturnValue(testName: String, actual: RuntimeValue, expectedRaw: String): Bool {
        let e = expectedRaw.trimAscii()
        if (e.isEmpty()) {
            return true
        }

        if (e == "true" || e == "false") {
            match (actual) {
                case RuntimeValue.BoolValue(v) =>
                    let expectedBool = (e == "true")
                    if (v != expectedBool) {
                        return failTest(testName, "return value mismatch: expected ${e}, got ${v}")
                    }
                    return true
                case RuntimeValue.NilValue =>
                    return failTest(testName, "return value mismatch: expected ${e}, got nil")
                case _ =>
                    return failTest(testName, "return value mismatch: expected ${e}, got non-bool")
            }
        }

        // 其余按数值语义比对，允许 7 与 7.0 等价
        try {
            let expectedNum = Float64.parse(e)
            let actualNum = match (actual) {
                case RuntimeValue.IntValue(v) => Float64(v)
                case RuntimeValue.FloatValue(v) => v
                case RuntimeValue.BoolValue(_) =>
                    return failTest(testName, "return value mismatch: expected ${e}, got bool")
                case RuntimeValue.NilValue =>
                    return failTest(testName, "return value mismatch: expected ${e}, got nil")
                case RuntimeValue.TextValue(v) =>
                    return failTest(testName, "return value mismatch: expected ${e}, got ${v}")
            }
            let diff = actualNum - expectedNum
            let absDiff = if (diff < 0.0) { -diff } else { diff }
            if (absDiff > EPSILON) {
                return failTest(testName, "return value mismatch: expected ${e}, got ${actualNum}")
            }
            return true
        } catch (_: Exception) {
            return failTest(testName, "invalid ExpectedReturn literal '${expectedRaw}'")
        }
    }

    /// 编译并执行一段源码，自动验证期望结果
    public func runTest(source: String, testName: String): Bool {
        println("\n=== ${testName} ===")

        let engine = CangjieLua()
        let expectedOutputs = parseExpectedOutputs(source)
        let expectedReturn = parseExpectedReturn(source)
        let expectError = parseExpectError(source)

        let actualOutputs = ArrayList<RuntimeValue>()
        PrintRuntime.beginCapture(actualOutputs)
        let result = engine.run(source)
        PrintRuntime.endCapture()

        // 断言顺序：ExpectError > 正常执行校验（输出 / 返回值）
        if (let Some(expectedMsg) <- expectError) {
            match (verifyExpectedError(testName, result, expectedMsg, engine)) {
                case Some(done) => return done
                case None => ()
            }
        }

        // 非预期错误
        match (result) {
            case None =>
                return failTest(testName, engineErrorText(engine))
            case _ => ()
        }

        let runtimeValue = result.getOrThrow()

        // 验证 println 输出
        if (let Some(expected) <- expectedOutputs) {
            if (!verifyOutputs(testName, actualOutputs, expected)) {
                return false
            }
        }

        // 验证 return 值
        if (let Some(expectedRet) <- expectedReturn) {
            if (!verifyReturnValue(testName, runtimeValue, expectedRet)) {
                return false
            }
        }

        if (let Some(_) <- expectedOutputs) {
            return passTest("(output verified)")
        } else if (let Some(_) <- expectedReturn) {
            return passTest("(return verified)")
        } else {
            return passTest("")
        }
    }

    // 从文件加载并执行测试
    private func runTestFile(path: Path): Bool {
        let fileName = path.fileName
        println("\n>>> Loading: ${fileName}")

        try {
            let bytes = File.readFrom(path)
            let source = String.fromUtf8(bytes)
            return runTest(source, fileName)
        } catch (e: Exception) {
            println("  [ERROR] Failed to read file: ${e.message}")
            _failed++
            errors.add("${fileName}: read error - ${e.message}")
            return false
        }
    }

    public func runTestFile(path: String): Bool {
        runTestFile(Path(path))
    }

    /// 扫描并执行指定目录下的所有 .scj 测试文件
    public func runAllTestFiles(path: String): Unit {
        let testDir = Path(path)
        println("========================================")
        println("Cangjie-Lua Interpreter Test Suite")
        println("========================================")
        println("Test directory: ${testDir}")

        try {
            let entries = Directory.readFrom(testDir)
            let testFiles = ArrayList<Path>()

            for (e in entries) {
                if (e.name.endsWith(".scj")) {
                    testFiles.add(testDir.join(e.name))
                }
            }

            println("Found ${testFiles.size} test files\n")

            for (f in testFiles) {
                runTestFile(f)
            }
        } catch (e: Exception) {
            println("[ERROR] Failed to read test directory: ${e.message}")
        }

        printSummary()
    }

    /// 打印测试汇总报告
    public func printSummary(): Unit {
        println("\n========================================")
        println("Test Summary")
        println("========================================")
        println("Passed: ${passed}")
        println("Failed: ${_failed}")
        println("Total:  ${passed + _failed}")

        if (errors.size > 0) {
            println("\nFailed tests:")
            for (e in errors) {
                println("  - ${e}")
            }
        }
        println("========================================")
    }
}