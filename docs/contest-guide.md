# 参赛扩展开发指南

> 本文件由 `scripts/competition_docs.py` 自动生成，用于补充任务书之外的工程实践建议。

## 1. 环境准备

1. 下载并解压题目给出的仓颉 SDK。
2. 执行 `source <sdk>/envsetup.sh` 让 `cjpm` / `cjc` 进入 PATH。
3. 在仓库根目录运行：

```bash
cjpm build
cjpm run
python3 scripts/competition_docs.py check
```

这样可以同时验证现有解释器功能与比赛文档是否同步。

## 建议的开发顺序

- 先从 lexer / parser 可独立落地的语法点开始，再进入 codegen 与运行时。
- 每实现一个特性，就追加最小可运行的 `.scj` 样例，不要等到最后统一补测试。
- 优先复用 Lua 5.5 现成指令和 table 语义，减少自定义运行时。

## 代码生成清单

- 确认 AST 是否需要新增节点、是否会影响现有优先级。
- 确认寄存器/局部变量生命周期是否被新语法拉长。
- 确认跳转指令是否需要新增回填列表，例如 `break` / `continue`。
- 确认子函数是否仍只依赖 `_ENV`，还是需要真实 upvalue。

## 错误处理要求

- 保持现有 `CompileError(ErrorStage, message, line)` 模型，不要随意抛出未捕获异常。
- 对语法缺失、类型不匹配、运行时失败分别给出稳定且可搜索的错误文本。
- 新增特性时同步补充 `ExpectError` 样例，确保失败路径也可回归。

## 文档与验收要求

- 修改 `luavm/luavm.md`、`task.md` 或 `docs/contest-guide.md` 后，务必重新运行文档校验脚本。
- 所有文档中的仓颉代码片段都应来自 `scripts/competition_docs.py` 的结构化数据，避免手工漂移。
- 如果扩展了 LuaVM FFI，请先更新 `src/luavm/ffi.cj`，再刷新接口说明文档。

## 调试建议

- 语法改动优先看 `src/lexer` 与 `src/parser`；不要一开始就修改 LuaVM 层。
- 若程序运行结果异常，先比较 `PrintRuntime` 捕获值与 return 值，再查看生成的指令序列。
- 需要分析 chunk 时，可运行仓库可执行文件的隐藏参数：

```bash
./target/release/bin/main --emit-bytecode-bytes /path/to/example.scj
```

该输出会被 `scripts/competition_docs.py` 解析成文档中的字段表，可作为你自己的调试入口。
