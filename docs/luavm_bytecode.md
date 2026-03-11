# LuaVM 接口与字节码说明文档

本文档详细介绍 CangjieLua 项目中集成的 LuaVM 接口和 Lua 5.5 字节码指令集，供扩展开发参考。

---

## 第一部分：仓颉 FFI 接口说明

CangjieLua 通过仓颉语言的 C 互操作机制（FFI）调用 Lua 5.5 虚拟机。以下是 `src/luavm/ffi.cj` 中已集成的全部接口。

### 1.1 状态管理

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `luaL_newstate` | `() -> CPointer<Unit>` | 创建新的 Lua 状态机，返回状态机指针 |
| `lua_close` | `(L: CPointer<Unit>) -> Unit` | 关闭并释放 Lua 状态机及所有关联资源 |
| `luaL_openselectedlibs` | `(L: CPointer<Unit>, load: Int32, preload: Int32) -> Unit` | 加载选定的标准库。`load` 为位掩码，`0x7FFFFFFF` 表示全部加载 |

### 1.2 栈操作

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `lua_gettop` | `(L: CPointer<Unit>) -> Int32` | 获取栈顶索引（即栈上元素个数） |
| `lua_settop` | `(L: CPointer<Unit>, idx: Int32) -> Unit` | 设置栈顶到指定索引。可用于弹出元素：`settop(L, -n-1)` 等价于 `pop(n)` |
| `lua_pushvalue` | `(L: CPointer<Unit>, idx: Int32) -> Unit` | 复制栈上指定索引的值到栈顶 |

### 1.3 压栈操作

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `lua_pushinteger` | `(L: CPointer<Unit>, n: Int64) -> Unit` | 将整数值压入栈顶 |
| `lua_pushnumber` | `(L: CPointer<Unit>, n: Float64) -> Unit` | 将浮点数值压入栈顶 |
| `lua_pushstring` | `(L: CPointer<Unit>, s: CString) -> Unit` | 将 C 字符串压入栈顶（Lua 会复制字符串） |
| `lua_pushboolean` | `(L: CPointer<Unit>, b: Int32) -> Unit` | 将布尔值压入栈顶（0 为 false，非 0 为 true） |
| `lua_pushnil` | `(L: CPointer<Unit>) -> Unit` | 将 nil 值压入栈顶 |
| `lua_pushcclosure` | `(L: CPointer<Unit>, fn: CFunc<(CPointer<Unit>) -> Int32>, n: Int32) -> Unit` | 将 C 函数闭包压入栈顶。`n` 为上值数量，`n=0` 时等价于 pushcfunction |

### 1.4 取值操作

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `lua_tointegerx` | `(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>) -> Int64` | 将栈上指定索引的值转为整数。`isnum` 可选，非 null 时写入转换是否成功 |
| `lua_tonumberx` | `(L: CPointer<Unit>, idx: Int32, isnum: CPointer<Int32>) -> Float64` | 将栈上指定索引的值转为浮点数 |
| `lua_toboolean` | `(L: CPointer<Unit>, idx: Int32) -> Int32` | 将栈上指定索引的值转为布尔值。nil 和 false 返回 0，其他返回 1 |
| `lua_tolstring` | `(L: CPointer<Unit>, idx: Int32, len: CPointer<UIntNative>) -> CString` | 将栈上指定索引的值转为字符串。`len` 可选，接收字符串长度 |

### 1.5 类型查询

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `lua_type` | `(L: CPointer<Unit>, idx: Int32) -> Int32` | 返回栈上指定索引的值的类型编号 |
| `lua_typename` | `(L: CPointer<Unit>, tp: Int32) -> CString` | 返回类型编号对应的类型名称字符串 |
| `lua_isnumber` | `(L: CPointer<Unit>, idx: Int32) -> Int32` | 检查值是否为数字（或可转换为数字的字符串） |
| `lua_isstring` | `(L: CPointer<Unit>, idx: Int32) -> Int32` | 检查值是否为字符串（或数字） |
| `lua_isinteger` | `(L: CPointer<Unit>, idx: Int32) -> Int32` | 检查值是否为整数 |
| `lua_iscfunction` | `(L: CPointer<Unit>, idx: Int32) -> Int32` | 检查值是否为 C 函数 |

### 1.6 表操作

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `lua_createtable` | `(L: CPointer<Unit>, narr: Int32, nrec: Int32) -> Unit` | 创建新表并压入栈顶。`narr` 预分配数组部分，`nrec` 预分配哈希部分 |
| `lua_getfield` | `(L: CPointer<Unit>, idx: Int32, k: CString) -> Int32` | 获取 `t[k]` 的值压入栈顶，`t` 为 `idx` 处的表。返回值的类型 |
| `lua_setfield` | `(L: CPointer<Unit>, idx: Int32, k: CString) -> Unit` | 设置 `t[k] = v`，`v` 为栈顶值（会弹出），`t` 为 `idx` 处的表 |
| `lua_getglobal` | `(L: CPointer<Unit>, name: CString) -> Int32` | 获取全局变量 `name` 的值压入栈顶。返回值的类型 |
| `lua_setglobal` | `(L: CPointer<Unit>, name: CString) -> Unit` | 设置全局变量 `name = v`，`v` 为栈顶值（会弹出） |

### 1.7 调用与执行

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `lua_pcallk` | `(L: CPointer<Unit>, nargs: Int32, nresults: Int32, errfunc: Int32, ctx: UIntNative, k: CPointer<Unit>) -> Int32` | 受保护调用。`nargs` 为参数数量，`nresults` 为期望返回值数量（`LUA_MULTRET=-1` 表示全部），`errfunc` 为错误处理函数栈索引（0 表示默认）。返回状态码 |

### 1.8 其他

| FFI 函数 | 签名 | 说明 |
|----------|------|------|
| `lua_gc` | `(L: CPointer<Unit>, what: Int32, ...) -> Int32` | 垃圾回收控制。`what` 取值：`LUA_GCSTOP(0)` 停止、`LUA_GCRESTART(1)` 重启、`LUA_GCCOLLECT(2)` 执行完整回收 |
| `lua_newthread` | `(L: CPointer<Unit>) -> CPointer<Unit>` | 创建新的 Lua 线程（协程），并压入栈顶 |
| `luaL_loadbufferx` | `(L: CPointer<Unit>, buf: CPointer<UInt8>, sz: UIntNative, name: CString, mode: CString) -> Int32` | 加载字节码缓冲区。`mode="b"` 表示仅加载二进制格式。返回 `LUA_OK(0)` 表示成功 |

### 1.9 常量定义

```
// 状态码
LUA_OK       = 0   // 成功
LUA_YIELD    = 1   // 协程让出
LUA_ERRRUN   = 2   // 运行时错误
LUA_ERRSYNTAX = 3  // 语法错误
LUA_ERRMEM   = 4   // 内存分配错误
LUA_ERRERR   = 5   // 错误处理函数本身出错

// 类型编号
LUA_TNONE          = -1  // 无效索引
LUA_TNIL           = 0   // nil
LUA_TBOOLEAN       = 1   // boolean
LUA_TLIGHTUSERDATA = 2   // light userdata
LUA_TNUMBER        = 3   // number (整数或浮点数)
LUA_TSTRING        = 4   // string
LUA_TTABLE         = 5   // table
LUA_TFUNCTION      = 6   // function
LUA_TUSERDATA      = 7   // userdata
LUA_TTHREAD        = 8   // thread (协程)

// 其他
LUA_MULTRET  = -1  // 多返回值标记
LUA_GCCOLLECT = 2  // GC 完整回收
LUA_GCSTOP    = 0  // GC 停止
LUA_GCRESTART = 1  // GC 重启
```

### 1.10 LuaState 包装类

`LuaState` 是对 Lua C API 的面向对象封装，管理所有 `unsafe` 调用：

| 方法 | 说明 |
|------|------|
| `init()` | 创建新的 Lua 状态机 |
| `init(state: CPointer<Unit>)` | 从已有指针构造 |
| `close()` | 关闭状态机 |
| `openLibs()` | 加载所有标准库 |
| `getTop() -> Int32` | 获取栈顶索引 |
| `pop(n: Int32)` | 弹出栈顶 n 个元素 |
| `pushInteger(n: Int64)` | 压入整数 |
| `pushNumber(n: Float64)` | 压入浮点数 |
| `pushString(s: String)` | 压入字符串 |
| `pushBoolean(b: Bool)` | 压入布尔值 |
| `pushNil()` | 压入 nil |
| `pushCFunction(fn)` | 压入 C 函数 |
| `toInteger(idx) -> Int64` | 取整数 |
| `toNumber(idx) -> Float64` | 取浮点数 |
| `toBoolean(idx) -> Bool` | 取布尔值 |
| `toString(idx) -> String` | 取字符串 |
| `luaType(idx) -> Int32` | 获取值类型 |
| `typeName(tp) -> String` | 获取类型名 |
| `isNil(idx) -> Bool` | 判断 nil |
| `isNumber(idx) -> Bool` | 判断数字 |
| `isInteger(idx) -> Bool` | 判断整数 |
| `isString(idx) -> Bool` | 判断字符串 |
| `isFunction(idx) -> Bool` | 判断函数 |
| `newTable()` | 创建空表 |
| `getGlobal(name) -> Int32` | 获取全局变量 |
| `setGlobal(name)` | 设置全局变量 |
| `getField(idx, k) -> Int32` | 获取表字段 |
| `setField(idx, k)` | 设置表字段 |
| `pCall(nargs, nresults, errfunc) -> Int32` | 受保护调用 |
| `loadBytecode(bytecode, name) -> Int32` | 加载字节码 |
| `gc(what) -> Int32` | GC 操作 |
| `getRawState() -> CPointer<Unit>` | 获取原始状态机指针 |

---

## 第二部分：libluavm 动态库导出接口

`libluavm.so` 是 Lua 5.5 独立虚拟机动态库（不含词法分析器和语法分析器），导出了完整的 Lua C API。以下按功能分类列出所有可用接口，扩展开发时可按需在 `ffi.cj` 中增加 `foreign` 声明来使用。

### 2.1 状态机管理（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_newstate` | `(f: lua_Alloc, ud: void*, seed: unsigned) -> lua_State*` | 使用自定义分配器创建状态机 |
| `lua_closethread` | `(L: lua_State*, from: lua_State*) -> int` | 关闭协程线程 |
| `lua_atpanic` | `(L: lua_State*, panicf: lua_CFunction) -> lua_CFunction` | 设置 panic 处理函数 |
| `lua_version` | `(L: lua_State*) -> lua_Number` | 获取 Lua 版本号 |

### 2.2 栈操作（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_absindex` | `(L, idx) -> int` | 将相对索引转为绝对索引 |
| `lua_rotate` | `(L, idx, n) -> void` | 旋转栈元素：在 idx 到栈顶范围内旋转 n 个位置 |
| `lua_copy` | `(L, fromidx, toidx) -> void` | 复制栈上一个位置的值到另一个位置 |
| `lua_checkstack` | `(L, n) -> int` | 确保栈有至少 n 个额外空位 |
| `lua_xmove` | `(from, to, n) -> void` | 在两个状态机之间移动栈上的值 |

### 2.3 压栈操作（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_pushlstring` | `(L, s, len) -> const char*` | 压入指定长度的字符串 |
| `lua_pushexternalstring` | `(L, s, len, falloc, ud) -> const char*` | 压入外部管理的字符串 |
| `lua_pushvfstring` | `(L, fmt, argp) -> const char*` | 压入格式化字符串（va_list 版本） |
| `lua_pushfstring` | `(L, fmt, ...) -> const char*` | 压入格式化字符串 |
| `lua_pushlightuserdata` | `(L, p) -> void` | 压入轻量用户数据 |
| `lua_pushthread` | `(L) -> int` | 将当前线程压入栈顶 |

### 2.4 取值操作（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_rawlen` | `(L, idx) -> lua_Unsigned` | 获取值的原始长度（不触发元方法） |
| `lua_tocfunction` | `(L, idx) -> lua_CFunction` | 将值转为 C 函数指针 |
| `lua_touserdata` | `(L, idx) -> void*` | 将值转为用户数据指针 |
| `lua_tothread` | `(L, idx) -> lua_State*` | 将值转为线程 |
| `lua_topointer` | `(L, idx) -> const void*` | 将值转为通用指针（仅用于调试） |
| `lua_isuserdata` | `(L, idx) -> int` | 检查值是否为用户数据 |

### 2.5 表操作（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_gettable` | `(L, idx) -> int` | 获取 `t[k]`，`k` 为栈顶值（会弹出），结果压入栈顶 |
| `lua_geti` | `(L, idx, n) -> int` | 获取 `t[n]`（整数索引），结果压入栈顶 |
| `lua_rawget` | `(L, idx) -> int` | 原始表访问（不触发元方法） |
| `lua_rawgeti` | `(L, idx, n) -> int` | 原始整数索引访问 |
| `lua_rawgetp` | `(L, idx, p) -> int` | 原始轻量用户数据索引访问 |
| `lua_newuserdatauv` | `(L, sz, nuvalue) -> void*` | 创建用户数据并压入栈顶 |
| `lua_getmetatable` | `(L, objindex) -> int` | 获取对象的元表 |
| `lua_getiuservalue` | `(L, idx, n) -> int` | 获取用户数据的第 n 个用户值 |
| `lua_settable` | `(L, idx) -> void` | 设置 `t[k] = v`，`k` 和 `v` 为栈顶两个值 |
| `lua_seti` | `(L, idx, n) -> void` | 设置 `t[n] = v`（整数索引） |
| `lua_rawset` | `(L, idx) -> void` | 原始表设置（不触发元方法） |
| `lua_rawseti` | `(L, idx, n) -> void` | 原始整数索引设置 |
| `lua_rawsetp` | `(L, idx, p) -> void` | 原始轻量用户数据索引设置 |
| `lua_setmetatable` | `(L, objindex) -> int` | 设置对象的元表 |
| `lua_setiuservalue` | `(L, idx, n) -> int` | 设置用户数据的第 n 个用户值 |

### 2.6 调用与加载（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_callk` | `(L, nargs, nresults, ctx, k) -> void` | 不受保护的函数调用（出错时调用 panic） |
| `lua_load` | `(L, reader, dt, chunkname, mode) -> int` | 从 reader 加载 Lua 代码块 |
| `lua_dump` | `(L, writer, data, strip) -> int` | 将函数原型导出为二进制格式 |

### 2.7 协程（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_yieldk` | `(L, nresults, ctx, k) -> int` | 让出协程执行 |
| `lua_resume` | `(L, from, narg, nres) -> int` | 恢复协程执行 |
| `lua_status` | `(L) -> int` | 获取协程状态 |
| `lua_isyieldable` | `(L) -> int` | 检查协程是否可让出 |

### 2.8 算术与比较（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_arith` | `(L, op) -> void` | 执行算术/位运算：弹出操作数，压入结果 |
| `lua_rawequal` | `(L, idx1, idx2) -> int` | 原始相等比较（不触发元方法） |
| `lua_compare` | `(L, idx1, idx2, op) -> int` | 比较两个值（可触发元方法） |

### 2.9 字符串与连接（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_concat` | `(L, n) -> void` | 连接栈顶 n 个值为字符串 |
| `lua_len` | `(L, idx) -> void` | 获取值的长度（压入栈顶） |
| `lua_stringtonumber` | `(L, s) -> size_t` | 将字符串转为数字并压入栈顶 |
| `lua_numbertocstring` | `(L, ...) -> const char*` | 将数字转为 C 字符串 |

### 2.10 GC 与内存（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_getallocf` | `(L, ud) -> lua_Alloc` | 获取内存分配函数 |
| `lua_setallocf` | `(L, f, ud) -> void` | 设置内存分配函数 |
| `lua_toclose` | `(L, idx) -> void` | 标记变量为 to-be-closed |
| `lua_closeslot` | `(L, idx) -> void` | 关闭 to-be-closed 变量的槽位 |

### 2.11 调试（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `lua_getstack` | `(L, level, ar) -> int` | 获取指定层级的活动记录 |
| `lua_getinfo` | `(L, what, ar) -> int` | 获取函数/活动记录的信息 |
| `lua_getlocal` | `(L, ar, n) -> const char*` | 获取局部变量的名称和值 |
| `lua_setlocal` | `(L, ar, n) -> const char*` | 设置局部变量的值 |
| `lua_getupvalue` | `(L, funcindex, n) -> const char*` | 获取上值的名称和值 |
| `lua_setupvalue` | `(L, funcindex, n) -> const char*` | 设置上值的值 |
| `lua_upvalueid` | `(L, fidx, n) -> void*` | 获取上值的唯一标识符 |
| `lua_upvaluejoin` | `(L, fidx1, n1, fidx2, n2) -> void` | 让两个闭包共享上值 |
| `lua_sethook` | `(L, func, mask, count) -> void` | 设置调试钩子 |
| `lua_gethook` | `(L) -> lua_Hook` | 获取当前调试钩子 |
| `lua_gethookmask` | `(L) -> int` | 获取钩子事件掩码 |
| `lua_gethookcount` | `(L) -> int` | 获取钩子计数 |

### 2.12 辅助库（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `luaL_alloc` | `(ud, ptr, osize, nsize) -> void*` | 默认内存分配器 |
| `luaL_checkversion_` | `(L, ver, sz) -> void` | 检查 API 版本兼容性 |
| `luaL_getmetafield` | `(L, obj, e) -> int` | 获取元表字段 |
| `luaL_callmeta` | `(L, obj, e) -> int` | 调用元方法 |
| `luaL_tolstring` | `(L, idx, len) -> const char*` | 将值转为显示字符串（调用 `__tostring`） |
| `luaL_argerror` | `(L, arg, extramsg) -> int` | 报告参数错误 |
| `luaL_typeerror` | `(L, arg, tname) -> int` | 报告类型错误 |
| `luaL_checkany` | `(L, arg) -> void` | 检查参数存在 |
| `luaL_checklstring` | `(L, arg, l) -> const char*` | 检查并获取字符串参数 |
| `luaL_optlstring` | `(L, arg, def, l) -> const char*` | 获取可选字符串参数 |
| `luaL_checknumber` | `(L, arg) -> lua_Number` | 检查并获取数字参数 |
| `luaL_optnumber` | `(L, arg, def) -> lua_Number` | 获取可选数字参数 |
| `luaL_checkinteger` | `(L, arg) -> lua_Integer` | 检查并获取整数参数 |
| `luaL_optinteger` | `(L, arg, def) -> lua_Integer` | 获取可选整数参数 |
| `luaL_checktype` | `(L, arg, t) -> void` | 检查参数类型 |
| `luaL_checkstack` | `(L, sz, msg) -> void` | 检查栈空间 |
| `luaL_checkudata` | `(L, ud, tname) -> void*` | 检查用户数据类型 |
| `luaL_testudata` | `(L, ud, tname) -> void*` | 测试用户数据类型 |
| `luaL_where` | `(L, lvl) -> void` | 将位置信息压入栈顶 |
| `luaL_error` | `(L, fmt, ...) -> int` | 报告错误 |
| `luaL_checkoption` | `(L, arg, def, lst) -> int` | 检查字符串选项 |
| `luaL_ref` | `(L, t) -> int` | 创建引用 |
| `luaL_unref` | `(L, t, ref) -> void` | 释放引用 |
| `luaL_loadfilex` | `(L, filename, mode) -> int` | 从文件加载 |
| `luaL_loadstring` | `(L, s) -> int` | 从字符串加载 |
| `luaL_newmetatable` | `(L, tname) -> int` | 创建或获取元表 |
| `luaL_setmetatable` | `(L, tname) -> void` | 设置栈顶对象的元表 |
| `luaL_getsubtable` | `(L, idx, fname) -> int` | 获取或创建子表 |
| `luaL_traceback` | `(L, L1, msg, level) -> void` | 生成回溯信息 |
| `luaL_requiref` | `(L, modname, openf, glb) -> void` | 加载模块 |
| `luaL_setfuncs` | `(L, l, nup) -> void` | 批量注册 C 函数 |
| `luaL_gsub` | `(L, s, p, r) -> const char*` | 字符串替换 |
| `luaL_addgsub` | `(L, b, s, p, r) -> void` | 向缓冲区添加替换结果 |
| `luaL_makeseed` | `(L) -> unsigned` | 生成随机种子 |
| `luaL_len` | `(L, idx) -> lua_Integer` | 获取长度（整数形式） |
| `luaL_execresult` | `(L, stat) -> int` | 执行结果处理 |
| `luaL_fileresult` | `(L, stat, fname) -> int` | 文件操作结果处理 |

### 2.13 缓冲区操作（扩展接口）

| 函数 | 签名 | 说明 |
|------|------|------|
| `luaL_buffinit` | `(L, B) -> void` | 初始化字符串缓冲区 |
| `luaL_buffinitsize` | `(L, B, sz) -> char*` | 初始化指定大小的缓冲区 |
| `luaL_prepbuffsize` | `(B, sz) -> char*` | 准备缓冲区空间 |
| `luaL_addlstring` | `(B, s, l) -> void` | 向缓冲区添加指定长度的字符串 |
| `luaL_addstring` | `(B, s) -> void` | 向缓冲区添加字符串 |
| `luaL_addvalue` | `(B) -> void` | 向缓冲区添加栈顶值 |
| `luaL_pushresult` | `(B) -> void` | 将缓冲区结果压入栈顶 |
| `luaL_pushresultsize` | `(B, sz) -> void` | 将指定大小的缓冲区结果压入栈顶 |

### 2.14 标准库打开函数

| 函数 | 说明 |
|------|------|
| `luaopen_base` | 打开基础库（print, type, tonumber, tostring, error, pcall 等） |
| `luaopen_coroutine` | 打开协程库（coroutine.create, resume, yield 等） |
| `luaopen_table` | 打开表操作库（table.insert, remove, sort, concat 等） |
| `luaopen_string` | 打开字符串库（string.format, find, gsub, sub 等） |
| `luaopen_math` | 打开数学库（math.sin, cos, sqrt, random 等） |
| `luaopen_io` | 打开 I/O 库（io.open, read, write 等） |
| `luaopen_os` | 打开操作系统库（os.time, clock, execute 等） |
| `luaopen_utf8` | 打开 UTF-8 库（utf8.len, char, codepoint 等） |
| `luaopen_debug` | 打开调试库（debug.getinfo, traceback 等） |
| `luaopen_package` | 打开包管理库（require, package.path 等） |

### 2.15 扩展开发中的 FFI 声明示例

当需要使用 `luavm/exports.txt` 中列出但 `ffi.cj` 中尚未声明的函数时，在 `foreign { }` 块中添加对应声明即可：

```cangjie
// 示例：添加 lua_concat 和 lua_len
foreign {
    func lua_concat(L: CPointer<Unit>, n: Int32): Unit
    func lua_len(L: CPointer<Unit>, idx: Int32): Unit
    func lua_rawget(L: CPointer<Unit>, idx: Int32): Int32
    func lua_rawset(L: CPointer<Unit>, idx: Int32): Unit
    func lua_rawgeti(L: CPointer<Unit>, idx: Int32, n: Int64): Int32
    func lua_rawseti(L: CPointer<Unit>, idx: Int32, n: Int64): Unit
    func lua_next(L: CPointer<Unit>, idx: Int32): Int32
    func lua_setmetatable(L: CPointer<Unit>, objindex: Int32): Int32
    func lua_getmetatable(L: CPointer<Unit>, objindex: Int32): Int32
}
```

然后在 `LuaState` 类中添加对应的包装方法即可调用。

---

## 第三部分：Lua 5.5 字节码指令集

Lua 5.5 虚拟机采用基于寄存器的架构，共有 **85 条指令**。每条指令为 32 位定长。

### 3.1 指令编码格式

Lua 5.5 使用四种主要指令格式：

```
  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
  1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0

iABC:     C(8)     |      B(8)     |k|     A(8)      |   Op(7)
iABx:               Bx(17)               |     A(8)      |   Op(7)
iAsBx:             sBx(signed 17)        |     A(8)      |   Op(7)
isJ:                        sJ(signed 25)               |   Op(7)
```

- **Op (7 bits)**：操作码，位于最低 7 位
- **A (8 bits)**：第一个操作数，通常是目标寄存器
- **B (8 bits)**：第二个操作数
- **C (8 bits)**：第三个操作数
- **k (1 bit)**：辅助标志位
- **Bx (17 bits)**：无符号扩展操作数（`B` 和 `C` 合并）
- **sBx (17 bits)**：有符号扩展操作数（存储时加偏移量 65535）
- **sJ (25 bits)**：有符号跳转偏移量（存储时加偏移量 16777215）

**约定符号**：
- `R[x]`：寄存器 x 的值
- `K[x]`：常量表索引 x 的值
- `RK(x)`：当 `k=1` 时表示 `K[x]`，当 `k=0` 时表示 `R[x]`
- `UpValue[x]`：上值表索引 x 的值
- `pc`：程序计数器

### 3.2 完整指令表

#### 3.2.1 加载与移动指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 0 | **MOVE** | `iABC: A B` | `R[A] := R[B]` | 寄存器间赋值。用于变量引用、参数传递、返回值准备 |
| 1 | **LOADI** | `iAsBx: A sBx` | `R[A] := sBx` | 加载小整数立即数（范围 -32768~32767）到寄存器 |
| 2 | **LOADF** | `iAsBx: A sBx` | `R[A] := (float)sBx` | 加载可表示为整数的浮点数（如 1.0、-5.0） |
| 3 | **LOADK** | `iABx: A Bx` | `R[A] := K[Bx]` | 从常量表加载常量到寄存器。用于大整数、浮点数、字符串 |
| 4 | **LOADKX** | `iABx: A` | `R[A] := K[extra arg]` | 加载扩展常量。下一条指令必须是 EXTRAARG，提供常量索引 |
| 5 | **LOADFALSE** | `iABC: A` | `R[A] := false` | 加载布尔值 false |
| 6 | **LFALSESKIP** | `iABC: A` | `R[A] := false; pc++` | 加载 false 并跳过下一条指令。用于条件转布尔值的模式 |
| 7 | **LOADTRUE** | `iABC: A` | `R[A] := true` | 加载布尔值 true |
| 8 | **LOADNIL** | `iABC: A B` | `R[A], ..., R[A+B] := nil` | 将连续 B+1 个寄存器设为 nil |

#### 3.2.2 上值操作指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 9 | **GETUPVAL** | `iABC: A B` | `R[A] := UpValue[B]` | 读取上值到寄存器。用于闭包访问外层变量 |
| 10 | **SETUPVAL** | `iABC: A B` | `UpValue[B] := R[A]` | 将寄存器值写入上值 |

#### 3.2.3 表访问指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 11 | **GETTABUP** | `iABC: A B C` | `R[A] := UpValue[B][K[C]]` | 通过上值表和字符串常量键访问表字段。**最常用**：访问全局变量 `_ENV[name]` |
| 12 | **GETTABLE** | `iABC: A B C` | `R[A] := R[B][R[C]]` | 用寄存器值作为键访问表 |
| 13 | **GETI** | `iABC: A B C` | `R[A] := R[B][C]` | 用整数立即数作为键访问表（数组索引） |
| 14 | **GETFIELD** | `iABC: A B C` | `R[A] := R[B][K[C]]` | 用字符串常量键访问表字段 |

#### 3.2.4 表赋值指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 15 | **SETTABUP** | `iABC: A B C` | `UpValue[A][K[B]] := RK(C)` | 通过上值表和字符串常量键设置表字段。**最常用**：设置全局变量 `_ENV[name] = value` |
| 16 | **SETTABLE** | `iABC: A B C` | `R[A][R[B]] := RK(C)` | 用寄存器值作为键设置表 |
| 17 | **SETI** | `iABC: A B C` | `R[A][B] := RK(C)` | 用整数立即数作为键设置表 |
| 18 | **SETFIELD** | `iABC: A B C` | `R[A][K[B]] := RK(C)` | 用字符串常量键设置表字段 |
| 19 | **NEWTABLE** | `ivABC: A vB vC k` | `R[A] := {}` | 创建新表。vB 为哈希部分大小的 log2+1，vC 为数组部分大小 |

#### 3.2.5 方法调用指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 20 | **SELF** | `iABC: A B C` | `R[A+1] := R[B]; R[A] := R[B][K[C]]` | 方法调用准备：保存 self 并加载方法 |

#### 3.2.6 立即数算术指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 21 | **ADDI** | `iABC: A B sC` | `R[A] := R[B] + sC` | 寄存器值加立即数 |

#### 3.2.7 常量算术指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 22 | **ADDK** | `iABC: A B C` | `R[A] := R[B] + K[C]` | 寄存器值加常量 |
| 23 | **SUBK** | `iABC: A B C` | `R[A] := R[B] - K[C]` | 寄存器值减常量 |
| 24 | **MULK** | `iABC: A B C` | `R[A] := R[B] * K[C]` | 寄存器值乘常量 |
| 25 | **MODK** | `iABC: A B C` | `R[A] := R[B] % K[C]` | 寄存器值模常量 |
| 26 | **POWK** | `iABC: A B C` | `R[A] := R[B] ^ K[C]` | 寄存器值幂常量 |
| 27 | **DIVK** | `iABC: A B C` | `R[A] := R[B] / K[C]` | 寄存器值除常量（浮点除法） |
| 28 | **IDIVK** | `iABC: A B C` | `R[A] := R[B] // K[C]` | 寄存器值整除常量 |

#### 3.2.8 常量位运算指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 29 | **BANDK** | `iABC: A B C` | `R[A] := R[B] & K[C]` | 与常量按位与 |
| 30 | **BORK** | `iABC: A B C` | `R[A] := R[B] \| K[C]` | 与常量按位或 |
| 31 | **BXORK** | `iABC: A B C` | `R[A] := R[B] ~ K[C]` | 与常量按位异或 |

#### 3.2.9 立即数移位指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 32 | **SHLI** | `iABC: A B sC` | `R[A] := sC << R[B]` | 立即数左移寄存器值位 |
| 33 | **SHRI** | `iABC: A B sC` | `R[A] := R[B] >> sC` | 寄存器值右移立即数位 |

#### 3.2.10 寄存器间算术指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 34 | **ADD** | `iABC: A B C` | `R[A] := R[B] + R[C]` | 加法。**本项目常用**：两个寄存器值相加 |
| 35 | **SUB** | `iABC: A B C` | `R[A] := R[B] - R[C]` | 减法 |
| 36 | **MUL** | `iABC: A B C` | `R[A] := R[B] * R[C]` | 乘法 |
| 37 | **MOD** | `iABC: A B C` | `R[A] := R[B] % R[C]` | 取模 |
| 38 | **POW** | `iABC: A B C` | `R[A] := R[B] ^ R[C]` | 幂运算 |
| 39 | **DIV** | `iABC: A B C` | `R[A] := R[B] / R[C]` | 浮点除法 |
| 40 | **IDIV** | `iABC: A B C` | `R[A] := R[B] // R[C]` | 整数除法 |

#### 3.2.11 寄存器间位运算指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 41 | **BAND** | `iABC: A B C` | `R[A] := R[B] & R[C]` | 按位与 |
| 42 | **BOR** | `iABC: A B C` | `R[A] := R[B] \| R[C]` | 按位或 |
| 43 | **BXOR** | `iABC: A B C` | `R[A] := R[B] ~ R[C]` | 按位异或 |
| 44 | **SHL** | `iABC: A B C` | `R[A] := R[B] << R[C]` | 左移 |
| 45 | **SHR** | `iABC: A B C` | `R[A] := R[B] >> R[C]` | 右移 |

#### 3.2.12 元方法回退指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 46 | **MMBIN** | `iABC: A B C` | 调用 C 号元方法处理 R[A] 和 R[B] | 紧跟在寄存器间算术指令之后。若算术成功则跳过此指令，否则调用元方法 |
| 47 | **MMBINI** | `iABC: A sB C k` | 调用 C 号元方法处理 R[A] 和立即数 sB | 紧跟在立即数算术指令之后 |
| 48 | **MMBINK** | `iABC: A B C k` | 调用 C 号元方法处理 R[A] 和 K[B] | 紧跟在常量算术指令之后 |

**元方法编号对照**：

| 编号 | 元方法名 | 对应运算 |
|------|----------|----------|
| 6 | `__add` | `+` 加法 |
| 7 | `__sub` | `-` 减法 |
| 8 | `__mul` | `*` 乘法 |
| 9 | `__div` | `/` 除法 |
| 10 | `__mod` | `%` 取模 |
| 11 | `__pow` | `^` 幂运算 |
| 12 | `__unm` | `-` 取负 |
| 13 | `__idiv` | `//` 整除 |
| 14 | `__band` | `&` 按位与 |
| 15 | `__bor` | `\|` 按位或 |
| 16 | `__bxor` | `~` 按位异或 |
| 17 | `__shl` | `<<` 左移 |
| 18 | `__shr` | `>>` 右移 |

#### 3.2.13 一元运算指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 49 | **UNM** | `iABC: A B` | `R[A] := -R[B]` | 取负。用于一元减号运算 |
| 50 | **BNOT** | `iABC: A B` | `R[A] := ~R[B]` | 按位取反 |
| 51 | **NOT** | `iABC: A B` | `R[A] := not R[B]` | 逻辑取反 |
| 52 | **LEN** | `iABC: A B` | `R[A] := #R[B]` | 取长度（字符串或表） |

#### 3.2.14 字符串连接指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 53 | **CONCAT** | `iABC: A B` | `R[A] := R[A].. ... ..R[A+B-1]` | 连接从 R[A] 开始的 B 个连续寄存器的值为字符串 |

#### 3.2.15 上值关闭指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 54 | **CLOSE** | `iABC: A` | 关闭所有 >= R[A] 的上值 | 作用域退出时关闭上值 |
| 55 | **TBC** | `iABC: A` | 标记变量 A 为 to-be-closed | to-be-closed 变量支持 |

#### 3.2.16 跳转指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 56 | **JMP** | `isJ: sJ` | `pc += sJ` | 无条件跳转。sJ 为有符号偏移量。**核心指令**：用于 if/else/while 控制流 |

#### 3.2.17 比较指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 57 | **EQ** | `iABC: A B k` | `if ((R[A] == R[B]) ~= k) then pc++` | 相等比较。若结果与 k 不同则跳过下一条指令 |
| 58 | **LT** | `iABC: A B k` | `if ((R[A] < R[B]) ~= k) then pc++` | 小于比较 |
| 59 | **LE** | `iABC: A B k` | `if ((R[A] <= R[B]) ~= k) then pc++` | 小于等于比较 |
| 60 | **EQK** | `iABC: A B k` | `if ((R[A] == K[B]) ~= k) then pc++` | 与常量相等比较 |
| 61 | **EQI** | `iABC: A sB k` | `if ((R[A] == sB) ~= k) then pc++` | 与立即数相等比较 |
| 62 | **LTI** | `iABC: A sB k` | `if ((R[A] < sB) ~= k) then pc++` | 与立即数小于比较 |
| 63 | **LEI** | `iABC: A sB k` | `if ((R[A] <= sB) ~= k) then pc++` | 与立即数小于等于比较 |
| 64 | **GTI** | `iABC: A sB k` | `if ((R[A] > sB) ~= k) then pc++` | 与立即数大于比较 |
| 65 | **GEI** | `iABC: A sB k` | `if ((R[A] >= sB) ~= k) then pc++` | 与立即数大于等于比较 |

**比较指令使用模式**：
所有比较指令都是"测试-跳过"模式——若测试结果与 k 不一致，则跳过紧跟的下一条指令（通常是 JMP）。

#### 3.2.18 条件测试指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 66 | **TEST** | `iABC: A k` | `if (not R[A] == k) then pc++` | 布尔值测试。若 R[A] 的真假性与 k 不符则跳过下一条。**本项目常用**：if/while 条件判断 |
| 67 | **TESTSET** | `iABC: A B k` | `if (not R[B] == k) then pc++ else R[A] := R[B]` | 条件赋值。用于短路求值（`a or b`、`a and b`） |

#### 3.2.19 函数调用指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 68 | **CALL** | `iABC: A B C` | `R[A], ..., R[A+C-2] := R[A](R[A+1], ..., R[A+B-1])` | 函数调用。B=参数数+1（B=0 表示用栈顶），C=返回值数+1（C=0 表示全部返回） |
| 69 | **TAILCALL** | `iABC: A B C k` | `return R[A](R[A+1], ..., R[A+B-1])` | 尾调用优化。不增加调用栈深度 |

#### 3.2.20 返回指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 70 | **RETURN** | `iABC: A B C k` | `return R[A], ..., R[A+B-2]` | 返回多个值。B=返回值数+1（B=0 表示返回到栈顶）。C>0 表示函数有隐藏的可变参数 |
| 71 | **RETURN0** | `iABC:` | `return` | 无返回值返回。**本项目常用**：函数末尾隐式返回 |
| 72 | **RETURN1** | `iABC: A` | `return R[A]` | 返回单个值 |

#### 3.2.21 循环指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 73 | **FORLOOP** | `iABx: A Bx` | 更新计数器；若循环继续则 `pc -= Bx` | 数值 for 循环的循环体末尾 |
| 74 | **FORPREP** | `iABx: A Bx` | 检查初始值并准备计数器；若不执行则 `pc += Bx + 1` | 数值 for 循环的入口 |
| 75 | **TFORPREP** | `iABx: A Bx` | 为 R[A+3] 创建上值；`pc += Bx` | 泛型 for 循环的准备 |
| 76 | **TFORCALL** | `iABC: A C` | `R[A+4], ..., R[A+3+C] := R[A](R[A+1], R[A+2])` | 泛型 for 循环的迭代器调用 |
| 77 | **TFORLOOP** | `iABx: A Bx` | `if R[A+2] ~= nil then { R[A] = R[A+2]; pc -= Bx }` | 泛型 for 循环的循环检查 |

#### 3.2.22 表初始化指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 78 | **SETLIST** | `ivABC: A vB vC k` | `R[A][vC+i] := R[A+i], 1 <= i <= vB` | 批量设置表的数组部分 |

#### 3.2.23 闭包指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 79 | **CLOSURE** | `iABx: A Bx` | `R[A] := closure(KPROTO[Bx])` | 从函数原型创建闭包。**本项目常用**：函数声明 |

#### 3.2.24 可变参数指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 80 | **VARARG** | `iABC: A B C k` | `R[A], ..., R[A+C-2] = varargs` | 获取可变参数 |
| 81 | **GETVARG** | `iABC: A B C` | `R[A] := R[B][R[C]]`（R[B]为可变参数） | 获取可变参数中的单个值 |
| 82 | **ERRNNIL** | `iABx: A Bx` | 若 `R[A] ~= nil` 则抛出错误 | 错误检查 |
| 83 | **VARARGPREP** | `iABx:` | 调整可变参数 | **本项目常用**：每个函数的第一条指令，准备可变参数帧 |

#### 3.2.25 扩展参数指令

| 编号 | 指令 | 格式 | 功能 | 使用场景 |
|------|------|------|------|----------|
| 84 | **EXTRAARG** | `iAx: Ax` | 为前一条指令提供扩展（更大的）参数 | 与 LOADKX、NEWTABLE、SETLIST 配合使用 |

### 3.3 CangjieLua 中常用的指令模式

#### 模式 1：加载常量

```
// 小整数 (范围 -32768~32767)
LOADI  R[dest], value         // 一条指令直接加载

// 大整数或浮点数
LOADK  R[dest], K[idx]        // 从常量表加载

// 超大常量（索引超过 17 位）
LOADKX R[dest], 0             // 占位
EXTRAARG idx                  // 提供实际索引

// 布尔值
LOADTRUE  R[dest]             // 加载 true
LOADFALSE R[dest]             // 加载 false
```

#### 模式 2：算术运算

每条算术指令后必须紧跟一条 MMBIN 元方法回退指令：

```
// R[dest] = R[left] + R[right]
ADD   R[dest], R[left], R[right]
MMBIN R[left], R[right], 6          // 6 = __add

// R[dest] = R[left] * R[right]
MUL   R[dest], R[left], R[right]
MMBIN R[left], R[right], 8          // 8 = __mul
```

#### 模式 3：比较表达式

CangjieLua 采用"先 false，条件改 true"的统一模板：

```
// dest = (left == right)
LOADFALSE R[dest]                    // 默认 false
EQ        R[left], R[right], k=0     // 若不相等则跳过 JMP
JMP       +1                         // 跳过 LOADTRUE
LOADTRUE  R[dest]                    // 相等则改为 true
```

#### 模式 4：if/else 控制流

```
// if (cond) { then } else { else }
<计算 cond 到 R[condReg]>
TEST   R[condReg], 0                 // 若 false/nil 则跳过
JMP    <到 else 分支>                 // 跳到 else（回填）
<then 分支指令>
JMP    <到 end>                       // 跳过 else（回填）
<else 分支指令>
// end:
```

#### 模式 5：while 循环

```
// while (cond) { body }
// loopStart:
<计算 cond 到 R[condReg]>
TEST   R[condReg], 0                 // 若 false/nil 则跳过
JMP    <到 afterLoop>                 // 跳出循环（回填）
<循环体指令>
JMP    <到 loopStart>                 // 跳回循环开头（负偏移）
// afterLoop:
```

#### 模式 6：函数声明与调用

```
// func add(a, b) { return a + b }
// 编译为子函数原型（FunctionProto），然后：
CLOSURE R[funcReg], KPROTO[funcIdx]  // 创建闭包
SETTABUP UpValue[0], K["add"], R[funcReg]  // 注册到 _ENV

// let result = add(3, 4)
GETTABUP R[funcReg], UpValue[0], K["add"]  // 从 _ENV 加载函数
LOADI    R[funcReg+1], 3                    // 参数 1
LOADI    R[funcReg+2], 4                    // 参数 2
CALL     R[funcReg], 3, 2                   // 调用：3=2 参数+1，2=1 返回值+1
```

#### 模式 7：全局变量访问

```
// 读取全局变量 x
GETTABUP R[dest], UpValue[0], K["x"]       // UpValue[0] = _ENV

// 设置全局变量 x = value
SETTABUP UpValue[0], K["x"], R[valueReg]
```

---

## 第四部分：Lua 5.5 二进制块格式

CangjieLua 将源码编译为 Lua 5.5 标准二进制格式（luac 格式），由 `ChunkWriter` 序列化。

### 4.1 文件头部（全局头部）

| 偏移 | 大小 | 内容 | 说明 |
|------|------|------|------|
| 0 | 4 | `\x1b\x4c\x75\x61` | 魔数（`\x1bLua`） |
| 4 | 1 | `0x55` | 版本号（Lua 5.5） |
| 5 | 1 | `0x00` | 格式号（官方格式） |
| 6 | 6 | `\x19\x93\x0d\x0a\x1a\x0a` | 校验数据 |
| 12 | 1 | `0x04` | sizeof(int) = 4 |
| 13 | 4 | `0xffffa988` | 整数校验值（小端序 -0x5678） |
| 17 | 1 | `0x04` | sizeof(Instruction) = 4 |
| 18 | 4 | `0x12345678` | 指令字节序校验 |
| 22 | 1 | `0x08` | sizeof(lua_Integer) = 8 |
| 23 | 8 | `-0x5678 的 8 字节表示` | 64 位整数校验 |
| 31 | 1 | `0x08` | sizeof(lua_Number) = 8 |
| 32 | 8 | `-370.5 的 IEEE 754 表示` | 浮点数校验 |
| 40 | 1 | `0x01` | 上值数量 = 1（_ENV） |

### 4.2 函数原型（Function Prototype）

每个函数原型包含以下信息：

| 字段 | 编码 | 说明 |
|------|------|------|
| linedefined | VarInt | 起始行号（main 为 0） |
| lastlinedefined | VarInt | 结束行号（main 为 0） |
| numparams | 1 字节 | 固定参数数量 |
| is_vararg | 1 字节 | 0=普通，1=可变参数 |
| maxstacksize | 1 字节 | 最大栈深度（含 2 的额外保留） |
| 指令数量 | VarInt | 指令数组长度 |
| 对齐填充 | 0~3 字节 | 4 字节对齐 |
| 指令数组 | 4×n 字节 | 每条指令 4 字节（小端序） |
| 常量数量 | VarInt | 常量表长度 |
| 常量表 | 变长 | 类型标签 + 值（见下文） |
| 上值数量 | VarInt | 上值表长度 |
| 上值表 | 3×n 字节 | 每个上值：instack(1) + idx(1) + kind(1) |
| 子函数数量 | VarInt | 嵌套函数原型数量 |
| 子函数 | 变长 | 递归的函数原型结构 |
| 源文件名 | VarInt | 调试信息（CangjieLua 中为空） |
| 行号信息 | VarInt | 调试信息（为空） |
| 绝对行号 | VarInt | 调试信息（为空） |
| 局部变量 | VarInt | 调试信息（为空） |
| 上值名称 | VarInt | 调试信息（为空） |

### 4.3 常量编码

| 类型标签 | 值 | 后续数据 | 说明 |
|----------|----|----------|------|
| `0x03` | LUA_VNUMINT | VarInt 编码的整数 | 整数常量。编码规则：非负数→2x，负数→-2x-1 |
| `0x13` | LUA_VNUMFLT | 8 字节 IEEE 754 | 浮点数常量 |
| `0x04` | LUA_VSHRSTR | VarInt(len+1) + 数据 + NUL | 短字符串常量 |

### 4.4 VarInt 编码

Lua 5.5 使用 MSB（最高有效位优先）变长整数编码：

- 每个字节的最高位（bit 7）为延续标志：1 表示后续还有字节，0 表示最后一个字节
- 低 7 位为数据位
- **高位组先写**（与 protobuf 的 LEB128 相反）

示例：
- `0` → `0x00`（1 字节）
- `127` → `0x7F`（1 字节）
- `128` → `0x81 0x00`（2 字节）
- `300` → `0x82 0x2C`（2 字节）

---

## 第五部分：典型代码的字节码解析

### 5.1 示例 1：返回常量 `return 42`

源码：
```cangjie
return 42
```

生成的字节码（主函数）：

| # | 指令 | 操作码 | 字段 | 含义 |
|---|------|--------|------|------|
| 0 | `VARARGPREP` | 83 | A=0, Bx=0 | 准备可变参数帧（main 函数必须） |
| 1 | `LOADI` | 1 | A=0, sBx=42 | R[0] := 42（加载整数立即数到寄存器 0） |
| 2 | `RETURN` | 70 | A=0, B=2, C=1 | 返回 R[0]（B=2 表示 1 个返回值；C=1 表示 main 函数的 vararg 标记） |
| 3 | `RETURN0` | 71 | | 隐式返回（函数末尾） |

**常量表**：空

**上值表**：1 个上值（`_ENV`，instack=1, idx=0, kind=0）

### 5.2 示例 2：变量与加法 `let x = 10; let y = 20; return x + y`

源码：
```cangjie
let x = 10
let y = 20
return x + y
```

生成的字节码：

| # | 指令 | 字段 | 含义 |
|---|------|------|------|
| 0 | `VARARGPREP` | A=0, Bx=0 | 准备可变参数帧 |
| 1 | `LOADI` | A=0, sBx=10 | R[0] := 10（x 分配到寄存器 0） |
| 2 | `LOADI` | A=1, sBx=20 | R[1] := 20（y 分配到寄存器 1） |
| 3 | `MOVE` | A=2, B=0 | R[2] := R[0]（复制 x 到临时寄存器） |
| 4 | `ADD` | A=2, B=2, C=1 | R[2] := R[2] + R[1]（计算 x + y） |
| 5 | `MMBIN` | A=2, B=1, C=6 | 元方法回退：__add |
| 6 | `RETURN` | A=2, B=2, C=1 | 返回 R[2] |
| 7 | `RETURN0` | | 隐式返回 |

### 5.3 示例 3：条件判断

源码：
```cangjie
var x = 10
if (x > 5.0) {
    x = 20
}
return x
```

生成的字节码：

| # | 指令 | 字段 | 含义 |
|---|------|------|------|
| 0 | `VARARGPREP` | | 准备可变参数帧 |
| 1 | `LOADI` | A=0, sBx=10 | R[0] := 10（x） |
| 2 | `MOVE` | A=2, B=0 | R[2] := R[0]（比较用临时寄存器：left） |
| 3 | `LOADF` | A=3, sBx=5 | R[3] := 5.0（比较用临时寄存器：right） |
| 4 | `LOADFALSE` | A=1 | R[1] := false（默认比较结果） |
| 5 | `LT` | A=3, B=2, k=0 | if (R[3] < R[2]) ~= 0) then pc++（即 right < left → x > 5.0） |
| 6 | `JMP` | sJ=+1 | 跳过 LOADTRUE（条件不满足时） |
| 7 | `LOADTRUE` | A=1 | R[1] := true（条件满足） |
| 8 | `TEST` | A=1, k=0 | if R[1] 为 false/nil 则跳过下一条 |
| 9 | `JMP` | sJ=+1 | 跳过 then 分支 |
| 10 | `LOADI` | A=0, sBx=20 | R[0] := 20（x = 20） |
| 11 | `MOVE` | A=1, B=0 | R[1] := R[0]（准备返回值） |
| 12 | `RETURN` | A=1, B=2, C=1 | 返回 R[1] |
| 13 | `RETURN0` | | 隐式返回 |

### 5.4 示例 4：while 循环求和

源码：
```cangjie
var count = 5
var sum = 0
while (count > 0) {
    sum = sum + count
    count = count - 1
}
return sum
```

生成的字节码：

| # | 指令 | 字段 | 含义 |
|---|------|------|------|
| 0 | `VARARGPREP` | | 准备可变参数帧 |
| 1 | `LOADI` | A=0, sBx=5 | R[0] := 5（count） |
| 2 | `LOADI` | A=1, sBx=0 | R[1] := 0（sum） |
| 3~7 | 比较指令组 | | 计算 `count > 0` 到 R[2]（LOADFALSE + LT + JMP + LOADTRUE 模式） |
| 8 | `TEST` | A=2, k=0 | 测试循环条件 |
| 9 | `JMP` | sJ=+N | 若条件为假，跳出循环 |
| 10 | `MOVE+ADD+MMBIN` | | sum = sum + count |
| 13 | `MOVE+SUB+MMBIN` | | count = count - 1 |
| 16 | `JMP` | sJ=-N | 跳回循环开头（指令 3） |
| 17 | `MOVE` | | 准备返回值 |
| 18 | `RETURN` | | 返回 sum |
| 19 | `RETURN0` | | 隐式返回 |

### 5.5 示例 5：函数声明与调用

源码：
```cangjie
func calculateArea(radius: Float64) {
    let pi = 3.14
    return pi * radius * radius
}
let r = 5.0
let area = calculateArea(r)
println(area)
```

主函数字节码：

| # | 指令 | 字段 | 含义 |
|---|------|------|------|
| 0 | `VARARGPREP` | | 准备可变参数帧 |
| 1 | `CLOSURE` | A=0, Bx=0 | R[0] := closure(KPROTO[0])（创建 calculateArea 闭包） |
| 2 | `SETTABUP` | A=0, B=0, C=0 | UpValue[0][K[0]] := R[0]（_ENV["calculateArea"] = 闭包） |
| 3 | `LOADF` | A=1, sBx=5 | R[1] := 5.0（r） |
| 4 | `GETTABUP` | A=2, B=0, C=0 | R[2] := UpValue[0][K[0]]（加载 calculateArea） |
| 5 | `MOVE` | A=3, B=1 | R[3] := R[1]（传参 r） |
| 6 | `CALL` | A=2, B=2, C=2 | 调用 R[2](R[3])，1 个参数，期望 1 个返回值 |
| 7 | `GETTABUP` | A=3, B=0, C=1 | R[3] := UpValue[0][K[1]]（加载 println） |
| 8 | `MOVE` | A=4, B=2 | R[4] := R[2]（传参 area） |
| 9 | `CALL` | A=3, B=2, C=1 | 调用 println(area)，不需要返回值 |
| 10 | `RETURN0` | | 隐式返回 |

常量表：`K[0] = "calculateArea"`, `K[1] = "println"`

**calculateArea 子函数字节码**：

| # | 指令 | 字段 | 含义 |
|---|------|------|------|
| 0 | `LOADK` | A=1, Bx=0 | R[1] := K[0]（pi = 3.14） |
| 1 | `MOVE` | A=2, B=1 | R[2] := R[1]（复制 pi） |
| 2 | `MUL` | A=2, B=2, C=0 | R[2] := R[2] * R[0]（pi * radius） |
| 3 | `MMBIN` | A=2, B=0, C=8 | 元方法回退：__mul |
| 4 | `MUL` | A=2, B=2, C=0 | R[2] := R[2] * R[0]（(pi*radius) * radius） |
| 5 | `MMBIN` | A=2, B=0, C=8 | 元方法回退：__mul |
| 6 | `RETURN` | A=2, B=2, C=0 | 返回 R[2] |
| 7 | `RETURN0` | | 隐式返回 |

子函数常量表：`K[0] = 3.14`（浮点数类型 0x13）

上值表：1 个上值（`_ENV`，instack=0, idx=0, kind=0 — 从父函数继承）

### 5.6 示例 6：阶乘函数

源码：
```cangjie
func factorial(n: Float64) {
    var result = 1.0
    var i = n
    while (i > 0.0) {
        result = result * i
        i = i - 1.0
    }
    return result
}
let f5 = factorial(5.0)
println(f5)
```

主函数关键字节码：

| # | 指令 | 含义 |
|---|------|------|
| 0 | `VARARGPREP` | 准备 main 帧 |
| 1 | `CLOSURE R[0], KPROTO[0]` | 创建 factorial 闭包 |
| 2 | `SETTABUP UpVal[0], K["factorial"], R[0]` | 注册到 _ENV |
| 3 | `GETTABUP R[1], UpVal[0], K["factorial"]` | 加载 factorial |
| 4 | `LOADF R[2], 5` | 参数 5.0 |
| 5 | `CALL R[1], 2, 2` | 调用 factorial(5.0) |
| 6 | `GETTABUP R[2], UpVal[0], K["println"]` | 加载 println |
| 7 | `MOVE R[3], R[1]` | 传参 |
| 8 | `CALL R[2], 2, 1` | 调用 println |
| 9 | `RETURN0` | 结束 |

factorial 子函数关键字节码流程：
1. 参数 `n` 在 R[0]
2. `LOADF R[1], 1` → result = 1.0
3. `MOVE R[2], R[0]` → i = n
4. 循环开始：计算 `i > 0.0` 比较结果
5. `TEST + JMP` → 条件跳出
6. `MUL + MMBIN` → result = result * i
7. `SUB + MMBIN` → i = i - 1.0
8. `JMP` → 跳回循环开头
9. `RETURN R[1]` → 返回 result

---

## 附录 A：指令编码函数速查

以下是 `bytecode.cj` 中提供的编码函数，可在扩展开发中直接使用：

```cangjie
// iABC 格式
encodeABC(op: OpCodes, a: UInt32, b: UInt32, c: UInt32) -> UInt32

// iABC 格式（带 k 标志）
encodeABCK(op: OpCodes, a: UInt32, b: UInt32, c: UInt32, k: UInt32) -> UInt32

// iABx 格式
encodeABx(op: OpCodes, a: UInt32, bx: UInt32) -> UInt32

// iAsBx 格式（有符号偏移量）
encodeAsBx(op: OpCodes, a: UInt32, sbx: Int32) -> UInt32

// isJ 格式（跳转偏移量）
encodeIsJ(op: OpCodes, sj: Int32) -> UInt32

// EQI 特殊编码
encodeEQI(a: UInt32, sB: Int32, k: UInt32) -> UInt32
```

## 附录 B：位域常量速查

```
A_SHIFT  = 7     B_SHIFT  = 16    C_SHIFT  = 24
K_SHIFT  = 15    BX_SHIFT = 15    SJ_SHIFT = 7

A_MASK   = 0xFF       B_MASK   = 0xFF       C_MASK   = 0xFF
K_MASK   = 0x1        BX_MASK  = 0x1FFFF    SJ_MASK  = 0x1FFFFFF

SBX_OFFSET = 65535    SJ_OFFSET = 16777215  SB_OFFSET = 127
```
