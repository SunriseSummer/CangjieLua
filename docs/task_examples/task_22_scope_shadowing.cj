// 任务 22：作用域与变量遮蔽
main() {
    let x = 10
    if (true) {
        let x = 20
        println(x)
    }
    println(x)
    // Expected: 20, 10
}
