package cangjie_lua.errors

// ============================================================
// CompileError —— 编译/运行错误模型
// 用 Option 代替 throw 的错误传播机制的核心数据结构。
// ============================================================

/// 错误阶段：标识错误来源
public enum ErrorStage {
    | LEXER
    | PARSER
    | RUNTIME
    | IO
}

/// 编译错误：包含阶段、信息和行号
public class CompileError {
    public let stage: ErrorStage
    public let message: String
    public let line: Int64

    public init(stage: ErrorStage, message: String, line: Int64) {
        this.stage = stage
        this.message = message
        this.line = line
    }

    public func toDisplayString(): String {
        let stageName = match (stage) {
            case ErrorStage.LEXER => "LEXER"
            case ErrorStage.PARSER => "PARSER"
            case ErrorStage.RUNTIME => "RUNTIME"
            case ErrorStage.IO => "IO"
        }
        if (line > 0) {
            return "[${stageName}] line ${line}: ${message}"
        }
        return "[${stageName}] ${message}"
    }
}
