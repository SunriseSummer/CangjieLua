package cangjie_lua

import cangjie_lua.errors.*
import cangjie_lua.lexer.*
import cangjie_lua.parser.*
import cangjie_lua.codegen.*
import cangjie_lua.luavm.*
import cangjie_lua.runtime.*

private func extractRuntimeValue(state: LuaState, idx: Int32): RuntimeValue {
    let tp = state.luaType(idx)
    if (tp == LUA_TBOOLEAN) {
        return RuntimeValue.BoolValue(state.toBoolean(idx))
    }
    if (tp == LUA_TNIL) {
        return RuntimeValue.NilValue
    }
    if (state.isInteger(idx)) {
        return RuntimeValue.IntValue(state.toInteger(idx))
    }
    if (tp == LUA_TNUMBER) {
        return RuntimeValue.FloatValue(state.toNumber(idx))
    }
    return RuntimeValue.TextValue(state.toString(idx))
}

// println 调用拦截器，记录 VM 中输出内容，便于测试校验
private func captureAndPrintTopValue(state: LuaState): Unit {
    let value = extractRuntimeValue(state, 1)
    PrintRuntime.appendOutputValue(value)
    let text = runtimeValueToDisplayString(value)
    println(text)
}

@C
func cangjiePrintln(L: CPointer<Unit>): Int32 {
    let state = LuaState(L)
    let n = state.getTop()
    if (n > 0) {
        captureAndPrintTopValue(state)
    } else {
        println()
    }
    return 0
}

public class CangjieLua {
    private var _error: ?CompileError = None

    public prop error: ?CompileError {
        get() { _error }
    }

    public func compileToBytecode(source: String): ?Array<UInt8> {
        let lexer = Lexer(source)
        let tokens = match (lexer.tokenize()) {
            case Some(v) => v
            case None =>
                _error = lexer.error
                return None
        }

        let parser = Parser(tokens)
        let statements = match (parser.parse()) {
            case Some(v) => v
            case None =>
                _error = parser.error
                return None
        }

        let codegen = CodeGenerator()
        let bytecode = codegen.generate(statements)
        return bytecode
    }

    private func executeBytecode(bytecode: Array<UInt8>): ?RuntimeValue {
        let state = LuaState()

        state.openLibs()
        state.pushCFunction(cangjiePrintln)
        state.setGlobal("println")

        let loadStatus = state.loadBytecode(bytecode, "main")
        if (loadStatus != LUA_OK) {
            _error = CompileError(ErrorStage.RUNTIME, "Load bytecode failed: ${state.toString(-1)}", 0)
            state.gc(LUA_GCCOLLECT)
            state.close()
            return None
        }

        let runStatus = state.pCall(0, 1, 0)
        if (runStatus != LUA_OK) {
            _error = CompileError(ErrorStage.RUNTIME, "Run bytecode failed: ${state.toString(-1)}", 0)
            state.gc(LUA_GCCOLLECT)
            state.close()
            return None
        }

        let returnValue = extractRuntimeValue(state, -1)
        state.pop(1)

        state.gc(LUA_GCCOLLECT)
        state.close()

        return returnValue
    }

    public func run(source: String): ?RuntimeValue {
        _error = None

        let bytecode = match (compileToBytecode(source)) {
            case Some(v) => v
            case None => return None
        }

        return executeBytecode(bytecode)
    }
}
