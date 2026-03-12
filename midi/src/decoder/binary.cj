package midi.decoder

// ============================================================
// MIDI 二进制读取工具
// ============================================================

// VLQ 读取结果
class DecVLQ {
    var value: UInt32
    var newPos: Int64
    init(value: UInt32, newPos: Int64) {
        this.value = value
        this.newPos = newPos
    }
}

// 读取大端 UInt16
func decReadU16(data: Array<UInt8>, pos: Int64): UInt16 {
    UInt16(data[pos]) << 8 | UInt16(data[pos + 1])
}

// 读取大端 UInt32
func decReadU32(data: Array<UInt8>, pos: Int64): UInt32 {
    UInt32(data[pos]) << 24 | UInt32(data[pos + 1]) << 16 |
        UInt32(data[pos + 2]) << 8 | UInt32(data[pos + 3])
}

// 读取 VLQ（变长数值编码）
func decReadVLQ(data: Array<UInt8>, pos: Int64, end: Int64): DecVLQ {
    var value: UInt32 = 0
    var i = pos
    while (i < end) {
        let b = data[i]
        value = (value << 7) | UInt32(b & 0x7F)
        i++
        if ((b & 0x80) == 0) { break }
    }
    DecVLQ(value, i)
}
