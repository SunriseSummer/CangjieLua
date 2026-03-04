package cangjie_lua

import cangjie_lua.lexer.*
import cangjie_lua.parser.*
import cangjie_lua.codegen.*
import cangjie_lua.luavm.*
import std.collection.*
import std.fs.*

// ============================================================
// cangjiePrintln —— 注册到 Lua VM 的 println 函数
// 作为 CFunc 回调，从 Lua 栈获取参数并输出到标准输出。
// ============================================================
@C
func cangjiePrintln(L: CPointer<Unit>): Int32 {
    unsafe {
        let n = luaGetTop(L)
        if (n > 0) {
            let v = luaToNumber(L, 1)
            println(v)
        } else {
            println()
        }
        return 0  // 无返回值
    }
}

// ============================================================
// TestRunner —— 测试运行器
// 负责加载 .scj 测试文件，执行完整的编译管线：
//   源码 → Lexer → Parser → CodeGenerator → LuaVM 执行
// ============================================================
public class TestRunner {
    private var passed: Int64 = 0                          // 通过数
    private var _failed: Int64 = 0                         // 失败数
    private var errors: ArrayList<String> = ArrayList<String>()  // 失败详情

    public prop failed: Int64 {
        get() { _failed }
    }

    /// 编译并执行一段源码，返回是否通过
    public func runTest(source: String, testName: String): Bool {
        println("\n=== ${testName} ===")
        
        let state = LuaState()
        
        try {
            // 1. 词法分析
            let lexer = Lexer(source)
            let tokens = lexer.tokenize()
            println("  Tokens: ${tokens.size}")

            // 2. 语法分析
            let parser = Parser(tokens)
            let statements = parser.parse()
            println("  Statements: ${statements.size}")

            // 3. 字节码生成
            let codegen = CodeGenerator()
            let bytecode = codegen.generate(statements)
            println("  Bytecode: ${bytecode.size} bytes")

            // 4. 初始化 LuaVM 并注册 println 函数
            state.openLibs()
            state.pushCFunction(cangjiePrintln)
            state.setGlobal("println")

            // 5. 加载字节码
            let status = state.loadBytecode(bytecode, "main")
            if (status != LUA_OK) {
                println("  [ERROR] Load failed")
                _failed++
                errors.add("${testName}: load failed")
                return false
            }

            // 6. 执行字节码
            let runStatus = state.pCall(0, 0, 0)
            if (runStatus != LUA_OK) {
                println("  [ERROR] Run failed: ${state.toString(-1)}")
                _failed++
                errors.add("${testName}: run failed")
                return false
            }

            passed++
            println("  [PASS]")
            return true
        } catch (e: Exception) {
            println("  [ERROR] ${e.message}")
            _failed++
            errors.add("${testName}: ${e.message}")
            return false
        } finally {
            state.gc(LUA_GCCOLLECT)
            state.close()
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