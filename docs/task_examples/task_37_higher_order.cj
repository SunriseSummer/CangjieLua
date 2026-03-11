// 任务 37：高阶函数
func apply(f: (Int64) -> Int64, x: Int64): Int64 {
    return f(x)
}

func square(n: Int64): Int64 {
    return n * n
}

main() {
    println(apply(square, 5))
    // Expected: 25
}
