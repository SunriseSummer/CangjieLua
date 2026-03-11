// 任务 10：多返回值
func swap(a: Float64, b: Float64): (Float64, Float64) {
    return (b, a)
}

main() {
    let (x, y) = swap(1.0, 2.0)
    println(x)
    println(y)
    // Expected: 2.0, 1.0
}
