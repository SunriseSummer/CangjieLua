// 任务 11：else if 链
main() {
    var x = 15
    var result = 0
    if (x > 20) {
        result = 3
    } else if (x > 10) {
        result = 2
    } else if (x > 5) {
        result = 1
    } else {
        result = 0
    }
    println(result)
    // Expected: 2
}
