package cangjie_lua.lexer

import cangjie_lua.errors.*
import std.convert.*
import std.collection.*

// ============================================================
// ASCII 字符常量定义 —— 消除词法分析器中的魔鬼数字
// ============================================================
let CHAR_NUL:       Byte = 0x00u8  // '\0' 空字符 / 输入结束标志
let CHAR_TAB:       Byte = 0x09u8  // '\t' 水平制表符
let CHAR_LF:        Byte = 0x0Au8  // '\n' 换行符 (Line Feed)
let CHAR_CR:        Byte = 0x0Du8  // '\r' 回车符 (Carriage Return)
let CHAR_SPACE:     Byte = 0x20u8  // ' '  空格
let CHAR_LPAREN:    Byte = 0x28u8  // '('
let CHAR_RPAREN:    Byte = 0x29u8  // ')'
let CHAR_STAR:      Byte = 0x2Au8  // '*'
let CHAR_PLUS:      Byte = 0x2Bu8  // '+'
let CHAR_COMMA:     Byte = 0x2Cu8  // ','
let CHAR_COLON:     Byte = 0x3Au8  // ':'
let CHAR_MINUS:     Byte = 0x2Du8  // '-'
let CHAR_DOT:       Byte = 0x2Eu8  // '.'
let CHAR_SLASH:     Byte = 0x2Fu8  // '/'
let CHAR_EXCLAM:    Byte = 0x21u8  // '!'
let CHAR_0:         Byte = 0x30u8  // '0'
let CHAR_9:         Byte = 0x39u8  // '9'
let CHAR_EQUALS:    Byte = 0x3Du8  // '='
let CHAR_LT:        Byte = 0x3Cu8  // '<'
let CHAR_GT:        Byte = 0x3Eu8  // '>'
let CHAR_UPPER_A:   Byte = 0x41u8  // 'A'
let CHAR_UPPER_Z:   Byte = 0x5Au8  // 'Z'
let CHAR_UNDERSCORE:Byte = 0x5Fu8  // '_'
let CHAR_LOWER_A:   Byte = 0x61u8  // 'a'
let CHAR_LOWER_Z:   Byte = 0x7Au8  // 'z'
let CHAR_LBRACE:    Byte = 0x7Bu8  // '{'
let CHAR_RBRACE:    Byte = 0x7Du8  // '}'

// ============================================================
// Lexer —— 词法分析器
// 将源代码字符串逐字节扫描，生成 Token 序列。
// 支持：数字字面量、标识符/关键字、运算符、括号、注释（//）。
// ============================================================
public class Lexer {
    private let source: ArrayList<Byte>  // 源码的 UTF-8 字节序列
    private var pos: Int64 = 0           // 当前扫描位置
    private var line: Int64 = 1          // 当前行号（用于错误报告）
    private var currentByte: Byte = CHAR_NUL  // 当前字节
    private var _error: ?CompileError = None

    public prop error: ?CompileError {
        get() { _error }
    }

    public init(source: String) {
        this.source = ArrayList<Byte>(source.toArray())
        if (this.source.size > 0) {
            currentByte = this.source[0]
        }
    }

    /// 前进一个字节，更新 currentByte
    private func advance(): Unit {
        pos++
        if (pos < source.size) {
            currentByte = source[pos]
        } else {
            currentByte = CHAR_NUL
        }
    }

    /// 预览下一个字节（不消费）
    private func peek(): Byte {
        let nextPos = pos + 1
        if (nextPos < source.size) {
            return source[nextPos]
        }
        return CHAR_NUL
    }

    /// 跳过空白字符（空格、制表符、回车）
    private func skipWhitespace(): Unit {
        while (currentByte == CHAR_SPACE || currentByte == CHAR_TAB || currentByte == CHAR_CR) {
            advance()
        }
    }

    /// 跳过行注释（以 // 开头，直到行尾）
    private func skipComment(): Unit {
        if (currentByte == CHAR_SLASH && peek() == CHAR_SLASH) {
            while (currentByte != CHAR_LF && currentByte != CHAR_NUL) {
                advance()
            }
        }
    }

    /// 读取数字字面量（整数或浮点数）
    private func readNumber(): ?Token {
        var text = ""
        let startLine = line
        var dotCount = 0

        while ((currentByte >= CHAR_0 && currentByte <= CHAR_9) || currentByte == CHAR_DOT) {
            if (currentByte == CHAR_DOT) {
                dotCount++
            }
            text = text + String.fromUtf8(currentByte)
            advance()
        }

        if (dotCount > 1 || text == ".") {
            _error = CompileError(ErrorStage.LEXER, "Invalid number literal '${text}'", startLine)
            return None
        }

        let value = Float64.parse(text)
        return Token(TokenType.NUMBER, value, text, startLine)
    }

    /// 读取标识符或关键字
    private func readIdentifier(): Token {
        var text = ""
        let startLine = line

        while (isAlphaNumeric(currentByte)) {
            text = text + String.fromUtf8(currentByte)
            advance()
        }

        let tokenType = lookupKeyword(text)
        return Token(tokenType, text, startLine)
    }

    /// 查找关键字，匹配失败则返回 IDENTIFIER
    private func lookupKeyword(text: String): TokenType {
        if (text == "let") { return TokenType.LET }
        if (text == "var") { return TokenType.VAR }
        if (text == "if") { return TokenType.IF }
        if (text == "else") { return TokenType.ELSE }
        if (text == "while") { return TokenType.WHILE }
        if (text == "func") { return TokenType.FUNC }
        if (text == "return") { return TokenType.RETURN }
        if (text == "true") { return TokenType.TRUE }
        if (text == "false") { return TokenType.FALSE }
        return TokenType.IDENTIFIER
    }

    /// 判断字节是否为字母或下划线 [a-zA-Z_]
    private func isAlpha(b: Byte): Bool {
        return (b >= CHAR_LOWER_A && b <= CHAR_LOWER_Z) || 
               (b >= CHAR_UPPER_A && b <= CHAR_UPPER_Z) || 
               b == CHAR_UNDERSCORE
    }

    /// 判断字节是否为数字 [0-9]
    private func isDigit(b: Byte): Bool {
        return b >= CHAR_0 && b <= CHAR_9
    }

    /// 判断字节是否为字母、数字或下划线
    private func isAlphaNumeric(b: Byte): Bool {
        return isAlpha(b) || isDigit(b)
    }

    /// 获取下一个 Token（词法分析核心方法）
    public func nextToken(): ?Token {
        while (currentByte != CHAR_NUL) {
            skipWhitespace()
            skipComment()

            // 处理换行符
            if (currentByte == CHAR_LF) {
                line++
                advance()
                continue
            }

            if (currentByte == CHAR_NUL) {
                break
            }

            // 数字字面量
            if (isDigit(currentByte)) {
                return readNumber()
            }

            // 标识符 / 关键字
            if (isAlpha(currentByte)) {
                return readIdentifier()
            }

            // 单字符运算符和分隔符
            let startLine = line
            let b = currentByte

            if (b == CHAR_PLUS) {
                advance()
                return Token(TokenType.PLUS, "+", startLine)
            }
            if (b == CHAR_MINUS) {
                advance()
                return Token(TokenType.MINUS, "-", startLine)
            }
            if (b == CHAR_STAR) {
                advance()
                return Token(TokenType.STAR, "*", startLine)
            }
            if (b == CHAR_SLASH) {
                if (peek() == CHAR_SLASH) {
                    skipComment()
                    continue
                }
                advance()
                return Token(TokenType.SLASH, "/", startLine)
            }
            if (b == CHAR_LPAREN) {
                advance()
                return Token(TokenType.LPAREN, "(", startLine)
            }
            if (b == CHAR_RPAREN) {
                advance()
                return Token(TokenType.RPAREN, ")", startLine)
            }
            if (b == CHAR_LBRACE) {
                advance()
                return Token(TokenType.LBRACE, "{", startLine)
            }
            if (b == CHAR_RBRACE) {
                advance()
                return Token(TokenType.RBRACE, "}", startLine)
            }
            if (b == CHAR_COMMA) {
                advance()
                return Token(TokenType.COMMA, ",", startLine)
            }
            if (b == CHAR_COLON) {
                advance()
                return Token(TokenType.COLON, ":", startLine)
            }
            if (b == CHAR_EQUALS) {
                if (peek() == CHAR_EQUALS) {
                    advance()
                    advance()
                    return Token(TokenType.EQEQ, "==", startLine)
                }
                advance()
                return Token(TokenType.ASSIGN, "=", startLine)
            }
            if (b == CHAR_EXCLAM) {
                if (peek() == CHAR_EQUALS) {
                    advance()
                    advance()
                    return Token(TokenType.NEQ, "!=", startLine)
                }
                let bad = String.fromUtf8(currentByte)
                _error = CompileError(ErrorStage.LEXER, "Unexpected character '${bad}'", line)
                return None
            }
            if (b == CHAR_LT) {
                if (peek() == CHAR_EQUALS) {
                    advance()
                    advance()
                    return Token(TokenType.LTE, "<=", startLine)
                }
                advance()
                return Token(TokenType.LT, "<", startLine)
            }
            if (b == CHAR_GT) {
                if (peek() == CHAR_EQUALS) {
                    advance()
                    advance()
                    return Token(TokenType.GTE, ">=", startLine)
                }
                advance()
                return Token(TokenType.GT, ">", startLine)
            }

            let bad = String.fromUtf8(currentByte)
            _error = CompileError(ErrorStage.LEXER, "Unexpected character '${bad}'", line)
            return None
        }

        return Token(TokenType.EOF, "", line)
    }

    /// 将整个源码一次性分词为 Token 列表（以 EOF 结尾）
    public func tokenize(): ?ArrayList<Token> {
        _error = None
        var tokens = ArrayList<Token>()
        while (true) {
            match (nextToken()) {
                case Some(token) =>
                    tokens.add(token)
                    if (token.tokenType == TokenType.EOF) {
                        return tokens
                    }
                case None =>
                    return None
            }
        }
        return None  // unreachable
    }
}
