# CangjieLua 扩展开发任务书

本任务书为 AI 编程大赛选手提供细粒度的仓颉语言特性扩展任务。每个任务对应一个具体的语言特性，包含特性描述、示例代码、期望效果和实现提示。选手完成任务后，根据任务分值计算总分。

---

## 评分规则

- 每个任务有固定分值（⭐表示，1~5 星）
- 必须通过对应的测试用例才算完成
- 测试用例使用项目现有的 `.scj` 测试框架（注释驱动断言）
- 部分完成不计分，必须完整实现
- 所有实现不能破坏现有的 130 个测试用例

---

## 任务列表

### 任务 1：字符串字面量支持 ⭐⭐

**分值**：20 分

**特性描述**：支持用双引号定义字符串字面量，并能在表达式中使用。

**示例代码**：
```cangjie
let greeting = "hello"
println(greeting)
return "world"
// Expected: hello
// ExpectedReturn: world
```

**期望效果**：
- 词法分析器能识别双引号字符串
- 解析器生成 `StringLiteral` AST 节点
- 代码生成器将字符串存入常量表，用 `LOADK` 加载

**实现提示**：
1. **词法分析器**（`lexer.cj`）：添加 `STRING` 类型到 `TokenType`，在 `nextToken()` 中处理双引号，调用新的 `readString()` 方法扫描到结束引号
2. **Token 类**：添加 `stringValue: String` 字段或复用 `text` 字段存储字符串内容
3. **AST**（`ast.cj`）：在 `Expr` 枚举中添加 `StringLiteral(String)` 分支
4. **解析器**（`parser.cj`）：在 `parsePrimary()` 中处理 `STRING` token
5. **代码生成器**（`code_generator.cj`）：在 `generateExpr()` 中处理 `StringLiteral`，调用 `addConstantString()` 添加到常量表，使用 `LOADK` 指令加载

**验证测试**：
```cangjie
let s = "hello world"
println(s)
// Expected: hello world
```

---

### 任务 2：字符串拼接运算符 ⭐⭐

**分值**：20 分

**特性描述**：支持 `+` 运算符用于字符串拼接（仓颉语言使用 `+` 拼接字符串）。

**示例代码**：
```cangjie
let a = "hello"
let b = " world"
let c = a + b
println(c)
// Expected: hello world
```

**期望效果**：
- 当 `+` 运算符的操作数为字符串时，使用 Lua 的 `CONCAT` 指令而非 `ADD`

**实现提示**：
1. 需要在代码生成阶段区分数字加法和字符串拼接
2. 可通过简单的类型推断（检查操作数是否为 `StringLiteral`）或直接生成通用代码
3. Lua 的 `CONCAT` 指令格式：`CONCAT A B` —— 连接 R[A] 到 R[A+B-1] 共 B 个值
4. 也可以使用 Lua 的 `..` 对应的元方法机制

---

### 任务 3：十六进制整数字面量 ⭐

**分值**：10 分

**特性描述**：支持十六进制整数字面量，使用 `0x` 或 `0X` 前缀表示。

**示例代码**：
```cangjie
println(0xFF)
println(0x1A)
// Expected: 255, 26
```

**期望效果**：
- 词法分析器能识别 `0x`/`0X` 前缀的十六进制整数
- 支持 0-9、a-f、A-F 数字字符

**实现提示**：
1. **词法分析器**（`lexer.cj`）：在 `readNumber()` 中，当读到 `0` 后检查下一个字符是否为 `x` 或 `X`
2. 检测到前缀后，循环读取十六进制数字字符（0-9、a-f、A-F）
3. 将十六进制字符串转换为整数值
4. 生成与普通数字相同的 `NUMBER` token

---

### 任务 4：下划线数字分隔符 ⭐

**分值**：10 分

**特性描述**：支持在数字字面量中使用下划线 `_` 作为视觉分隔符，提升大数字的可读性。仓颉语言支持此特性。

**示例代码**：
```cangjie
println(1_000_000)
println(3.14_159)
// Expected: 1000000, 3.14159
```

**期望效果**：
- 数字中的下划线不影响数值
- 支持整数和浮点数中的下划线

**实现提示**：
1. **词法分析器**（`lexer.cj`）：在 `readNumber()` 方法中，遇到下划线 `_` 时跳过，不计入数字字符串
2. 下划线不能出现在数字的开头或结尾（可选校验）
3. 将去除下划线后的数字字符串正常转换为数值

---

### 任务 5：逻辑运算符 `&&` 和 `||` ⭐⭐⭐

**分值**：30 分

**特性描述**：支持短路逻辑运算符 `&&`（逻辑与）和 `||`（逻辑或）。

**示例代码**：
```cangjie
let a = true
let b = false
println(a && b)
println(a || b)
println(false || true)
println(true && true)
// Expected: false, true, true, true
```

**期望效果**：
- `&&` 短路求值：左操作数为 false 时不计算右操作数
- `||` 短路求值：左操作数为 true 时不计算右操作数

**实现提示**：
1. **词法分析器**：添加 `AND`（`&&`）和 `OR`（`||`）token 类型
2. **AST**：在 `BinaryOp` 中添加 `AND` 和 `OR`
3. **解析器**：在运算符优先级中添加 `&&` 和 `||`（优先级低于比较运算符）
4. **代码生成器**：
   - `||`：使用 `TESTSET` 指令实现短路。计算左操作数，若为 true 则跳过右操作数
   - `&&`：类似，若为 false 则跳过右操作数
   - 也可以使用 `TEST + JMP` 组合实现

---

### 任务 6：逻辑非运算符 `!` ⭐

**分值**：10 分

**特性描述**：支持一元逻辑非运算符 `!`。

**示例代码**：
```cangjie
println(!true)
println(!false)
let x = true
println(!x)
// Expected: false, true, false
```

**期望效果**：
- `!` 将布尔值取反

**实现提示**：
1. **词法分析器**：添加 `BANG`（`!`）token 类型
2. **解析器**：在 `parseUnary()` 中处理 `!`
3. **代码生成器**：使用 `NOT` 指令（OpCode 51）：`NOT A B` → `R[A] := not R[B]`

---

### 任务 7：取模运算符 `%` ⭐

**分值**：10 分

**特性描述**：支持取模运算符。

**示例代码**：
```cangjie
println(10 % 3)
println(15 % 4)
// Expected: 1, 3
```

**期望效果**：
- `%` 运算符计算整数或浮点数的余数

**实现提示**：
1. **词法分析器**：添加 `PERCENT`（`%`）token 类型
2. **AST**：在 `BinaryOp` 中添加 `MOD`
3. **解析器**：在 `parseMultiplication()` 中与 `*`、`/` 同优先级处理 `%`
4. **代码生成器**：使用 `MOD` 指令（OpCode 37）+ `MMBIN` 元方法回退（MM_MOD=10）

---

### 任务 8：幂运算符 `**` ⭐⭐

**分值**：20 分

**特性描述**：支持幂运算符 `**`。

**示例代码**：
```cangjie
println(2 ** 10)
println(3.0 ** 2.0)
// Expected: 1024, 9.0
```

**期望效果**：
- `**` 计算幂运算

**实现提示**：
1. **词法分析器**：识别 `**`（两个连续 `*`）为 `POWER` token
2. **AST**：在 `BinaryOp` 中添加 `POW`
3. **解析器**：幂运算优先级高于乘除（右结合）
4. **代码生成器**：使用 `POW` 指令（OpCode 38）+ `MMBIN` 元方法回退（MM_POW=11）

---

### 任务 9：Rune（字符）字面量 ⭐

**分值**：10 分

**特性描述**：支持仓颉语言的 Rune 字面量，使用单引号表示单个字符。

**示例代码**：
```cangjie
let c = 'A'
println(c)
// Expected: A
```

**期望效果**：
- 词法分析器能识别单引号字符字面量
- 在 Lua 层面以单字符字符串表示

**实现提示**：
1. **词法分析器**（`lexer.cj`）：在 `nextToken()` 中检测单引号 `'`
2. 读取引号之间的单个字符（或转义序列如 `'\n'`）
3. 生成字符串类型的常量（Lua 没有独立的字符类型，用长度为 1 的字符串表示）
4. **AST**：可复用 `StringLiteral` 节点或添加 `RuneLiteral(Rune)` 分支

---

### 任务 10：多返回值 ⭐⭐⭐

**分值**：30 分

**特性描述**：支持函数返回多个值，并能在调用处解构接收。

**示例代码**：
```cangjie
func swap(a: Float64, b: Float64) {
    return (b, a)
}
let (x, y) = swap(1.0, 2.0)
println(x)
println(y)
// Expected: 2.0, 1.0
```

**期望效果**：
- 函数可以返回多个值
- 调用方可以接收多个返回值

**实现提示**：
1. **AST**：修改 `ReturnStmt` 支持多个表达式：`ReturnStmt(ArrayList<Expr>)`
2. **解析器**：return 后解析逗号分隔的表达式列表
3. **代码生成器**：
   - 将多个返回值放入连续寄存器
   - `RETURN A B C`：B = 返回值数+1
   - `CALL A B C`：C = 期望返回值数+1（C=0 表示全部接收）

---

### 任务 11：else if 链 ⭐⭐

**分值**：20 分

**特性描述**：当前已支持 `if/else`，扩展支持 `else if` 链。

**示例代码**：
```cangjie
var x = 15
var result = 0
if (x > 20) {
    result = 3
} else if (x > 10) {
    result = 2
} else if (x > 5) {
    result = 1
} else {
    result = 0
}
println(result)
// Expected: 2
```

**期望效果**：
- `else if` 可以任意链接
- 最后可选 `else` 分支

**实现提示**：
1. 当前解析器中 `else` 后可能已经部分支持 `if`，检查 `parseIfStmt()` 中 else 分支是否递归调用 `parseIfStmt()`
2. 如果尚未支持，修改 else 解析：当 else 后面紧跟 `if` 关键字时，递归解析为新的 if 表达式
3. 代码生成器不需要修改——嵌套的 if 自然会生成正确的 JMP 链

---

### 任务 12：for-in 范围循环 ⭐⭐⭐

**分值**：30 分

**特性描述**：支持仓颉语言的 `for-in` 循环，遍历数值范围。

**示例代码**：
```cangjie
var sum = 0
for (i in 1..=5) {
    sum = sum + i
}
println(sum)
// Expected: 15
```

**期望效果**：
- `for (i in start..end)` 遍历 `[start, end)`（左闭右开）
- `for (i in start..=end)` 遍历 `[start, end]`（左闭右闭）

**实现提示**：
1. **词法分析器**：添加 `FOR`、`IN`、`DOTDOT`（`..`）、`DOTDOTEQ`（`..=`）token
2. **AST**：添加 `ForInStmt(String, Expr, Expr, Bool, ArrayList<Stmt>)` —— 循环变量、起始值、结束值、是否包含结束值、循环体
3. **代码生成器**：可以使用 Lua 的 `FORPREP/FORLOOP` 指令对实现数值循环：
   - R[A] = 初始值，R[A+1] = 限制值，R[A+2] = 步长
   - `FORPREP A Bx`：准备循环，若不需要执行则跳过 Bx+1 条指令
   - `FORLOOP A Bx`：更新计数器，若继续则向后跳 Bx 条指令
   - R[A+3] = 循环变量（外部可见）

---

### 任务 13：一元取反运算符 `~` ⭐

**分值**：10 分

**特性描述**：支持整数（Int64）按位取反运算符 `~`。

**示例代码**：
```cangjie
println(~0)
println(~1)
// Expected: -1, -2
```

**实现提示**：
1. **词法分析器**：添加 `TILDE`（`~`）token
2. **解析器**：在 `parseUnary()` 中处理 `~`，操作数必须为整数类型
3. **代码生成器**：使用 `BNOT` 指令（OpCode 50）：`BNOT A B` → `R[A] := ~R[B]`

---

### 任务 14：长度运算符 ⭐

**分值**：10 分

**特性描述**：支持获取字符串长度。仓颉语言中通过 `.size` 属性获取字符串长度。

**示例代码**：
```cangjie
let s = "hello"
println(s.size)
// Expected: 5
```

**实现提示**：
1. **词法分析器**：添加 `DOT`（`.`）token
2. **AST**：添加 `PropertyAccess(Box<Expr>, String)` 表达式
3. **解析器**：在 `parsePrimary()` 后处理 `.identifier` 后缀
4. **代码生成器**：对 `.size` 属性，生成 `LEN` 指令（OpCode 52）：`LEN A B` → `R[A] := #R[B]`

---

### 任务 15：多行注释 ⭐

**分值**：10 分

**特性描述**：支持 `/* ... */` 形式的多行注释。

**示例代码**：
```cangjie
/* 这是多行
   注释 */
let x = 42
/* 另一个注释 */
return x
// ExpectedReturn: 42.0
```

**实现提示**：
1. 在词法分析器的 `skipComment()` 中，检测 `/*` 开头
2. 扫描直到遇到 `*/`
3. 注意处理嵌套注释（可选）和行号跟踪

---

### 任务 16：位运算符 `&` 和 `|` ⭐⭐

**分值**：20 分

**特性描述**：支持仓颉语言中的位与（`&`）和位或（`|`）运算符。结合任务 13 的按位取反 `~`，构成完整的基础位运算支持。

**示例代码**：
```cangjie
println(5 & 3)
println(5 | 3)
// Expected: 1, 7
```

**实现提示**：
1. **词法分析器**：添加 `AMP`（`&`）、`PIPE`（`|`）token
2. **AST/解析器**：位运算优先级低于算术运算但高于比较运算
3. **代码生成器**：使用对应指令 `BAND(41)`、`BOR(42)` + 元方法回退

---

### 任务 17：数组字面量与索引访问 ⭐⭐⭐⭐

**分值**：40 分

**特性描述**：支持数组字面量和索引访问。在 Lua 层面使用 table 实现。

**示例代码**：
```cangjie
let arr = [10, 20, 30]
println(arr[0])
println(arr[1])
println(arr[2])
// Expected: 10, 20, 30
```

**期望效果**：
- `[expr, ...]` 创建数组
- `arr[index]` 访问数组元素（0-based 索引，编译时转换为 Lua 的 1-based）

**实现提示**：
1. **词法分析器**：添加 `LBRACKET`（`[`）和 `RBRACKET`（`]`）token
2. **AST**：
   - 添加 `ArrayLiteral(ArrayList<Expr>)` 表达式
   - 添加 `IndexAccess(Box<Expr>, Box<Expr>)` 表达式
3. **代码生成器**：
   - 数组创建：`NEWTABLE` 创建表 + `SETI` 或 `SETLIST` 设置元素（注意 Lua 表从 1 开始索引）
   - 索引访问：`GETI` 指令（OpCode 13）或 `GETTABLE`
   - 注意 0-based 到 1-based 的转换

---

### 任务 18：数组赋值与修改 ⭐⭐

**分值**：20 分

**特性描述**：支持通过索引修改数组元素。

**示例代码**：
```cangjie
var arr = [1, 2, 3]
arr[1] = 99
println(arr[1])
// Expected: 99
```

**实现提示**：
1. **AST**：添加 `IndexAssignment(Box<Expr>, Box<Expr>, Expr)` 表达式
2. **解析器**：在赋值解析中识别 `identifier[expr] = expr` 模式
3. **代码生成器**：使用 `SETI` 指令（OpCode 17）或 `SETTABLE`

---

### 任务 19：类型注解增强 ⭐⭐

**分值**：20 分

**特性描述**：增强变量声明和函数参数的类型注解，支持更多类型名称。

**示例代码**：
```cangjie
let x: Int64 = 42
let y: Float64 = 3.14
let s: String = "hello"
let b: Bool = true
func add(a: Int64, b: Int64): Int64 {
    return a + b
}
println(add(3, 4))
// Expected: 7
```

**期望效果**：
- 变量声明支持 `let x: Type = value` 语法
- 支持 `Int64`、`Float64`、`String`、`Bool` 类型名

**实现提示**：
1. **解析器**：在 `parseVarDecl()` 中，变量名后可选 `: Type`
2. **AST**：修改 `VarDecl` 增加可选类型注解字段
3. 当前阶段类型注解仅做语法检查，不需要完整的类型系统

---

### 任务 20：let 不可变检查 ⭐⭐

**分值**：20 分

**特性描述**：确保用 `let` 声明的变量不能被重新赋值。

**示例代码**：
```cangjie
let x = 10
x = 20
// ExpectError: immutable
```

**期望效果**：
- 对 `let` 声明的变量进行赋值时，报编译错误

**实现提示**：
1. 在解析器或代码生成器中维护变量的可变性信息
2. 在处理 `Assignment` 表达式时，检查目标变量是否用 `let` 声明
3. 如果是不可变变量，生成包含 "immutable" 的错误信息

---

### 任务 21：作用域与变量遮蔽 ⭐⭐⭐

**分值**：30 分

**特性描述**：支持块级作用域，内层作用域可以遮蔽外层同名变量。

**示例代码**：
```cangjie
let x = 10
if (true) {
    let x = 20
    println(x)
}
println(x)
// Expected: 20, 10
```

**期望效果**：
- if/while/代码块中声明的变量只在该块内可见
- 离开作用域后恢复外层变量

**实现提示**：
1. 维护作用域栈，进入代码块时压入新作用域
2. 变量查找从最内层作用域开始向外搜索
3. 离开作用域时恢复寄存器分配状态
4. 可以使用 `CLOSE` 指令关闭上值（如果实现了闭包捕获）

---

### 任务 22：嵌套函数与闭包 ⭐⭐⭐⭐

**分值**：40 分

**特性描述**：支持函数嵌套定义，内层函数可以捕获外层函数的局部变量。

**示例代码**：
```cangjie
func makeAdder(n: Float64) {
    func adder(x: Float64) {
        return x + n
    }
    return adder
}
let add5 = makeAdder(5.0)
println(add5(10.0))
// Expected: 15.0
```

**期望效果**：
- 内层函数可以读写外层函数的局部变量
- 外层函数返回后，被捕获的变量仍然有效

**实现提示**：
1. 需要正确处理上值（upvalue）的捕获
2. 子函数的上值表需要记录：instack=1 直接从父函数栈捕获，instack=0 从父函数上值继承
3. 当前实现所有子函数共享一个上值 `_ENV`，需要扩展为支持捕获任意局部变量
4. 使用 `GETUPVAL` / `SETUPVAL` 指令操作上值

---

### 任务 23：递归函数调用 ⭐⭐

**分值**：20 分

**特性描述**：确保函数可以递归调用自身。

**示例代码**：
```cangjie
func fib(n: Float64): Float64 {
    if (n <= 1.0) {
        return n
    }
    return fib(n - 1.0) + fib(n - 2.0)
}
println(fib(10.0))
// Expected: 55.0
```

**期望效果**：
- 函数体内可以通过函数名调用自身
- 递归深度受 Lua 栈大小限制

**实现提示**：
1. 当前实现函数通过 `SETTABUP` 注册到全局表 `_ENV`，然后通过 `GETTABUP` 加载
2. 递归调用时，函数在 `_ENV` 中已注册，因此自然支持
3. 需要验证 `CLOSURE` 和 `SETTABUP` 的执行顺序——确保函数先注册再调用
4. 可能需要测试深递归场景下的栈溢出处理

---

### 任务 24：尾调用优化 ⭐⭐⭐

**分值**：30 分

**特性描述**：尾调用（Tail Call）是指函数的最后一个求值表达式是一个函数调用。在这种情况下，当前函数的栈帧可以被复用，不需要额外分配新的栈帧，从而避免栈溢出。尾调用优化使得递归算法可以在常量栈空间内执行，等效于循环。

**示例代码**：
```cangjie
func loop(n: Float64, acc: Float64): Float64 {
    if (n <= 0.0) {
        return acc
    }
    return loop(n - 1.0, acc + n)
}
println(loop(10000.0, 0.0))
// Expected: 50005000.0
```

**期望效果**：
- 当函数的最后一个求值表达式是函数调用时，使用尾调用优化
- 尾调用不增加调用栈深度
- 大递归深度不会栈溢出

**实现提示**：
1. 在代码生成器中检测：`Return(Call(...))` 模式——即 return 表达式的求值内容是函数调用
2. 使用 `TAILCALL` 指令（OpCode 69）替代 `CALL` + `RETURN`
3. `TAILCALL A B C k`：调用 R[A] 并直接返回结果

---

### 任务 25：默认参数值 ⭐⭐⭐

**分值**：30 分

**特性描述**：支持函数命名参数的默认值。仓颉语言中只有命名参数才能设置默认值，命名参数使用 `参数名!: 类型 = 默认值` 语法。

**示例代码**：
```cangjie
func greet(name: String, greeting!: String = "Hello") {
    println(greeting)
    println(name)
}
greet("World")
greet("World", greeting: "Hi")
// Expected: Hello, World, Hi, World
```

**实现提示**：
1. **词法分析器**：添加 `BANG`（`!`）token 用于命名参数标记
2. **解析器**：函数参数识别 `name!: Type = defaultValue` 语法，支持命名参数
3. **AST**：`FuncParam` 添加 `isNamed: Bool` 和 `defaultValue: ?Expr` 字段
4. **代码生成器**：在函数入口检查命名参数是否未传入，如果是则使用默认值
5. Lua 层面：对每个有默认值的参数，生成 `TEST + JMP + LOADK` 序列
6. 调用时支持 `funcName(positionalArgs, namedParam: value)` 语法

---

### 任务 26：println 多参数 ⭐⭐

**分值**：20 分

**特性描述**：支持 `println` 接受多个参数，空格分隔输出。

**示例代码**：
```cangjie
println("x =", 42)
println("sum:", 1 + 2)
// Expected: x = 42, sum: 3
```

**实现提示**：
1. 当前 `println` 只接受一个参数
2. 修改 `cangjiePrintln` C 回调函数，遍历栈上所有参数
3. 参数间用空格分隔
4. 需要修改 `PrintRuntime` 的输出捕获逻辑

---

### 任务 27：print 函数（不换行） ⭐

**分值**：10 分

**特性描述**：添加 `print` 函数，输出后不自动换行。

**示例代码**：
```cangjie
print("hello ")
println("world")
// Expected: hello world
```

**实现提示**：
1. 在 `cangjie_lua.cj` 中注册新的 C 函数 `cangjiePrint`
2. 与 `cangjiePrintln` 类似但不输出换行符
3. 需要处理 `PrintRuntime` 的输出拼接

---

### 任务 28：字符串插值 ⭐⭐⭐

**分值**：30 分

**特性描述**：支持仓颉语言的字符串插值语法 `"text ${expr} text"`。

**示例代码**：
```cangjie
let name = "World"
let x = 42
println("Hello ${name}, x = ${x}")
// Expected: Hello World, x = 42
```

**实现提示**：
1. **词法分析器**：在字符串扫描中检测 `${`，将字符串分解为多个 token（字符串段 + 表达式）
2. **AST**：添加 `StringInterpolation(ArrayList<Expr>)` 表达式，包含文本段和表达式交替
3. **代码生成器**：
   - 将文本段和表达式值依次放入连续寄存器
   - 使用 `CONCAT` 指令连接所有段
   - 对于非字符串类型的表达式，可能需要调用 `tostring()` 转换

---

### 任务 29：break 表达式 ⭐⭐

**分值**：20 分

**特性描述**：在 while 循环中支持 break 表达式，跳出循环。

**示例代码**：
```cangjie
var i = 0
while (true) {
    if (i >= 5) {
        break
    }
    i = i + 1
}
println(i)
// Expected: 5
```

**实现提示**：
1. **词法分析器**：添加 `BREAK` 关键字
2. **AST**：添加 `BreakExpr` 表达式节点
3. **代码生成器**：
   - 维护循环上下文栈，记录当前循环的退出点
   - break 生成 `JMP` 指令，跳转目标需要回填
   - 循环结束时回填所有 break 的跳转目标

---

### 任务 30：continue 表达式 ⭐⭐

**分值**：20 分

**特性描述**：在 while 循环中支持 continue 表达式，跳到循环条件检查。

**示例代码**：
```cangjie
var sum = 0
var i = 0
while (i < 10) {
    i = i + 1
    if (i % 2 == 0) {
        continue
    }
    sum = sum + i
}
println(sum)
// Expected: 25
```

**实现提示**：
1. **词法分析器**：添加 `CONTINUE` 关键字
2. **AST**：添加 `ContinueExpr` 表达式节点
3. **代码生成器**：
   - continue 生成 `JMP` 指令，跳转到循环开头
   - 跳转偏移量 = loopStart - currentPC - 1（负偏移）

---

### 任务 31：多变量声明 ⭐⭐

**分值**：20 分

**特性描述**：支持同时声明多个变量。

**示例代码**：
```cangjie
let (a, b, c) = (1, 2, 3)
println(a)
println(b)
println(c)
// Expected: 1, 2, 3
```

**实现提示**：
1. **解析器**：识别 `let (a, b, c) = (expr1, expr2, expr3)` 模式
2. **AST**：添加 `MultiVarDecl` 表达式或扩展 `VarDecl`
3. **代码生成器**：依次分配寄存器并加载值

---

### 任务 32：类型转换表达式 ⭐⭐

**分值**：20 分

**特性描述**：支持仓颉语言的类型转换语法，在不同数值类型之间进行转换。

**示例代码**：
```cangjie
let a: Float64 = Float64(42)
let b: Int64 = Int64(3.7)
println(a)
println(b)
// Expected: 42.0, 3
```

**期望效果**：
- `Int64(expr)`：将值转换为整数（浮点数截断小数部分）
- `Float64(expr)`：将值转换为浮点数

**实现提示**：
1. **解析器**：识别 `TypeName(expr)` 模式，将其解析为类型转换表达式
2. **AST**：添加 `TypeCast(String, Box<Expr>)` 表达式节点，存储目标类型名和被转换的表达式
3. **代码生成器**：
   - `Int64()` 转换：先计算表达式，如果是浮点数则需要使用整数截断逻辑
   - `Float64()` 转换：先计算表达式，如果是整数则转换为浮点数
   - 可利用 Lua 的 `math.floor` 实现浮点到整数的截断

---

### 任务 33：复合赋值运算符 ⭐⭐

**分值**：20 分

**特性描述**：支持 `+=`、`-=`、`*=`、`/=` 复合赋值运算符。

**示例代码**：
```cangjie
var x = 10
x += 5
println(x)
x -= 3
println(x)
x *= 2
println(x)
x /= 6
println(x)
// Expected: 15, 12, 24, 4
```

**实现提示**：
1. **词法分析器**：添加 `PLUS_ASSIGN`、`MINUS_ASSIGN`、`STAR_ASSIGN`、`SLASH_ASSIGN` token
2. **解析器**：将 `x += expr` 解糖为 `x = x + expr`
3. 也可以在 AST 中保留复合赋值节点，在代码生成时展开

---

### 任务 34：元组(Tuple)字面量 ⭐⭐⭐⭐

**分值**：40 分

**特性描述**：支持仓颉语言的元组字面量，将多个不同类型的值打包在一起。使用 Lua table 实现。

**示例代码**：
```cangjie
let pair = (10, 20)
println(pair[0])
println(pair[1])
// Expected: 10, 20
```

**期望效果**：
- `(expr1, expr2, ...)` 创建元组（至少两个元素）
- `tuple[index]` 访问元组元素（0-based 索引，编译时转换为 Lua 的 1-based）

**实现提示**：
1. **解析器**：识别 `(expr, expr, ...)` 语法——当括号内包含逗号分隔的多个表达式时，解析为元组（注意与分组括号 `(expr)` 区分）
2. **AST**：添加 `TupleLiteral(ArrayList<Expr>)` 表达式
3. **代码生成器**：
   - 使用 `NEWTABLE` 创建 Lua table
   - 将元组元素依次存入（注意 0-based 到 Lua 1-based 的转换）
   - 索引访问复用数组的 `GETI` 指令

---

### 任务 35：错误处理 try-catch ⭐⭐⭐⭐

**分值**：40 分

**特性描述**：支持 try-catch 错误处理结构。

**示例代码**：
```cangjie
func divide(a: Float64, b: Float64): Float64 {
    if (b == 0.0) {
        throw "division by zero"
    }
    return a / b
}
try {
    divide(10.0, 0.0)
} catch (e) {
    println(e)
}
// Expected: division by zero
```

**实现提示**：
1. **throw**：可以使用 Lua 的 `error()` 函数抛出错误
2. **try-catch**：使用 `lua_pcallk()` 实现受保护调用
3. 需要将 try 块编译为独立的函数，然后用 pcall 调用
4. catch 块接收错误消息

---

### 任务 36：lambda 表达式 ⭐⭐⭐

**分值**：30 分

**特性描述**：支持仓颉语言的 lambda 表达式。

**示例代码**：
```cangjie
let double = { x: Float64 => x * 2.0 }
println(double(5.0))
// Expected: 10.0
```

**期望效果**：
- `{ params => body }` 创建匿名函数
- lambda 可以赋值给变量、作为参数传递

**实现提示**：
1. **解析器**：识别 `{ params => body }` 语法（注意与代码块 `{ stmts }` 区分）
2. **AST**：添加 `Lambda(ArrayList<FuncParam>, ArrayList<Stmt>)` 表达式
3. **代码生成器**：与 `FuncDecl` 类似，创建子函数原型 + `CLOSURE` 指令

---

### 任务 37：高阶函数 ⭐⭐⭐

**分值**：30 分

**特性描述**：支持函数作为参数传递和返回。

**示例代码**：
```cangjie
func apply(f: (Float64) -> Float64, x: Float64): Float64 {
    return f(x)
}
func square(n: Float64): Float64 {
    return n * n
}
println(apply(square, 5.0))
// Expected: 25.0
```

**实现提示**：
1. 当前实现中函数已经是 Lua 的 first-class value
2. 需要支持函数类型注解 `(ParamTypes) -> ReturnType`
3. 函数参数传递和调用：将函数名作为变量引用，通过 `GETTABUP` 加载后作为参数传递
4. 在调用 `f(x)` 时，`f` 是一个寄存器中的函数值，直接 `CALL` 即可

---

## 分数统计

| 难度 | 数量 | 单任务分值 | 小计 |
|------|------|----------|------|
| ⭐ (简单) | 9 个 | 10 分 | 90 分 |
| ⭐⭐ (中等) | 15 个 | 20 分 | 300 分 |
| ⭐⭐⭐ (较难) | 9 个 | 30 分 | 270 分 |
| ⭐⭐⭐⭐ (困难) | 4 个 | 40 分 | 160 分 |
| ⭐⭐⭐⭐⭐ (极难) | 5 个（附加任务） | 50 分 | 250 分 |
| **总计** | **42 个** | | **1070 分** |

---

## 附加挑战任务

以下任务难度极高，完成后获得额外加分：

### 附加任务 A：简单类定义 ⭐⭐⭐⭐⭐

**分值**：50 分

**特性描述**：支持简单的 class 定义，包括构造函数和方法。

**示例代码**：
```cangjie
class Point {
    var x: Float64
    var y: Float64

    init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }

    func getX(): Float64 {
        return this.x
    }
}

let p = Point(3.0, 4.0)
println(p.getX())
// Expected: 3.0
```

**实现提示**：
- 使用 Lua table + metatable 实现
- 构造函数创建新表并设置元表
- 方法通过 SELF 指令调用
- `this` 对应 Lua 的 `self`

### 附加任务 B：类的继承和多态 ⭐⭐⭐⭐⭐

**分值**：50 分

**特性描述**：在简单类定义的基础上，支持类的继承（`<:`）和方法重写（多态）。

**示例代码**：
```cangjie
open class Animal {
    var name: String

    init(name: String) {
        this.name = name
    }

    public open func speak(): String {
        return "..."
    }
}

class Dog <: Animal {
    init(name: String) {
        super(name)
    }

    public override func speak(): String {
        return "Woof"
    }
}

let d = Dog("Rex")
println(d.speak())
// Expected: Woof
```

**实现提示**：
- 使用 Lua metatable 链实现继承：子类的元表的 `__index` 指向父类的元表
- 方法重写：子类元表中覆盖父类方法
- `super` 调用：通过保存父类引用实现
- `open` 关键字标记类是否允许被继承

### 附加任务 C：模式匹配 match ⭐⭐⭐⭐⭐

**分值**：50 分

**特性描述**：支持仓颉语言的 match 表达式，包含常量模式和通配符模式。常量模式匹配具体值（整数、浮点数、布尔值、字符串等），通配符模式 `_` 匹配任意值作为默认分支。

**示例代码**：
```cangjie
func describe(x: Float64): String {
    match (x) {
        case 0.0 => return "zero"
        case 1.0 => return "one"
        case _ => return "other"
    }
}
println(describe(1.0))
// Expected: one
```

**实现提示**：
1. **词法分析器**：添加 `MATCH`、`CASE`、`ARROW`（`=>`）、`UNDERSCORE`（`_`）token
2. **AST**：添加 `MatchExpr(Box<Expr>, ArrayList<MatchArm>)` 表达式，`MatchArm` 包含模式和分支体
3. **代码生成器**：
   - 常量模式：使用 `EQ`/`EQK`/`EQI` 指令依次比较，不匹配则跳到下一个 case
   - 通配符模式 `_`：无条件执行分支体（作为默认 fallthrough）
   - 每个 case 分支结束后 `JMP` 跳到 match 表达式末尾

### 附加任务 D：extend 扩展 ⭐⭐⭐⭐⭐

**分值**：50 分

**特性描述**：支持仓颉语言的 `extend` 特性，为已有类型添加新方法，而不修改原始类型定义。

**示例代码**：
```cangjie
extend Int64 {
    func isEven(): Bool {
        return this % 2 == 0
    }
}

let x = 4
println(x.isEven())
// Expected: true
```

**实现提示**：
- 使用 Lua metatable 为已有类型附加方法
- 需要为基础类型（Int64、Float64、String 等）建立 metatable 系统
- `this` 绑定到调用方法的值
- extend 块中的方法注册到对应类型的 metatable 的 `__index` 表中

### 附加任务 E：interface 接口 ⭐⭐⭐⭐⭐

**分值**：50 分

**特性描述**：支持仓颉语言的 `interface` 特性，定义接口并让类实现接口。

**示例代码**：
```cangjie
interface Printable {
    func display(): String
}

class User <: Printable {
    var name: String

    init(name: String) {
        this.name = name
    }

    public func display(): String {
        return this.name
    }
}

let u = User("Alice")
println(u.display())
// Expected: Alice
```

**实现提示**：
- interface 定义为方法签名集合（仅声明，无实现）
- 在编译期检查类是否实现了接口要求的所有方法
- 使用 Lua metatable 机制，接口约束在编译期验证
- 类通过 `<:` 声明实现接口，与继承语法统一
