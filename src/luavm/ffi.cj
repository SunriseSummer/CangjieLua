package cangjie_lua.luavm

// ============================================================
// LuaVM C API —— FFI 外部函数声明
// 通过仓颉的 foreign 块声明 Lua 5.5 C API 函数，
// 运行时链接 luavm.dll 动态库。
// ============================================================
foreign {
    // === 状态管理 ===
    func luaL_newstate(): CPointer<Unit>                    // 创建新的 Lua 状态机
    func lua_close(L: CPointer<Unit>): Unit                 // 关闭并释放 Lua 状态机
    func luaL_openselectedlibs(L: CPointer<Unit>, load: Int32, preload: Int32): Unit  // 加载标准库

    // === 栈操作 ===
    func lua_gettop(L: CPointer<Unit>): Int32               // 获取栈顶索引
    func lua_settop(L: CPointer<Unit>, idx: Int32): Unit     // 设置栈顶（可用于 pop）
    func lua_pushvalue(L: CPointer<Unit>, idx: Int32): Unit  // 复制栈上元素到栈顶

    // === 压栈操作 ===
    func lua_pushinteger(L: CPointer<Unit>, n: Int64): Unit
    func lua_pushnumber(L: CPointer<Unit>, n: Float64): Unit
    func lua_pushstring(L: CPointer<Unit>, s: CString): Unit
    func lua_pushboolean(L: CPointer<Unit>, b: Int32): Unit
    func lua_pushnil(L: CPointer<Unit>): Unit
    func lua_pushcclosure(L: CPointer<Unit>, fn: CFunc<(CPointer<Unit>) -> Int32>, n: Int32): Unit

    // === 取值操作 ===
    func lua_tointegerx(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>): Int64
    func lua_tonumberx(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>): Float64
    func lua_toboolean(L: CPointer<Unit>, idx: Int32): Int32
    func lua_tolstring(L: CPointer<Unit>, idx: Int32, len: CPointer<UIntNative>): CString

    // === 类型查询 ===
    func lua_type(L: CPointer<Unit>, idx: Int32): Int32
    func lua_typename(L: CPointer<Unit>, tp: Int32): CString
    func lua_isnumber(L: CPointer<Unit>, idx: Int32): Int32
    func lua_isstring(L: CPointer<Unit>, idx: Int32): Int32
    func lua_isinteger(L: CPointer<Unit>, idx: Int32): Int32
    func lua_iscfunction(L: CPointer<Unit>, idx: Int32): Int32

    // === 表操作 ===
    func lua_createtable(L: CPointer<Unit>, narr: Int32, nrec: Int32): Unit
    func lua_getfield(L: CPointer<Unit>, idx: Int32, k: CString): Int32
    func lua_setfield(L: CPointer<Unit>, idx: Int32, k: CString): Unit
    func lua_getglobal(L: CPointer<Unit>, name: CString): Int32
    func lua_setglobal(L: CPointer<Unit>, name: CString): Unit

    // === 调用与执行 ===
    func lua_pcallk(L: CPointer<Unit>, nargs: Int32, nresults: Int32, errfunc: Int32, ctx: UIntNative, k: CPointer<Unit>): Int32

    // === 其他 ===
    func lua_gc(L: CPointer<Unit>, what: Int32, ...): Int32
    func lua_newthread(L: CPointer<Unit>): CPointer<Unit>
    func luaL_loadbufferx(L: CPointer<Unit>, buf: CPointer<UInt8>, sz: UIntNative, name: CString, mode: CString): Int32
}

// ============================================================
// Lua 状态码常量
// ============================================================
public let LUA_OK: Int32 = 0
public let LUA_YIELD: Int32 = 1
public let LUA_ERRRUN: Int32 = 2
public let LUA_ERRSYNTAX: Int32 = 3
public let LUA_ERRMEM: Int32 = 4
public let LUA_ERRERR: Int32 = 5

// ============================================================
// Lua 类型常量
// ============================================================
public let LUA_TNONE: Int32 = -1
public let LUA_TNIL: Int32 = 0
public let LUA_TBOOLEAN: Int32 = 1
public let LUA_TLIGHTUSERDATA: Int32 = 2
public let LUA_TNUMBER: Int32 = 3
public let LUA_TSTRING: Int32 = 4
public let LUA_TTABLE: Int32 = 5
public let LUA_TFUNCTION: Int32 = 6
public let LUA_TUSERDATA: Int32 = 7
public let LUA_TTHREAD: Int32 = 8

// 特殊常量
public let LUA_MULTRET: Int32 = -1  // 多返回值标记

// GC 操作常量
public let LUA_GCCOLLECT: Int32 = 2
public let LUA_GCSTOP: Int32 = 0
public let LUA_GCRESTART: Int32 = 1

// ============================================================
// 便捷包装函数
// ============================================================

/// 获取栈顶索引
public func luaGetTop(L: CPointer<Unit>): Int32 {
    unsafe {
        return lua_gettop(L)
    }
}

/// 获取栈上指定位置的数值
public func luaToNumber(L: CPointer<Unit>, idx: Int32): Float64 {
    unsafe {
        return lua_tonumberx(L, idx, CPointer<Int32>())
    }
}

/// 加载二进制字节码到 Lua 状态机（mode="b" 表示仅加载二进制格式）
public func luaVM_loadbytecode(L: CPointer<Unit>, buf: CPointer<UInt8>, sz: UIntNative, name: CString): Int32 {
    unsafe {
        let mode = LibC.mallocCString("b")
        let result = luaL_loadbufferx(L, buf, sz, name, mode)
        LibC.free(mode)
        return result
    }
}

// ============================================================
// LuaState —— Lua 状态机包装类
// 封装常用的 Lua C API 操作，管理 unsafe 块。
// ============================================================
public class LuaState {
    private let state: CPointer<Unit>  // Lua 状态机指针

    public init() {
        unsafe {
            state = luaL_newstate()
        }
    }

    public func close(): Unit {
        unsafe {
            lua_close(state)
        }
    }

    public func openLibs(): Unit {
        unsafe {
            luaL_openselectedlibs(state, 0x7FFFFFFF, 0)
        }
    }

    public func getTop(): Int32 {
        unsafe {
            return lua_gettop(state)
        }
    }

    public func pop(n: Int32): Unit {
        unsafe {
            lua_settop(state, -(n) - 1)
        }
    }

    public func pushInteger(n: Int64): Unit {
        unsafe {
            lua_pushinteger(state, n)
        }
    }

    public func pushNumber(n: Float64): Unit {
        unsafe {
            lua_pushnumber(state, n)
        }
    }

    public func pushString(s: String): Unit {
        unsafe {
            let cs = LibC.mallocCString(s)
            lua_pushstring(state, cs)
            LibC.free(cs)
        }
    }

    public func pushBoolean(b: Bool): Unit {
        unsafe {
            lua_pushboolean(state, if (b) { 1 } else { 0 })
        }
    }

    public func pushNil(): Unit {
        unsafe {
            lua_pushnil(state)
        }
    }

    public func pushCFunction(fn: CFunc<(CPointer<Unit>) -> Int32>): Unit {
        unsafe {
            lua_pushcclosure(state, fn, 0)
        }
    }

    public func toInteger(idx: Int32): Int64 {
        unsafe {
            return lua_tointegerx(state, idx, CPointer<Int32>())
        }
    }

    public func toNumber(idx: Int32): Float64 {
        unsafe {
            return lua_tonumberx(state, idx, CPointer<Int32>())
        }
    }

    public func toBoolean(idx: Int32): Bool {
        unsafe {
            return lua_toboolean(state, idx) != 0
        }
    }

    public func toString(idx: Int32): String {
        unsafe {
            let cs = lua_tolstring(state, idx, CPointer<UIntNative>())
            if (cs.isNull()) {
                return ""
            }
            return cs.toString()
        }
    }

    public func luaType(idx: Int32): Int32 {
        unsafe {
            return lua_type(state, idx)
        }
    }

    public func typeName(tp: Int32): String {
        unsafe {
            let cs = lua_typename(state, tp)
            return cs.toString()
        }
    }

    public func isNil(idx: Int32): Bool {
        unsafe {
            return lua_type(state, idx) == LUA_TNIL
        }
    }

    public func isNumber(idx: Int32): Bool {
        unsafe {
            return lua_isnumber(state, idx) != 0
        }
    }

    public func isString(idx: Int32): Bool {
        unsafe {
            return lua_isstring(state, idx) != 0
        }
    }

    public func isFunction(idx: Int32): Bool {
        unsafe {
            return lua_type(state, idx) == LUA_TFUNCTION
        }
    }

    public func newTable(): Unit {
        unsafe {
            lua_createtable(state, 0, 0)
        }
    }

    public func getGlobal(name: String): Int32 {
        unsafe {
            let cs = LibC.mallocCString(name)
            let result = lua_getglobal(state, cs)
            LibC.free(cs)
            return result
        }
    }

    public func setGlobal(name: String): Unit {
        unsafe {
            let cs = LibC.mallocCString(name)
            lua_setglobal(state, cs)
            LibC.free(cs)
        }
    }

    public func getField(idx: Int32, k: String): Int32 {
        unsafe {
            let cs = LibC.mallocCString(k)
            let result = lua_getfield(state, idx, cs)
            LibC.free(cs)
            return result
        }
    }

    public func setField(idx: Int32, k: String): Unit {
        unsafe {
            let cs = LibC.mallocCString(k)
            lua_setfield(state, idx, cs)
            LibC.free(cs)
        }
    }

    public func pCall(nargs: Int32, nresults: Int32, errfunc: Int32): Int32 {
        unsafe {
            return lua_pcallk(state, nargs, nresults, errfunc, 0, CPointer<Unit>())
        }
    }

    public func loadBytecode(bytecode: Array<UInt8>, name: String): Int32 {
        unsafe {
            let handle = acquireArrayRawData(bytecode)
            let cs = LibC.mallocCString(name)
            let result = luaVM_loadbytecode(state, handle.pointer, UIntNative(bytecode.size), cs)
            LibC.free(cs)
            releaseArrayRawData(handle)
            return result
        }
    }

    public func gc(what: Int32): Int32 {
        unsafe {
            return lua_gc(state, what)
        }
    }

    public func getRawState(): CPointer<Unit> {
        return state
    }
}
