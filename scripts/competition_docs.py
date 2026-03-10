#!/usr/bin/env python3
from __future__ import annotations

import argparse
import inspect
import os
import subprocess
import struct
import sys
import tempfile
import textwrap
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
FFI_FILE = REPO_ROOT / "src/luavm/ffi.cj"
EXPORTS_FILE = REPO_ROOT / "luavm/exports.txt"
BYTECODE_FILE = REPO_ROOT / "src/codegen/bytecode.cj"
LUAVM_DOC = REPO_ROOT / "luavm/luavm.md"
TASK_DOC = REPO_ROOT / "task.md"
GUIDE_DOC = REPO_ROOT / "docs/contest-guide.md"
DEFAULT_BINARY_CANDIDATES = [
    REPO_ROOT / "target/release/bin/main",
    REPO_ROOT / "target/release/bin/cangjie_lua",
]
LUAVM_LIB_DIR = REPO_ROOT / "luavm"

A_SHIFT = 7
K_SHIFT = 15
B_SHIFT = 16
C_SHIFT = 24
BX_SHIFT = 15
SJ_SHIFT = 7
A_MASK = 0xFF
B_MASK = 0xFF
C_MASK = 0xFF
BX_MASK = 0x1FFFF
SJ_MASK = 0x1FFFFFF
SBX_OFFSET = 65535
SJ_OFFSET = 16777215


@dataclass(frozen=True)
class DocExample:
    key: str
    title: str
    source: str
    expect_return: str | None = None
    expect_outputs: tuple[str, ...] = ()
    expect_error: str | None = None
    purpose: str = ""


BYTECODE_EXAMPLES: list[DocExample] = [
    DocExample(
        key="return_42",
        title="常量返回：`return 42`",
        source="return 42\n",
        expect_return="42",
        purpose="覆盖 main 原型、`VARARGPREP + LOADI + RETURN + RETURN0` 的最小路径。",
    ),
    DocExample(
        key="if_else",
        title="条件分支：`if / else`",
        source=textwrap.dedent(
            """\
            if (true) {
                println(1)
            } else {
                println(2)
            }
            return 0
            """
        ),
        expect_outputs=("1",),
        purpose="覆盖 `TEST`、前向 `JMP`、分支块收尾跳转以及 `println` 调用模板。",
    ),
    DocExample(
        key="while_loop",
        title="循环：`while` + 变量更新",
        source=textwrap.dedent(
            """\
            var i = 0
            while (i < 3) {
                println(i)
                i = i + 1
            }
            return i
            """
        ),
        expect_outputs=("0", "1", "2"),
        purpose="覆盖循环入口比较、回跳、局部变量复用与加法指令模板。",
    ),
    DocExample(
        key="function_call",
        title="函数声明与调用",
        source=textwrap.dedent(
            """\
            func add(a: Int64, b: Int64): Int64 {
                return a + b
            }
            println(add(2, 3))
            return 0
            """
        ),
        expect_outputs=("5",),
        purpose="覆盖 `CLOSURE`、子函数原型、`SETTABUP` 注册全局函数与 `CALL`。",
    ),
]


TASKS: list[dict[str, Any]] = [
    {
        "id": "T01",
        "title": "逻辑与 / 逻辑或短路",
        "feature": "为表达式系统补齐 `&&` 与 `||`，并严格遵守短路求值。",
        "score": 30,
        "difficulty": "入门",
        "baseline_example": textwrap.dedent(
            """\
            let a = true
            let b = false
            if (a) {
                println(1)
            }
            if (b) {
                println(2)
            }
            return 0
            """
        ),
        "baseline_expect_outputs": ("1",),
        "target_syntax": "if (a && !b) { println(1) }",
        "expected_effect": "支持逻辑组合表达式，并保证右侧表达式仅在必要时求值。",
        "hints": [
            "在 parser 中新增低于比较、高于赋值的优先级层级。",
            "代码生成建议直接复用 `TEST + JMP` 模板实现短路，而不是退化成数值运算。",
        ],
    },
    {
        "id": "T02",
        "title": "一元逻辑非 `!`",
        "feature": "新增布尔取反操作符。",
        "score": 20,
        "difficulty": "入门",
        "baseline_example": "let value = true\nprintln(value)\nreturn 0\n",
        "baseline_expect_outputs": ("true",),
        "target_syntax": "println(!value)",
        "expected_effect": "支持布尔值求反，并在 parser 阶段对非 Bool 使用给出明确错误。",
        "hints": [
            "可将 `!expr` 归一化为新的 `UnaryOp.NOT`。",
            "Lua 5.5 已有 `NOT` 指令，若保持布尔结果可直接复用。",
        ],
    },
    {
        "id": "T03",
        "title": "`else if` 语法糖",
        "feature": "支持链式条件分支，避免深层嵌套块。",
        "score": 25,
        "difficulty": "入门",
        "baseline_example": textwrap.dedent(
            """\
            let flag = true
            if (flag) {
                println(1)
            } else {
                println(2)
            }
            return 0
            """
        ),
        "baseline_expect_outputs": ("1",),
        "target_syntax": textwrap.dedent(
            """\
            if (a) {
                println(1)
            } else if (b) {
                println(2)
            } else {
                println(3)
            }
            """
        ).strip(),
        "expected_effect": "解析器可连续处理 `else if`，代码生成仍输出扁平跳转链。",
        "hints": [
            "最简单做法是在 parser 中把 `else if` 递归转成嵌套 `IfStmt`。",
            "文档中的字节码模板仍可复用现有 `if / else` 实现。",
        ],
    },
    {
        "id": "T04",
        "title": "`break` 语句",
        "feature": "允许提前终止最近一层循环。",
        "score": 40,
        "difficulty": "中等",
        "baseline_example": textwrap.dedent(
            """\
            var i = 0
            while (i < 3) {
                println(i)
                i = i + 1
            }
            return 0
            """
        ),
        "baseline_expect_outputs": ("0", "1", "2"),
        "target_syntax": textwrap.dedent(
            """\
            while (i < 10) {
                if (i == 5) {
                    break
                }
                i = i + 1
            }
            """
        ).strip(),
        "expected_effect": "循环体内可生成跳出当前循环的前向跳转，并在循环结束时统一回填。",
        "hints": [
            "为 `while` 维护 `break` 回填列表即可，不必一开始就实现多层标签。",
            "若在非循环上下文看到 `break`，应直接报 parser error。",
        ],
    },
    {
        "id": "T05",
        "title": "`continue` 语句",
        "feature": "跳过当前迭代剩余语句，进入下一轮。",
        "score": 45,
        "difficulty": "中等",
        "baseline_example": textwrap.dedent(
            """\
            var i = 0
            while (i < 3) {
                i = i + 1
                println(i)
            }
            return 0
            """
        ),
        "baseline_expect_outputs": ("1", "2", "3"),
        "target_syntax": textwrap.dedent(
            """\
            while (i < 5) {
                i = i + 1
                if (i == 2) {
                    continue
                }
                println(i)
            }
            """
        ).strip(),
        "expected_effect": "支持回跳到循环条件计算点，而不是简单跳到循环体开头。",
        "hints": [
            "为每个循环保存“继续目标 PC”，让 `continue` 直接跳到条件重算位置。",
            "注意 `continue` 前的栈临时寄存器要恢复。",
        ],
    },
    {
        "id": "T06",
        "title": "字符串字面量与打印",
        "feature": "支持 `\"text\"` 字符串、字符串常量池与 `println` 输出。",
        "score": 35,
        "difficulty": "中等",
        "baseline_example": "println(42)\nreturn 0\n",
        "baseline_expect_outputs": ("42",),
        "target_syntax": 'println("hello")',
        "expected_effect": "词法、AST、常量表、运行时输出全部支持字符串。",
        "hints": [
            "Lua chunk 已支持短字符串常量，可复用 `Constant.Str`。",
            "需要同时更新测试框架的 `Expected` 解析，确保字符串断言可读。",
        ],
    },
    {
        "id": "T07",
        "title": "字符串拼接",
        "feature": "支持字符串 `+` 或专用拼接语义。",
        "score": 35,
        "difficulty": "中等",
        "baseline_example": "println(1)\nprintln(2)\nreturn 0\n",
        "baseline_expect_outputs": ("1", "2"),
        "target_syntax": 'println("hello" + " world")',
        "expected_effect": "可将两个字符串连接为新值，并在运行时保持 Lua 字符串语义。",
        "hints": [
            "若沿用 `+`，请在类型检查里明确数字加法与字符串拼接的分派规则。",
            "也可以直接映射到 Lua 的 `CONCAT` 指令。",
        ],
    },
    {
        "id": "T08",
        "title": "数组字面量",
        "feature": "支持形如 `[1, 2, 3]` 的数组构造。",
        "score": 60,
        "difficulty": "中等",
        "baseline_example": textwrap.dedent(
            """\
            println(1)
            println(2)
            println(3)
            return 0
            """
        ),
        "baseline_expect_outputs": ("1", "2", "3"),
        "target_syntax": "let nums = [1, 2, 3]",
        "expected_effect": "可构造顺序容器，并把元素映射到 Lua table 的数组段。",
        "hints": [
            "代码生成可先用 `NEWTABLE` 建表，再用 `SETI` / `SETLIST` 写入元素。",
            "建议先只支持同构元素和整数下标。",
        ],
    },
    {
        "id": "T09",
        "title": "数组索引读取",
        "feature": "支持 `nums[0]` / `nums[1]` 形式的读取。",
        "score": 45,
        "difficulty": "中等",
        "baseline_example": textwrap.dedent(
            """\
            let a = 10
            println(a)
            return 0
            """
        ),
        "baseline_expect_outputs": ("10",),
        "target_syntax": "println(nums[0])",
        "expected_effect": "能够从数组或 table 中按索引取值，并在错误下标时报出清晰信息。",
        "hints": [
            "先定义 Cangjie 子集的索引起点（建议与当前题目说明保持一致并写进文档）。",
            "Lua VM 有 `GETI` 指令，适合整数索引。",
        ],
    },
    {
        "id": "T10",
        "title": "数组索引写入",
        "feature": "支持 `nums[i] = value`。",
        "score": 50,
        "difficulty": "中等",
        "baseline_example": textwrap.dedent(
            """\
            var x = 1
            x = 2
            println(x)
            return 0
            """
        ),
        "baseline_expect_outputs": ("2",),
        "target_syntax": "nums[1] = 99",
        "expected_effect": "允许更新可变数组元素，并保持局部变量与全局变量赋值规则一致。",
        "hints": [
            "可以在 AST 中新增 `IndexAssignment` 节点，避免与普通赋值共享过多分支。",
            "Lua VM 有 `SETI` 指令；若索引不是常量，再考虑 `SETTABLE`。",
        ],
    },
    {
        "id": "T11",
        "title": "`for-in` 区间循环",
        "feature": "支持 `for (i in 0..10)` 或等价语法。",
        "score": 80,
        "difficulty": "进阶",
        "baseline_example": textwrap.dedent(
            """\
            var i = 0
            while (i < 3) {
                println(i)
                i = i + 1
            }
            return 0
            """
        ),
        "baseline_expect_outputs": ("0", "1", "2"),
        "target_syntax": textwrap.dedent(
            """\
            for (i in 0..3) {
                println(i)
            }
            """
        ).strip(),
        "expected_effect": "提供比 `while` 更高层的循环语法，可映射为计数循环模板。",
        "hints": [
            "先把语法糖降级成初始化 + 条件 + 递增的 `while`，不要急着引入新 opcode。",
            "如果后续需要优化，再研究 `FORPREP` / `FORLOOP`。",
        ],
    },
    {
        "id": "T12",
        "title": "局部块作用域",
        "feature": "支持在 `{ ... }` 中定义只在块内可见的变量。",
        "score": 50,
        "difficulty": "进阶",
        "baseline_example": textwrap.dedent(
            """\
            let x = 1
            if (true) {
                println(x)
            }
            return 0
            """
        ),
        "baseline_expect_outputs": ("1",),
        "target_syntax": textwrap.dedent(
            """\
            if (true) {
                let y = 2
                println(y)
            }
            """
        ).strip(),
        "expected_effect": "进入块时可新建符号表，退出后回收局部寄存器与名字绑定。",
        "hints": [
            "当前 `locals` 是平铺的，建议在 generator 中维护作用域栈或保存回滚点。",
            "Parser 侧只需继续把 `{}` 解析成 `Stmt.Block`。",
        ],
    },
    {
        "id": "T13",
        "title": "闭包捕获局部变量",
        "feature": "支持内部函数读取外层函数局部变量。",
        "score": 120,
        "difficulty": "挑战",
        "baseline_example": textwrap.dedent(
            """\
            func add(a: Int64, b: Int64): Int64 {
                return a + b
            }
            println(add(2, 3))
            return 0
            """
        ),
        "baseline_expect_outputs": ("5",),
        "target_syntax": textwrap.dedent(
            """\
            func outer(x: Int64): Int64 {
                func inner(y: Int64): Int64 {
                    return x + y
                }
                return inner(2)
            }
            """
        ).strip(),
        "expected_effect": "内部函数能够捕获上层局部变量，而不仅仅是共享 `_ENV`。",
        "hints": [
            "需要扩展 upvalue 描述，不再把所有子函数固定写成 `_ENV`。",
            "建议先支持只读捕获，再考虑写回。",
        ],
    },
    {
        "id": "T14",
        "title": "结构体字面量与字段读取",
        "feature": "为子集加入值对象/记录类型的最小实现。",
        "score": 110,
        "difficulty": "挑战",
        "baseline_example": textwrap.dedent(
            """\
            func pointSum(x: Int64, y: Int64): Int64 {
                return x + y
            }
            println(pointSum(2, 3))
            return 0
            """
        ),
        "baseline_expect_outputs": ("5",),
        "target_syntax": textwrap.dedent(
            """\
            struct Point { x: Int64, y: Int64 }
            let p = Point(1, 2)
            println(p.x)
            """
        ).strip(),
        "expected_effect": "支持简单记录对象，并能通过字段名读取值。",
        "hints": [
            "可以先把结构体实例映射成 Lua table，再逐步补齐类型检查。",
            "字段读取阶段可优先复用 `GETFIELD`。",
        ],
    },
    {
        "id": "T15",
        "title": "枚举与 `match`",
        "feature": "支持离散状态建模与分支匹配。",
        "score": 130,
        "difficulty": "挑战",
        "baseline_example": textwrap.dedent(
            """\
            let isOk = true
            if (isOk) {
                println(1)
            } else {
                println(0)
            }
            return 0
            """
        ),
        "baseline_expect_outputs": ("1",),
        "target_syntax": textwrap.dedent(
            """\
            enum Color { Red | Green | Blue }
            match (color) {
                case Red => println(1)
                case Green => println(2)
                case Blue => println(3)
            }
            """
        ).strip(),
        "expected_effect": "允许用更清晰的语法描述有限状态，并把匹配编译为跳转链或查表。",
        "hints": [
            "第一阶段可以只支持无参枚举成员和穷举匹配。",
            "AST 设计尽量预留未来支持带参枚举的空间。",
        ],
    },
    {
        "id": "T16",
        "title": "模块导入与多文件编译",
        "feature": "支持把一个任务拆成多个 `.cj` 源文件协同编译。",
        "score": 140,
        "difficulty": "挑战",
        "baseline_example": textwrap.dedent(
            """\
            func helper(a: Int64): Int64 {
                return a + 1
            }
            println(helper(2))
            return 0
            """
        ),
        "baseline_expect_outputs": ("3",),
        "target_syntax": textwrap.dedent(
            """\
            // math_utils.cj
            public func addOne(a: Int64): Int64 { return a + 1 }

            // main.cj
            import math_utils.*
            println(addOne(2))
            """
        ).strip(),
        "expected_effect": "参赛者可以开始实现更接近真实仓颉工程的编译输入模型。",
        "hints": [
            "先做“多文件拼接后统一编译”的朴素版本，再逐步补齐包/导入规则。",
            "文档与错误信息里要明确指出符号来自哪个文件。",
        ],
    },
]


GUIDE_SECTIONS: list[tuple[str, list[str]]] = [
    (
        "建议的开发顺序",
        [
            "先从 lexer / parser 可独立落地的语法点开始，再进入 codegen 与运行时。",
            "每实现一个特性，就追加最小可运行的 `.scj` 样例，不要等到最后统一补测试。",
            "优先复用 Lua 5.5 现成指令和 table 语义，减少自定义运行时。",
        ],
    ),
    (
        "代码生成清单",
        [
            "确认 AST 是否需要新增节点、是否会影响现有优先级。",
            "确认寄存器/局部变量生命周期是否被新语法拉长。",
            "确认跳转指令是否需要新增回填列表，例如 `break` / `continue`。",
            "确认子函数是否仍只依赖 `_ENV`，还是需要真实 upvalue。",
        ],
    ),
    (
        "错误处理要求",
        [
            "保持现有 `CompileError(ErrorStage, message, line)` 模型，不要随意抛出未捕获异常。",
            "对语法缺失、类型不匹配、运行时失败分别给出稳定且可搜索的错误文本。",
            "新增特性时同步补充 `ExpectError` 样例，确保失败路径也可回归。",
        ],
    ),
    (
        "文档与验收要求",
        [
            "修改 `luavm/luavm.md`、`task.md` 或 `docs/contest-guide.md` 后，务必重新运行文档校验脚本。",
            "所有文档中的仓颉代码片段都应来自 `scripts/competition_docs.py` 的结构化数据，避免手工漂移。",
            "如果扩展了 LuaVM FFI，请先更新 `src/luavm/ffi.cj`，再刷新接口说明文档。",
        ],
    ),
]

OPCODE_DETAILS: dict[str, tuple[str, str, str]] = {
    "MOVE": ("寄存器复制", "把寄存器 B 的值拷贝到寄存器 A。", "局部变量读取、参数搬运、表达式结果转存。"),
    "LOADI": ("加载整数立即数", "把 sBx 范围内的整数直接写入寄存器 A。", "小整数常量、循环计数器、简单 return。"),
    "LOADF": ("加载浮点立即数", "把可表示为整数形态的浮点值写入寄存器 A。", "小范围 `3.0`、`-2.0` 这类浮点字面量。"),
    "LOADK": ("加载常量表项", "从常量表索引 Bx 读取值到寄存器 A。", "大整数、普通浮点、字符串常量。"),
    "LOADKX": ("扩展常量加载", "与 `EXTRAARG` 配合，装载超出 `LOADK` 范围的常量索引。", "常量表很大时的降级路径。"),
    "LOADFALSE": ("加载 `false`", "把布尔假写入寄存器 A。", "比较结果默认值、显式布尔字面量。"),
    "LFALSESKIP": ("加载 `false` 并跳过下一条", "Lua VM 内部使用的分支辅助指令。", "复杂逻辑布尔模板、官方编译器生成代码。"),
    "LOADTRUE": ("加载 `true`", "把布尔真写入寄存器 A。", "比较成功路径、显式布尔字面量。"),
    "LOADNIL": ("加载 `nil`", "把 `nil` 写入寄存器 A（可覆盖一段寄存器）。", "默认初始化、空返回、占位值。"),
    "GETUPVAL": ("读取 upvalue", "把上值表 B 中的值取到寄存器 A。", "闭包捕获、共享 `_ENV`。"),
    "SETUPVAL": ("写入 upvalue", "把寄存器 A 的值写回上值 B。", "闭包内修改外层变量、共享状态。"),
    "GETTABUP": ("读 upvalue 表字段", "从 upvalue B 指向的表里读取常量/寄存器键 C 到 A。", "读取 `_ENV.println`、全局变量访问。"),
    "GETTABLE": ("按键读表", "使用寄存器键从寄存器表对象中读取元素。", "动态下标、map/table 访问。"),
    "GETI": ("按整数索引读表", "从寄存器表对象中按整数索引读取元素。", "数组段访问、顺序容器读取。"),
    "GETFIELD": ("按字段名读表", "以常量字符串字段名读取表字段。", "对象字段、记录类型访问。"),
    "SETTABUP": ("写 upvalue 表字段", "把寄存器值写入 upvalue 表的指定字段。", "把函数/全局变量写回 `_ENV`。"),
    "SETTABLE": ("按键写表", "使用寄存器键和值更新表对象。", "动态字典赋值。"),
    "SETI": ("按整数索引写表", "把寄存器值写到数组段索引位置。", "数组初始化、列表元素更新。"),
    "SETFIELD": ("按字段名写表", "用常量字段名更新表项。", "对象字段赋值、记录构造。"),
    "NEWTABLE": ("创建新表", "在寄存器 A 中分配一个新的 Lua table。", "数组、对象、环境表构造。"),
    "SELF": ("方法调用准备", "把对象和值方法同时装入连续寄存器，为 `obj:method()` 做准备。", "面向对象语法糖。"),
    "ADDI": ("寄存器加立即数", "寄存器 B 与立即数 C 相加，结果写入 A。", "自增、自减、线性下标运算。"),
    "ADDK": ("寄存器加常量", "寄存器值与常量表项相加。", "常量参与的算术表达式。"),
    "SUBK": ("寄存器减常量", "寄存器值减常量表项。", "固定偏移量计算。"),
    "MULK": ("寄存器乘常量", "寄存器值乘常量表项。", "比例缩放、常量倍数。"),
    "MODK": ("寄存器模常量", "寄存器值对常量表项取模。", "周期判断、奇偶判断。"),
    "POWK": ("寄存器幂常量", "寄存器值的常量次幂。", "幂函数、快速模板生成。"),
    "DIVK": ("寄存器除常量", "寄存器值除以常量表项。", "固定系数归一化。"),
    "IDIVK": ("寄存器整除常量", "寄存器值整除常量表项。", "整数网格、块大小分组。"),
    "BANDK": ("按位与常量", "寄存器值与常量按位与。", "标志位过滤。"),
    "BORK": ("按位或常量", "寄存器值与常量按位或。", "标志位组合。"),
    "BXORK": ("按位异或常量", "寄存器值与常量按位异或。", "位翻转、简单编码。"),
    "SHLI": ("左移立即数", "寄存器值左移固定 bit 数。", "位图编码、乘以 2^n。"),
    "SHRI": ("右移立即数", "寄存器值右移固定 bit 数。", "位提取、除以 2^n。"),
    "ADD": ("寄存器加法", "寄存器 B 与 C 相加，结果写入 A。", "普通数值表达式 `a + b`。"),
    "SUB": ("寄存器减法", "寄存器 B 减 C，结果写入 A。", "差值、偏移计算。"),
    "MUL": ("寄存器乘法", "寄存器 B 与 C 相乘。", "面积、比例、累乘。"),
    "MOD": ("寄存器取模", "寄存器 B 对 C 取模。", "循环索引、奇偶判断。"),
    "POW": ("寄存器幂运算", "寄存器 B 的 C 次幂。", "数值计算、指数模板。"),
    "DIV": ("寄存器除法", "寄存器 B 除以 C。", "浮点除法、平均值。"),
    "IDIV": ("寄存器整除", "寄存器 B 整除 C。", "整数除法、分桶。"),
    "BAND": ("按位与", "寄存器 B 与 C 按位与。", "位掩码过滤。"),
    "BOR": ("按位或", "寄存器 B 与 C 按位或。", "位标志累加。"),
    "BXOR": ("按位异或", "寄存器 B 与 C 按位异或。", "校验位、位翻转。"),
    "SHL": ("左移", "寄存器 B 左移 C 位。", "高效乘法、位打包。"),
    "SHR": ("右移", "寄存器 B 右移 C 位。", "位拆包、范围压缩。"),
    "MMBIN": ("二元元方法回退", "在普通二元算术失败时回退到元方法。", "table/userdata 自定义算术。"),
    "MMBINI": ("立即数元方法回退", "当一侧是立即数时执行元方法回退。", "常量参与的自定义运算。"),
    "MMBINK": ("常量元方法回退", "当一侧来自常量表时执行元方法回退。", "常量表达式与对象混算。"),
    "UNM": ("一元负号", "对寄存器 B 执行数值取负，结果写入 A。", "`-x`、数值翻转。"),
    "BNOT": ("按位非", "对寄存器 B 执行按位取反。", "掩码反转。"),
    "NOT": ("逻辑非", "按 Lua 真值语义对寄存器 B 取反。", "布尔取反、条件规约。"),
    "LEN": ("求长度", "读取字符串或 table 的长度到寄存器 A。", "字符串长度、数组长度。"),
    "CONCAT": ("字符串拼接", "把一段连续寄存器内的值拼成字符串。", "字符串连接、格式化拼装。"),
    "CLOSE": ("关闭 upvalue", "关闭从寄存器 A 开始的待关闭上值。", "离开作用域时释放闭包引用。"),
    "TBC": ("标记待关闭变量", "把寄存器 A 标记为 to-be-closed 资源。", "资源管理、RAII 风格清理。"),
    "JMP": ("无条件跳转", "按 sJ 相对偏移调整 PC。", "跳过分支、回到循环头、短路控制。"),
    "EQ": ("寄存器相等比较", "比较两个寄存器是否相等，并结合 k 决定是否跳过下一条。", "`==`、`!=` 模板。"),
    "LT": ("寄存器小于比较", "比较寄存器 B 是否小于 C。", "`<`、`>` 模板。"),
    "LE": ("寄存器小于等于比较", "比较寄存器 B 是否小于等于 C。", "`<=`、`>=` 模板。"),
    "EQK": ("寄存器与常量比较", "把寄存器 A 与常量 Bx 比较。", "常量分支、模式匹配。"),
    "EQI": ("寄存器与立即数比较", "把寄存器 A 与有符号立即数比较。", "小整数快速判断。"),
    "LTI": ("小于立即数", "把寄存器 A 与立即数做 `<` 判断。", "范围检查、循环上界。"),
    "LEI": ("小于等于立即数", "把寄存器 A 与立即数做 `<=` 判断。", "边界判断。"),
    "GTI": ("大于立即数", "把寄存器 A 与立即数做 `>` 判断。", "反向区间判断。"),
    "GEI": ("大于等于立即数", "把寄存器 A 与立即数做 `>=` 判断。", "下界判断。"),
    "TEST": ("真值测试", "检查寄存器 A 的布尔语义并决定是否跳过下一条。", "`if`、`while`、短路求值。"),
    "TESTSET": ("测试并赋值", "在条件满足时把寄存器 B 赋给 A，否则跳过。", "逻辑运算、条件绑定。"),
    "CALL": ("普通函数调用", "从寄存器 A 开始组织函数与参数，按 B/C 约定调用并接收返回。", "函数调用、内置函数调用。"),
    "TAILCALL": ("尾调用", "以尾调用方式调用函数，避免额外栈帧。", "尾递归优化、转发调用。"),
    "RETURN": ("通用返回", "从寄存器 A 开始返回 B-1 个值，C 控制延展语义。", "普通函数 return、多返回值。"),
    "RETURN0": ("零返回快速路径", "直接返回零个值。", "函数末尾隐式返回。"),
    "RETURN1": ("单返回快速路径", "直接返回一个值。", "简单函数/表达式函数优化。"),
    "FORLOOP": ("数值 for 回环", "更新内部索引并判断是否继续循环。", "计数型 `for`。"),
    "FORPREP": ("数值 for 预处理", "初始化计数器、步长和边界后跳入循环。", "数值 `for` 的入口。"),
    "TFORPREP": ("泛型 for 预处理", "为迭代器协议建立循环初始布局。", "`for-in` / 迭代器循环。"),
    "TFORCALL": ("泛型 for 调用", "调用迭代器函数产出下一组值。", "Lua 风格泛型迭代。"),
    "TFORLOOP": ("泛型 for 回环", "根据迭代器返回值判断是否继续循环。", "集合遍历。"),
    "SETLIST": ("批量写数组段", "把一段连续寄存器批量写入 table 数组部分。", "数组字面量、大批量初始化。"),
    "CLOSURE": ("创建闭包", "从子函数原型 Bx 构造闭包并写入寄存器 A。", "函数声明、嵌套函数。"),
    "VARARG": ("读取可变参数", "把当前函数的 vararg 装入目标寄存器段。", "可变参数函数。"),
    "GETVARG": ("访问 vararg 区域", "从 vararg 保存区读取参数。", "高级 vararg 优化。"),
    "ERRNNIL": ("nil 保护报错", "对不允许为 nil 的访问生成专门错误。", "严格索引、空值诊断。"),
    "VARARGPREP": ("vararg 入口准备", "在函数入口整理可变参数布局。", "main 函数、`func f(... )`。"),
    "EXTRAARG": ("扩展参数字", "为前一条指令补充额外宽度的操作数。", "大常量索引、大表大小参数。"),
}

ABX_OPS = {"LOADK", "LOADKX", "CLOSURE", "VARARGPREP"}
ASBX_OPS = {"LOADI", "LOADF", "FORLOOP", "FORPREP"}
SJ_OPS = {"JMP"}
ABCK_OPS = {"EQ", "LT", "LE", "EQK", "EQI", "LTI", "LEI", "GTI", "GEI"}

def parse_ffi_functions() -> list[dict[str, str]]:
    lines = FFI_FILE.read_text(encoding="utf-8").splitlines()
    inside_foreign = False
    current_category = "未分类"
    functions: list[dict[str, str]] = []
    for raw in lines:
        line = raw.strip()
        if line == "foreign {":
            inside_foreign = True
            continue
        if inside_foreign and line == "}":
            break
        if not inside_foreign:
            continue
        if line.startswith("//"):
            category = line[2:].strip()
            if category and not category.startswith("Lua"):
                current_category = category
            continue
        match = re.match(r"func\s+(\w+)\((.*)\):\s*(.+)$", line)
        if match:
            return_type = match.group(3).split("//", 1)[0].rstrip()
            functions.append(
                {
                    "name": match.group(1),
                    "signature": f"{match.group(1)}({match.group(2)}): {return_type}",
                    "category": current_category,
                }
            )
    return functions


def parse_exported_symbols() -> list[str]:
    symbols: list[str] = []
    for line in EXPORTS_FILE.read_text(encoding="utf-8").splitlines():
        item = line.strip()
        if item.startswith("lua"):
            symbols.append(item)
    return symbols


def parse_opcodes() -> list[tuple[str, int]]:
    text = BYTECODE_FILE.read_text(encoding="utf-8")
    enum_match = re.search(r"public enum OpCodes \{(.*?)\n\}", text, re.S)
    if not enum_match:
        raise ValueError("Cannot find OpCodes enum")
    raw_enum = enum_match.group(1)
    enum_names = [line.strip().lstrip("|").strip() for line in raw_enum.splitlines() if line.strip().startswith("|")]

    value_matches = dict(re.findall(r"case OpCodes\.(\w+) => (\d+)", text))
    result: list[tuple[str, int]] = []
    for name in enum_names:
        if name not in value_matches:
            raise ValueError(f"Missing opcode value for {name}")
        result.append((name, int(value_matches[name])))
    return result


def format_md_code(source: str) -> str:
    return source.rstrip() + "\n"


def ensure_binary(path: Path) -> Path:
    if path.exists():
        return path
    for candidate in DEFAULT_BINARY_CANDIDATES:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(
        f"Missing built binary: {path}. Please run `cjpm build` first (after sourcing the Cangjie SDK envsetup.sh)."
    )


def annotate_example(example: DocExample) -> str:
    lines: list[str] = []
    if example.expect_outputs:
        lines.append("// Expected: " + ", ".join(example.expect_outputs))
    if example.expect_return is not None:
        lines.append(f"// ExpectedReturn: {example.expect_return}")
    if example.expect_error is not None:
        suffix = f": {example.expect_error}" if example.expect_error else ""
        lines.append(f"// ExpectError{suffix}")
    lines.append(example.source.rstrip())
    return "\n".join(lines) + "\n"


def runtime_env() -> dict[str, str]:
    env = os.environ.copy()
    lib_paths = [str(LUAVM_LIB_DIR)]
    existing = env.get("LD_LIBRARY_PATH")
    if existing:
        lib_paths.append(existing)
    env["LD_LIBRARY_PATH"] = ":".join(lib_paths)
    return env


def run_example(binary: Path, example: DocExample) -> None:
    with tempfile.TemporaryDirectory(prefix="cangjie-doc-example-") as tmp:
        path = Path(tmp) / f"{example.key}.scj"
        path.write_text(annotate_example(example), encoding="utf-8")
        proc = subprocess.run(
            [str(binary), str(path)],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
            env=runtime_env(),
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"Example {example.key} failed with exit code {proc.returncode}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
            )


def emit_bytecode(binary: Path, source: str, key: str) -> bytes:
    with tempfile.TemporaryDirectory(prefix="cangjie-bytecode-") as tmp:
        path = Path(tmp) / f"{key}.scj"
        path.write_text(source, encoding="utf-8")
        proc = subprocess.run(
            [str(binary), "--emit-bytecode-bytes", str(path)],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
            env=runtime_env(),
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"Bytecode generation failed for {key}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
            )
        numbers = [int(part) for part in proc.stdout.strip().split() if part.strip()]
        return bytes(numbers)


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    while True:
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if byte & 0x80 == 0:
            return value, offset


def decode_lua_integer(coded: int) -> int:
    if coded % 2 == 0:
        return coded // 2
    return -((coded + 1) // 2)


def parse_short_string(data: bytes, offset: int) -> tuple[str, int]:
    length_with_nul, offset = read_varint(data, offset)
    if length_with_nul == 0:
        return "", offset
    raw = data[offset : offset + length_with_nul - 1]
    offset += length_with_nul - 1
    offset += 1
    return raw.decode("utf-8"), offset


def align4(offset: int) -> int:
    while offset % 4 != 0:
        offset += 1
    return offset


def parse_instruction(inst: int, opcode_names: dict[int, str]) -> dict[str, Any]:
    opcode_value = inst & 0x7F
    name = opcode_names[opcode_value]
    decoded: dict[str, Any] = {"raw": inst, "opcode": name, "opcode_value": opcode_value}
    if name in ABX_OPS:
        decoded["A"] = (inst >> A_SHIFT) & A_MASK
        decoded["Bx"] = (inst >> BX_SHIFT) & BX_MASK
    elif name in ASBX_OPS:
        decoded["A"] = (inst >> A_SHIFT) & A_MASK
        decoded["sBx"] = ((inst >> BX_SHIFT) & BX_MASK) - SBX_OFFSET
    elif name in SJ_OPS:
        decoded["sJ"] = ((inst >> SJ_SHIFT) & SJ_MASK) - SJ_OFFSET
    elif name in ABCK_OPS:
        decoded["A"] = (inst >> A_SHIFT) & A_MASK
        decoded["k"] = (inst >> K_SHIFT) & 0x1
        decoded["B"] = (inst >> B_SHIFT) & B_MASK
        decoded["C"] = (inst >> C_SHIFT) & C_MASK
    else:
        decoded["A"] = (inst >> A_SHIFT) & A_MASK
        decoded["B"] = (inst >> B_SHIFT) & B_MASK
        decoded["C"] = (inst >> C_SHIFT) & C_MASK
    return decoded


def parse_proto(data: bytes, offset: int, opcode_names: dict[int, str]) -> tuple[dict[str, Any], int]:
    linedefined, offset = read_varint(data, offset)
    lastlinedefined, offset = read_varint(data, offset)
    numparams = data[offset]
    is_vararg = data[offset + 1]
    maxstacksize = data[offset + 2]
    offset += 3

    instruction_count, offset = read_varint(data, offset)
    offset = align4(offset)
    instructions: list[dict[str, Any]] = []
    for _ in range(instruction_count):
        inst = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        instructions.append(parse_instruction(inst, opcode_names))

    constant_count, offset = read_varint(data, offset)
    constants: list[dict[str, Any]] = []
    for _ in range(constant_count):
        tag = data[offset]
        offset += 1
        if tag == 0x03:
            coded, offset = read_varint(data, offset)
            constants.append({"tag": tag, "type": "Int64", "value": decode_lua_integer(coded)})
        elif tag == 0x13:
            value = struct.unpack_from("<d", data, offset)[0]
            offset += 8
            constants.append({"tag": tag, "type": "Float64", "value": value})
        elif tag == 0x04:
            value, offset = parse_short_string(data, offset)
            constants.append({"tag": tag, "type": "String", "value": value})
        else:
            raise ValueError(f"Unknown constant tag: {tag}")

    upvalue_count, offset = read_varint(data, offset)
    upvalues: list[dict[str, int]] = []
    for _ in range(upvalue_count):
        instack, idx, kind = data[offset], data[offset + 1], data[offset + 2]
        offset += 3
        upvalues.append({"instack": instack, "idx": idx, "kind": kind})

    subproto_count, offset = read_varint(data, offset)
    subprotos: list[dict[str, Any]] = []
    for _ in range(subproto_count):
        subproto, offset = parse_proto(data, offset, opcode_names)
        subprotos.append(subproto)

    metadata_names = ["source_name", "source_position", "lineinfo", "abslineinfo", "locvars", "upvalnames"]
    metadata: dict[str, int] = {}
    for name in metadata_names:
        metadata[name], offset = read_varint(data, offset)

    return (
        {
            "linedefined": linedefined,
            "lastlinedefined": lastlinedefined,
            "numparams": numparams,
            "is_vararg": is_vararg,
            "maxstacksize": maxstacksize,
            "instructions": instructions,
            "constants": constants,
            "upvalues": upvalues,
            "subprotos": subprotos,
            "metadata": metadata,
        },
        offset,
    )


def parse_chunk(data: bytes, opcode_names: dict[int, str]) -> dict[str, Any]:
    offset = 0
    header = {
        "signature": data[offset : offset + 4].hex(" "),
        "version": data[offset + 4],
        "format": data[offset + 5],
        "luac_data": data[offset + 6 : offset + 12].hex(" "),
    }
    offset = 12
    header["sizeof_int"] = data[offset]
    offset += 1
    header["luac_int"] = struct.unpack_from("<i", data, offset)[0]
    offset += 4
    header["sizeof_instruction"] = data[offset]
    offset += 1
    header["luac_inst"] = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    header["sizeof_integer"] = data[offset]
    offset += 1
    header["luac_int64"] = struct.unpack_from("<q", data, offset)[0]
    offset += 8
    header["sizeof_number"] = data[offset]
    offset += 1
    header["luac_num"] = struct.unpack_from("<d", data, offset)[0]
    offset += 8
    header["main_upvalue_count"] = data[offset]
    offset += 1

    proto, offset = parse_proto(data, offset, opcode_names)
    if offset != len(data):
        raise ValueError(f"Chunk parse ended at {offset}, expected {len(data)}")
    return {"header": header, "main": proto}


def format_instruction_fields(inst: dict[str, Any]) -> str:
    order = ["A", "B", "C", "k", "Bx", "sBx", "sJ"]
    parts = [f"{key}={inst[key]}" for key in order if key in inst]
    return ", ".join(parts)

def family_for_export(name: str) -> str:
    if name.startswith("luaL_"):
        return "辅助库（luaL_*）"
    if name.startswith("luaopen_"):
        return "标准库入口（luaopen_*）"
    return "核心 C API（lua_*）"


def note_for_export(name: str, integrated: bool) -> str:
    if integrated:
        return "已在 `src/luavm/ffi.cj` 中绑定，可直接通过 FFI 调用。"
    if name.startswith("luaopen_"):
        return "标准库模块入口，适合细粒度控制要开放哪些 Lua 标准库。"
    if "load" in name or "dump" in name:
        return "与 chunk 加载/导出相关，扩展调试器、缓存或字节码工具时常用。"
    if name.startswith("lua_push") or name.startswith("lua_to"):
        return "栈读写辅助接口，新增宿主函数或原生对象桥接时常用。"
    if name.startswith("lua_get") or name.startswith("lua_set"):
        return "表、栈帧、调试信息或全局环境访问接口。"
    if name.startswith("luaL_check") or name.startswith("luaL_opt"):
        return "参数校验辅助，适合实现更复杂的内置函数。"
    if "thread" in name or "yield" in name or "resume" in name:
        return "协程/线程相关接口，可用于未来的并发与生成器能力。"
    return "当前仓库未直接绑定，扩展运行时能力时可按需加入 FFI。"


def generate_exports_table(ffi_functions: list[dict[str, str]], exports: list[str]) -> str:
    ffi_by_name = {item["name"]: item for item in ffi_functions}
    lines = ["| 符号 | 分类 | 是否已集成 | 仓颉签名 / 说明 | 典型扩展用途 |", "|---|---|---|---|---|"]
    for symbol in exports:
        ffi_item = ffi_by_name.get(symbol)
        signature = f"`{ffi_item['signature']}`" if ffi_item else "未绑定，见导出符号"
        integrated = "是" if ffi_item else "否"
        note = note_for_export(symbol, ffi_item is not None)
        lines.append(
            f"| {symbol} | {family_for_export(symbol)} | {integrated} | {signature} | {note} |"
        )
    return "\n".join(lines)


def generate_ffi_summary_table(ffi_functions: list[dict[str, str]]) -> str:
    lines = ["| 分类 | 接口 | 仓颉签名 |", "|---|---|---|"]
    for item in ffi_functions:
        lines.append(f"| {item['category']} | `{item['name']}` | `{item['signature']}` |")
    return "\n".join(lines)


def instruction_encoding(name: str) -> str:
    if name in ABX_OPS:
        return "iABx"
    if name in ASBX_OPS:
        return "iAsBx"
    if name in SJ_OPS:
        return "isJ"
    if name in ABCK_OPS:
        return "iABC(k)"
    return "iABC"


def generate_opcode_table(opcodes: list[tuple[str, int]]) -> str:
    lines = ["| 编号 | 指令 | 编码 | 功能 | 用法 | 使用场景 |", "|---:|---|---|---|---|---|"]
    for name, value in opcodes:
        summary, usage, scene = OPCODE_DETAILS[name]
        lines.append(f"| {value} | `{name}` | {instruction_encoding(name)} | {summary} | {usage} | {scene} |")
    return "\n".join(lines)


def generate_example_sections(example_chunks: list[dict[str, Any]]) -> str:
    sections: list[str] = []
    for chunk in example_chunks:
        example = chunk["example"]
        parsed = chunk["parsed"]
        header = parsed["header"]
        proto = parsed["main"]
        sections.append(f"### {example.title}")
        sections.append("")
        sections.append(example.purpose)
        sections.append("")
        sections.append("```cangjie")
        sections.append(format_md_code(example.source).rstrip())
        sections.append("```")
        sections.append("")
        sections.append("Header 摘要：")
        sections.append("")
        sections.append(f"- `signature` = `{header['signature']}`")
        sections.append(f"- `version` = `0x{header['version']:02x}`，对应 Lua 5.5")
        sections.append(f"- `format` = `0x{header['format']:02x}`")
        sections.append(f"- `luac_data` = `{header['luac_data']}`")
        sections.append(
            f"- 类型校验 = `int({header['sizeof_int']}) / instruction({header['sizeof_instruction']}) / integer({header['sizeof_integer']}) / number({header['sizeof_number']})`"
        )
        sections.append(f"- `main_upvalue_count` = `{header['main_upvalue_count']}`（当前工程固定为 `_ENV`）")
        sections.append("")
        sections.append("Main Prototype 字段：")
        sections.append("")
        sections.append(f"- `linedefined` / `lastlinedefined` = `{proto['linedefined']} / {proto['lastlinedefined']}`")
        sections.append(f"- `numparams` = `{proto['numparams']}`")
        sections.append(f"- `is_vararg` = `{proto['is_vararg']}`")
        sections.append(f"- `maxstacksize` = `{proto['maxstacksize']}`")
        sections.append(f"- `instruction_count` = `{len(proto['instructions'])}`")
        sections.append(f"- `constant_count` = `{len(proto['constants'])}`")
        sections.append(f"- `upvalue_count` = `{len(proto['upvalues'])}`")
        sections.append(f"- `subproto_count` = `{len(proto['subprotos'])}`")
        sections.append("")
        sections.append("指令序列：")
        sections.append("")
        sections.append("| PC | 指令 | 字段 | 说明 |")
        sections.append("|---:|---|---|---|")
        for pc, inst in enumerate(proto["instructions"]):
            summary = OPCODE_DETAILS[inst["opcode"]][0]
            sections.append(f"| {pc} | `{inst['opcode']}` | `{format_instruction_fields(inst)}` | {summary} |")
        sections.append("")
        if proto["constants"]:
            sections.append("常量表：")
            sections.append("")
            sections.append("| 索引 | 类型 | 值 |")
            sections.append("|---:|---|---|")
            for index, constant in enumerate(proto["constants"]):
                sections.append(f"| {index} | {constant['type']} | `{constant['value']}` |")
            sections.append("")
        else:
            sections.append("常量表为空：该示例中的值都落在立即数或布尔快速路径内。")
            sections.append("")
        sections.append("Upvalue 描述：")
        sections.append("")
        sections.append("| 索引 | instack | idx | kind | 说明 |")
        sections.append("|---:|---:|---:|---:|---|")
        for index, upvalue in enumerate(proto["upvalues"]):
            meaning = "main 函数固定绑定 `_ENV`" if index == 0 else "扩展时可映射到真实闭包上值"
            sections.append(f"| {index} | {upvalue['instack']} | {upvalue['idx']} | {upvalue['kind']} | {meaning} |")
        sections.append("")
        if proto["subprotos"]:
            for sub_index, subproto in enumerate(proto["subprotos"]):
                sections.append(f"子函数原型 #{sub_index}：")
                sections.append("")
                sections.append(f"- `numparams={subproto['numparams']}`，`is_vararg={subproto['is_vararg']}`，`maxstacksize={subproto['maxstacksize']}`")
                sections.append(f"- 指令数 = `{len(subproto['instructions'])}`，常量数 = `{len(subproto['constants'])}`")
                sections.append("- 该原型由 `CLOSURE` 指令在主函数里实例化。")
                sections.append("")
                sections.append("| PC | 指令 | 字段 | 说明 |")
                sections.append("|---:|---|---|---|")
                for pc, inst in enumerate(subproto["instructions"]):
                    summary = OPCODE_DETAILS[inst["opcode"]][0]
                    sections.append(f"| {pc} | `{inst['opcode']}` | `{format_instruction_fields(inst)}` | {summary} |")
                sections.append("")
    return "\n".join(sections).rstrip() + "\n"


def render_luavm_doc(
    ffi_functions: list[dict[str, str]],
    exports: list[str],
    opcodes: list[tuple[str, int]],
    example_chunks: list[dict[str, Any]],
) -> str:
    content = inspect.cleandoc(
        f"""\
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

        {generate_ffi_summary_table(ffi_functions)}

        这些接口覆盖了 CangjieLua 当前必需的运行路径：状态机创建/销毁、栈读写、类型转换、全局环境访问、chunk 加载、受保护调用与 GC。

        ## 3. `luavm/` 动态库全部导出符号

        `luavm/exports.txt` 中共导出 **{len(exports)}** 个符号。为了方便扩展开发，下表同时标明某个符号是否已经在 `ffi.cj` 中集成。

        {generate_exports_table(ffi_functions, exports)}

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

        {generate_opcode_table(opcodes)}

        ## 6. 典型代码对应的 chunk 字段解析

        下列示例全部由 `scripts/competition_docs.py` 调用项目当前构建出的可执行文件，实际生成字节码后解析得到；因此它们既是文档，也是回归测试样例。

        {generate_example_sections(example_chunks)}

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
        """
    )
    return "\n".join(line[8:] if line.startswith("        ") else line for line in content.splitlines()) + "\n"

def task_score_table() -> str:
    lines = ["| 任务 | 特性 | 难度 | 分值 |", "|---|---|---|---:|"]
    for task in TASKS:
        lines.append(f"| {task['id']} | {task['title']} | {task['difficulty']} | {task['score']} |")
    lines.append(f"| **总分** |  |  | **{sum(task['score'] for task in TASKS)}** |")
    return "\n".join(lines)


def render_task_doc() -> str:
    sections = [
        "# AI 编程大赛任务书",
        "",
        "> 本文件由 `scripts/competition_docs.py` 自动生成。所有 `cangjie` 代码块都来自脚本中的结构化数据，并会在文档校验时自动执行。",
        "",
        "## 1. 评分方式",
        "",
        "- 每个小任务对应一个细粒度仓颉语言特性。",
        "- 选手完成并通过测试后，即可获得对应分值。",
        "- 建议按“入门 → 中等 → 进阶 → 挑战”的顺序逐步实现，避免一次引入过多语法与运行时变化。",
        "",
        task_score_table(),
        "",
        "## 2. 任务列表",
        "",
    ]
    for task in TASKS:
        sections.extend(
            [
                f"### {task['id']} · {task['title']}（{task['score']} 分，{task['difficulty']}）",
                "",
                f"**特性描述**：{task['feature']}",
                "",
                "**当前可运行的对照片段**：",
                "",
                "```cangjie",
                format_md_code(task['baseline_example']).rstrip(),
                "```",
                "",
                "**建议扩展后的目标写法（说明用途，不纳入当前自动执行）**：",
                "",
                "```text",
                task['target_syntax'],
                "```",
                "",
                f"**期望效果**：{task['expected_effect']}",
                "",
                "**实现方案提示**：",
            ]
        )
        for hint in task["hints"]:
            sections.append(f"- {hint}")
        sections.append("")
    sections.extend(
        [
            "## 3. 验收建议",
            "",
            "- 每完成一个任务，至少补充一条成功样例和一条失败样例。",
            "- 若任务影响字节码生成，建议同步刷新 `luavm/luavm.md` 中的相关说明。",
            "- 涉及新的 LuaVM FFI 时，先确认动态库已导出对应符号，再更新 `src/luavm/ffi.cj`。",
        ]
    )
    return "\n".join(sections).rstrip() + "\n"


def render_guide_doc() -> str:
    lines = [
        "# 参赛扩展开发指南",
        "",
        "> 本文件由 `scripts/competition_docs.py` 自动生成，用于补充任务书之外的工程实践建议。",
        "",
        "## 1. 环境准备",
        "",
        "1. 下载并解压题目给出的仓颉 SDK。",
        "2. 执行 `source <sdk>/envsetup.sh` 让 `cjpm` / `cjc` 进入 PATH。",
        "3. 在仓库根目录运行：",
        "",
        "```bash",
        "cjpm build",
        "cjpm run",
        "python3 scripts/competition_docs.py check",
        "```",
        "",
        "这样可以同时验证现有解释器功能与比赛文档是否同步。",
        "",
    ]
    for title, bullets in GUIDE_SECTIONS:
        lines.append(f"## {title}")
        lines.append("")
        for item in bullets:
            lines.append(f"- {item}")
        lines.append("")
    lines.extend(
        [
            "## 调试建议",
            "",
            "- 语法改动优先看 `src/lexer` 与 `src/parser`；不要一开始就修改 LuaVM 层。",
            "- 若程序运行结果异常，先比较 `PrintRuntime` 捕获值与 return 值，再查看生成的指令序列。",
            "- 需要分析 chunk 时，可运行仓库可执行文件的隐藏参数：",
            "",
            "```bash",
            "./target/release/bin/main --emit-bytecode-bytes /path/to/example.scj",
            "```",
            "",
            "该输出会被 `scripts/competition_docs.py` 解析成文档中的字段表，可作为你自己的调试入口。",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def build_example_chunks(binary: Path, opcode_names: dict[int, str]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for example in BYTECODE_EXAMPLES:
        bytecode = emit_bytecode(binary, example.source, example.key)
        parsed = parse_chunk(bytecode, opcode_names)
        result.append({"example": example, "parsed": parsed})
    return result


def generated_documents(binary: Path) -> dict[Path, str]:
    ffi_functions = parse_ffi_functions()
    exports = parse_exported_symbols()
    opcodes = parse_opcodes()
    opcode_names = {value: name for name, value in opcodes}
    if set(OPCODE_DETAILS) != {name for name, _ in opcodes}:
        missing = sorted({name for name, _ in opcodes} - set(OPCODE_DETAILS))
        extra = sorted(set(OPCODE_DETAILS) - {name for name, _ in opcodes})
        raise ValueError(f"Opcode metadata mismatch. Missing={missing}, Extra={extra}")
    example_chunks = build_example_chunks(binary, opcode_names)
    return {
        LUAVM_DOC: render_luavm_doc(ffi_functions, exports, opcodes, example_chunks),
        TASK_DOC: render_task_doc(),
        GUIDE_DOC: render_guide_doc(),
    }


def write_documents(binary: Path) -> None:
    for path, content in generated_documents(binary).items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"wrote {path.relative_to(REPO_ROOT)}")


def check_documents(binary: Path) -> None:
    docs = generated_documents(binary)
    for path, expected in docs.items():
        actual = path.read_text(encoding="utf-8") if path.exists() else None
        if actual != expected:
            raise AssertionError(f"Document out of date: {path.relative_to(REPO_ROOT)}. Run `python3 scripts/competition_docs.py generate`.")
    for example in BYTECODE_EXAMPLES:
        run_example(binary, example)
    for task in TASKS:
        run_example(
            binary,
            DocExample(
                key=task["id"].lower(),
                title=task["title"],
                source=task["baseline_example"],
                expect_outputs=tuple(task["baseline_expect_outputs"]),
                expect_return=task.get("baseline_expect_return"),
                expect_error=task.get("baseline_expect_error"),
            ),
        )
    print("competition docs are up to date and all documented examples passed")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate and validate competition documentation")
    parser.add_argument("command", choices=["generate", "check"], help="write docs or verify docs")
    parser.add_argument("--binary", default=str(DEFAULT_BINARY_CANDIDATES[0]), help="path to built CangjieLua executable")
    args = parser.parse_args()

    binary = ensure_binary(Path(args.binary))
    if args.command == "generate":
        write_documents(binary)
    else:
        check_documents(binary)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
