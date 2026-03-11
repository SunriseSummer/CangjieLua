// 任务 20：类型注解增强
func add(a: Int64, b: Int64): Int64 {
    return a + b
}

main() {
    let x: Int64 = 42
    let y: Float64 = 3.14
    let s: String = "hello"
    let b: Bool = true
    println(add(3, 4))
    // Expected: 7
}
