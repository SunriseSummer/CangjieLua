// 附加任务 B：类的继承和多态
open class Animal {
    var name: String

    init(name: String) {
        this.name = name
    }

    public open func speak(): String {
        return "..."
    }
}

class Dog <: Animal {
    init(name: String) {
        super(name)
    }

    public override func speak(): String {
        return "Woof"
    }
}

main() {
    let d = Dog("Rex")
    println(d.speak())
    // Expected: Woof
}
