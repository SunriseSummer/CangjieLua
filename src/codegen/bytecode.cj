package cangjie_lua.codegen

// Lua 5.5 二进制块头部常量
let LUA_SIGNATURE: Array<UInt8> = [0x1b, 0x4c, 0x75, 0x61]  // "\x1bLua"

let LUAC_VERSION: UInt8 = 0x55      // Lua 5.5
let LUAC_FORMAT: UInt8 = 0x00       // 官方格式

let LUAC_DATA: Array<UInt8> = [0x19, 0x93, 0x0d, 0x0a, 0x1a, 0x0a]  // 校验数据

let LUAC_INT: Int32 = -0x5678       // 整数格式校验值
let LUAC_INST: UInt32 = 0x12345678  // 指令格式校验值（字节序检测）
let LUAC_INT64: Int64 = -0x5678     // 64 位整数校验值
let LUAC_NUM: Float64 = -370.5      // 浮点数格式校验值

// Lua 5.5 指令格式位域常量
// Lua 指令为 32 位定长，常见编码形式：
//   iABC : [opcode:7][A:8][k:1][B:8][C:8]
//   iABx : [opcode:7][A:8][Bx:17]
//   iAsBx: [opcode:7][A:8][sBx:17 signed]
//   isJ  : [opcode:7][sJ:25 signed]

let A_SHIFT:     UInt32 = 7    // A 字段起始位 = OP_BITS
let K_SHIFT:     UInt32 = 15   // k 标志起始位 = OP_BITS + A_BITS
let B_SHIFT:     UInt32 = 16   // B 字段起始位 = OP_BITS + A_BITS + K_BITS
let C_SHIFT:     UInt32 = 24   // C 字段起始位 = OP_BITS + A_BITS + K_BITS + B_BITS
let BX_SHIFT:    UInt32 = 15   // Bx 字段起始位 = OP_BITS + A_BITS
let SJ_SHIFT:    UInt32 = 7    // sJ 字段起始位 = OP_BITS

let A_MASK:      UInt32 = 0xFF       // A 字段掩码  (8 bits)
let B_MASK:      UInt32 = 0xFF       // B 字段掩码  (8 bits)
let C_MASK:      UInt32 = 0xFF       // C 字段掩码  (8 bits)
let K_MASK:      UInt32 = 0x1        // k 标志掩码  (1 bit)
let BX_MASK:     UInt32 = 0x1FFFF    // Bx 字段掩码 (17 bits)
let SJ_MASK:     UInt32 = 0x1FFFFFF  // sJ 字段掩码 (25 bits)

let SBX_OFFSET:  Int32 = 65535       // sBx 偏移量 = 2^16 - 1 (将有符号值映射到无符号)
let SJ_OFFSET:   Int32 = 16777215    // sJ 偏移量  = 2^24 - 1
let SB_OFFSET:   Int32 = 127         // sB 偏移量  = 2^7 - 1 (EQI 指令的 sB 字段)

// OpCodes：Lua 5.5 虚拟机操作码枚举（共 85 个）
public enum OpCodes {
    | MOVE
    | LOADI
    | LOADF
    | LOADK
    | LOADKX
    | LOADFALSE
    | LFALSESKIP
    | LOADTRUE
    | LOADNIL
    | GETUPVAL
    | SETUPVAL
    | GETTABUP
    | GETTABLE
    | GETI
    | GETFIELD
    | SETTABUP
    | SETTABLE
    | SETI
    | SETFIELD
    | NEWTABLE
    | SELF
    | ADDI
    | ADDK
    | SUBK
    | MULK
    | MODK
    | POWK
    | DIVK
    | IDIVK
    | BANDK
    | BORK
    | BXORK
    | SHLI
    | SHRI
    | ADD
    | SUB
    | MUL
    | MOD
    | POW
    | DIV
    | IDIV
    | BAND
    | BOR
    | BXOR
    | SHL
    | SHR
    | MMBIN
    | MMBINI
    | MMBINK
    | UNM
    | BNOT
    | NOT
    | LEN
    | CONCAT
    | CLOSE
    | TBC
    | JMP
    | EQ
    | LT
    | LE
    | EQK
    | EQI
    | LTI
    | LEI
    | GTI
    | GEI
    | TEST
    | TESTSET
    | CALL
    | TAILCALL
    | RETURN
    | RETURN0
    | RETURN1
    | FORLOOP
    | FORPREP
    | TFORPREP
    | TFORCALL
    | TFORLOOP
    | SETLIST
    | CLOSURE
    | VARARG
    | GETVARG
    | ERRNNIL
    | VARARGPREP
    | EXTRAARG
}

/// 将 OpCodes 枚举映射为对应的数值编号
public func opcodeValue(op: OpCodes): UInt32 {
    match (op) {
        case OpCodes.MOVE => 0
        case OpCodes.LOADI => 1
        case OpCodes.LOADF => 2
        case OpCodes.LOADK => 3
        case OpCodes.LOADKX => 4
        case OpCodes.LOADFALSE => 5
        case OpCodes.LFALSESKIP => 6
        case OpCodes.LOADTRUE => 7
        case OpCodes.LOADNIL => 8
        case OpCodes.GETUPVAL => 9
        case OpCodes.SETUPVAL => 10
        case OpCodes.GETTABUP => 11
        case OpCodes.GETTABLE => 12
        case OpCodes.GETI => 13
        case OpCodes.GETFIELD => 14
        case OpCodes.SETTABUP => 15
        case OpCodes.SETTABLE => 16
        case OpCodes.SETI => 17
        case OpCodes.SETFIELD => 18
        case OpCodes.NEWTABLE => 19
        case OpCodes.SELF => 20
        case OpCodes.ADDI => 21
        case OpCodes.ADDK => 22
        case OpCodes.SUBK => 23
        case OpCodes.MULK => 24
        case OpCodes.MODK => 25
        case OpCodes.POWK => 26
        case OpCodes.DIVK => 27
        case OpCodes.IDIVK => 28
        case OpCodes.BANDK => 29
        case OpCodes.BORK => 30
        case OpCodes.BXORK => 31
        case OpCodes.SHLI => 32
        case OpCodes.SHRI => 33
        case OpCodes.ADD => 34
        case OpCodes.SUB => 35
        case OpCodes.MUL => 36
        case OpCodes.MOD => 37
        case OpCodes.POW => 38
        case OpCodes.DIV => 39
        case OpCodes.IDIV => 40
        case OpCodes.BAND => 41
        case OpCodes.BOR => 42
        case OpCodes.BXOR => 43
        case OpCodes.SHL => 44
        case OpCodes.SHR => 45
        case OpCodes.MMBIN => 46
        case OpCodes.MMBINI => 47
        case OpCodes.MMBINK => 48
        case OpCodes.UNM => 49
        case OpCodes.BNOT => 50
        case OpCodes.NOT => 51
        case OpCodes.LEN => 52
        case OpCodes.CONCAT => 53
        case OpCodes.CLOSE => 54
        case OpCodes.TBC => 55
        case OpCodes.JMP => 56
        case OpCodes.EQ => 57
        case OpCodes.LT => 58
        case OpCodes.LE => 59
        case OpCodes.EQK => 60
        case OpCodes.EQI => 61
        case OpCodes.LTI => 62
        case OpCodes.LEI => 63
        case OpCodes.GTI => 64
        case OpCodes.GEI => 65
        case OpCodes.TEST => 66
        case OpCodes.TESTSET => 67
        case OpCodes.CALL => 68
        case OpCodes.TAILCALL => 69
        case OpCodes.RETURN => 70
        case OpCodes.RETURN0 => 71
        case OpCodes.RETURN1 => 72
        case OpCodes.FORLOOP => 73
        case OpCodes.FORPREP => 74
        case OpCodes.TFORPREP => 75
        case OpCodes.TFORCALL => 76
        case OpCodes.TFORLOOP => 77
        case OpCodes.SETLIST => 78
        case OpCodes.CLOSURE => 79
        case OpCodes.VARARG => 80
        case OpCodes.GETVARG => 81
        case OpCodes.ERRNNIL => 82
        case OpCodes.VARARGPREP => 83
        case OpCodes.EXTRAARG => 84
    }
}

// 指令编码函数：将操作码与操作数打包为 32 位指令

/// 编码 iABC 格式指令：op | A | B | C
public func encodeABC(op: OpCodes, a: UInt32, b: UInt32, c: UInt32): UInt32 {
    return opcodeValue(op) | ((a & A_MASK) << A_SHIFT) | ((b & B_MASK) << B_SHIFT) | ((c & C_MASK) << C_SHIFT)
}

/// 编码 iABx 格式指令：op | A | Bx（无符号）
public func encodeABx(op: OpCodes, a: UInt32, bx: UInt32): UInt32 {
    return opcodeValue(op) | ((a & A_MASK) << A_SHIFT) | ((bx & BX_MASK) << BX_SHIFT)
}

/// 编码 iAsBx 格式指令：op | A | sBx（有符号，加偏移量转无符号）
public func encodeAsBx(op: OpCodes, a: UInt32, sbx: Int32): UInt32 {
    let unsignedSbx = UInt32(sbx + SBX_OFFSET)
    return opcodeValue(op) | ((a & A_MASK) << A_SHIFT) | ((unsignedSbx & BX_MASK) << BX_SHIFT)
}

/// 编码 isJ 格式指令：op | sJ（有符号跳转偏移量）
public func encodeIsJ(op: OpCodes, sj: Int32): UInt32 {
    let unsignedSj = UInt32(sj + SJ_OFFSET)
    return opcodeValue(op) | ((unsignedSj & SJ_MASK) << SJ_SHIFT)
}

/// 编码 iABC 格式指令（带 k 标志位）：op | A | k | B | C
public func encodeABCK(op: OpCodes, a: UInt32, b: UInt32, c: UInt32, k: UInt32): UInt32 {
    return opcodeValue(op) | ((a & A_MASK) << A_SHIFT) | ((b & B_MASK) << B_SHIFT) | (c << C_SHIFT) | ((k & K_MASK) << K_SHIFT)
}

/// 编码 EQI 指令：EQI A sB k —— 比较寄存器 A 与立即数 sB
public func encodeEQI(a: UInt32, sB: Int32, k: UInt32): UInt32 {
    let offsetB = UInt32(sB + SB_OFFSET)
    return opcodeValue(OpCodes.EQI) | ((a & A_MASK) << A_SHIFT) | ((offsetB & B_MASK) << B_SHIFT) | ((k & K_MASK) << K_SHIFT)
}
