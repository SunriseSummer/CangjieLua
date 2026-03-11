// 任务 35：错误处理 try-catch
func divide(a: Float64, b: Float64): Float64 {
    if (b == 0.0) {
        throw Exception("division by zero")
    }
    return a / b
}

main() {
    try {
        let _ = divide(10.0, 0.0)
    } catch (e: Exception) {
        println(e.message)
    }
    // Expected: division by zero
}
