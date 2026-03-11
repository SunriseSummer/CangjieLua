// 附加任务 A：简单类定义
class Point {
    var x: Float64
    var y: Float64

    init(x: Float64, y: Float64) {
        this.x = x
        this.y = y
    }

    func getX(): Float64 {
        return this.x
    }
}

main() {
    let p = Point(3.0, 4.0)
    println(p.getX())
    // Expected: 3.0
}
