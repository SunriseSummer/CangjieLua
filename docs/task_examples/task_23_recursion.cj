// 任务 23：递归函数调用
func fib(n: Int64): Int64 {
    if (n <= 1) {
        return n
    }
    return fib(n - 1) + fib(n - 2)
}

main() {
    println(fib(10))
    // Expected: 55
}
