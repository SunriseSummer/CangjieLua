// 任务 22：嵌套函数与闭包
func makeAdder(n: Int64): (Int64) -> Int64 {
    return { x: Int64 => x + n }
}

main() {
    let add5 = makeAdder(5)
    println(add5(10))
    // Expected: 15
}
