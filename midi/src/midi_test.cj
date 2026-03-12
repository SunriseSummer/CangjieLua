package midi

// ============================================================
// 测试辅助函数（供所有测试文件共用）
// ============================================================

// 验证两个字节数组二进制完全一致
func verifyBinaryIdentical(a: Array<UInt8>, b: Array<UInt8>) {
    @Expect(a.size, b.size)
    var i: Int64 = 0
    while (i < a.size && i < b.size) {
        if (a[i] != b[i]) {
            println("  BINARY DIFF at byte ${i}: expected ${a[i]}, got ${b[i]}")
            @Assert(false)
            return
        }
        i++
    }
}
