// 任务 29：break 表达式
main() {
    var i = 0
    while (true) {
        if (i >= 5) {
            break
        }
        i = i + 1
    }
    println(i)
    // Expected: 5
}
