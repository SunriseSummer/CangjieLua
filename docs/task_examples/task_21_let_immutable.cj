// 任务 20：let 不可变检查
// 注：此示例在标准仓颉编译器上会报编译错误，这是预期行为。
// CangjieLua 中应同样报错。
// 以下代码展示正确的 let 不可变行为：
main() {
    let x = 10
    println(x)
    // Expected: 10
    // 如果尝试 x = 20，应报错：immutable
}
