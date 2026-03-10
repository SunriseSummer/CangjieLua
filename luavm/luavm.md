# LuaVM 接口与字节码技术说明

本文档面向 CangjieLua 工程，系统说明两部分内容：

1. Lua VM FFI 接口层能力与用途
2. Lua 5.5 字节码格式、全部操作码说明，以及一个可运行字节码块示例

适用代码：

- src/luavm/ffi.cj
- src/codegen/bytecode.cj
- src/codegen/chunk_writer.cj
- src/codegen/code_generator.cj

---

## 1. LuaVM FFI 接口总览

CangjieLua 通过 foreign 声明直接绑定 Lua C API，再由 LuaState 封装为更易用的对象化接口

### 1.1 状态管理接口

| 接口 | 作用 | 典型用途 |
|---|---|---|
| luaL_newstate() | 创建 Lua 主状态机 | 解释器启动 VM |
| lua_close(L) | 释放状态机资源 | 执行结束清理 |
| luaL_openselectedlibs(L, load, preload) | 按位加载标准库 | 初始化运行环境 |

### 1.2 栈操作接口

| 接口 | 作用 | 说明 |
|---|---|---|
| lua_gettop(L) | 获取栈顶索引 | Lua 栈 1-based，0 表示空栈 |
| lua_settop(L, idx) | 设置栈顶 | 可实现截断、扩展、pop |
| lua_pushvalue(L, idx) | 复制指定栈槽到栈顶 | 常用于参数/返回值重排 |

### 1.3 压栈接口

| 接口 | 作用 |
|---|---|
| lua_pushinteger(L, n) | 压入整数 |
| lua_pushnumber(L, n) | 压入浮点 |
| lua_pushstring(L, s) | 压入字符串 |
| lua_pushboolean(L, b) | 压入布尔 |
| lua_pushnil(L) | 压入 nil |
| lua_pushcclosure(L, fn, n) | 压入 C 函数闭包 |

### 1.4 取值与类型查询接口

| 接口 | 作用 | 备注 |
|---|---|---|
| lua_tointegerx | 栈值转整数 | 第三个参数可获知是否成功 |
| lua_tonumberx | 栈值转浮点 | 同上 |
| lua_toboolean | 栈值转布尔 | Lua 语义：仅 false/nil 为假 |
| lua_tolstring | 栈值转字符串 | 返回 C 字符串指针 |
| lua_type | 读取类型码 | 返回 LUA_T* |
| lua_typename | 类型码转名称 | 便于日志 |
| lua_isnumber / lua_isstring / lua_isinteger / lua_iscfunction | 快速类型谓词 | 轻量分支判断 |

### 1.5 表与全局环境接口

| 接口 | 作用 |
|---|---|
| lua_createtable | 新建表 |
| lua_getfield / lua_setfield | 字段读写 |
| lua_getglobal / lua_setglobal | 全局变量读写 |

### 1.6 执行与加载接口

| 接口 | 作用 | 关键点 |
|---|---|---|
| luaL_loadbufferx | 从字节缓冲加载 chunk | mode="b" 可限制仅二进制 |
| lua_pcallk | 受保护调用 | 不崩 VM，错误留在栈顶 |

### 1.7 其他接口

| 接口 | 作用 |
|---|---|
| lua_gc | 触发或控制 GC |
| lua_newthread | 创建协程线程 |

---

## 2. LuaState 包装层

LuaState 是 FFI 的工程化封装，目标是：

- 减少上层 unsafe 代码
- 统一字符串/数组句柄生命周期管理
- 提供稳定 API 给 CangjieLua 运行入口

### 2.1 常用方法与语义

| 方法 | 对应 C API | 语义 |
|---|---|---|
| openLibs() | luaL_openselectedlibs | 打开标准库 |
| pop(n) | lua_settop | 等价 lua_pop(L, n) |
| getGlobal/setGlobal | lua_getglobal/lua_setglobal | 全局符号读写 |
| pCall(nargs, nresults, errfunc) | lua_pcallk | 受保护调用 |
| loadBytecode(bytes, name) | luaL_loadbufferx | 加载二进制 chunk |
| gc(what) | lua_gc | 垃圾回收控制 |

### 2.2 状态码与类型码

#### 状态码

- LUA_OK = 0
- LUA_YIELD = 1
- LUA_ERRRUN = 2
- LUA_ERRSYNTAX = 3
- LUA_ERRMEM = 4
- LUA_ERRERR = 5

#### 特殊常量

- LUA_MULTRET = -1（表示返回“所有结果”）

#### 类型码

- LUA_TNONE = -1
- LUA_TNIL = 0
- LUA_TBOOLEAN = 1
- LUA_TLIGHTUSERDATA = 2
- LUA_TNUMBER = 3
- LUA_TSTRING = 4
- LUA_TTABLE = 5
- LUA_TFUNCTION = 6
- LUA_TUSERDATA = 7
- LUA_TTHREAD = 8

---

## 3. 字节码编码模型

### 3.1 32 位指令格式

Lua 5.5 指令为固定 32 位，常见形式：

- iABC: [opcode:7][A:8][k:1][B:8][C:8]
- iABx: [opcode:7][A:8][Bx:17]
- iAsBx: [opcode:7][A:8][sBx:17 signed]
- isJ: [opcode:7][sJ:25 signed]

工程内编码器：

- encodeABC
- encodeABx
- encodeAsBx
- encodeIsJ
- encodeABCK
- encodeEQI

### 3.2 关键位域常量

- A_SHIFT=7, K_SHIFT=15, B_SHIFT=16, C_SHIFT=24
- BX_SHIFT=15, SJ_SHIFT=7
- A/B/C 掩码 0xFF，k 掩码 0x1
- Bx 掩码 0x1FFFF，sJ 掩码 0x1FFFFFF
- sBx 偏移 SBX_OFFSET=65535
- sJ 偏移 SJ_OFFSET=16777215

---

## 4. 全部操作码技术说明（85 条）

以下编号与工程 opcodeValue 一致

说明：本节是面向工程实践的技术说明，语义表述做了适度抽象
对于 Lua VM 的逐指令精确定义，应以 Lua 源码与官方实现为准

### 4.1 装载与数据移动

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 0 | MOVE | 寄存器到寄存器拷贝 |
| 1 | LOADI | 加载小范围整数立即数 |
| 2 | LOADF | 加载小范围“整数值形式”的浮点立即数（如 3.0） |
| 3 | LOADK | 从常量表加载 |
| 4 | LOADKX | 扩展常量加载，配合 EXTRAARG |
| 5 | LOADFALSE | 加载 false |
| 6 | LFALSESKIP | 加载 false 并跳过下一条（特定流程用） |
| 7 | LOADTRUE | 加载 true |
| 8 | LOADNIL | 加载 nil |

### 4.2 Upvalue / 表访问

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 9 | GETUPVAL | 读取 upvalue |
| 10 | SETUPVAL | 写入 upvalue |
| 11 | GETTABUP | 从 upvalue 表取字段（常见 _ENV） |
| 12 | GETTABLE | R[B][R/C] 读表 |
| 13 | GETI | 以整数索引读表 |
| 14 | GETFIELD | 以常量字符串字段读表 |
| 15 | SETTABUP | 写 upvalue 表字段 |
| 16 | SETTABLE | 写普通表 |
| 17 | SETI | 以整数索引写表 |
| 18 | SETFIELD | 以字符串字段写表 |
| 19 | NEWTABLE | 创建新表 |
| 20 | SELF | 面向对象调用前置（method/self） |

### 4.3 算术与位运算（立即数/常量版本）

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 21 | ADDI | 加立即数 |
| 22 | ADDK | 加常量 |
| 23 | SUBK | 减常量 |
| 24 | MULK | 乘常量 |
| 25 | MODK | 取模常量 |
| 26 | POWK | 幂常量 |
| 27 | DIVK | 除常量 |
| 28 | IDIVK | 整除常量 |
| 29 | BANDK | 按位与常量 |
| 30 | BORK | 按位或常量 |
| 31 | BXORK | 按位异或常量 |
| 32 | SHLI | 左移立即数 |
| 33 | SHRI | 右移立即数 |

### 4.4 算术与位运算（寄存器版本）

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 34 | ADD | 加 |
| 35 | SUB | 减 |
| 36 | MUL | 乘 |
| 37 | MOD | 模 |
| 38 | POW | 幂 |
| 39 | DIV | 除 |
| 40 | IDIV | 整除 |
| 41 | BAND | 按位与 |
| 42 | BOR | 按位或 |
| 43 | BXOR | 按位异或 |
| 44 | SHL | 左移 |
| 45 | SHR | 右移 |

### 4.5 元方法辅助

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 46 | MMBIN | 二元运算元方法回退 |
| 47 | MMBINI | 立即数版本元方法回退 |
| 48 | MMBINK | 常量版本元方法回退 |

### 4.6 一元与其他运算

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 49 | UNM | 一元负号 |
| 50 | BNOT | 按位非 |
| 51 | NOT | 逻辑非 |
| 52 | LEN | 长度运算 |
| 53 | CONCAT | 字符串拼接 |
| 54 | CLOSE | 关闭 upvalue |
| 55 | TBC | to-be-closed 变量管理 |

### 4.7 跳转与比较

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 56 | JMP | 无条件相对跳转 |
| 57 | EQ | 相等比较 |
| 58 | LT | 小于比较 |
| 59 | LE | 小于等于比较 |
| 60 | EQK | 寄存器与常量相等比较 |
| 61 | EQI | 寄存器与立即数相等比较 |
| 62 | LTI | 小于立即数 |
| 63 | LEI | 小于等于立即数 |
| 64 | GTI | 大于立即数 |
| 65 | GEI | 大于等于立即数 |
| 66 | TEST | 条件测试 |
| 67 | TESTSET | 条件测试并可赋值 |

### 4.8 调用与返回

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 68 | CALL | 普通调用 |
| 69 | TAILCALL | 尾调用 |
| 70 | RETURN | 通用返回 |
| 71 | RETURN0 | 无返回值快速返回 |
| 72 | RETURN1 | 单返回值快速返回 |

### 4.9 循环与迭代

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 73 | FORLOOP | 数值 for 回环 |
| 74 | FORPREP | 数值 for 预处理 |
| 75 | TFORPREP | 泛型 for 预处理 |
| 76 | TFORCALL | 泛型 for 调用迭代器 |
| 77 | TFORLOOP | 泛型 for 循环 |

### 4.10 闭包、可变参数与扩展

| 编号 | 操作码 | 说明 |
|---:|---|---|
| 78 | SETLIST | 批量写数组段 |
| 79 | CLOSURE | 构造闭包 |
| 80 | VARARG | 读取 vararg |
| 81 | GETVARG | 访问 vararg 区域 |
| 82 | ERRNNIL | nil 错误保护指令 |
| 83 | VARARGPREP | vararg 函数入口准备 |
| 84 | EXTRAARG | 扩展参数字 |

---

## 5. Chunk（二进制块）结构说明

本工程输出的 chunk 结构分为：

1. 文件头 Header
2. 主函数 upvalue 数量（本工程写 1，表示 `_ENV`）
3. 主函数原型（main）
4. 子函数原型列表（递归）
5. 调试信息区（当前多为空）

### 5.1 Header 字段

| 字段 | 含义 |
|---|---|
| LUA_SIGNATURE | 魔数，标识 Lua chunk |
| LUAC_VERSION | 版本号（0x55） |
| LUAC_FORMAT | 格式号（0x00） |
| LUAC_DATA | 固定校验序列 |
| sizeof(int) + LUAC_INT | 整数格式与字节序校验 |
| sizeof(Instruction) + LUAC_INST | 指令格式校验 |
| sizeof(lua_Integer) + LUAC_INT64 | 64 位整数校验 |
| sizeof(lua_Number) + LUAC_NUM | 浮点格式校验 |
| main upvalue count | 主函数上值数量（本工程固定为 1） |

### 5.2 函数原型字段（简化）

| 顺序 | 字段 | 说明 |
|---:|---|---|
| 1 | linedefined / lastlinedefined | 行号范围 |
| 2 | numparams | 固定参数个数 |
| 3 | is_vararg | 是否可变参数 |
| 4 | maxstacksize | 最大寄存器栈需求 |
| 5 | instruction list | 指令序列 |
| 6 | constants | 常量表 |
| 7 | upvalues | 上值描述 |
| 8 | nested protos | 子函数原型 |
| 9 | source / debug sections | 源信息与调试信息 |

---

## 6. 可运行字节码块示例（字段逐项解释）

示例源码：

return 42

编译后主函数可以抽象为如下结构

### 6.1 Header

- signature = 1B 4C 75 61
- version = 55
- format = 00
- luac_data = 19 93 0D 0A 1A 0A
- type checks = int32 / instruction32 / int64 / float64 对应校验值
- main upvalue count = 01（即 `_ENV`）

### 6.2 Main Prototype（核心）

- numparams = 0
- is_vararg = 1
- maxstacksize = 至少 2（工程会额外保留）

指令序列（逻辑视图）

1. VARARGPREP A=0 Bx=0
2. LOADI A=R0 sBx=42
3. RETURN A=R0 B=2 C=1
4. RETURN0

说明：

- 第 1 条保证 main 作为 vararg 入口与 Lua 约定一致
- 第 2 条把整数 42 放入寄存器 R0
- 第 3 条返回 1 个值（R0）
- 第 4 条作为兜底尾返回，确保函数原型完整（正常路径通常在第 3 条已返回）

常量表：

- 该例可不需要常量表（42 落在 LOADI 范围内）

upvalue 表：

- 1 条记录，通常为 _ENV

调试信息：

- 当前工程默认写空段，减小 chunk 体积

该 chunk 可由 LuaState.loadBytecode + pCall 直接执行，返回整数 42

---

## 7. 在 CangjieLua 中的实际使用路径

执行路径可概括为：

1. CodeGenerator.generate() 输出 chunk
2. LuaState.loadBytecode(chunk, "main") 加载
3. LuaState.pCall(0, 1, 0) 执行
4. 从栈顶读取返回值并转换为 RuntimeValue

补充：当前工程在 `pCall` 时使用 `nresults=1`，即主流程按“单返回值”约定取回结果

此外，宿主会将 cangjiePrintln 注入为全局 println，实现脚本输出与测试捕获共用

---

## 8. 工程实现注意事项

1. 栈纪律
   - 调用前后应保持栈平衡
   - 错误对象通常位于栈顶，读取后可及时 pop

2. 字符串生命周期
   - 传入 C API 的 CString 必须在调用后释放

3. 原始数组句柄
   - loadBytecode 时 acquireArrayRawData 与 releaseArrayRawData 必须成对出现

4. 跳转偏移
   - 所有回填偏移都以“当前 PC 相对偏移”计算，注意减 1 的实现细节

5. 比较结果布尔化
   - 通过 LOADFALSE + 比较 + JMP + LOADTRUE 保证结果显式为 Bool

6. 指令子集
   - 虽然文档列出 Lua 5.5 全部 85 条操作码，但本工程实际仅使用其中一部分
   - 例如算术、比较、跳转、调用、返回、闭包、表访问等
   - 其余操作码当前主要用于保持枚举完整性与后续扩展

---

## 9. 小结

该工程的 VM 层设计可概括为：

- 接口层：Lua C API 的最小充分封装
- 编码层：与 Lua 5.5 指令格式严格对齐
- 运行层：受保护调用、错误可诊断、资源可控释放

在此基础上，Cangjie 前端只需专注语义与代码生成，即可稳定复用 Lua VM 作为执行后端
