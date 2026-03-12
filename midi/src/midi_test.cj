package midi

import std.fs.*
import midi.encoder.*
import midi.decoder.*

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

// 验证外部 .mid 文件的反编译+重编码二进制一致性
func verifyExternalMid(midPath: String) {
    let p = Path(midPath)
    if (!exists(p)) {
        return
    }

    let data = File.readFrom(p)
    @Assert(data.size >= 14)
    @Assert(data[0], 0x4D)  // 'M'
    @Assert(data[1], 0x54)  // 'T'
    @Assert(data[2], 0x68)  // 'h'
    @Assert(data[3], 0x64)  // 'd'

    let text = decompile(data)
    @Assert(text.startsWith("MIDI"))

    let regen = generate(text)
    @Expect(data.size, regen.size)
    verifyBinaryIdentical(data, regen)
}
