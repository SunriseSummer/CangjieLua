// 任务 14：一元取反运算符 ~
main() {
    let a = 0 ^ (-1)
    println(a)
    let b = 1 ^ (-1)
    println(b)
    // Expected: -1, -2
    // 注：标准仓颉中 ~ 运算符不能直接用于表达式，
    // 这里用 XOR -1 等价实现来验证逻辑。
    // CangjieLua 中应实现 ~expr 前缀语法。
}
