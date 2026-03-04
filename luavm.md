# LuaVM 接口文档

本文档描述 `libluavm` 库（基于 Lua 5.5）导出的 C API 接口，以及仓颉侧封装类 `LuaState` 的用法。

## 引擎概述

`libluavm` 是一个**仅执行字节码**的 Lua 虚拟机库，不包含 Lua 源码解析器/编译器。它提供完整的 Lua C API 用于状态管理、栈操作、表访问、函数调用、GC 控制和标准库，但**不能直接加载 Lua 源码文本**（仅接受预编译的二进制字节码）。

## 基本使用流程

### 仓颉侧使用（通过 LuaState 封装类）

```cangjie
// 1. 创建 Lua 状态机
let state = LuaState()

// 2. 加载标准库
state.openLibs()

// 3. 注册自定义函数（如 println）
state.pushCFunction(cangjiePrintln)
state.setGlobal("println")

// 4. 加载预编译字节码
let status = state.loadBytecode(bytecodeArray, "main")
if (status != LUA_OK) {
    // 加载失败处理
}

// 5. 执行字节码
let runStatus = state.pCall(0, 0, 0)
if (runStatus != LUA_OK) {
    let errMsg = state.toString(-1)
    // 运行失败处理
}

// 6. GC 与关闭
state.gc(LUA_GCCOLLECT)
state.close()
```

### C 侧典型用法

```c
lua_State *L = luaL_newstate();
luaL_openlibs(L);
luaL_loadbufferx(L, bytecode, size, "chunk", "b");
lua_pcall(L, 0, LUA_MULTRET, 0);
lua_close(L);
```

## 仓颉 FFI 声明的接口列表

以下是 `src/luavm/ffi.cj` 中通过 `foreign` 块声明、在仓颉侧可调用的 C API 函数：

### 状态管理

- `luaL_newstate()` — 创建一个新的 Lua 状态机，分配并初始化所有内部结构。返回 `CPointer<Unit>` 状态机指针
- `lua_close(L)` — 关闭并释放 Lua 状态机，回收所有相关内存。参数 `L: CPointer<Unit>` 状态机指针
- `luaL_openselectedlibs(L, load, preload)` — 按位掩码选择性加载 Lua 标准库。参数 `L: CPointer<Unit>` 状态机指针，`load: Int32` 加载位掩码，`preload: Int32` 预加载位掩码。传入 `0x7FFFFFFF` 则加载所有库

### 栈操作

- `lua_gettop(L)` — 返回栈顶元素的索引（即栈中元素个数）。参数 `L: CPointer<Unit>`。返回 `Int32`
- `lua_settop(L, idx)` — 设置栈顶索引。参数 `L: CPointer<Unit>`，`idx: Int32` 目标索引。若 idx < 当前栈顶则弹出多余元素；可用 `lua_settop(L, -(n)-1)` 实现 pop(n)
- `lua_pushvalue(L, idx)` — 将栈上指定位置的值复制并压入栈顶。参数 `L: CPointer<Unit>`，`idx: Int32` 源索引

### 压栈操作

- `lua_pushinteger(L, n)` — 将一个整数值压入栈顶。参数 `L: CPointer<Unit>`，`n: Int64` 整数值
- `lua_pushnumber(L, n)` — 将一个浮点数值压入栈顶。参数 `L: CPointer<Unit>`，`n: Float64` 浮点数值
- `lua_pushstring(L, s)` — 将一个字符串压入栈顶。参数 `L: CPointer<Unit>`，`s: CString` C 字符串
- `lua_pushboolean(L, b)` — 将一个布尔值压入栈顶（0 为 false，非 0 为 true）。参数 `L: CPointer<Unit>`，`b: Int32` 布尔值
- `lua_pushnil(L)` — 将 nil 值压入栈顶。参数 `L: CPointer<Unit>`
- `lua_pushcclosure(L, fn, n)` — 创建一个 C 闭包并压入栈顶，n=0 时等同于 pushcfunction。参数 `L: CPointer<Unit>`，`fn: CFunc<(CPointer<Unit>) -> Int32>` C 函数指针，`n: Int32` 上值个数

### 取值操作

- `lua_tointegerx(L, idx, isnum)` — 将栈上指定位置的值转换为整数并返回。参数 `L: CPointer<Unit>`，`idx: Int32` 栈索引，`isnum: CPointer<Int32>` 可选输出(是否为数字)。返回 `Int64`
- `lua_tonumberx(L, idx, isnum)` — 将栈上指定位置的值转换为浮点数并返回。参数 `L: CPointer<Unit>`，`idx: Int32` 栈索引，`isnum: CPointer<Int32>` 可选输出。返回 `Float64`
- `lua_toboolean(L, idx)` — 将栈上指定位置的值转换为布尔值（0 或 1）。参数 `L: CPointer<Unit>`，`idx: Int32` 栈索引。返回 `Int32`
- `lua_tolstring(L, idx, len)` — 将栈上指定位置的值转换为字符串并返回指针。参数 `L: CPointer<Unit>`，`idx: Int32` 栈索引，`len: CPointer<UIntNative>` 可选输出(字符串长度)。返回 `CString`

### 类型查询

- `lua_type(L, idx)` — 返回栈上指定位置值的类型编号（LUA_TNIL, LUA_TNUMBER 等）。参数 `L: CPointer<Unit>`，`idx: Int32` 栈索引。返回 `Int32`
- `lua_typename(L, tp)` — 返回类型编号对应的类型名字符串（如 "nil", "number"）。参数 `L: CPointer<Unit>`，`tp: Int32` 类型编号。返回 `CString`
- `lua_isnumber(L, idx)` — 判断栈上指定位置的值是否为数字（或可转换为数字），1=是 0=否。参数 `L: CPointer<Unit>`，`idx: Int32`。返回 `Int32`
- `lua_isstring(L, idx)` — 判断栈上指定位置的值是否为字符串（或可转换为字符串），1=是 0=否。参数 `L: CPointer<Unit>`，`idx: Int32`。返回 `Int32`
- `lua_isinteger(L, idx)` — 判断栈上指定位置的值是否为整数，1=是 0=否。参数 `L: CPointer<Unit>`，`idx: Int32`。返回 `Int32`
- `lua_iscfunction(L, idx)` — 判断栈上指定位置的值是否为 C 函数，1=是 0=否。参数 `L: CPointer<Unit>`，`idx: Int32`。返回 `Int32`

### 表操作

- `lua_createtable(L, narr, nrec)` — 创建新表并压入栈顶。参数 `L: CPointer<Unit>`，`narr: Int32` 数组部分预分配大小，`nrec: Int32` 哈希部分预分配大小
- `lua_getfield(L, idx, k)` — 将 `t[k]` 的值压入栈顶（t 是索引 idx 处的表）。参数 `L: CPointer<Unit>`，`idx: Int32` 表的栈索引，`k: CString` 字段名。返回 `Int32` 值的类型
- `lua_setfield(L, idx, k)` — 将栈顶值赋给 `t[k]`（t 是索引 idx 处的表），并弹出栈顶值。参数 `L: CPointer<Unit>`，`idx: Int32` 表的栈索引，`k: CString` 字段名
- `lua_getglobal(L, name)` — 将全局变量 `name` 的值压入栈顶。参数 `L: CPointer<Unit>`，`name: CString` 全局变量名。返回 `Int32` 值的类型
- `lua_setglobal(L, name)` — 将栈顶值设为全局变量 `name` 的值，并弹出栈顶值。参数 `L: CPointer<Unit>`，`name: CString` 全局变量名

### 调用与执行

- `lua_pcallk(L, nargs, nresults, errfunc, ctx, k)` — 以保护模式调用栈上的函数，返回 LUA_OK(0) 表示成功。参数 `L: CPointer<Unit>`，`nargs: Int32` 参数个数，`nresults: Int32` 期望返回值个数，`errfunc: Int32` 错误处理函数栈索引(0=无)，`ctx: UIntNative` 延续上下文，`k: CPointer<Unit>` 延续函数(NULL=无)。返回 `Int32` 状态码
- `luaL_loadbufferx(L, buf, sz, name, mode)` — 从内存缓冲区加载字节码，本 VM 仅支持 mode="b"。参数 `L: CPointer<Unit>`，`buf: CPointer<UInt8>` 字节码缓冲区，`sz: UIntNative` 缓冲区大小，`name: CString` 块名称，`mode: CString` 加载模式("b"=二进制)。返回 `Int32` 状态码

### 其他

- `lua_gc(L, what, ...)` — 控制垃圾回收器，what=LUA_GCCOLLECT(2) 执行完整 GC。参数 `L: CPointer<Unit>`，`what: Int32` GC 操作类型。返回 `Int32`
- `lua_newthread(L)` — 创建新的 Lua 协程线程并压入栈顶。参数 `L: CPointer<Unit>`。返回 `CPointer<Unit>` 新线程指针

## 便捷包装函数

`ffi.cj` 中还提供了以下便捷函数：

- `luaGetTop(L)` — 获取栈顶索引（封装 `lua_gettop`）
- `luaToNumber(L, idx)` — 获取栈上指定位置的浮点数值（封装 `lua_tonumberx`，忽略 isnum 输出）
- `luaVM_loadbytecode(L, buf, sz, name)` — 加载二进制字节码（封装 `luaL_loadbufferx`，mode 固定为 "b"）

## LuaState 封装类

`LuaState` 类（定义在 `src/luavm/ffi.cj`）是对 Lua C API 的面向对象封装，管理 `unsafe` 块和 CString 内存分配，提供安全的仓颉风格接口：

- `init()` — 构造函数，调用 `luaL_newstate()` 创建状态机
- `close()` — 关闭并释放状态机
- `openLibs()` — 加载所有标准库
- `getTop()` — 获取栈顶索引。返回 `Int32`
- `pop(n)` — 从栈顶弹出 n 个元素。参数 `n: Int32` 弹出个数
- `pushInteger(n)` — 压入整数。参数 `n: Int64`
- `pushNumber(n)` — 压入浮点数。参数 `n: Float64`
- `pushString(s)` — 压入字符串。参数 `s: String`
- `pushBoolean(b)` — 压入布尔值。参数 `b: Bool`
- `pushNil()` — 压入 nil
- `pushCFunction(fn)` — 压入 C 函数。参数 `fn: CFunc<(CPointer<Unit>) -> Int32>`
- `toInteger(idx)` — 取整数值。参数 `idx: Int32` 栈索引。返回 `Int64`
- `toNumber(idx)` — 取浮点数值。参数 `idx: Int32` 栈索引。返回 `Float64`
- `toBoolean(idx)` — 取布尔值。参数 `idx: Int32` 栈索引。返回 `Bool`
- `toString(idx)` — 取字符串值。参数 `idx: Int32` 栈索引。返回 `String`
- `luaType(idx)` — 获取值的类型编号。参数 `idx: Int32` 栈索引。返回 `Int32`
- `typeName(tp)` — 获取类型名称。参数 `tp: Int32` 类型编号。返回 `String`
- `isNil(idx)` — 判断是否为 nil。参数 `idx: Int32`。返回 `Bool`
- `isNumber(idx)` — 判断是否为数字。参数 `idx: Int32`。返回 `Bool`
- `isString(idx)` — 判断是否为字符串。参数 `idx: Int32`。返回 `Bool`
- `isFunction(idx)` — 判断是否为函数。参数 `idx: Int32`。返回 `Bool`
- `newTable()` — 创建空表并压入栈顶
- `getGlobal(name)` — 获取全局变量值并压入栈顶。参数 `name: String`。返回 `Int32` 值类型
- `setGlobal(name)` — 将栈顶值设为全局变量。参数 `name: String`
- `getField(idx, k)` — 获取表字段值。参数 `idx: Int32`，`k: String`。返回 `Int32` 值类型
- `setField(idx, k)` — 设置表字段值。参数 `idx: Int32`，`k: String`
- `pCall(nargs, nresults, errfunc)` — 保护模式调用函数。参数 `nargs: Int32`，`nresults: Int32`，`errfunc: Int32`。返回 `Int32` 状态码
- `loadBytecode(bytecode, name)` — 加载字节码数组。参数 `bytecode: Array<UInt8>`，`name: String`。返回 `Int32` 状态码
- `gc(what)` — 控制 GC。参数 `what: Int32`。返回 `Int32`
- `getRawState()` — 获取底层状态机指针。返回 `CPointer<Unit>`

## 常量定义

### 状态码

- `LUA_OK` = 0 — 操作成功
- `LUA_YIELD` = 1 — 协程挂起
- `LUA_ERRRUN` = 2 — 运行时错误
- `LUA_ERRSYNTAX` = 3 — 语法错误
- `LUA_ERRMEM` = 4 — 内存分配错误
- `LUA_ERRERR` = 5 — 错误处理函数自身出错

### 类型常量

- `LUA_TNONE` = -1 — 无效索引
- `LUA_TNIL` = 0 — nil 类型
- `LUA_TBOOLEAN` = 1 — 布尔类型
- `LUA_TLIGHTUSERDATA` = 2 — 轻量用户数据
- `LUA_TNUMBER` = 3 — 数字类型
- `LUA_TSTRING` = 4 — 字符串类型
- `LUA_TTABLE` = 5 — 表类型
- `LUA_TFUNCTION` = 6 — 函数类型
- `LUA_TUSERDATA` = 7 — 用户数据
- `LUA_TTHREAD` = 8 — 线程（协程）类型

### GC 操作常量

- `LUA_GCCOLLECT` = 2 — 执行一次完整 GC 周期
- `LUA_GCSTOP` = 0 — 停止 GC
- `LUA_GCRESTART` = 1 — 重启 GC

### 其他常量

- `LUA_MULTRET` = -1 — 多返回值标记，用于 pCall 的 nresults 参数

## 注册自定义 C 函数示例

在仓颉侧通过 `@C` 注解定义可注册到 Lua VM 的回调函数：

```cangjie
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
        return 0  // 返回 0 表示无返回值给 Lua
    }
}

// 注册到 LuaState
state.pushCFunction(cangjiePrintln)
state.setGlobal("println")
```

## 编译管线总览

本项目的完整编译执行流程为：

```
仓颉源码(.scj) → Lexer(词法分析) → Parser(语法分析) → CodeGenerator(字节码生成) → LuaVM(执行)
```

1. **Lexer**：将源码文本扫描为 Token 序列
2. **Parser**：将 Token 序列解析为 AST（抽象语法树）
3. **CodeGenerator**：将 AST 编译为 Lua 5.5 二进制字节码
4. **LuaVM**：通过 `loadBytecode` 加载字节码，再通过 `pCall` 执行
