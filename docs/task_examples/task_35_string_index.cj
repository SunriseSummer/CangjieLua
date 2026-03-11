// 任务 35：字符串索引访问
// 注：在 CangjieLua 中，str[index] 直接返回单字符字符串
// 标准仓颉编译器使用 toRuneArray() 后索引访问等价实现
main() {
    let s = "hello"
    var runes = s.toRuneArray()
    println(runes[0])
    println(runes[4])
    // Expected: h, o
}
