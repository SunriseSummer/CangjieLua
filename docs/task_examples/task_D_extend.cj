// 附加任务 D：extend 扩展
extend Int64 {
    func isEven(): Bool {
        return this % 2 == 0
    }
}

main() {
    let x = 4
    println(x.isEven())
    // Expected: true
}
