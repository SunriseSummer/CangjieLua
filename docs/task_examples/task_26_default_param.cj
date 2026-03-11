// 任务 26：默认参数值
func greet(name: String, greeting!: String = "Hello") {
    println(greeting)
    println(name)
}

main() {
    greet("World")
    greet("World", greeting: "Hi")
    // Expected: Hello, World, Hi, World
}
