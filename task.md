# 仓颉 AI 编程大赛 —— 任务书

## 一、任务背景

本项目 **CangjieLua** 是一个用仓颉语言编写的**仓颉语言子集解释器**。它将仓颉源码编译为 Lua 5.5 虚拟机字节码，并通过仓颉 C 互操作（FFI）机制集成 `libluavm` 执行字节码。

项目已实现的编译管线为：

```
仓颉源码(.scj) → Lexer(词法分析) → Parser(语法分析) → CodeGenerator(字节码生成) → LuaVM(执行)
```

### 已支持的语言特性

- 数字字面量（浮点数）
- 变量声明（`let` / `var`）和赋值
- 四则运算（`+` `-` `*` `/`）及运算符优先级和括号
- `println()` 内置函数调用
- `if` / `else` 条件语句（条件为非零值即真）
- `while` 循环语句
- 函数定义（`func`）和调用，支持参数和返回值
- `return` 语句

### 项目结构

```
CangjieLua/
├── src/
│   ├── main.cj              # 入口，运行测试
│   ├── tester.cj             # 测试运行器，管线串联
│   ├── lexer/
│   │   ├── token.cj          # 词法单元类型定义
│   │   └── lexer.cj          # 词法分析器
│   ├── parser/
│   │   ├── ast.cj            # AST 节点定义
│   │   └── parser.cj         # 语法分析器
│   ├── codegen/
│   │   ├── bytecode.cj       # 操作码、指令编码
│   │   ├── chunk_writer.cj   # 二进制块写入器
│   │   └── code_generator.cj # 字节码生成器
│   └── luavm/
│       └── ffi.cj            # LuaVM FFI 声明与封装
├── tests/                    # 测试用例（.scj 文件）
├── luavm/                    # libluavm 库及源码
├── luavm.md                  # LuaVM 接口文档
├── cangjie-docs/             # 仓颉语言/标准库/工具链文档
└── cjpm.toml                 # 仓颉包管理配置
```

### 参考文档

- `cangjie-docs/` 目录下包含仓颉语言特性、标准库和工具链的完整文档
- `luavm.md` 描述了 LuaVM 各接口的参数与功能

## 二、任务目标

在现有基础上，**扩展实现更多仓颉语言特性**（不包括并发和宏）。每个特性通过对应的测试用例验证，**按通过的特性测试累计得分**。

### 评分规则

1. 每个测试用例有对应分值，以测试用例通过（程序正确编译执行，输出与预期匹配）为评判标准
2. 提交后，后台针对每个特性还有更多变体测试用例，任务书中的用例供选手自测
3. 特性之间尽量独立，可以选择性实现
4. 总分 **200 分**

## 三、特性测试用例与评分

测试用例为 `.scj` 文件，使用仓颉语法子集，注释中标注 `// expect:` 表示预期的标准输出（每行一个值）。测试通过标准：程序不崩溃且标准输出与预期完全一致。

---

### 特性 1：比较运算符（15 分）

实现 `<`、`>`、`<=`、`>=`、`==`、`!=` 六个比较运算符，返回布尔值（`true`/`false`），`true` 在条件中视为真，`false` 视为假。以下分步计分：

#### 1.1 等于与不等于（5 分）

```
let a = 10.0
let b = 10.0
let c = 20.0
if (a == b) {
    println(1.0)
}
if (a != c) {
    println(2.0)
}
if (a == c) {
    println(3.0)
}
// expect:
// 1.0
// 2.0
```

#### 1.2 小于与大于（5 分）

```
let x = 5.0
let y = 10.0
if (x < y) {
    println(1.0)
}
if (y > x) {
    println(2.0)
}
if (x > y) {
    println(3.0)
}
// expect:
// 1.0
// 2.0
```

#### 1.3 小于等于与大于等于（5 分）

```
let a = 10.0
let b = 10.0
let c = 5.0
if (a <= b) {
    println(1.0)
}
if (a >= b) {
    println(2.0)
}
if (c <= a) {
    println(3.0)
}
if (c >= a) {
    println(4.0)
}
// expect:
// 1.0
// 2.0
// 3.0
```

---

### 特性 2：逻辑运算符（10 分）

实现 `&&`（逻辑与）和 `||`（逻辑或），支持短路求值。

#### 2.1 逻辑与（5 分）

```
let a = 1.0
let b = 0.0
if (a && a) {
    println(1.0)
}
if (a && b) {
    println(2.0)
}
// expect:
// 1.0
```

#### 2.2 逻辑或（5 分）

```
let a = 0.0
let b = 1.0
if (a || b) {
    println(1.0)
}
if (a || a) {
    println(2.0)
}
// expect:
// 1.0
```

---

### 特性 3：取模与一元负号（8 分）

#### 3.1 取模运算 `%`（4 分）

```
let a = 10.0
let b = 3.0
let c = a % b
println(c)
let d = 15.0 % 4.0
println(d)
// expect:
// 1.0
// 3.0
```

#### 3.2 一元负号 `-`（4 分）

```
let a = 5.0
let b = -a
println(b)
let c = -10.0
println(c)
let d = -(-3.0)
println(d)
// expect:
// -5.0
// -10.0
// 3.0
```

---

### 特性 4：字符串支持（10 分）

#### 4.1 字符串字面量与 println（5 分）

实现双引号字符串字面量的词法分析、解析和代码生成，支持 `println` 输出字符串。

```
let s = "hello"
println(s)
println("world")
// expect:
// hello
// world
```

#### 4.2 字符串拼接 `+`（5 分）

实现字符串之间的 `+` 运算符进行拼接。

```
let a = "hello"
let b = " "
let c = "world"
let d = a + b + c
println(d)
// expect:
// hello world
```

---

### 特性 5：else if 链（5 分）

已有 `if`/`else`，需确保 `else if` 链正确工作（多分支选择）。

```
let x = 15.0
if (x == 10.0) {
    println(1.0)
} else if (x == 15.0) {
    println(2.0)
} else {
    println(3.0)
}
// expect:
// 2.0
```

> 注：此特性依赖比较运算符（特性 1），若未实现比较运算符，可改用数值条件测试 else if 链路。

---

### 特性 6：for-in 范围循环（10 分）

#### 6.1 基本 for-in 循环（5 分）

实现 `for (i in start..end) { body }` 形式的范围循环，`start..end` 不包含 `end`。

```
var sum = 0.0
for (i in 0..5) {
    sum = sum + i
}
println(sum)
// expect:
// 10.0
```

#### 6.2 for-in 嵌套循环（5 分）

```
var count = 0.0
for (i in 0..3) {
    for (j in 0..3) {
        count = count + 1.0
    }
}
println(count)
// expect:
// 9.0
```

---

### 特性 7：break 与 continue（8 分）

#### 7.1 break 语句（4 分）

```
var i = 0.0
while (1.0) {
    if (i == 5.0) {
        break
    }
    i = i + 1.0
}
println(i)
// expect:
// 5.0
```

#### 7.2 continue 语句（4 分）

```
var sum = 0.0
for (i in 0..10) {
    if (i == 5.0) {
        continue
    }
    sum = sum + i
}
println(sum)
// expect:
// 40.0
```

---

### 特性 8：多返回值与多参数 println（6 分）

#### 8.1 多参数 println（3 分）

支持 `println` 接受多个参数，以空格分隔输出。

```
let a = 1.0
let b = 2.0
println(a, b)
// expect:
// 1.0 2.0
```

#### 8.2 函数多返回值（3 分）

支持函数返回多个值，调用侧可接收。

```
func swap(a, b) {
    return b, a
}
let x = swap(1.0, 2.0)
println(x)
// expect:
// 2.0
```

---

### 特性 9：类型标注与 Bool 类型（8 分）

#### 9.1 变量类型标注语法（4 分）

支持 `let x: Int64 = 10` 和 `var y: Float64 = 3.14` 形式的类型标注语法（解析器层面识别并忽略或校验类型标注）。

```
let a: Float64 = 3.14
let b: Float64 = 2.0
let c = a + b
println(c)
// expect:
// 5.14
```

#### 9.2 Bool 字面量与逻辑运算（4 分）

支持 `true` 和 `false` 关键字作为布尔字面量。

```
let a = true
let b = false
if (a) {
    println(1.0)
}
if (b) {
    println(2.0)
}
// expect:
// 1.0
```

---

### 特性 10：作用域与变量遮蔽（5 分）

支持块级作用域和变量遮蔽（内层同名变量覆盖外层）。

```
let x = 1.0
{
    let x = 2.0
    println(x)
}
println(x)
// expect:
// 2.0
// 1.0
```

---

### 特性 11：函数递归与高级调用（7 分）

#### 11.1 递归调用（4 分）

确保递归函数正确工作（已有基础支持，此处测试更深层递归）。

```
func fib(n) {
    if (n <= 1.0) {
        return n
    }
    return fib(n - 1.0) + fib(n - 2.0)
}
println(fib(10.0))
// expect:
// 55.0
```

#### 11.2 函数作为参数传递（3 分）

```
func apply(f, x) {
    return f(x)
}
func double(x) {
    return x * 2.0
}
let result = apply(double, 5.0)
println(result)
// expect:
// 10.0
```

---

### 特性 12：复合赋值运算符（5 分）

实现 `+=`、`-=`、`*=`、`/=` 复合赋值运算符。

```
var a = 10.0
a += 5.0
println(a)
a -= 3.0
println(a)
a *= 2.0
println(a)
a /= 4.0
println(a)
// expect:
// 15.0
// 12.0
// 24.0
// 6.0
```

---

### 特性 13：嵌套函数定义（5 分）

支持在函数体内定义子函数，并正确调用。

```
func outer(x) {
    func inner(y) {
        return y * 2.0
    }
    return inner(x) + 1.0
}
let result = outer(5.0)
println(result)
// expect:
// 11.0
```

---

### 特性 14：类定义与实例化（30 分）

实现仓颉的 `class` 关键字，支持成员变量（属性）、构造函数、成员方法的定义和使用。

#### 14.1 基本类定义与构造（8 分）

支持 `class` 定义、成员变量声明和 `init` 构造函数，通过 `ClassName(args)` 实例化。

```
class Point {
    var x: Float64
    var y: Float64
    init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }
}
let p = Point(3.0, 4.0)
println(p.x)
println(p.y)
// expect:
// 3.0
// 4.0
```

#### 14.2 成员方法（8 分）

支持在类中定义方法，通过 `instance.method()` 调用。

```
class Counter {
    var count: Float64
    init() {
        this.count = 0.0
    }
    func increment() {
        this.count = this.count + 1.0
    }
    func getCount() {
        return this.count
    }
}
let c = Counter()
c.increment()
c.increment()
c.increment()
println(c.getCount())
// expect:
// 3.0
```

#### 14.3 带参数的成员方法（7 分）

支持成员方法接受参数。

```
class Rect {
    var width: Float64
    var height: Float64
    init(w: Float64, h: Float64) {
        this.width = w
        this.height = h
    }
    func area() {
        return this.width * this.height
    }
    func scale(factor: Float64) {
        this.width = this.width * factor
        this.height = this.height * factor
    }
}
let r = Rect(3.0, 4.0)
println(r.area())
r.scale(2.0)
println(r.area())
// expect:
// 12.0
// 48.0
```

#### 14.4 多实例独立性（7 分）

多个实例之间的状态互不影响。

```
class Box {
    var value: Float64
    init(v: Float64) {
        this.value = v
    }
    func add(n: Float64) {
        this.value = this.value + n
    }
}
let a = Box(10.0)
let b = Box(20.0)
a.add(5.0)
b.add(3.0)
println(a.value)
println(b.value)
// expect:
// 15.0
// 23.0
```

---

### 特性 15：类继承（25 分）

支持 `class Child <: Parent` 形式的单继承，子类继承父类的成员变量和方法，可覆盖（override）父类方法。

#### 15.1 基本继承与方法继承（8 分）

```
class Animal {
    var name: Float64
    init(n: Float64) {
        this.name = n
    }
    func speak() {
        return this.name
    }
}
class Dog <: Animal {
    init(n: Float64) {
        super(n)
    }
}
let d = Dog(42.0)
println(d.speak())
// expect:
// 42.0
```

#### 15.2 方法覆盖（override）（8 分）

子类可覆盖父类方法，调用时执行子类版本。

```
class Shape {
    func area() {
        return 0.0
    }
}
class Circle <: Shape {
    var radius: Float64
    init(r: Float64) {
        this.radius = r
    }
    func area() {
        return 3.14 * this.radius * this.radius
    }
}
let s = Circle(5.0)
println(s.area())
// expect:
// 78.5
```

#### 15.3 继承链与 super 调用（9 分）

支持多层继承和 `super` 调用父类方法。

```
class Base {
    var value: Float64
    init(v: Float64) {
        this.value = v
    }
    func compute() {
        return this.value
    }
}
class Mid <: Base {
    init(v: Float64) {
        super(v)
    }
    func compute() {
        return super.compute() * 2.0
    }
}
class Top <: Mid {
    init(v: Float64) {
        super(v)
    }
    func compute() {
        return super.compute() + 1.0
    }
}
let t = Top(5.0)
println(t.compute())
// expect:
// 11.0
```

---

### 特性 16：接口（20 分）

实现 `interface` 关键字，支持接口定义方法签名，类通过 `<:` 实现接口中声明的方法。

#### 16.1 基本接口实现（10 分）

```
interface Printable {
    func display()
}
class Item <: Printable {
    var id: Float64
    init(id: Float64) {
        this.id = id
    }
    func display() {
        println(this.id)
    }
}
let item = Item(99.0)
item.display()
// expect:
// 99.0
```

#### 16.2 多接口实现（10 分）

一个类可以实现多个接口。

```
interface HasArea {
    func area()
}
interface HasPerimeter {
    func perimeter()
}
class Square <: HasArea & HasPerimeter {
    var side: Float64
    init(s: Float64) {
        this.side = s
    }
    func area() {
        return this.side * this.side
    }
    func perimeter() {
        return this.side * 4.0
    }
}
let sq = Square(5.0)
println(sq.area())
println(sq.perimeter())
// expect:
// 25.0
// 20.0
```

---

### 特性 17：扩展（15 分）

实现 `extend` 关键字，支持为已有类型添加新方法（不修改原始定义）。

#### 17.1 为类添加扩展方法（8 分）

```
class MyNum {
    var val: Float64
    init(v: Float64) {
        this.val = v
    }
}
extend MyNum {
    func doubled() {
        return this.val * 2.0
    }
}
let n = MyNum(7.0)
println(n.doubled())
// expect:
// 14.0
```

#### 17.2 为类添加多个扩展方法（7 分）

```
class Vec2 {
    var x: Float64
    var y: Float64
    init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }
}
extend Vec2 {
    func dot(other: Vec2) {
        return this.x * other.x + this.y * other.y
    }
    func sum() {
        return this.x + this.y
    }
}
let a = Vec2(3.0, 4.0)
let b = Vec2(1.0, 2.0)
println(a.dot(b))
println(a.sum())
// expect:
// 11.0
// 7.0
```

---

### 特性 18：函数参数类型标注（6 分）

支持函数参数带类型标注 `func foo(x: Float64)` 的解析。

```
func add(a: Float64, b: Float64) {
    return a + b
}
let result = add(3.0, 4.0)
println(result)
// expect:
// 7.0
```

---

### 特性 19：返回值类型标注（6 分）

支持函数返回值类型标注 `func foo(): Float64 { ... }` 的解析。

```
func square(x: Float64): Float64 {
    return x * x
}
println(square(6.0))
// expect:
// 36.0
```

---

## 四、评分总览

| 特性编号 | 特性名称 | 子项 | 分值 | 累计 |
|----------|----------|------|------|------|
| 1.1 | 比较运算：== != | t01 | 5 | 5 |
| 1.2 | 比较运算：< > | t02 | 5 | 10 |
| 1.3 | 比较运算：<= >= | t03 | 5 | 15 |
| 2.1 | 逻辑与 && | t04 | 5 | 20 |
| 2.2 | 逻辑或 \|\| | t05 | 5 | 25 |
| 3.1 | 取模 % | t06 | 4 | 29 |
| 3.2 | 一元负号 - | t07 | 4 | 33 |
| 4.1 | 字符串字面量与输出 | t08 | 5 | 38 |
| 4.2 | 字符串拼接 + | t09 | 5 | 43 |
| 5 | else if 链 | t10 | 5 | 48 |
| 6.1 | for-in 范围循环 | t11 | 5 | 53 |
| 6.2 | for-in 嵌套循环 | t12 | 5 | 58 |
| 7.1 | break 语句 | t13 | 4 | 62 |
| 7.2 | continue 语句 | t14 | 4 | 66 |
| 8.1 | 多参数 println | t15 | 3 | 69 |
| 8.2 | 函数多返回值 | t16 | 3 | 72 |
| 9.1 | 类型标注语法 | t17 | 4 | 76 |
| 9.2 | Bool 字面量 | t18 | 4 | 80 |
| 10 | 作用域与变量遮蔽 | t19 | 5 | 85 |
| 11.1 | 递归调用 | t20 | 4 | 89 |
| 11.2 | 函数作为参数传递 | t21 | 3 | 92 |
| 12 | 复合赋值运算符 | t22 | 5 | 97 |
| 13 | 嵌套函数定义 | t23 | 5 | 102 |
| 14.1 | 类定义与构造 | t24 | 8 | 110 |
| 14.2 | 成员方法 | t25 | 8 | 118 |
| 14.3 | 带参数的成员方法 | t26 | 7 | 125 |
| 14.4 | 多实例独立性 | t27 | 7 | 132 |
| 15.1 | 基本继承与方法继承 | t28 | 8 | 140 |
| 15.2 | 方法覆盖（override） | t29 | 8 | 148 |
| 15.3 | 继承链与 super 调用 | t30 | 9 | 157 |
| 16.1 | 基本接口实现 | t31 | 10 | 167 |
| 16.2 | 多接口实现 | t32 | 10 | 177 |
| 17.1 | 类扩展方法 | t33 | 8 | 185 |
| 17.2 | 多个扩展方法 | t34 | 7 | 192 |
| 18 | 函数参数类型标注 | t35 | 6 | 198 |
| 19 | 返回值类型标注 | t36 | 2 | 200 |

## 五、提交与评判规则

1. **提交内容**：整个项目代码（包含修改的源码和新增测试文件）
2. **编译检查**：提交的代码必须能通过 `cjpm build` 编译
3. **测试方法**：后台使用 `cjpm run -- <test_file.scj>` 逐一运行测试用例，捕获标准输出与预期输出进行对比
4. **评判标准**：
   - 程序无崩溃/异常退出
   - 标准输出与预期输出逐行完全匹配（含浮点数格式）
   - 每个测试用例独立评分，通过即获得该用例对应分值
5. **注意事项**：
   - 不得修改 `luavm/` 目录下的虚拟机库文件
   - 可以修改 `src/` 下的所有源码文件
   - 可以新增源码文件，但需保证包结构正确
   - 建议使用 `tests/` 目录下已有用例验证不引入回归错误
   - 每个特性可以独立实现，无需按顺序完成
   - 本任务不涉及并发和宏特性
