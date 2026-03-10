# CangjieLua 扩展开发指南

本文档为 AI 编程大赛选手提供项目理解、环境搭建、开发流程和调试技巧等方面的指导。

---

## 一、项目架构总览

### 1.1 编译执行流水线

```
仓颉源码 (.scj)
    │
    ▼
┌─────────┐     ┌─────────┐     ┌──────────────┐     ┌───────────────┐
│  Lexer  │ ──▶ │ Parser  │ ──▶ │ CodeGenerator│ ──▶ │  ChunkWriter  │
│ 词法分析 │     │ 语法分析 │     │  字节码生成   │     │ 二进制序列化   │
└─────────┘     └─────────┘     └──────────────┘     └───────┬───────┘
                                                             │
                                                    Lua 5.5 字节码
                                                      (Array<UInt8>)
                                                             │
                                                             ▼
                                                    ┌───────────────┐
                                                    │   LuaVM (FFI)  │
                                                    │ 加载并执行字节码 │
                                                    └───────────────┘
```

### 1.2 源码目录说明

```
src/
├── main.cj                    # 程序入口，运行测试
├── cangjie_lua.cj             # 编译器主控：串联 Lexer→Parser→CodeGen→LuaVM
├── tester.cj                  # 测试框架：解析注释断言，自动验证
├── lexer/
│   ├── lexer.cj               # 词法分析器：UTF-8 字节扫描，生成 Token 序列
│   └── token.cj               # Token 和 TokenType 定义
├── parser/
│   ├── parser.cj              # 递归下降解析器：Token → AST
│   └── ast.cj                 # AST 节点定义（Expr、Stmt、BinaryOp）
├── codegen/
│   ├── code_generator.cj      # 代码生成器：AST → Lua 字节码指令
│   ├── bytecode.cj            # 操作码枚举和指令编码函数
│   └── chunk_writer.cj        # 二进制块序列化器
├── luavm/
│   └── ffi.cj                 # Lua C API 的仓颉 FFI 绑定
├── runtime/
│   ├── runtime_value.cj       # 运行时值类型
│   └── print_runtime.cj       # 输出捕获机制
└── errors/
    └── errors.cj              # 错误模型
```

### 1.3 模块间数据流

| 阶段 | 输入 | 输出 | 关键文件 |
|------|------|------|----------|
| 词法分析 | 源码字符串 `String` | `ArrayList<Token>` | `lexer.cj` |
| 语法分析 | `ArrayList<Token>` | `ArrayList<Stmt>` | `parser.cj`, `ast.cj` |
| 代码生成 | `ArrayList<Stmt>` | `Array<UInt8>` (字节码) | `code_generator.cj`, `bytecode.cj`, `chunk_writer.cj` |
| 执行 | `Array<UInt8>` | `RuntimeValue` | `ffi.cj`, `cangjie_lua.cj` |

---

## 二、环境搭建

### 2.1 获取仓颉 SDK

```bash
# 下载仓颉 SDK
wget https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz
tar xzf cangjie-sdk-linux-x64-1.0.5.tar.gz

# 设置环境变量
source cangjie/envsetup.sh

# 验证安装
cjc --version
cjpm --version
```

### 2.2 构建项目

```bash
cd CangjieLua

# 构建
cjpm build

# 运行所有测试
cjpm run

# 运行单个测试
cjpm run --run-args tests/01_return_constant.scj
```

### 2.3 构建 Lua 完整版本（可选，用于调试）

```bash
cd luavm/src
cmake .
make -j4

# 生成的文件：
# - libluavm.so     独立 VM 动态库（项目使用）
# - liblua.a        完整 Lua 静态库（含解析器）
# - lua             完整 Lua 解释器（可用于调试）
```

---

## 三、开发流程

### 3.1 添加新语言特性的标准流程

以添加新运算符 `%`（取模）为例：

#### 步骤 1：先写测试用例

在 `tests/` 目录下创建测试文件：

```
// tests/131_modulo.scj
// Test 131: Modulo operator
println(10 % 3)
println(15 % 4)
// Expected: 1, 3
```

#### 步骤 2：修改词法分析器

在 `src/lexer/token.cj` 中添加 token 类型：

```cangjie
public enum TokenType {
    // ... 现有类型
    | PERCENT       // %
}
```

在 `src/lexer/lexer.cj` 的 `nextToken()` 中添加字符处理：

```cangjie
0x25 =>  // '%' 字符
    advance()
    return Token(TokenType.PERCENT, "%", line)
```

#### 步骤 3：修改 AST

在 `src/parser/ast.cj` 的 `BinaryOp` 中添加：

```cangjie
public enum BinaryOp {
    // ... 现有运算符
    | MOD  // %
}
```

#### 步骤 4：修改解析器

在 `src/parser/parser.cj` 的 `parseMultiplication()` 中添加 `%` 的处理：

```cangjie
while (match(TokenType.STAR) || match(TokenType.SLASH) || match(TokenType.PERCENT)) {
    let op = match ... {
        // ...
        case TokenType.PERCENT => BinaryOp.MOD
    }
    // ...
}
```

#### 步骤 5：修改代码生成器

在 `src/codegen/code_generator.cj` 的 `generateExpr()` 中添加：

```cangjie
case BinaryOp.MOD =>
    emitABC(OpCodes.MOD, dest, leftReg, rightReg)
    emitABC(OpCodes.MMBIN, leftReg, rightReg, 10u32)  // MM_MOD = 10
```

#### 步骤 6：运行测试

```bash
# 运行新测试
cjpm run --run-args tests/131_modulo.scj

# 运行所有测试确保没有回归
cjpm run
```

### 3.2 提交前检查清单

- [ ] 新功能有对应的 `.scj` 测试文件
- [ ] 所有现有 130 个测试仍然通过
- [ ] 错误情况有 `// ExpectError` 测试覆盖
- [ ] 代码风格与现有代码一致

---

## 四、测试框架使用

### 4.1 断言语法

测试文件使用注释驱动的断言：

```cangjie
// Expected: value1, value2, value3     ← 验证 println 输出（逗号或 then 分隔）
// ExpectedReturn: value                ← 验证返回值
// ExpectError: substring               ← 期望包含 substring 的错误
// ExpectError                          ← 期望任何错误
```

### 4.2 值比较规则

- 浮点数容差：`|a - b| < 0.001`
- 整数/浮点等价：`7 ≈ 7.0`（数值相等即可）
- 布尔值：精确匹配 `true`/`false`
- nil：精确匹配 `nil`
- 字符串：精确匹配

### 4.3 输出格式

- `println(42)` → 输出 `42`
- `println(3.14)` → 输出 `3.140000`（Lua 默认浮点格式）
- `println(true)` → 输出 `true`
- `println(false)` → 输出 `false`

### 4.4 创建测试文件的建议

1. 文件名格式：`NNN_feature_name.scj`（NNN 为三位数字编号）
2. 从 131 开始编号（现有测试到 130）
3. 每个测试文件聚焦一个功能点
4. 同时测试正常路径和错误路径

---

## 五、关键实现细节

### 5.1 常量表管理

代码生成器维护三种常量：

```cangjie
enum Constant {
    | IntNumber(Int64)      // 整数常量，二进制格式标签 0x03
    | FloatNumber(Float64)  // 浮点常量，二进制格式标签 0x13
    | Str(String)           // 字符串常量，二进制格式标签 0x04
}
```

常量去重通过 `HashMap<String, Int64>` 实现，键格式：
- 整数：`"int_${value}"`
- 浮点：`"flt_${value}"`
- 字符串：`"str_${value}"`

### 5.2 寄存器分配

- 局部变量按声明顺序分配连续寄存器（从 R[0] 开始）
- 函数参数占据前 N 个寄存器
- 临时值使用 `currentStack` 之后的寄存器
- `maxStack` 跟踪最大使用深度（写入函数头部的 `maxstacksize`）

### 5.3 跳转回填

`if` 和 `while` 的条件跳转使用回填技术：

```cangjie
// 1. 发射占位跳转（偏移量为 0）
let jmpIdx = instructions.size
emitIsJ(OpCodes.JMP, 0)

// 2. 生成后续指令...

// 3. 回填实际偏移量
let actualOffset = Int32(instructions.size - jmpIdx - 1)
instructions[jmpIdx] = encodeIsJ(OpCodes.JMP, actualOffset)
```

### 5.4 函数编译

函数编译使用独立的 `CodeGenerator` 实例：

```cangjie
// 创建子生成器
let funcGen = CodeGenerator()
funcGen.generateFunction(params, body)

// 保存为函数原型
let funcIdx = functions.size
functions.add(FunctionProto(name, funcGen, params.size))

// 在主函数中创建闭包并注册
emitABx(OpCodes.CLOSURE, reg, UInt32(funcIdx))      // 创建闭包
emitABC(OpCodes.SETTABUP, 0, K["name"], reg)         // 注册到 _ENV
```

### 5.5 全局变量与 _ENV

所有全局变量通过 `_ENV` 表访问：
- **读取**：`GETTABUP R[dest], UpValue[0], K["varName"]`
- **写入**：`SETTABUP UpValue[0], K["varName"], R[src]`

`_ENV` 是每个函数的第一个上值（upvalue[0]）：
- main 函数：`instack=1, idx=0`（直接在栈上）
- 子函数：`instack=0, idx=0`（从父函数上值继承）

### 5.6 错误处理模式

项目使用 `Option<T>` + `CompileError` 模式，不使用异常：

```cangjie
// 设置错误
_error = CompileError(ErrorStage.PARSER, "unexpected token", line)
return None

// 检查错误
if (_error != None) {
    return None
}
```

---

## 六、调试技巧

### 6.1 字节码调试

可以使用完整版 Lua 解释器验证字节码行为：

```bash
cd luavm/src

# 编译 Lua 代码为字节码并查看
echo 'return 42' | ./lua -e "
local f = load(io.read('*a'))
local bc = string.dump(f)
print('bytecode bytes:', #bc)
for i = 1, #bc do
  io.write(string.format('%02x ', bc:byte(i)))
  if i % 16 == 0 then print() end
end
print()
"
```

### 6.2 字节码十六进制分析

```
Lua 5.5 头部（固定）:
1b 4c 75 61                    # 魔数 \x1bLua
55                             # 版本 5.5
00                             # 格式 0
19 93 0d 0a 1a 0a              # 校验数据
04 xx xx xx xx                 # sizeof(int)=4 + 校验值
04 78 56 34 12                 # sizeof(Instruction)=4 + 校验值
08 xx xx xx xx xx xx xx xx     # sizeof(Integer)=8 + 校验值
08 xx xx xx xx xx xx xx xx     # sizeof(Number)=8 + 校验值
01                             # 上值数量=1

函数原型:
xx                             # linedefined (VarInt)
xx                             # lastlinedefined (VarInt)
xx                             # numparams
xx                             # is_vararg
xx                             # maxstacksize
xx                             # 指令数量 (VarInt)
[00]                           # 对齐填充
xx xx xx xx                    # 指令 0 (4字节, 小端序)
xx xx xx xx                    # 指令 1
...
xx                             # 常量数量 (VarInt)
xx [data]                      # 常量 0 (类型标签 + 数据)
...
xx                             # 上值数量 (VarInt)
xx xx xx                       # 上值 0 (instack, idx, kind)
...
```

### 6.3 指令解码

将 32 位小端序十六进制指令解码为操作码和操作数：

```
指令字节: xx xx xx xx (小端序)
→ 32位值: 将4字节按小端序组合

操作码: value & 0x7F               (低7位)
A 字段: (value >> 7) & 0xFF        (8位)
k 标志: (value >> 15) & 0x1        (1位)
B 字段: (value >> 16) & 0xFF       (8位)
C 字段: (value >> 24) & 0xFF       (8位)

对于 iABx:
Bx 字段: (value >> 15) & 0x1FFFF   (17位)

对于 iAsBx:
sBx 字段: ((value >> 15) & 0x1FFFF) - 65535  (有符号)

对于 isJ:
sJ 字段: ((value >> 7) & 0x1FFFFFF) - 16777215  (有符号)
```

**示例**：解码 `53 00 00 00`

```
32位值 = 0x00000053
操作码 = 0x53 & 0x7F = 83 = VARARGPREP
A = 0, Bx = 0
→ VARARGPREP 0, 0
```

### 6.4 打印调试

在代码生成器中添加临时调试输出：

```cangjie
// 在 generateExpr() 中添加
println("DEBUG: generating expr for ${expr}")
println("DEBUG: dest=${dest}, currentStack=${currentStack}")
```

构建后运行单个测试查看输出：

```bash
cjpm run --run-args tests/your_test.scj
```

### 6.5 常见问题排查

| 问题 | 可能原因 | 排查方法 |
|------|----------|----------|
| 字节码加载失败 | 头部格式错误 | 与标准 Lua 字节码对比头部 |
| 运行时错误 | 指令编码错误 | 检查操作码值和字段偏移 |
| 寄存器错误 | 栈分配冲突 | 打印 currentStack/maxStack |
| 全局变量未找到 | 常量表索引错误 | 检查 addConstantString 返回值 |
| 函数调用失败 | CALL 参数数量错误 | 检查 B（nargs+1）和 C 字段 |
| 跳转偏移错误 | 回填计算错误 | 打印 jmpIdx 和 targetIdx |

---

## 七、扩展 FFI 接口

当需要调用 `luavm/exports.txt` 中列出但尚未在 `ffi.cj` 中声明的函数时：

### 7.1 添加 foreign 声明

```cangjie
// 在 src/luavm/ffi.cj 的 foreign { } 块中添加
foreign {
    // ... 现有声明

    // 新增：表遍历
    func lua_next(L: CPointer<Unit>, idx: Int32): Int32

    // 新增：原始表操作
    func lua_rawget(L: CPointer<Unit>, idx: Int32): Int32
    func lua_rawset(L: CPointer<Unit>, idx: Int32): Unit
    func lua_rawgeti(L: CPointer<Unit>, idx: Int32, n: Int64): Int32
    func lua_rawseti(L: CPointer<Unit>, idx: Int32, n: Int64): Unit
}
```

### 7.2 添加 LuaState 包装方法

```cangjie
// 在 LuaState 类中添加
public func next(idx: Int32): Int32 {
    unsafe {
        return lua_next(state, idx)
    }
}

public func rawGet(idx: Int32): Int32 {
    unsafe {
        return lua_rawget(state, idx)
    }
}
```

### 7.3 C 类型映射参考

| C 类型 | 仓颉类型 | 说明 |
|--------|----------|------|
| `int` | `Int32` | 32 位有符号整数 |
| `unsigned int` | `UInt32` | 32 位无符号整数 |
| `size_t` | `UIntNative` | 平台相关的无符号整数 |
| `lua_Integer` | `Int64` | 64 位有符号整数 |
| `lua_Number` | `Float64` | 64 位浮点数 |
| `const char*` | `CString` | C 字符串 |
| `lua_State*` | `CPointer<Unit>` | 不透明指针 |
| `void*` | `CPointer<Unit>` | 通用指针 |
| `lua_CFunction` | `CFunc<(CPointer<Unit>) -> Int32>` | C 函数指针 |

### 7.4 注册自定义 C 函数

```cangjie
// 定义 C 函数（用于 Lua 回调）
let myFunction: CFunc<(CPointer<Unit>) -> Int32> = { rawState: CPointer<Unit> =>
    let state = LuaState(rawState)
    // 从栈上获取参数
    let arg1 = state.toNumber(-1)
    // 计算结果
    let result = arg1 * 2.0
    // 将结果压入栈
    state.pushNumber(result)
    // 返回值数量
    return 1
}

// 注册到全局环境
state.pushCFunction(myFunction)
state.setGlobal("myFunction")
```

---

## 八、仓颉语言速查

以下列出本项目中用到的仓颉语言核心语法，供不熟悉仓颉语言的选手参考。

### 8.1 变量声明

```cangjie
let x = 10          // 不可变变量
var y = 20          // 可变变量
let z: Int64 = 30   // 带类型注解
```

### 8.2 函数定义

```cangjie
func add(a: Int64, b: Int64): Int64 {
    return a + b
}
```

### 8.3 控制流

```cangjie
if (condition) {
    // ...
} else {
    // ...
}

while (condition) {
    // ...
}

for (i in 0..10) {
    // ...
}
```

### 8.4 枚举与模式匹配

```cangjie
enum Color {
    | Red
    | Green
    | Blue(Int64)
}

match (color) {
    case Color.Red => "red"
    case Color.Green => "green"
    case Color.Blue(v) => "blue ${v}"
}
```

### 8.5 类

```cangjie
class MyClass {
    private var value: Int64

    public init(v: Int64) {
        value = v
    }

    public func getValue(): Int64 {
        return value
    }
}
```

### 8.6 集合

```cangjie
import std.collection.*

let list = ArrayList<Int64>()
list.add(1)
list.add(2)

let map = HashMap<String, Int64>()
map["key"] = 42
```

### 8.7 Option 类型

```cangjie
let x: ?Int64 = Some(42)
let y: ?Int64 = None

if (let Some(v) <- x) {
    println(v)
}
```

### 8.8 unsafe 与 FFI

```cangjie
foreign {
    func c_function(arg: Int32): Int32
}

unsafe {
    let result = c_function(42)
}
```

---

## 九、常见扩展模式

### 9.1 添加新的一元运算符

```
词法分析器: 添加 token → 解析器: parseUnary() → 代码生成器: 生成对应指令

示例指令: UNM(取负), BNOT(按位取反), NOT(逻辑非), LEN(取长度)
```

### 9.2 添加新的二元运算符

```
词法分析器: 添加 token → 解析器: 在对应优先级层处理 → AST: 添加 BinaryOp 分支
→ 代码生成器: 生成对应指令 + MMBIN 回退

优先级从低到高:
  逻辑或 (||) → 逻辑与 (&&) → 比较 (==,!=,<,<=,>,>=)
  → 位或 (|) → 位异或 (^) → 位与 (&)
  → 移位 (<<,>>) → 加减 (+,-) → 乘除模 (*,/,%)
  → 幂 (**) → 一元 (-,!,~)
```

### 9.3 添加新的语句类型

```
词法分析器: 添加关键字 → 解析器: 在 parseStatement() 中添加分支
→ AST: 添加 Stmt 枚举分支 → 代码生成器: 在 generateStatement() 中处理
```

### 9.4 添加新的内置函数

```cangjie
// 在 cangjie_lua.cj 的 run() 方法中，LuaState 初始化后添加：
let myBuiltin: CFunc<(CPointer<Unit>) -> Int32> = { rawState: CPointer<Unit> =>
    let s = LuaState(rawState)
    // 获取参数、计算、返回
    return 1  // 返回值数量
}
state.pushCFunction(myBuiltin)
state.setGlobal("myBuiltinName")
```

---

## 十、参考资源

1. **Lua 5.5 源码**：`luavm/src/` 目录下的 C 源码
2. **Lua 5.4 参考手册**：https://www.lua.org/manual/5.4/（5.5 为开发版，大部分兼容）
3. **仓颉语言文档**：通过 `cangjie-*` skills 获取
4. **项目 README**：`README.md` 中有详细的架构说明
5. **字节码文档**：`docs/luavm_bytecode.md` 中有完整的指令集说明
6. **任务书**：`docs/task.md` 中有所有扩展任务说明

---

## 十一、FAQ

**Q: 如何知道某个 Lua 操作码的正确用法？**

A: 查看 `luavm/src/lopcodes.h` 中的注释，以及 `lvm.c` 中的 VM 执行逻辑。也可以用完整版 Lua 编译一段等价代码，用 `string.dump` 获取字节码进行对比。

**Q: 为什么每个算术指令后都需要 MMBIN？**

A: Lua 5.5 的设计要求——如果算术操作成功（操作数都是数字），MMBIN 会被跳过；如果操作数需要元方法处理（如自定义类型），MMBIN 会调用相应的元方法。即使当前不使用元方法，字节码格式也要求包含。

**Q: 字节码加载失败怎么办？**

A: 最常见的原因是头部格式错误。使用十六进制编辑器对比你生成的字节码和标准 Lua 字节码的头部。确保版本号、校验值、类型大小等字段正确。

**Q: 如何处理 CangjieLua 中还不支持的仓颉语法？**

A: 在词法分析阶段会报 "unexpected character" 错误，或在解析阶段报 "unexpected token" 错误。你需要从词法分析器开始逐层添加支持。

**Q: 测试文件中的 `Expected` 注释支持哪些格式？**

A: 
- `// Expected: val1, val2` — 逗号分隔多个预期输出
- `// Expected: val1 then val2` — "then" 分隔多个预期输出
- `// ExpectedReturn: val` — 验证返回值
- `// ExpectError: msg` — 期望错误包含 msg
- 数值支持整数和浮点格式，布尔值为 `true`/`false`，空值为 `nil`
