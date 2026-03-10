# LuaVM 接口与字节码说明

> 本文件由 `scripts/competition_docs.py` 自动生成。若修改了 `src/luavm/ffi.cj`、`luavm/exports.txt`、`src/codegen/bytecode.cj` 或文档示例，请重新运行：`python3 scripts/competition_docs.py generate`。

本说明面向 AI 编程大赛参赛者，目标是帮助大家在扩展 CangjieLua 时，既能快速找到 LuaVM 入口，也能准确理解当前项目生成的 Lua 5.5 chunk 结构与指令模板。

## 1. 当前工程如何使用 LuaVM

当前执行链路是：**仓颉源码 → Lexer → Parser → CodeGenerator → Lua 5.5 二进制 chunk → FFI 加载执行**。

运行时最关键的几个动作如下：

1. `CodeGenerator.generate()` 产出 `Array<UInt8>` 形式的 chunk。
2. `LuaState.loadBytecode()` 通过 `luaL_loadbufferx(..., mode="b")` 仅加载二进制 chunk。
3. `LuaState.pCall()` 执行主函数，返回值从 Lua 栈顶转成 `RuntimeValue`。
4. 宿主函数 `println` 通过 `pushCFunction + setGlobal` 注入 `_ENV`。

## 2. `src/luavm/ffi.cj` 已集成接口

当前仓库已经直接绑定的 FFI 接口如下。

| 分类 | 接口 | 仓颉签名 |
|---|---|---|
| 状态管理 | `luaL_newstate` | `luaL_newstate(): CPointer<Unit>` |
| 状态管理 | `lua_close` | `lua_close(L: CPointer<Unit>): Unit` |
| 状态管理 | `luaL_openselectedlibs` | `luaL_openselectedlibs(L: CPointer<Unit>, load: Int32, preload: Int32): Unit` |
| 栈操作 | `lua_gettop` | `lua_gettop(L: CPointer<Unit>): Int32` |
| 栈操作 | `lua_settop` | `lua_settop(L: CPointer<Unit>, idx: Int32): Unit` |
| 栈操作 | `lua_pushvalue` | `lua_pushvalue(L: CPointer<Unit>, idx: Int32): Unit` |
| 压栈操作 | `lua_pushinteger` | `lua_pushinteger(L: CPointer<Unit>, n: Int64): Unit` |
| 压栈操作 | `lua_pushnumber` | `lua_pushnumber(L: CPointer<Unit>, n: Float64): Unit` |
| 压栈操作 | `lua_pushstring` | `lua_pushstring(L: CPointer<Unit>, s: CString): Unit` |
| 压栈操作 | `lua_pushboolean` | `lua_pushboolean(L: CPointer<Unit>, b: Int32): Unit` |
| 压栈操作 | `lua_pushnil` | `lua_pushnil(L: CPointer<Unit>): Unit` |
| 压栈操作 | `lua_pushcclosure` | `lua_pushcclosure(L: CPointer<Unit>, fn: CFunc<(CPointer<Unit>) -> Int32>, n: Int32): Unit` |
| 取值操作 | `lua_tointegerx` | `lua_tointegerx(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>): Int64` |
| 取值操作 | `lua_tonumberx` | `lua_tonumberx(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>): Float64` |
| 取值操作 | `lua_toboolean` | `lua_toboolean(L: CPointer<Unit>, idx: Int32): Int32` |
| 取值操作 | `lua_tolstring` | `lua_tolstring(L: CPointer<Unit>, idx: Int32, len: CPointer<UIntNative>): CString` |
| 类型查询 | `lua_type` | `lua_type(L: CPointer<Unit>, idx: Int32): Int32` |
| 类型查询 | `lua_typename` | `lua_typename(L: CPointer<Unit>, tp: Int32): CString` |
| 类型查询 | `lua_isnumber` | `lua_isnumber(L: CPointer<Unit>, idx: Int32): Int32` |
| 类型查询 | `lua_isstring` | `lua_isstring(L: CPointer<Unit>, idx: Int32): Int32` |
| 类型查询 | `lua_isinteger` | `lua_isinteger(L: CPointer<Unit>, idx: Int32): Int32` |
| 类型查询 | `lua_iscfunction` | `lua_iscfunction(L: CPointer<Unit>, idx: Int32): Int32` |
| 表操作 | `lua_createtable` | `lua_createtable(L: CPointer<Unit>, narr: Int32, nrec: Int32): Unit` |
| 表操作 | `lua_getfield` | `lua_getfield(L: CPointer<Unit>, idx: Int32, k: CString): Int32` |
| 表操作 | `lua_setfield` | `lua_setfield(L: CPointer<Unit>, idx: Int32, k: CString): Unit` |
| 表操作 | `lua_getglobal` | `lua_getglobal(L: CPointer<Unit>, name: CString): Int32` |
| 表操作 | `lua_setglobal` | `lua_setglobal(L: CPointer<Unit>, name: CString): Unit` |
| 调用与执行 | `lua_pcallk` | `lua_pcallk(L: CPointer<Unit>, nargs: Int32, nresults: Int32, errfunc: Int32, ctx: UIntNative, k: CPointer<Unit>): Int32` |
| 其他 | `lua_gc` | `lua_gc(L: CPointer<Unit>, what: Int32, ...): Int32` |
| 其他 | `lua_newthread` | `lua_newthread(L: CPointer<Unit>): CPointer<Unit>` |
| 其他 | `luaL_loadbufferx` | `luaL_loadbufferx(L: CPointer<Unit>, buf: CPointer<UInt8>, sz: UIntNative, name: CString, mode: CString): Int32` |

这些接口覆盖了 CangjieLua 当前必需的运行路径：状态机创建/销毁、栈读写、类型转换、全局环境访问、chunk 加载、受保护调用与 GC。

## 3. `luavm/` 动态库全部导出符号

`luavm/exports.txt` 中共导出 **156** 个符号。为了方便扩展开发，下表同时标明某个符号是否已经在 `ffi.cj` 中集成。

| 符号 | 分类 | 是否已集成 | 仓颉签名 / 说明 | 典型扩展用途 |
|---|---|---|---|---|
| luaL_addgsub | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_addlstring | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_addstring | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_addvalue | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_alloc | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_argerror | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_buffinit | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_buffinitsize | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_callmeta | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_checkany | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checkinteger | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checklstring | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checknumber | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checkoption | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checkstack | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checktype | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checkudata | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_checkversion_ | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_error | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_execresult | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_fileresult | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_getmetafield | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_getsubtable | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_gsub | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_len | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_loadbufferx | 辅助库（luaL_*） | 是 | `luaL_loadbufferx(L: CPointer<Unit>, buf: CPointer<UInt8>, sz: UIntNative, name: CString, mode: CString): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| luaL_loadfilex | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 与 chunk 加载/导出相关，扩展调试器、缓存或字节码工具时常用。 |
| luaL_loadstring | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 与 chunk 加载/导出相关，扩展调试器、缓存或字节码工具时常用。 |
| luaL_makeseed | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_newmetatable | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_newstate | 辅助库（luaL_*） | 是 | `luaL_newstate(): CPointer<Unit>` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| luaL_openselectedlibs | 辅助库（luaL_*） | 是 | `luaL_openselectedlibs(L: CPointer<Unit>, load: Int32, preload: Int32): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| luaL_optinteger | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_optlstring | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_optnumber | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 参数校验辅助，适合实现更复杂的内置函数。 |
| luaL_prepbuffsize | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_pushresult | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_pushresultsize | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_ref | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_requiref | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_setfuncs | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_setmetatable | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_testudata | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_tolstring | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_traceback | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_typeerror | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_unref | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| luaL_where | 辅助库（luaL_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_absindex | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_arith | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_atpanic | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_callk | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_checkstack | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_close | 核心 C API（lua_*） | 是 | `lua_close(L: CPointer<Unit>): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_closeslot | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_closethread | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 协程/线程相关接口，可用于未来的并发与生成器能力。 |
| lua_compare | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_concat | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_copy | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_createtable | 核心 C API（lua_*） | 是 | `lua_createtable(L: CPointer<Unit>, narr: Int32, nrec: Int32): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_dump | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 与 chunk 加载/导出相关，扩展调试器、缓存或字节码工具时常用。 |
| lua_error | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_gc | 核心 C API（lua_*） | 是 | `lua_gc(L: CPointer<Unit>, what: Int32, ...): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_getallocf | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_getfield | 核心 C API（lua_*） | 是 | `lua_getfield(L: CPointer<Unit>, idx: Int32, k: CString): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_getglobal | 核心 C API（lua_*） | 是 | `lua_getglobal(L: CPointer<Unit>, name: CString): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_gethook | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_gethookcount | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_gethookmask | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_geti | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_getinfo | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_getiuservalue | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_getlocal | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_getmetatable | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_getstack | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_gettable | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_gettop | 核心 C API（lua_*） | 是 | `lua_gettop(L: CPointer<Unit>): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_getupvalue | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_iscfunction | 核心 C API（lua_*） | 是 | `lua_iscfunction(L: CPointer<Unit>, idx: Int32): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_isinteger | 核心 C API（lua_*） | 是 | `lua_isinteger(L: CPointer<Unit>, idx: Int32): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_isnumber | 核心 C API（lua_*） | 是 | `lua_isnumber(L: CPointer<Unit>, idx: Int32): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_isstring | 核心 C API（lua_*） | 是 | `lua_isstring(L: CPointer<Unit>, idx: Int32): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_isuserdata | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_isyieldable | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 协程/线程相关接口，可用于未来的并发与生成器能力。 |
| lua_len | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_load | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 与 chunk 加载/导出相关，扩展调试器、缓存或字节码工具时常用。 |
| lua_newstate | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_newthread | 核心 C API（lua_*） | 是 | `lua_newthread(L: CPointer<Unit>): CPointer<Unit>` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_newuserdatauv | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_next | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_numbertocstring | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_pcallk | 核心 C API（lua_*） | 是 | `lua_pcallk(L: CPointer<Unit>, nargs: Int32, nresults: Int32, errfunc: Int32, ctx: UIntNative, k: CPointer<Unit>): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushboolean | 核心 C API（lua_*） | 是 | `lua_pushboolean(L: CPointer<Unit>, b: Int32): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushcclosure | 核心 C API（lua_*） | 是 | `lua_pushcclosure(L: CPointer<Unit>, fn: CFunc<(CPointer<Unit>) -> Int32>, n: Int32): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushexternalstring | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_pushfstring | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_pushinteger | 核心 C API（lua_*） | 是 | `lua_pushinteger(L: CPointer<Unit>, n: Int64): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushlightuserdata | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_pushlstring | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_pushnil | 核心 C API（lua_*） | 是 | `lua_pushnil(L: CPointer<Unit>): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushnumber | 核心 C API（lua_*） | 是 | `lua_pushnumber(L: CPointer<Unit>, n: Float64): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushstring | 核心 C API（lua_*） | 是 | `lua_pushstring(L: CPointer<Unit>, s: CString): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushthread | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_pushvalue | 核心 C API（lua_*） | 是 | `lua_pushvalue(L: CPointer<Unit>, idx: Int32): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_pushvfstring | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_rawequal | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_rawget | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_rawgeti | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_rawgetp | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_rawlen | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_rawset | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_rawseti | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_rawsetp | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_resume | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 协程/线程相关接口，可用于未来的并发与生成器能力。 |
| lua_rotate | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_setallocf | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_setfield | 核心 C API（lua_*） | 是 | `lua_setfield(L: CPointer<Unit>, idx: Int32, k: CString): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_setglobal | 核心 C API（lua_*） | 是 | `lua_setglobal(L: CPointer<Unit>, name: CString): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_sethook | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_seti | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_setiuservalue | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_setlocal | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_setmetatable | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_settable | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_settop | 核心 C API（lua_*） | 是 | `lua_settop(L: CPointer<Unit>, idx: Int32): Unit` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_setupvalue | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_setwarnf | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 表、栈帧、调试信息或全局环境访问接口。 |
| lua_status | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_stringtonumber | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_toboolean | 核心 C API（lua_*） | 是 | `lua_toboolean(L: CPointer<Unit>, idx: Int32): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_tocfunction | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_toclose | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_tointegerx | 核心 C API（lua_*） | 是 | `lua_tointegerx(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>): Int64` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_tolstring | 核心 C API（lua_*） | 是 | `lua_tolstring(L: CPointer<Unit>, idx: Int32, len: CPointer<UIntNative>): CString` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_tonumberx | 核心 C API（lua_*） | 是 | `lua_tonumberx(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>): Float64` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_topointer | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_tothread | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_touserdata | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 栈读写辅助接口，新增宿主函数或原生对象桥接时常用。 |
| lua_type | 核心 C API（lua_*） | 是 | `lua_type(L: CPointer<Unit>, idx: Int32): Int32` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_typename | 核心 C API（lua_*） | 是 | `lua_typename(L: CPointer<Unit>, tp: Int32): CString` | 已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。 |
| lua_upvalueid | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_upvaluejoin | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_version | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_warning | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_xmove | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。 |
| lua_yieldk | 核心 C API（lua_*） | 否 | 未绑定，见导出符号 | 协程/线程相关接口，可用于未来的并发与生成器能力。 |
| luaopen_base | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_coroutine | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_debug | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_io | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_math | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_os | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_package | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_string | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_table | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |
| luaopen_utf8 | 标准库入口（luaopen_*） | 否 | 未绑定，见导出符号 | 标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。 |

> 建议：如果比赛任务需要新增内置函数、数组/结构体桥接、调试器、协程或模块系统，优先从上表里找已经导出的 Lua C API，再决定是否补充新的 `foreign` 声明。

## 4. Lua 5.5 指令编码模型

`src/codegen/bytecode.cj` 中的编码常量与当前工程保持严格一致：

- `iABC  = [opcode:7][A:8][k:1][B:8][C:8]`
- `iABx  = [opcode:7][A:8][Bx:17]`
- `iAsBx = [opcode:7][A:8][sBx:17 signed]`
- `isJ   = [opcode:7][sJ:25 signed]`
- 位移常量：`A_SHIFT=7`、`K_SHIFT=15`、`B_SHIFT=16`、`C_SHIFT=24`、`BX_SHIFT=15`、`SJ_SHIFT=7`
- 偏移常量：`SBX_OFFSET=65535`、`SJ_OFFSET=16777215`

这些常量不只是文档描述；文档后面的所有指令字段示例，都是脚本调用项目自身编译器生成 chunk 后再解析出来的结果。

## 5. LuaVM 全部 85 条指令说明

| 编号 | 指令 | 编码 | 功能 | 用法 | 使用场景 |
|---:|---|---|---|---|---|
| 0 | `MOVE` | iABC | 寄存器复制 | 把寄存器 B 的值拷贝到寄存器 A。 | 局部变量读取、参数搬运、表达式结果转存。 |
| 1 | `LOADI` | iAsBx | 加载整数立即数 | 把 sBx 范围内的整数直接写入寄存器 A。 | 小整数常量、循环计数器、简单 return。 |
| 2 | `LOADF` | iAsBx | 加载浮点立即数 | 把可表示为整数形态的浮点值写入寄存器 A。 | 小范围 `3.0`、`-2.0` 这类浮点字面量。 |
| 3 | `LOADK` | iABx | 加载常量表项 | 从常量表索引 Bx 读取值到寄存器 A。 | 大整数、普通浮点、字符串常量。 |
| 4 | `LOADKX` | iABx | 扩展常量加载 | 与 `EXTRAARG` 配合，装载超出 `LOADK` 范围的常量索引。 | 常量表很大时的降级路径。 |
| 5 | `LOADFALSE` | iABC | 加载 `false` | 把布尔假写入寄存器 A。 | 比较结果默认值、显式布尔字面量。 |
| 6 | `LFALSESKIP` | iABC | 加载 `false` 并跳过下一条 | Lua VM 内部使用的分支辅助指令。 | 复杂逻辑布尔模板、官方编译器生成代码。 |
| 7 | `LOADTRUE` | iABC | 加载 `true` | 把布尔真写入寄存器 A。 | 比较成功路径、显式布尔字面量。 |
| 8 | `LOADNIL` | iABC | 加载 `nil` | 把 `nil` 写入寄存器 A（可覆盖一段寄存器）。 | 默认初始化、空返回、占位值。 |
| 9 | `GETUPVAL` | iABC | 读取 upvalue | 把上值表 B 中的值取到寄存器 A。 | 闭包捕获、共享 `_ENV`。 |
| 10 | `SETUPVAL` | iABC | 写入 upvalue | 把寄存器 A 的值写回上值 B。 | 闭包内修改外层变量、共享状态。 |
| 11 | `GETTABUP` | iABC | 读 upvalue 表字段 | 从 upvalue B 指向的表里读取常量/寄存器键 C 到 A。 | 读取 `_ENV.println`、全局变量访问。 |
| 12 | `GETTABLE` | iABC | 按键读表 | 使用寄存器键从寄存器表对象中读取元素。 | 动态下标、map/table 访问。 |
| 13 | `GETI` | iABC | 按整数索引读表 | 从寄存器表对象中按整数索引读取元素。 | 数组段访问、顺序容器读取。 |
| 14 | `GETFIELD` | iABC | 按字段名读表 | 以常量字符串字段名读取表字段。 | 对象字段、记录类型访问。 |
| 15 | `SETTABUP` | iABC | 写 upvalue 表字段 | 把寄存器值写入 upvalue 表的指定字段。 | 把函数/全局变量写回 `_ENV`。 |
| 16 | `SETTABLE` | iABC | 按键写表 | 使用寄存器键和值更新表对象。 | 动态字典赋值。 |
| 17 | `SETI` | iABC | 按整数索引写表 | 把寄存器值写到数组段索引位置。 | 数组初始化、列表元素更新。 |
| 18 | `SETFIELD` | iABC | 按字段名写表 | 用常量字段名更新表项。 | 对象字段赋值、记录构造。 |
| 19 | `NEWTABLE` | iABC | 创建新表 | 在寄存器 A 中分配一个新的 Lua table。 | 数组、对象、环境表构造。 |
| 20 | `SELF` | iABC | 方法调用准备 | 把对象和值方法同时装入连续寄存器，为 `obj:method()` 做准备。 | 面向对象语法糖。 |
| 21 | `ADDI` | iABC | 寄存器加立即数 | 寄存器 B 与立即数 C 相加，结果写入 A。 | 自增、自减、线性下标运算。 |
| 22 | `ADDK` | iABC | 寄存器加常量 | 寄存器值与常量表项相加。 | 常量参与的算术表达式。 |
| 23 | `SUBK` | iABC | 寄存器减常量 | 寄存器值减常量表项。 | 固定偏移量计算。 |
| 24 | `MULK` | iABC | 寄存器乘常量 | 寄存器值乘常量表项。 | 比例缩放、常量倍数。 |
| 25 | `MODK` | iABC | 寄存器模常量 | 寄存器值对常量表项取模。 | 周期判断、奇偶判断。 |
| 26 | `POWK` | iABC | 寄存器幂常量 | 寄存器值的常量次幂。 | 幂函数、快速模板生成。 |
| 27 | `DIVK` | iABC | 寄存器除常量 | 寄存器值除以常量表项。 | 固定系数归一化。 |
| 28 | `IDIVK` | iABC | 寄存器整除常量 | 寄存器值整除常量表项。 | 整数网格、块大小分组。 |
| 29 | `BANDK` | iABC | 按位与常量 | 寄存器值与常量按位与。 | 标志位过滤。 |
| 30 | `BORK` | iABC | 按位或常量 | 寄存器值与常量按位或。 | 标志位组合。 |
| 31 | `BXORK` | iABC | 按位异或常量 | 寄存器值与常量按位异或。 | 位翻转、简单编码。 |
| 32 | `SHLI` | iABC | 左移立即数 | 寄存器值左移固定 bit 数。 | 位图编码、乘以 2^n。 |
| 33 | `SHRI` | iABC | 右移立即数 | 寄存器值右移固定 bit 数。 | 位提取、除以 2^n。 |
| 34 | `ADD` | iABC | 寄存器加法 | 寄存器 B 与 C 相加，结果写入 A。 | 普通数值表达式 `a + b`。 |
| 35 | `SUB` | iABC | 寄存器减法 | 寄存器 B 减 C，结果写入 A。 | 差值、偏移计算。 |
| 36 | `MUL` | iABC | 寄存器乘法 | 寄存器 B 与 C 相乘。 | 面积、比例、累乘。 |
| 37 | `MOD` | iABC | 寄存器取模 | 寄存器 B 对 C 取模。 | 循环索引、奇偶判断。 |
| 38 | `POW` | iABC | 寄存器幂运算 | 寄存器 B 的 C 次幂。 | 数值计算、指数模板。 |
| 39 | `DIV` | iABC | 寄存器除法 | 寄存器 B 除以 C。 | 浮点除法、平均值。 |
| 40 | `IDIV` | iABC | 寄存器整除 | 寄存器 B 整除 C。 | 整数除法、分桶。 |
| 41 | `BAND` | iABC | 按位与 | 寄存器 B 与 C 按位与。 | 位掩码过滤。 |
| 42 | `BOR` | iABC | 按位或 | 寄存器 B 与 C 按位或。 | 位标志累加。 |
| 43 | `BXOR` | iABC | 按位异或 | 寄存器 B 与 C 按位异或。 | 校验位、位翻转。 |
| 44 | `SHL` | iABC | 左移 | 寄存器 B 左移 C 位。 | 高效乘法、位打包。 |
| 45 | `SHR` | iABC | 右移 | 寄存器 B 右移 C 位。 | 位拆包、范围压缩。 |
| 46 | `MMBIN` | iABC | 二元元方法回退 | 在普通二元算术失败时回退到元方法。 | table/userdata 自定义算术。 |
| 47 | `MMBINI` | iABC | 立即数元方法回退 | 当一侧是立即数时执行元方法回退。 | 常量参与的自定义运算。 |
| 48 | `MMBINK` | iABC | 常量元方法回退 | 当一侧来自常量表时执行元方法回退。 | 常量表达式与对象混算。 |
| 49 | `UNM` | iABC | 一元负号 | 对寄存器 B 执行数值取负，结果写入 A。 | `-x`、数值翻转。 |
| 50 | `BNOT` | iABC | 按位非 | 对寄存器 B 执行按位取反。 | 掩码反转。 |
| 51 | `NOT` | iABC | 逻辑非 | 按 Lua 真值语义对寄存器 B 取反。 | 布尔取反、条件规约。 |
| 52 | `LEN` | iABC | 求长度 | 读取字符串或 table 的长度到寄存器 A。 | 字符串长度、数组长度。 |
| 53 | `CONCAT` | iABC | 字符串拼接 | 把一段连续寄存器内的值拼成字符串。 | 字符串连接、格式化拼装。 |
| 54 | `CLOSE` | iABC | 关闭 upvalue | 关闭从寄存器 A 开始的待关闭上值。 | 离开作用域时释放闭包引用。 |
| 55 | `TBC` | iABC | 标记待关闭变量 | 把寄存器 A 标记为 to-be-closed 资源。 | 资源管理、RAII 风格清理。 |
| 56 | `JMP` | isJ | 无条件跳转 | 按 sJ 相对偏移调整 PC。 | 跳过分支、回到循环头、短路控制。 |
| 57 | `EQ` | iABC(k) | 寄存器相等比较 | 比较两个寄存器是否相等，并结合 k 决定是否跳过下一条。 | `==`、`!=` 模板。 |
| 58 | `LT` | iABC(k) | 寄存器小于比较 | 比较寄存器 B 是否小于 C。 | `<`、`>` 模板。 |
| 59 | `LE` | iABC(k) | 寄存器小于等于比较 | 比较寄存器 B 是否小于等于 C。 | `<=`、`>=` 模板。 |
| 60 | `EQK` | iABC(k) | 寄存器与常量比较 | 把寄存器 A 与常量 Bx 比较。 | 常量分支、模式匹配。 |
| 61 | `EQI` | iABC(k) | 寄存器与立即数比较 | 把寄存器 A 与有符号立即数比较。 | 小整数快速判断。 |
| 62 | `LTI` | iABC(k) | 小于立即数 | 把寄存器 A 与立即数做 `<` 判断。 | 范围检查、循环上界。 |
| 63 | `LEI` | iABC(k) | 小于等于立即数 | 把寄存器 A 与立即数做 `<=` 判断。 | 边界判断。 |
| 64 | `GTI` | iABC(k) | 大于立即数 | 把寄存器 A 与立即数做 `>` 判断。 | 反向区间判断。 |
| 65 | `GEI` | iABC(k) | 大于等于立即数 | 把寄存器 A 与立即数做 `>=` 判断。 | 下界判断。 |
| 66 | `TEST` | iABC | 真值测试 | 检查寄存器 A 的布尔语义并决定是否跳过下一条。 | `if`、`while`、短路求值。 |
| 67 | `TESTSET` | iABC | 测试并赋值 | 在条件满足时把寄存器 B 赋给 A，否则跳过。 | 逻辑运算、条件绑定。 |
| 68 | `CALL` | iABC | 普通函数调用 | 从寄存器 A 开始组织函数与参数，按 B/C 约定调用并接收返回。 | 函数调用、内置函数调用。 |
| 69 | `TAILCALL` | iABC | 尾调用 | 以尾调用方式调用函数，避免额外栈帧。 | 尾递归优化、转发调用。 |
| 70 | `RETURN` | iABC | 通用返回 | 从寄存器 A 开始返回 B-1 个值，C 控制延展语义。 | 普通函数 return、多返回值。 |
| 71 | `RETURN0` | iABC | 零返回快速路径 | 直接返回零个值。 | 函数末尾隐式返回。 |
| 72 | `RETURN1` | iABC | 单返回快速路径 | 直接返回一个值。 | 简单函数/表达式函数优化。 |
| 73 | `FORLOOP` | iAsBx | 数值 for 回环 | 更新内部索引并判断是否继续循环。 | 计数型 `for`。 |
| 74 | `FORPREP` | iAsBx | 数值 for 预处理 | 初始化计数器、步长和边界后跳入循环。 | 数值 `for` 的入口。 |
| 75 | `TFORPREP` | iABC | 泛型 for 预处理 | 为迭代器协议建立循环初始布局。 | `for-in` / 迭代器循环。 |
| 76 | `TFORCALL` | iABC | 泛型 for 调用 | 调用迭代器函数产出下一组值。 | Lua 风格泛型迭代。 |
| 77 | `TFORLOOP` | iABC | 泛型 for 回环 | 根据迭代器返回值判断是否继续循环。 | 集合遍历。 |
| 78 | `SETLIST` | iABC | 批量写数组段 | 把一段连续寄存器批量写入 table 数组部分。 | 数组字面量、大批量初始化。 |
| 79 | `CLOSURE` | iABx | 创建闭包 | 从子函数原型 Bx 构造闭包并写入寄存器 A。 | 函数声明、嵌套函数。 |
| 80 | `VARARG` | iABC | 读取可变参数 | 把当前函数的 vararg 装入目标寄存器段。 | 可变参数函数。 |
| 81 | `GETVARG` | iABC | 访问 vararg 区域 | 从 vararg 保存区读取参数。 | 高级 vararg 优化。 |
| 82 | `ERRNNIL` | iABC | nil 保护报错 | 对不允许为 nil 的访问生成专门错误。 | 严格索引、空值诊断。 |
| 83 | `VARARGPREP` | iABx | vararg 入口准备 | 在函数入口整理可变参数布局。 | main 函数、`func f(... )`。 |
| 84 | `EXTRAARG` | iABC | 扩展参数字 | 为前一条指令补充额外宽度的操作数。 | 大常量索引、大表大小参数。 |

## 6. 典型代码对应的 chunk 字段解析

下列示例全部由 `scripts/competition_docs.py` 调用项目当前构建出的可执行文件，实际生成字节码后解析得到；因此它们既是文档，也是回归测试样例。

### 常量返回：`return 42`

覆盖 main 原型、`VARARGPREP + LOADI + RETURN + RETURN0` 的最小路径。

```cangjie
return 42
```

Header 摘要：

- `signature` = `1b 4c 75 61`
- `version` = `0x55`，对应 Lua 5.5
- `format` = `0x00`
- `luac_data` = `19 93 0d 0a 1a 0a`
- 类型校验 = `int(4) / instruction(4) / integer(8) / number(8)`
- `main_upvalue_count` = `1`（当前工程固定为 `_ENV`）

Main Prototype 字段：

- `linedefined` / `lastlinedefined` = `0 / 0`
- `numparams` = `0`
- `is_vararg` = `1`
- `maxstacksize` = `2`
- `instruction_count` = `4`
- `constant_count` = `0`
- `upvalue_count` = `1`
- `subproto_count` = `0`

指令序列：

| PC | 指令 | 字段 | 说明 |
|---:|---|---|---|
| 0 | `VARARGPREP` | `A=0, Bx=0` | vararg 入口准备 |
| 1 | `LOADI` | `A=0, sBx=42` | 加载整数立即数 |
| 2 | `RETURN` | `A=0, B=2, C=1` | 通用返回 |
| 3 | `RETURN0` | `A=0, B=0, C=0` | 零返回快速路径 |

常量表为空：该示例中的值都落在立即数或布尔快速路径内。

Upvalue 描述：

| 索引 | instack | idx | kind | 说明 |
|---:|---:|---:|---:|---|
| 0 | 1 | 0 | 0 | main 函数固定绑定 `_ENV` |

### 条件分支：`if / else`

覆盖 `TEST`、前向 `JMP`、分支块收尾跳转以及 `println` 调用模板。

```cangjie
if (true) {
    println(1)
} else {
    println(2)
}
return 0
```

Header 摘要：

- `signature` = `1b 4c 75 61`
- `version` = `0x55`，对应 Lua 5.5
- `format` = `0x00`
- `luac_data` = `19 93 0d 0a 1a 0a`
- 类型校验 = `int(4) / instruction(4) / integer(8) / number(8)`
- `main_upvalue_count` = `1`（当前工程固定为 `_ENV`）

Main Prototype 字段：

- `linedefined` / `lastlinedefined` = `0 / 0`
- `numparams` = `0`
- `is_vararg` = `1`
- `maxstacksize` = `4`
- `instruction_count` = `14`
- `constant_count` = `1`
- `upvalue_count` = `1`
- `subproto_count` = `0`

指令序列：

| PC | 指令 | 字段 | 说明 |
|---:|---|---|---|
| 0 | `VARARGPREP` | `A=0, Bx=0` | vararg 入口准备 |
| 1 | `LOADTRUE` | `A=0, B=0, C=0` | 加载 `true` |
| 2 | `TEST` | `A=0, B=0, C=0` | 真值测试 |
| 3 | `JMP` | `sJ=4` | 无条件跳转 |
| 4 | `GETTABUP` | `A=0, B=0, C=0` | 读 upvalue 表字段 |
| 5 | `LOADI` | `A=1, sBx=1` | 加载整数立即数 |
| 6 | `CALL` | `A=0, B=2, C=1` | 普通函数调用 |
| 7 | `JMP` | `sJ=3` | 无条件跳转 |
| 8 | `GETTABUP` | `A=0, B=0, C=0` | 读 upvalue 表字段 |
| 9 | `LOADI` | `A=1, sBx=2` | 加载整数立即数 |
| 10 | `CALL` | `A=0, B=2, C=1` | 普通函数调用 |
| 11 | `LOADI` | `A=0, sBx=0` | 加载整数立即数 |
| 12 | `RETURN` | `A=0, B=2, C=1` | 通用返回 |
| 13 | `RETURN0` | `A=0, B=0, C=0` | 零返回快速路径 |

常量表：

| 索引 | 类型 | 值 |
|---:|---|---|
| 0 | String | `println` |

Upvalue 描述：

| 索引 | instack | idx | kind | 说明 |
|---:|---:|---:|---:|---|
| 0 | 1 | 0 | 0 | main 函数固定绑定 `_ENV` |

### 循环：`while` + 变量更新

覆盖循环入口比较、回跳、局部变量复用与加法指令模板。

```cangjie
var i = 0
while (i < 3) {
    println(i)
    i = i + 1
}
return i
```

Header 摘要：

- `signature` = `1b 4c 75 61`
- `version` = `0x55`，对应 Lua 5.5
- `format` = `0x00`
- `luac_data` = `19 93 0d 0a 1a 0a`
- 类型校验 = `int(4) / instruction(4) / integer(8) / number(8)`
- `main_upvalue_count` = `1`（当前工程固定为 `_ENV`）

Main Prototype 字段：

- `linedefined` / `lastlinedefined` = `0 / 0`
- `numparams` = `0`
- `is_vararg` = `1`
- `maxstacksize` = `6`
- `instruction_count` = `21`
- `constant_count` = `1`
- `upvalue_count` = `1`
- `subproto_count` = `0`

指令序列：

| PC | 指令 | 字段 | 说明 |
|---:|---|---|---|
| 0 | `VARARGPREP` | `A=0, Bx=0` | vararg 入口准备 |
| 1 | `LOADI` | `A=0, sBx=0` | 加载整数立即数 |
| 2 | `MOVE` | `A=2, B=0, C=0` | 寄存器复制 |
| 3 | `LOADI` | `A=3, sBx=3` | 加载整数立即数 |
| 4 | `LOADFALSE` | `A=1, B=0, C=0` | 加载 `false` |
| 5 | `LT` | `A=2, B=3, C=0, k=0` | 寄存器小于比较 |
| 6 | `JMP` | `sJ=1` | 无条件跳转 |
| 7 | `LOADTRUE` | `A=1, B=0, C=0` | 加载 `true` |
| 8 | `TEST` | `A=1, B=0, C=0` | 真值测试 |
| 9 | `JMP` | `sJ=8` | 无条件跳转 |
| 10 | `GETTABUP` | `A=1, B=0, C=0` | 读 upvalue 表字段 |
| 11 | `MOVE` | `A=2, B=0, C=0` | 寄存器复制 |
| 12 | `CALL` | `A=1, B=2, C=1` | 普通函数调用 |
| 13 | `MOVE` | `A=0, B=0, C=0` | 寄存器复制 |
| 14 | `LOADI` | `A=1, sBx=1` | 加载整数立即数 |
| 15 | `ADD` | `A=0, B=0, C=1` | 寄存器加法 |
| 16 | `MMBIN` | `A=0, B=1, C=6` | 二元元方法回退 |
| 17 | `JMP` | `sJ=-16` | 无条件跳转 |
| 18 | `MOVE` | `A=1, B=0, C=0` | 寄存器复制 |
| 19 | `RETURN` | `A=1, B=2, C=1` | 通用返回 |
| 20 | `RETURN0` | `A=0, B=0, C=0` | 零返回快速路径 |

常量表：

| 索引 | 类型 | 值 |
|---:|---|---|
| 0 | String | `println` |

Upvalue 描述：

| 索引 | instack | idx | kind | 说明 |
|---:|---:|---:|---:|---|
| 0 | 1 | 0 | 0 | main 函数固定绑定 `_ENV` |

### 函数声明与调用

覆盖 `CLOSURE`、子函数原型、`SETTABUP` 注册全局函数与 `CALL`。

```cangjie
func add(a: Int64, b: Int64): Int64 {
    return a + b
}
println(add(2, 3))
return 0
```

Header 摘要：

- `signature` = `1b 4c 75 61`
- `version` = `0x55`，对应 Lua 5.5
- `format` = `0x00`
- `luac_data` = `19 93 0d 0a 1a 0a`
- 类型校验 = `int(4) / instruction(4) / integer(8) / number(8)`
- `main_upvalue_count` = `1`（当前工程固定为 `_ENV`）

Main Prototype 字段：

- `linedefined` / `lastlinedefined` = `0 / 0`
- `numparams` = `0`
- `is_vararg` = `1`
- `maxstacksize` = `7`
- `instruction_count` = `12`
- `constant_count` = `2`
- `upvalue_count` = `1`
- `subproto_count` = `1`

指令序列：

| PC | 指令 | 字段 | 说明 |
|---:|---|---|---|
| 0 | `VARARGPREP` | `A=0, Bx=0` | vararg 入口准备 |
| 1 | `CLOSURE` | `A=0, Bx=0` | 创建闭包 |
| 2 | `SETTABUP` | `A=0, B=0, C=0` | 写 upvalue 表字段 |
| 3 | `GETTABUP` | `A=1, B=0, C=1` | 读 upvalue 表字段 |
| 4 | `GETTABUP` | `A=2, B=0, C=0` | 读 upvalue 表字段 |
| 5 | `LOADI` | `A=3, sBx=2` | 加载整数立即数 |
| 6 | `LOADI` | `A=4, sBx=3` | 加载整数立即数 |
| 7 | `CALL` | `A=2, B=3, C=2` | 普通函数调用 |
| 8 | `CALL` | `A=1, B=2, C=1` | 普通函数调用 |
| 9 | `LOADI` | `A=1, sBx=0` | 加载整数立即数 |
| 10 | `RETURN` | `A=1, B=2, C=1` | 通用返回 |
| 11 | `RETURN0` | `A=0, B=0, C=0` | 零返回快速路径 |

常量表：

| 索引 | 类型 | 值 |
|---:|---|---|
| 0 | String | `add` |
| 1 | String | `println` |

Upvalue 描述：

| 索引 | instack | idx | kind | 说明 |
|---:|---:|---:|---:|---|
| 0 | 1 | 0 | 0 | main 函数固定绑定 `_ENV` |

子函数原型 #0：

- `numparams=2`，`is_vararg=0`，`maxstacksize=6`
- 指令数 = `6`，常量数 = `0`
- 该原型由 `CLOSURE` 指令在主函数里实例化。

| PC | 指令 | 字段 | 说明 |
|---:|---|---|---|
| 0 | `MOVE` | `A=2, B=0, C=0` | 寄存器复制 |
| 1 | `MOVE` | `A=3, B=1, C=0` | 寄存器复制 |
| 2 | `ADD` | `A=2, B=2, C=3` | 寄存器加法 |
| 3 | `MMBIN` | `A=2, B=3, C=6` | 二元元方法回退 |
| 4 | `RETURN` | `A=2, B=2, C=0` | 通用返回 |
| 5 | `RETURN0` | `A=0, B=0, C=0` | 零返回快速路径 |


## 7. 如何把这些信息用于扩展开发

1. **先确定目标语义需要哪一类 Lua 指令**：例如数组通常围绕 `NEWTABLE / GETI / SETI / SETLIST`，闭包捕获则需要真实 `GETUPVAL / SETUPVAL`。
2. **再确认当前仓库是否已暴露所需 FFI**：若需要更细粒度控制栈、调试信息或协程，可以从导出符号表中选择新增绑定。
3. **最后补样例并刷新文档**：把最小可运行代码加入脚本数据，重新生成文档并执行校验，这样字节码说明就会自动保持最新。

## 8. 文档校验命令

在已经 `source <sdk>/envsetup.sh` 且完成 `cjpm build` 后，执行：

```bash
python3 scripts/competition_docs.py check
```

该命令会同时校验：

- FFI 接口与导出符号表是否完整反映到文档
- 85 条 opcode 说明是否与源码枚举一致
- 文档示例能否通过当前解释器执行
- 字节码块解析是否能从当前构建产物稳定生成

