// 任务 25：尾调用优化
func loop(n: Int64, acc: Int64): Int64 {
    if (n <= 0) {
        return acc
    }
    return loop(n - 1, acc + n)
}

main() {
    println(loop(10000, 0))
    // Expected: 50005000
}
