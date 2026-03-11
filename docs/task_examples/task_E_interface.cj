// 附加任务 E：interface 接口
interface Printable {
    func display(): String
}

class User <: Printable {
    var name: String

    init(name: String) {
        this.name = name
    }

    public func display(): String {
        return this.name
    }
}

main() {
    let u = User("Alice")
    println(u.display())
    // Expected: Alice
}
