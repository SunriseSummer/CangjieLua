package cangjie_lua.codegen

import std.collection.*

// ============================================================
// VarInt 编码常量（Lua 5.5 使用 LSB-first 变长整数编码）
// ============================================================
let VARINT_CONTINUE_MASK: Int64 = 0x80  // 最高位为 1 表示后续还有字节
let VARINT_DATA_MASK:     Int64 = 0x7F  // 低 7 位为数据位

// 短字符串长度阈值：len < 此值时用单字节表示长度
let SHORT_STRING_LEN_THRESHOLD: Int64 = 254

// ============================================================
// ChunkWriter —— Lua 二进制块写入器
// 负责将字节码数据序列化为 Lua 5.5 二进制格式。
// 内部维护一个字节缓冲区，提供多种写入方法。
// ============================================================
public class ChunkWriter {
    private var buffer = ArrayList<UInt8>()  // 输出字节缓冲区

    public init() {}

    /// 写入单个字节
    public func writeByte(b: UInt8): Unit {
        buffer.add(b)
    }

    /// 写入字节数组
    public func writeBytes(bytes: Array<UInt8>): Unit {
        for (b in bytes) {
            buffer.add(b)
        }
    }

    /// 写入 32 位有符号整数（小端序）
    public func writeInt32(n: Int32): Unit {
        buffer.add(UInt8(n & 0xFF))
        buffer.add(UInt8((n >> 8) & 0xFF))
        buffer.add(UInt8((n >> 16) & 0xFF))
        buffer.add(UInt8((n >> 24) & 0xFF))
    }

    /// 写入 32 位无符号整数（小端序）
    public func writeUInt32(n: UInt32): Unit {
        buffer.add(UInt8(n & 0xFF))
        buffer.add(UInt8((n >> 8) & 0xFF))
        buffer.add(UInt8((n >> 16) & 0xFF))
        buffer.add(UInt8((n >> 24) & 0xFF))
    }

    /// 写入 64 位有符号整数（小端序）
    public func writeInt64(n: Int64): Unit {
        buffer.add(UInt8(n & 0xFF))
        buffer.add(UInt8((n >> 8) & 0xFF))
        buffer.add(UInt8((n >> 16) & 0xFF))
        buffer.add(UInt8((n >> 24) & 0xFF))
        buffer.add(UInt8((n >> 32) & 0xFF))
        buffer.add(UInt8((n >> 40) & 0xFF))
        buffer.add(UInt8((n >> 48) & 0xFF))
        buffer.add(UInt8((n >> 56) & 0xFF))
    }

    /// 写入 64 位浮点数（通过 unsafe 内存拷贝获取 IEEE 754 字节表示）
    public func writeFloat64(n: Float64): Unit {
        unsafe {
            let ptr = LibC.malloc<Float64>()
            ptr.write(n)
            var arr = Array<UInt8>(8, { _ => 0 })
            var handle = acquireArrayRawData(arr)
            var src = CPointer<UInt8>(ptr)
            for (i in 0..8) {
                arr[i] = src.read(i)
            }
            releaseArrayRawData(handle)
            LibC.free(ptr)
            for (b in arr) {
                buffer.add(b)
            }
        }
    }

    /// 写入长度前缀字符串（旧格式，短字符串用单字节长度，长字符串用 0xFF + Int64）
    public func writeString(s: String): Unit {
        let bytes = s.toArray()
        let len = bytes.size
        if (len < SHORT_STRING_LEN_THRESHOLD) {
            writeByte(UInt8(len))
        } else {
            writeByte(0xFFu8)
            writeInt64(Int64(len))
        }
        for (b in bytes) {
            buffer.add(b)
        }
    }

    /// 写入短字符串（VarInt 长度 + 内容 + NUL 终止符）
    public func writeShortString(s: String): Unit {
        let bytes = s.toArray()
        let len = bytes.size
        writeVarInt(len + 1)  // +1 包含 NUL 终止符
        for (b in bytes) {
            buffer.add(b)
        }
        writeByte(0u8)  // NUL 终止符
    }

    /// 写入变长整数（LSB-first VarInt 编码）
    /// 每字节低 7 位为数据，最高位为 1 表示后续还有字节
    public func writeVarInt(n: Int64): Unit {
        var val = n
        while (val >= VARINT_CONTINUE_MASK) {
            writeByte(UInt8((val & VARINT_DATA_MASK) | VARINT_CONTINUE_MASK))
            val = val >> 7
        }
        writeByte(UInt8(val))
    }

    /// 写入空字符串标记（两个 0 字节）
    public func writeNullString(): Unit {
        writeByte(0u8)
        writeByte(0u8)
    }

    /// writeVarInt 的 Int32 便捷重载
    public func writeVarIntInt(n: Int32): Unit {
        writeVarInt(Int64(n))
    }

    /// 写入对齐填充字节，使 buffer 大小对齐到指定边界
    public func writeAlign(align: Int64): Unit {
        let offset = buffer.size
        let padding = align - (offset % align)
        if (padding < align) {
            for (_ in 0..padding) {
                writeByte(0u8)
            }
        }
    }

    /// 写入一条 32 位指令（等价于 writeUInt32）
    public func writeInstruction(inst: UInt32): Unit {
        writeUInt32(inst)
    }

    /// 获取当前缓冲区大小
    public func size(): Int64 {
        return buffer.size
    }

    /// 将缓冲区导出为字节数组
    public func toByteArray(): Array<UInt8> {
        return buffer.toArray()
    }

    /// 获取内部缓冲区引用
    public func getBuffer(): ArrayList<UInt8> {
        return buffer
    }
}
