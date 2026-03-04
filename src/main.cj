package cangjie_lua

// 程序入口：支持指定单个测试文件或批量运行 tests/ 目录
main(args: Array<String>): Int64 {
    let runner = TestRunner()
    if (args.size > 0) {
        runner.runTestFile(args[0])
    } else {
        runner.runAllTestFiles("./tests")
    }
    return runner.failed
}
