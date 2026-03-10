package cangjie_lua.lexer
import std.deriving.*

// ============================================================
// TokenType —— 词法单元类型枚举
// 包括：EOF、字面量（数字）、标识符、运算符、分隔符、关键字。
// ============================================================
@Derive[Equatable]
public enum TokenType {
    | EOF           // 输入结束
    | NUMBER        // 数字字面量（整数或浮点数）
    | TRUE          // true
    | FALSE         // false
    | IDENTIFIER    // 标识符
    // 运算符
    | PLUS          // +
    | MINUS         // -
    | STAR          // *
    | SLASH         // /
    | EQEQ          // ==
    | NEQ           // !=
    | LT            // <
    | LTE           // <=
    | GT            // >
    | GTE           // >=
    // 分隔符
    | LPAREN        // (
    | RPAREN        // )
    | LBRACE        // {
    | RBRACE        // }
    | COMMA         // ,
    | COLON         // :
    | ASSIGN        // =
    // 关键字
    | LET           // let —— 不可变变量声明
    | VAR           // var —— 可变变量声明
    | IF            // if
    | WHILE         // while
    | FUNC          // func —— 函数定义
    | RETURN        // return
    | ELSE          // else
}

// ============================================================
// Token —— 词法单元
// 记录类型、数值（仅用于 NUMBER）、源码文本和行号。
// ============================================================
public class Token {
    public let tokenType: TokenType  // 词法单元类型
    public let value: Float64        // 数值（仅 NUMBER 类型有效）
    public let text: String          // 源码中的原始文本
    public let line: Int64           // 所在行号

    /// 带数值的构造器（用于 NUMBER 类型）
    public init(tokenType: TokenType, value: Float64, text: String, line: Int64) {
        this.tokenType = tokenType
        this.value = value
        this.text = text
        this.line = line
    }

    /// 不带数值的构造器（用于关键字、运算符等）
    public init(tokenType: TokenType, text: String, line: Int64) {
        this.tokenType = tokenType
        this.value = 0.0
        this.text = text
        this.line = line
    }
}
