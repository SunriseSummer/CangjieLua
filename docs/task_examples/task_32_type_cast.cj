// 任务 32：类型转换表达式
main() {
    let a: Float64 = Float64(42)
    let b: Int64 = Int64(3.7)
    println(a)
    println(b)
    // Expected: 42.0, 3
    // 注：标准仓颉中 Float64(42) 输出为 42.000000，
    // CangjieLua 中应输出 42.0（与 Lua 浮点数格式一致）
}
