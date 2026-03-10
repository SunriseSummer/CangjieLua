# CangjieLua 解释器实现说明

> 仓颉语言团队 刘俊杰  Powered by AI

使用仓颉语言实现仓颉语言子集的解释器，生成 Lua 虚拟机字节码，并通过 C 互操作集成调用 LuaVM 以执行字节码。

---

## 1. 项目定位

CangjieLua 不是“逐条解释执行 AST”的传统解释器，而是采用 **前端编译 + 字节码执行** 的路线：

- 前端：词法分析、语法分析、轻量语义检查
- 中端：AST 到 LuaVM 字节码生成
- 后端：序列化为 Lua 5.5 二进制 chunk
- 运行时：通过 FFI 调用 Lua VM 加载并执行

这种设计让项目同时具备教学价值（编译管线完整）与工程价值（复用 Lua VM 高性能运行时）

---

## 2. 顶层架构

核心入口与模块如下：

- [src/main.cj](src/main.cj)：程序入口，驱动测试执行
- [src/cangjie_lua.cj](src/cangjie_lua.cj)：编译/执行总控接口 `CangjieLua.run(source)`
- [src/lexer](src/lexer)：词法分析
- [src/parser](src/parser)：递归下降语法分析与 AST
- [src/codegen](src/codegen)：Lua 指令生成与二进制 chunk 写入
- [src/luavm/ffi.cj](src/luavm/ffi.cj)：Lua C API 的 FFI 封装
- [src/runtime](src/runtime)：运行值模型与输出捕获
- [src/errors/errors.cj](src/errors/errors.cj)：统一错误模型
- [src/tester.cj](src/tester.cj)：注释驱动测试框架

`cjpm.toml` 中通过 `[ffi.c]` 将本地 `luavm` C 代码接入构建链路

---

## 3. 端到端执行流程

`CangjieLua.run()` 的流程可概括为：

1. `Lexer.tokenize()` 将源码转为 Token 序列
2. `Parser.parse()` 生成 AST 语句列表
3. `CodeGenerator.generate()` 产出 Lua 字节码数组 `Array<UInt8>`
4. `LuaState.loadBytecode()` 加载字节码
5. `LuaState.pCall()` 执行主函数并取回返回值
6. 将 Lua 栈顶值转换为 `RuntimeValue`

关键特点：

- 所有阶段错误均以 `Option` + `CompileError` 传播，不依赖抛异常
- 运行前将宿主函数 `println` 注入 Lua 全局环境，实现可测试输出

---

## 4. 词法分析器设计（Lexer）

参考 [src/lexer/lexer.cj](src/lexer/lexer.cj)

### 4.1 扫描策略

- 基于 UTF-8 字节序列顺序扫描
- 使用 `currentByte` + `peek()` 处理一字符前瞻
- 记录 `line` 用于定位错误

### 4.2 支持的词法单元

参考 [src/lexer/token.cj](src/lexer/token.cj)

- 字面量：`NUMBER`（整数/浮点统一词法入口）
- 标识符与关键字：`let var if else while func return true false`
- 运算符：`+ - * / == != < <= > >= =`
- 分隔符：`() {} , :`

### 4.3 注释与空白

- 支持 `//` 单行注释
- 跳过空格、制表符、回车
- 换行会更新行号计数

### 4.4 错误处理

遇到非法字符或非法数值字面量时，返回 `None` 并设置 `CompileError(ErrorStage.LEXER, ...)`

---

## 5. 语法分析与 AST（Parser）

参考 [src/parser/parser.cj](src/parser/parser.cj) 与 [src/parser/ast.cj](src/parser/ast.cj)

### 5.1 语法风格

采用递归下降，按优先级分层：

- `expression -> comparison`
- `comparison -> addition ((==|!=|<|<=|>|>=) addition)*`
- `addition -> multiplication ((+|-) multiplication)*`
- `multiplication -> unary ((*|/) unary)*`
- `unary -> -unary | primary`

### 5.2 语句与声明

- 变量声明：`let/var name = expr`
- 赋值语句：`name = expr`
- 条件语句：`if (...) { ... } else { ... }`
- 循环语句：`while (...) { ... }`
- 函数声明：`func f(x: Int64, y: Float64): Bool { ... }`
- 返回语句：`return expr`

### 5.3 轻量语义校验

Parser 内部维护简单类型推断映射，用于前置约束：

- `if` / `while` 条件必须推断为 `Bool`
- 函数参数必须显式类型标注（缺失即报错）
- 函数返回类型可选，当前用于轻量推断辅助

这是一种“解析期约束”，并非完整静态类型系统

### 5.4 一元负号处理

- 对字面量执行常量折叠：`-3`、`-3.5`
- 对一般表达式退化为 `0 - expr`

---

## 6. 字节码生成（CodeGen）

参考 [src/codegen/code_generator.cj](src/codegen/code_generator.cj)

### 6.1 生成器职责

- 常量池管理（整数、浮点、字符串去重）
- 局部变量与寄存器分配
- 控制流跳转回填（`if` / `while`）
- 主函数与子函数原型序列化

### 6.2 指令选择策略

#### 算术

- 使用 `ADD/SUB/MUL/DIV`
- 每条算术指令后跟 `MMBIN`，与 Lua 元方法回退机制兼容

#### 比较

- 使用 Lua 原生比较指令 `EQ/LT/LE`
- `>` 与 `>=` 通过交换左右操作数复用 `LT/LE`
- 统一布尔产出模板：
  1. 先 `LOADFALSE`
  2. 比较 + 条件跳转
  3. 满足时 `LOADTRUE`

#### 控制流

- `if` 与 `while` 均采用 `TEST + JMP` 模板
- 通过记录指令索引并在末尾回填相对偏移

### 6.3 函数与作用域

- 函数声明会生成子函数原型并通过 `CLOSURE` 构造闭包
- 再 `SETTABUP` 写入 `_ENV`，使函数可按全局名调用
- 局部变量优先寄存器访问，不命中时回退全局表

---

## 7. Lua 5.5 二进制 chunk 序列化

参考：

- [src/codegen/bytecode.cj](src/codegen/bytecode.cj)
- [src/codegen/chunk_writer.cj](src/codegen/chunk_writer.cj)

### 7.1 Header

按 Lua 5.5 规范写入：

- `LUA_SIGNATURE`
- 版本与格式号
- `LUAC_DATA`
- 整数/指令/整数64/浮点的校验值与尺寸信息

### 7.2 指令编码

支持 `iABC / iABx / iAsBx / isJ` 等布局，封装为 `encodeABC/ABx/AsBx/IsJ/ABCK`

### 7.3 数据写入细节

- 指令按 4 字节对齐写入
- 常量表含类型标签与对应编码
- 字符串采用 Lua 兼容长度前缀格式
- 整数写入使用 VarInt 方案

---

## 8. Lua VM FFI 与执行层

参考 [src/luavm/ffi.cj](src/luavm/ffi.cj)

### 8.1 封装方式

- `foreign {}` 声明 Lua C API
- `LuaState` 提供更安全的对象化包装（创建、关闭、压栈、取值、调用）

### 8.2 执行关键点

- `loadBytecode` 只以二进制模式加载
- `pCall` 使用受保护调用，错误信息留在 Lua 栈
- 执行完成后主动 GC 并关闭状态机

### 8.3 宿主函数注入

`cangjiePrintln` 注册为 Lua 全局 `println`：

- 打印到宿主标准输出
- 同步写入 `PrintRuntime` 捕获缓冲，用于测试断言

---

## 9. 运行值与错误模型

### 9.1 运行值模型

参考 [src/runtime/runtime_value.cj](src/runtime/runtime_value.cj)

`RuntimeValue` 统一表示跨阶段结果：

- `IntValue(Int64)`
- `FloatValue(Float64)`
- `BoolValue(Bool)`
- `NilValue`
- `TextValue(String)`

### 9.2 错误模型

参考 [src/errors/errors.cj](src/errors/errors.cj)

- `ErrorStage`：`LEXER | PARSER | RUNTIME | IO`
- `CompileError`：阶段 + 文本 + 行号
- 全流程通过 `Option` 返回错误，避免异常链路污染主流程

---

## 10. 测试框架设计

参考 [src/tester.cj](src/tester.cj)

### 10.1 测试输入来源

- 默认扫描 `tests/*.scj`
- 文件名按序执行，便于渐进覆盖

### 10.2 注释驱动断言

支持三类注释：

- `// Expected: ...` 断言输出序列
- `// ExpectedReturn: ...` 断言返回值
- `// ExpectError[: substring]` 断言出错及错误消息片段

优先级规则：

1. 若有 `ExpectError`，先走错误断言
2. 否则校验执行成功
3. 再按需校验输出与返回值

### 10.3 数值与类型比较

- 支持 `Int/Float/Bool/Nil/Text` 的类型化比较
- 浮点比较使用 `EPSILON` 容差

---

## 11. 当前语言能力边界

### 已支持

- 数值运算：`+ - * /`
- 比较运算：`== != < <= > >=`
- 一元负号
- 变量声明与赋值
- `if / else`、`while`
- 函数定义、函数调用、参数与可选返回类型注解
- `println` 输出与 `return`
- `Bool` 条件约束

### 暂未实现（可作为扩展方向）

- 完整静态类型系统与类型检查
- 复杂数据结构（数组、对象字面量等）
- 更丰富标准库与模块系统
- 更细粒度调试信息写回 chunk

---

## 12. 如何运行

### 构建

在工程根目录执行：

- `cjpm build`

### 测试

- 全量测试：`cjpm run`
- 指定测试文件：`cjpm run --run-args tests/xx_xxx.scj`

---

## 13. 典型样例

```cangjie
func add(a: Int64, b: Int64): Int64 {
    return a + b
}

let x = add(3, 4)
println(x)
return x
```

该程序会经历：

1. 词法拆分为 Token
2. 语法构建为 `FuncDecl + VarDecl + ExprStmt + ReturnStmt`
3. 生成 Lua 指令与常量表
4. 序列化为 chunk
5. Lua VM 执行并返回 `RuntimeValue.IntValue(7)`

---

## 14. 设计总结

CangjieLua 的核心价值在于：

- 结构上完整覆盖“前端解析 -> 后端字节码 -> 虚拟机执行”的闭环
- 工程上采用清晰模块边界与统一错误模型
- 测试上采用声明式注释断言，便于快速扩展案例库

如果将其继续演进，可优先投入：

1. 语义层（更强类型系统）
2. 语言层（更多语法能力）
3. 工具层（AST/IR 可视化、调试支持）

这样可以在保持当前架构稳定性的前提下，持续提升表达力与可维护性
