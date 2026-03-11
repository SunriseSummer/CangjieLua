// 任务 30：continue 表达式
main() {
    var sum = 0
    var i = 0
    while (i < 10) {
        i = i + 1
        if (i % 2 == 0) {
            continue
        }
        sum = sum + i
    }
    println(sum)
    // Expected: 25
}
