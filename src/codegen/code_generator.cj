package cangjie_lua.codegen

import cangjie_lua.parser.*
import std.collection.*

// ============================================================
// Lua 5.5 常量类型标签（用于二进制块中的常量表）
// ============================================================
let LUA_VNUMFLT:  UInt8 = 0x13  // 浮点数常量
let LUA_VSHRSTR:  UInt8 = 0x04  // 短字符串常量

// ============================================================
// MMBIN 元方法编号（算术运算的元方法索引）
// 在 MMBIN 指令中用于指定触发哪个元方法的回退
// ============================================================
let MM_ADD: UInt32 = 6   // __add  加法
let MM_SUB: UInt32 = 7   // __sub  减法
let MM_MUL: UInt32 = 8   // __mul  乘法
let MM_DIV: UInt32 = 9   // __div  除法

// ============================================================
// LOADI/LOADF/LOADK 指令的操作数范围限制
// ============================================================
let LOADI_MIN: Int64 = -32768      // LOADI sBx 最小值 (-(2^15))
let LOADI_MAX: Int64 = 32767       // LOADI sBx 最大值 (2^15 - 1)
let LOADF_MIN: Int64 = -65536      // LOADF sBx 最小值 (-(2^16))
let LOADF_MAX: Int64 = 65535       // LOADF sBx 最大值 (2^16 - 1)
let LOADK_MAX: Int64 = 131072      // LOADK Bx 最大值 (2^17)，超过则需使用 LOADKX

// RK 编码：当寄存器索引 >= 此值时，表示引用常量表而非寄存器
let RK_CONSTANT_BIT: UInt32 = 0x100  // 第 9 位标记常量引用

// ============================================================
// Upvalue 描述字段常量
// ============================================================
let UPVAL_INSTACK:     UInt8 = 0x01  // 上值在栈上（直接捕获）
let UPVAL_NOT_INSTACK: UInt8 = 0x00  // 上值不在栈上（从父级继承）
let UPVAL_IDX_ZERO:    UInt8 = 0x00  // 上值索引 0（通常指 _ENV）
let UPVAL_KIND_REGULAR:UInt8 = 0x00  // 普通上值

// 函数头部标志
let FUNC_IS_VARARG:    UInt8 = 0x01  // 函数是变长参数函数
let FUNC_NOT_VARARG:   UInt8 = 0x00  // 函数不是变长参数函数

// 栈空间额外保留量（Lua 要求 maxStackSize 至少比实际使用多 2）
let STACK_EXTRA: Int64 = 2

// ============================================================
// CodeGenerator —— 字节码生成器
// 将 AST 翻译为 Lua 5.5 虚拟机可执行的二进制字节码。
// 
// 核心职责：
// - 常量表管理（数字、字符串去重）
// - 寄存器分配（基于栈的线性分配）
// - 指令发射（通过 encodeABC/ABx/AsBx/IsJ 编码）
// - 二进制块序列化（头部 + 函数原型）
// ============================================================
public class CodeGenerator {
    // 常量表
    private var constants = ArrayList<Constant>()          // 常量列表
    private var constantIndex = HashMap<String, Int64>()   // 常量去重索引

    // 指令序列
    private var instructions = ArrayList<UInt32>()

    // 局部变量表（寄存器分配）
    private var locals = ArrayList<String>()               // 变量名列表
    private var localIndex = HashMap<String, Int64>()      // 变量名 → 寄存器映射

    // 栈空间跟踪
    private var maxStack = 0       // 函数使用的最大栈深度
    private var currentStack = 0   // 当前已分配的栈位置

    // 子函数原型
    private var functions = ArrayList<FunctionProto>()
    private var functionNames = HashMap<String, Int64>()

    public init() {}

    /// 添加数字常量到常量表（去重），返回索引
    private func addConstant(value: Float64): Int64 {
        let key = "num_${value}"
        if (let Some(v) <- constantIndex.get(key)) {
            return v
        }
        let idx = constants.size
        constants.add(Constant.Number(value))
        constantIndex[key] = idx
        return idx
    }

    /// 添加字符串常量到常量表（去重），返回索引
    private func addConstantString(s: String): Int64 {
        let key = "str_${s}"
        if (let Some(v) <- constantIndex.get(key)) {
            return v
        }
        let idx = constants.size
        constants.add(Constant.Str(s))
        constantIndex[key] = idx
        return idx
    }

    /// 注册局部变量，分配寄存器并返回索引
    private func addLocal(name: String): Int64 {
        if (let Some(v) <- localIndex.get(name)) {
            return v
        }
        let idx = locals.size
        locals.add(name)
        localIndex[name] = idx
        currentStack++
        if (currentStack > maxStack) {
            maxStack = currentStack
        }
        return idx
    }

    /// 查找局部变量的寄存器索引，未找到返回 -1
    private func getLocal(name: String): Int64 {
        if (let Some(v) <- localIndex.get(name)) {
            return v
        }
        return -1
    }

    /// 发射一条原始指令
    private func emit(inst: UInt32): Unit {
        instructions.add(inst)
    }

    /// 发射 iABC 格式指令
    private func emitABC(op: OpCodes, a: UInt32, b: UInt32, c: UInt32): Unit {
        emit(encodeABC(op, a, b, c))
    }

    /// 发射 iABx 格式指令
    private func emitABx(op: OpCodes, a: UInt32, bx: UInt32): Unit {
        emit(encodeABx(op, a, bx))
    }
    /// 发射 iAsBx 格式指令（有符号偏移量）
    private func emitAsBx(op: OpCodes, a: UInt32, sbx: Int32): Unit {
        emit(encodeAsBx(op, a, sbx))
    }
    /// 发射 isJ 格式指令（跳转指令）
    private func emitIsJ(op: OpCodes, sj: Int32): Unit {
        emit(encodeIsJ(op, sj))
    }

    /// 生成入口：将语句列表编译为 Lua 5.5 二进制字节码
    public func generate(statements: ArrayList<Stmt>): Array<UInt8> {
        let mainWriter = ChunkWriter()

        // === 写入 Lua 二进制块全局头部 ===
        mainWriter.writeBytes(LUA_SIGNATURE)    // 魔数 "\x1bLua"
        mainWriter.writeByte(LUAC_VERSION)      // 版本号 0x55 (Lua 5.5)
        mainWriter.writeByte(LUAC_FORMAT)       // 格式号 0x00 (官方格式)
        mainWriter.writeBytes(LUAC_DATA)        // 校验数据
        // 类型大小校验
        mainWriter.writeByte(4u8)               // sizeof(int) = 4
        mainWriter.writeInt32(LUAC_INT)         // 整数字节序校验
        mainWriter.writeByte(4u8)               // sizeof(Instruction) = 4
        mainWriter.writeUInt32(LUAC_INST)       // 指令字节序校验
        mainWriter.writeByte(8u8)               // sizeof(lua_Integer) = 8
        mainWriter.writeInt64(LUAC_INT64)       // 64 位整数校验
        mainWriter.writeByte(8u8)               // sizeof(lua_Number) = 8
        mainWriter.writeFloat64(LUAC_NUM)       // 浮点数格式校验

        // 上值数量（main 函数有 1 个上值 _ENV）
        mainWriter.writeByte(1)

        // main 函数是变长参数函数，需要以 VARARGPREP 开头
        emit(encodeABx(OpCodes.VARARGPREP, 0u32, 0u32))

        generateStatements(statements, true)

        // main 函数以 RETURN0 结尾
        emitABC(OpCodes.RETURN0, 0u32, 0u32, 0u32)

        writeFunction(mainWriter)

        return mainWriter.toByteArray()
    }

    /// 生成语句列表的字节码
    private func generateStatements(statements: ArrayList<Stmt>, isMain: Bool): Unit {
        for (stmt in statements) {
            generateStatement(stmt, isMain)
        }
    }

    /// 生成单条语句的字节码
    private func generateStatement(stmt: Stmt, isMain: Bool): Unit {
        match (stmt) {
            case Stmt.VarDecl(name, isMutable, initExpr) =>
                // 变量声明：分配寄存器并生成初始化表达式
                let reg = UInt32(addLocal(name))
                generateExpr(initExpr, reg)
            case Stmt.Assignment(name, expr) =>
                // 赋值语句：区分局部变量和全局变量
                let localIdx = getLocal(name)
                if (localIdx >= 0) {
                    // 局部变量：直接写入对应寄存器
                    let reg = UInt32(localIdx)
                    generateExpr(expr, reg)
                } else {
                    // 全局变量：先计算到临时寄存器，再通过 SETTABUP 写入 _ENV
                    let reg = UInt32(currentStack)
                    generateExpr(expr, reg)
                    let nameIdx = addConstantString(name)
                    emitABC(OpCodes.SETTABUP, 0, UInt32(nameIdx), reg | RK_CONSTANT_BIT)
                }
            case Stmt.IfStmt(condition, thenBranch, elseBranch) =>
                generateIfStmt(condition, thenBranch, elseBranch, isMain)
            case Stmt.WhileStmt(condition, body) =>
                generateWhileStmt(condition, body, isMain)
            case Stmt.FuncDecl(name, params, body) =>
                // 函数声明：创建子代码生成器编译函数体，
                // 然后用 CLOSURE 创建闭包，并通过 SETTABUP 注册为全局函数
                let funcGen = CodeGenerator()
                funcGen.generateFunction(params, body)
                let funcIdx = functions.size
                functions.add(FunctionProto(name, funcGen, params.size))
                functionNames[name] = funcIdx
                let reg = UInt32(addLocal(name))
                emitABx(OpCodes.CLOSURE, reg, UInt32(funcIdx))
                let nameIdx = addConstantString(name)
                emitABC(OpCodes.SETTABUP, 0u32, UInt32(nameIdx), reg)
            case Stmt.ReturnStmt(expr) =>
                // return 语句：将返回值放入临时寄存器后发射 RETURN
                let reg = UInt32(currentStack)
                generateExpr(expr, reg)
                // RETURN C 字段：vararg 函数(main)为 1，普通函数为 0
                let cVal = if (isMain) { 1u32 } else { 0u32 }
                emitABC(OpCodes.RETURN, reg, 2u32, cVal)
            case Stmt.ExprStmt(expr) =>
                generateExprStmt(expr)
            case Stmt.Block(stmts) =>
                generateStatements(stmts, isMain)
        }
    }

    /// 生成 if 语句的字节码（支持 else 分支）
    ///
    /// 生成模式：
    ///   <计算条件到 condReg>
    ///   EQI condReg 0 1     -- 如果条件 == 0 则跳过 then
    ///   JMP <跳过 then>
    ///   <then 分支>
    ///   JMP <跳过 else>       -- 仅当有 else 时
    ///   <else 分支>
    private func generateIfStmt(condition: Expr, thenBranch: ArrayList<Stmt>, elseBranch: ArrayList<Stmt>, isMain: Bool): Unit {
        let savedStack = currentStack
        let condReg = UInt32(currentStack)
        generateExpr(condition, condReg)

        currentStack = savedStack
        emit(encodeEQI(condReg, 0, 1u32))

        let testIdx = instructions.size
        emitIsJ(OpCodes.JMP, 0)

        generateStatements(thenBranch, isMain)

        if (elseBranch.size > 0) {
            let elseJmpIdx = instructions.size
            emitIsJ(OpCodes.JMP, 0)

            let thenEnd = instructions.size
            let testOffset = Int32(thenEnd - testIdx - 1)
            instructions[testIdx] = encodeIsJ(OpCodes.JMP, testOffset)

            currentStack = savedStack
            generateStatements(elseBranch, isMain)
            currentStack = savedStack

            let elseEnd = instructions.size
            let elseOffset = Int32(elseEnd - elseJmpIdx - 1)
            instructions[elseJmpIdx] = encodeIsJ(OpCodes.JMP, elseOffset)
        } else {
            let thenEnd = instructions.size
            let testOffset = Int32(thenEnd - testIdx - 1)
            instructions[testIdx] = encodeIsJ(OpCodes.JMP, testOffset)
            currentStack = savedStack
        }
    }

    /// 生成 while 循环的字节码
    ///
    /// 生成模式：
    ///   loopStart:
    ///     <计算条件到 condReg>
    ///     EQI condReg 0 1   -- 如果条件 == 0 则退出循环
    ///     JMP <跳到 afterLoop>
    ///     <循环体>
    ///     JMP <跳回 loopStart>
    ///   afterLoop:
    private func generateWhileStmt(condition: Expr, body: ArrayList<Stmt>, isMain: Bool): Unit {
        let savedStack = currentStack
        let condReg = UInt32(currentStack)

        let loopStart = instructions.size
        generateExpr(condition, condReg)

        currentStack = savedStack
        emit(encodeEQI(condReg, 0, 1u32))

        let testIdx = instructions.size
        emitIsJ(OpCodes.JMP, 0)

        generateStatements(body, isMain)

        currentStack = savedStack

        let loopEnd = instructions.size
        let backOffset = Int32(loopStart - loopEnd - 1)
        emitIsJ(OpCodes.JMP, backOffset)

        let afterLoop = instructions.size
        let testOffset = Int32(afterLoop - testIdx - 1)
        instructions[testIdx] = encodeIsJ(OpCodes.JMP, testOffset)
    }

    /// 生成表达式语句的字节码（主要处理函数调用）
    private func generateExprStmt(expr: Expr): Unit {
        match (expr) {
            case Expr.Call(funcName, args) =>
                let savedStack = currentStack
                let funcReg = UInt32(currentStack)
                let funcIdx = addConstantString(funcName)

                // 通过 GETTABUP 从全局表 _ENV 加载函数到 funcReg
                emitABC(OpCodes.GETTABUP, funcReg, 0u32, UInt32(funcIdx))

                // 将参数依次放入 funcReg 之后的连续寄存器
                currentStack = Int64(funcReg) + 1
                for (arg in args) {
                    let argReg = UInt32(currentStack)
                    generateExpr(arg, argReg)
                    currentStack = Int64(argReg) + 1
                }
                if (currentStack > maxStack) {
                    maxStack = currentStack
                }

                // CALL A B C：调用 funcReg，B=nargs+1，C=1（不需要返回值）
                let nargs = UInt32(args.size)
                emitABC(OpCodes.CALL, funcReg, nargs + 1u32, 1u32)

                currentStack = savedStack
            case _ =>
                let reg = UInt32(currentStack)
                generateExpr(expr, reg)
        }
    }

    /// 生成表达式的字节码，将结果存入目标寄存器 dest
    private func generateExpr(expr: Expr, dest: UInt32): Unit {
        match (expr) {
            case Expr.Number(value) =>
                // 根据数值范围选择最优的加载指令
                let intVal = Int64(value)
                if (value == Float64(intVal) && intVal >= LOADI_MIN && intVal <= LOADI_MAX) {
                    // 小整数：使用 LOADI（sBx 直接编码）
                    emitAsBx(OpCodes.LOADI, dest, Int32(intVal))
                } else if (value == Float64(intVal) && intVal >= LOADF_MIN && intVal <= LOADF_MAX) {
                    // 稍大的整数：使用 LOADF（作为浮点数直接编码）
                    emitAsBx(OpCodes.LOADF, dest, Int32(intVal))
                } else {
                    // 其他值：从常量表加载
                    let idx = addConstant(value)
                    if (idx < LOADK_MAX) {
                        emitABx(OpCodes.LOADK, dest, UInt32(idx))
                    } else {
                        // 常量索引超出 Bx 范围，使用 LOADKX + EXTRAARG
                        emitABx(OpCodes.LOADKX, dest, 0u32)
                        emitABx(OpCodes.EXTRAARG, 0u32, UInt32(idx))
                    }
                }
            case Expr.Variable(name) =>
                // 变量引用：优先查找局部变量，否则从全局表加载
                let localIdx = getLocal(name)
                if (localIdx >= 0) {
                    emitABC(OpCodes.MOVE, dest, UInt32(localIdx), 0u32)
                } else {
                    let nameIdx = addConstantString(name)
                    emitABC(OpCodes.GETTABUP, dest, 0u32, UInt32(nameIdx))
                }
            case Expr.Binary(left, op, right) =>
                // 二元运算：先计算左操作数到 dest，再计算右操作数到临时寄存器
                let leftReg = dest
                generateExpr(left.value, leftReg)
                var rightReg = UInt32(currentStack)
                currentStack++
                if (rightReg == leftReg) {
                    rightReg = UInt32(currentStack)
                    currentStack++
                }
                if (currentStack > maxStack) {
                    maxStack = currentStack
                }
                generateExpr(right.value, rightReg)
                // 每个算术指令后紧跟 MMBIN 元方法回退指令
                match (op) {
                    case BinaryOp.ADD => 
                        emitABC(OpCodes.ADD, dest, leftReg, rightReg)
                        emitABC(OpCodes.MMBIN, leftReg, rightReg, MM_ADD)
                    case BinaryOp.SUB => 
                        emitABC(OpCodes.SUB, dest, leftReg, rightReg)
                        emitABC(OpCodes.MMBIN, leftReg, rightReg, MM_SUB)
                    case BinaryOp.MUL => 
                        emitABC(OpCodes.MUL, dest, leftReg, rightReg)
                        emitABC(OpCodes.MMBIN, leftReg, rightReg, MM_MUL)
                    case BinaryOp.DIV => 
                        emitABC(OpCodes.DIV, dest, leftReg, rightReg)
                        emitABC(OpCodes.MMBIN, leftReg, rightReg, MM_DIV)
                }
            case Expr.Call(funcName, args) =>
                // 函数调用（作为表达式，需要返回值）
                let savedStack = currentStack
                let funcReg = dest
                let funcIdx = addConstantString(funcName)
                emitABC(OpCodes.GETTABUP, funcReg, 0u32, UInt32(funcIdx))
                currentStack = Int64(funcReg) + 1
                for (arg in args) {
                    let argReg = UInt32(currentStack)
                    generateExpr(arg, argReg)
                    currentStack++
                }
                if (currentStack > maxStack) {
                    maxStack = currentStack
                }
                // CALL A B C：B=nargs+1，C=2（需要 1 个返回值）
                let nargs = UInt32(args.size)
                emitABC(OpCodes.CALL, funcReg, nargs + 1u32, 2u32)
                currentStack = savedStack
        }
    }

    /// 编译子函数体（供 FuncDecl 调用）
    private func generateFunction(params: ArrayList<String>, body: ArrayList<Stmt>): Unit {
        // 重置生成器状态
        locals = ArrayList<String>()
        localIndex = HashMap<String, Int64>()
        constants = ArrayList<Constant>()
        constantIndex = HashMap<String, Int64>()
        instructions = ArrayList<UInt32>()
        currentStack = params.size
        maxStack = params.size

        // 注册参数为局部变量
        for (i in 0..params.size) {
            locals.add(params[i])
            localIndex[params[i]] = i
        }

        generateStatements(body, false)

        // 函数末尾添加隐式 RETURN0
        emitABC(OpCodes.RETURN0, 0u32, 0u32, 0u32)
    }

    /// 将 main 函数原型序列化写入二进制块
    private func writeFunction(writer: ChunkWriter): Unit {
        // 源文件信息（linedefined, lastlinedefined = 0 表示 main）
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)

        // 函数头部：numparams, is_vararg, maxstacksize
        writer.writeByte(UPVAL_KIND_REGULAR)           // numparams = 0（main 无固定参数）
        writer.writeByte(FUNC_IS_VARARG)               // is_vararg = 1（main 是变长参数）
        writer.writeByte(UInt8(maxStack + STACK_EXTRA)) // maxstacksize（加额外保留）

        // 指令列表
        writer.writeVarIntInt(Int32(instructions.size))
        writer.writeAlign(4)  // 指令需 4 字节对齐
        for (inst in instructions) {
            writer.writeInstruction(inst)
        }

        // 常量表
        writer.writeVarIntInt(Int32(constants.size))
        for (c in constants) {
            match (c) {
                case Constant.Number(v) =>
                    writer.writeByte(LUA_VNUMFLT)   // 浮点数类型标签
                    writer.writeFloat64(v)
                case Constant.Str(s) =>
                    writer.writeByte(LUA_VSHRSTR)   // 短字符串类型标签
                    writer.writeShortString(s)
            }
        }

        // 上值表：main 函数有 1 个上值 _ENV
        writer.writeVarIntInt(1)
        writer.writeByte(UPVAL_INSTACK)        // instack = 1（直接在栈上）
        writer.writeByte(UPVAL_IDX_ZERO)       // idx = 0（栈位置 0）
        writer.writeByte(UPVAL_KIND_REGULAR)   // kind = 0（普通上值）

        // 子函数原型表
        writer.writeVarIntInt(Int32(functions.size))
        for (f in functions) {
            writeSubFunction(writer, f)
        }

        // 源文件名（空）
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)

        // 调试信息（lineinfo, abslineinfo, locvars, upvalnames 均为空）
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)
    }

    /// 将子函数原型序列化写入二进制块
    private func writeSubFunction(writer: ChunkWriter, proto: FunctionProto): Unit {
        // 源文件信息
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)

        let gen = proto.generator

        // 函数头部：numparams, is_vararg, maxstacksize
        writer.writeByte(UInt8(proto.numParams))
        writer.writeByte(FUNC_NOT_VARARG)                  // 子函数不是变长参数
        writer.writeByte(UInt8(gen.maxStack + STACK_EXTRA))

        // 指令列表
        writer.writeVarIntInt(Int32(gen.instructions.size))
        writer.writeAlign(4)
        for (inst in gen.instructions) {
            writer.writeInstruction(inst)
        }

        // 常量表
        writer.writeVarIntInt(Int32(gen.constants.size))
        for (c in gen.constants) {
            match (c) {
                case Constant.Number(v) =>
                    writer.writeByte(LUA_VNUMFLT)
                    writer.writeFloat64(v)
                case Constant.Str(s) =>
                    writer.writeByte(LUA_VSHRSTR)
                    writer.writeShortString(s)
            }
        }

        // 上值表：1 个上值 _ENV（从父函数继承）
        writer.writeVarIntInt(1)
        writer.writeByte(UPVAL_NOT_INSTACK)    // instack = 0（从父级的上值表继承）
        writer.writeByte(UPVAL_IDX_ZERO)       // idx = 0（父级的 upvalue[0] = _ENV）
        writer.writeByte(UPVAL_KIND_REGULAR)   // kind = 0

        // 嵌套子函数
        writer.writeVarIntInt(Int32(gen.functions.size))
        for (subF in gen.functions) {
            writeSubFunction(writer, subF)
        }

        // 源文件名（空）
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)

        // 调试信息（均为空）
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)
        writer.writeVarIntInt(0)
    }
}

/// 常量类型：Lua 常量表中的条目
public enum Constant {
    | Number(Float64)  // 浮点数常量
    | Str(String)      // 字符串常量
}

/// 函数原型：记录子函数的名称、代码生成器和参数数量
public class FunctionProto {
    public let name: String             // 函数名
    public let generator: CodeGenerator // 该函数的代码生成器（持有指令、常量等）
    public let numParams: Int64         // 固定参数数量

    public init(name: String, generator: CodeGenerator, numParams: Int64) {
        this.name = name
        this.generator = generator
        this.numParams = numParams
    }
}
