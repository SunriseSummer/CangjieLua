// 附加任务 C：模式匹配 match
func describe(x: Int64): String {
    match (x) {
        case 0 => return "zero"
        case 1 => return "one"
        case _ => return "other"
    }
}

main() {
    println(describe(1))
    // Expected: one
}
