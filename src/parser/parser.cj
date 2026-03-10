package cangjie_lua.parser

import cangjie_lua.errors.*
import cangjie_lua.lexer.*
import std.collection.*
import std.convert.*

// Parser：递归下降语法分析器
// 负责将 Token 序列转换为 AST，并在解析阶段完成一小部分轻量语义约束
// （例如 if/while 条件必须为 Bool、函数参数需带类型标注）
//
// 文法（简化）：
//   program        → declaration* EOF
//   declaration    → varDecl | funcDecl | statement
//   varDecl        → ("let" | "var") IDENTIFIER "=" expression
//   funcDecl       → "func" IDENTIFIER "(" params? ")" (":" type)? "{" block "}"
//   statement      → ifStmt | whileStmt | returnStmt | block | exprOrAssign
//   expression     → comparison
//   comparison     → addition (("=="|"!="|"<"|"<="|">"|">=") addition)*
//   addition       → multiplication (("+"|"-") multiplication)*
//   multiplication → unary (("*"|"/") unary)*
//   unary          → "-" unary | primary
//   primary        → NUMBER | BOOL | IDENTIFIER ("(" args? ")")? | "(" expression ")"
public class Parser {
    private let tokens: ArrayList<Token>  // 词法单元列表
    private var pos: Int64 = 0            // 当前解析位置
    private var _error: ?CompileError = None
    private var varTypes = HashMap<String, String>()
    private var functionReturnTypes = HashMap<String, String>()

    public prop error: ?CompileError {
        get() { _error }
    }

    public init(tokens: ArrayList<Token>) {
        this.tokens = tokens
    }

    /// 获取当前 Token（不消费）
    private func current(): Token {
        if (pos < tokens.size) {
            return tokens[pos]
        }
        return tokens[tokens.size - 1]
    }

    /// 预览下一个 Token（不消费）
    private func peek(): Token {
        let nextPos = pos + 1
        if (nextPos < tokens.size) {
            return tokens[nextPos]
        }
        return tokens[tokens.size - 1]
    }

    /// 消费并返回当前 Token，位置前进一步
    private func advance(): Token {
        let token = current()
        pos++
        return token
    }

    /// 检查当前 Token 是否为指定类型
    private func check(tokenType: TokenType): Bool {
        return current().tokenType == tokenType
    }

    /// 断言当前 Token 为指定类型并消费，否则记录错误并尽量前进恢复
    private func consume(tokenType: TokenType, message: String): Token {
        if (check(tokenType)) {
            return advance()
        }
        match (_error) {
            case None =>
                _error = CompileError(ErrorStage.PARSER, "${message}, got '${current().text}'", current().line)
            case _ => ()
        }
        return advance()
    }

    /// 解析入口：将 Token 列表解析为语句列表
    public func parse(): ?ArrayList<Stmt> {
        _error = None<CompileError>
        varTypes = HashMap<String, String>()
        functionReturnTypes = HashMap<String, String>()
        var statements = ArrayList<Stmt>()
        while (!check(TokenType.EOF)) {
            statements.add(parseDeclaration())
            match (_error) {
                case Some(_) => return None
                case None => ()
            }
        }
        return statements
    }

    /// 解析声明（变量声明 / 函数声明 / 普通语句）
    private func parseDeclaration(): Stmt {
        if (check(TokenType.LET) || check(TokenType.VAR)) {
            return parseVarDecl()
        }
        if (check(TokenType.FUNC)) {
            return parseFuncDecl()
        }
        return parseStatement()
    }

    /// 解析变量声明：let/var name = expr
    private func parseVarDecl(): Stmt {
        let isMutable = check(TokenType.VAR)
        advance()

        let nameToken = consume(TokenType.IDENTIFIER, "Expected variable name")
        let name = nameToken.text

        consume(TokenType.ASSIGN, "Expected '=' after variable name")
        let initExpr = parseExpression()
        varTypes[name] = inferExprType(initExpr)

        return Stmt.VarDecl(name, isMutable, initExpr)
    }

    /// 解析函数声明：func name(params) { body }
    private func parseFuncDecl(): Stmt {
        consume(TokenType.FUNC, "Expected 'func'")
        let nameToken = consume(TokenType.IDENTIFIER, "Expected function name")
        let name = nameToken.text

        consume(TokenType.LPAREN, "Expected '(' after function name")

        var params = ArrayList<FuncParam>()
        if (!check(TokenType.RPAREN)) {
            // 支持 func f(x: Int64, y: Float64)
            while (true) {
                let paramToken = consume(TokenType.IDENTIFIER, "Expected parameter name")
                let paramName = paramToken.text
                // 必须有冒号和类型名
                if (!check(TokenType.COLON)) {
                    match (_error) {
                        case None =>
                            _error = CompileError(ErrorStage.PARSER, "Function parameter '${paramName}' missing type annotation", paramToken.line)
                        case _ => ()
                    }
                    // 跳过到下一个逗号或右括号
                    while (!check(TokenType.COMMA) && !check(TokenType.RPAREN) && !check(TokenType.EOF)) { advance() }
                    params.add(FuncParam(paramName, ""))
                } else {
                    advance() // 跳过冒号
                    let typeToken = consume(TokenType.IDENTIFIER, "Expected type name after ':'")
                    params.add(FuncParam(paramName, typeToken.text))
                }
                if (check(TokenType.COMMA)) {
                    advance()
                } else {
                    break
                }
            }
        }
        consume(TokenType.RPAREN, "Expected ')' after parameters")

        // 支持可选的返回类型标注 : Type
        var returnType: ?String = None
        if (check(TokenType.COLON)) {
            advance()
            let typeToken = consume(TokenType.IDENTIFIER, "Expected return type name after ':'")
            returnType = typeToken.text
            functionReturnTypes[name] = typeToken.text
        }

        consume(TokenType.LBRACE, "Expected '{' before function body")
        let body = parseBlock()
        consume(TokenType.RBRACE, "Expected '}' after function body")

        return Stmt.FuncDecl(name, params, returnType, body)
    }

    /// 解析语句（if / while / return / block / 表达式或赋值）
    private func parseStatement(): Stmt {
        if (check(TokenType.IF)) {
            return parseIfStmt()
        }
        if (check(TokenType.WHILE)) {
            return parseWhileStmt()
        }
        if (check(TokenType.RETURN)) {
            return parseReturnStmt()
        }
        if (check(TokenType.LBRACE)) {
            advance()
            let stmts = parseBlock()
            consume(TokenType.RBRACE, "Expected '}' after block")
            return Stmt.Block(stmts)
        }
        return parseExprOrAssignmentStmt()
    }

    /// 解析 if 语句（支持 else / else if）
    private func parseIfStmt(): Stmt {
        consume(TokenType.IF, "Expected 'if'")
        consume(TokenType.LPAREN, "Expected '(' after 'if'")
        let condition = parseExpression()
        if (inferExprType(condition) != "Bool") {
            match (_error) {
                case None =>
                    _error = CompileError(ErrorStage.PARSER, "If condition must be Bool", current().line)
                case _ => ()
            }
        }
        consume(TokenType.RPAREN, "Expected ')' after condition")

        consume(TokenType.LBRACE, "Expected '{' before if body")
        let thenBranch = parseBlock()
        consume(TokenType.RBRACE, "Expected '}' after if body")

        var elseBranch = ArrayList<Stmt>()
        if (check(TokenType.ELSE)) {
            advance()
            if (check(TokenType.LBRACE)) {
                advance()
                elseBranch = parseBlock()
                consume(TokenType.RBRACE, "Expected '}' after else body")
            } else if (check(TokenType.IF)) {
                elseBranch.add(parseIfStmt())
            }
        }

        return Stmt.IfStmt(condition, thenBranch, elseBranch)
    }

    /// 解析 while 循环语句
    private func parseWhileStmt(): Stmt {
        consume(TokenType.WHILE, "Expected 'while'")
        consume(TokenType.LPAREN, "Expected '(' after 'while'")
        let condition = parseExpression()
        if (inferExprType(condition) != "Bool") {
            match (_error) {
                case None =>
                    _error = CompileError(ErrorStage.PARSER, "While condition must be Bool", current().line)
                case _ => ()
            }
        }
        consume(TokenType.RPAREN, "Expected ')' after condition")

        consume(TokenType.LBRACE, "Expected '{' before while body")
        let body = parseBlock()
        consume(TokenType.RBRACE, "Expected '}' after while body")

        return Stmt.WhileStmt(condition, body)
    }

    /// 解析 return 语句
    private func parseReturnStmt(): Stmt {
        consume(TokenType.RETURN, "Expected 'return'")
        let value = parseExpression()
        return Stmt.ReturnStmt(value)
    }

    /// 解析代码块（直到遇到 '}' 或 EOF）
    private func parseBlock(): ArrayList<Stmt> {
        var statements = ArrayList<Stmt>()
        while (!check(TokenType.RBRACE) && !check(TokenType.EOF)) {
            statements.add(parseDeclaration())
        }
        return statements
    }

    /// 解析表达式语句或赋值语句
    private func parseExprOrAssignmentStmt(): Stmt {
        if (check(TokenType.IDENTIFIER) && peek().tokenType == TokenType.ASSIGN) {
            let nameToken = advance()
            advance()
            let value = parseExpression()
            varTypes[nameToken.text] = inferExprType(value)
            return Stmt.Assignment(nameToken.text, value)
        }
        let expr = parseExpression()
        return Stmt.ExprStmt(expr)
    }

    /// 表达式解析入口（最低优先级层）：比较运算
    private func parseExpression(): Expr {
        return parseComparison()
    }

    /// 解析比较运算（优先级低于加减）
    private func parseComparison(): Expr {
        var left = parseAddition()

        while (check(TokenType.EQEQ) || check(TokenType.NEQ) || check(TokenType.LT) || check(TokenType.LTE) || check(TokenType.GT) || check(TokenType.GTE)) {
            let op = match (current().tokenType) {
                case TokenType.EQEQ => BinaryOp.EQ
                case TokenType.NEQ => BinaryOp.NEQ
                case TokenType.LT => BinaryOp.LT
                case TokenType.LTE => BinaryOp.LTE
                case TokenType.GT => BinaryOp.GT
                case TokenType.GTE => BinaryOp.GTE
                case _ => BinaryOp.EQ
            }
            advance()
            let right = parseAddition()
            left = Expr.Binary(Box(left), op, Box(right))
        }

        return left
    }

    /// 解析加减运算（左结合）
    private func parseAddition(): Expr {
        var left = parseMultiplication()

        while (check(TokenType.PLUS) || check(TokenType.MINUS)) {
            let op = if (check(TokenType.PLUS)) { BinaryOp.ADD } else { BinaryOp.SUB }
            advance()
            let right = parseMultiplication()
            left = Expr.Binary(Box(left), op, Box(right))
        }

        return left
    }

    /// 解析乘除运算（左结合，优先级高于加减）
    private func parseMultiplication(): Expr {
        var left = parseUnary()

        while (check(TokenType.STAR) || check(TokenType.SLASH)) {
            let op = if (check(TokenType.STAR)) { BinaryOp.MUL } else { BinaryOp.DIV }
            advance()
            let right = parseUnary()
            left = Expr.Binary(Box(left), op, Box(right))
        }

        return left
    }

    /// 解析一元运算（当前仅支持一元负号）
    private func parseUnary(): Expr {
        if (check(TokenType.MINUS)) {
            advance()
            let right = parseUnary()
            match (right) {
                case Expr.IntLiteral(v) => return Expr.IntLiteral(-v)
                case Expr.FloatLiteral(v) => return Expr.FloatLiteral(-v)
                case _ => return Expr.Binary(Box(Expr.IntLiteral(0)), BinaryOp.SUB, Box(right))
            }
        }
        return parsePrimary()
    }

    /// 解析基本表达式（数字、变量、函数调用、括号表达式）
    private func parsePrimary(): Expr {
        if (check(TokenType.NUMBER)) {
            let token = advance()
            if (token.text.contains(".")) {
                return Expr.FloatLiteral(Float64.parse(token.text))
            }
            return Expr.IntLiteral(Int64.parse(token.text))
        }

        if (check(TokenType.TRUE)) {
            advance()
            return Expr.BoolLiteral(true)
        }

        if (check(TokenType.FALSE)) {
            advance()
            return Expr.BoolLiteral(false)
        }

        if (check(TokenType.IDENTIFIER)) {
            let token = advance()
            if (check(TokenType.LPAREN)) {
                advance()
                var args = ArrayList<Expr>()
                if (!check(TokenType.RPAREN)) {
                    args.add(parseExpression())
                    while (check(TokenType.COMMA)) {
                        advance()
                        args.add(parseExpression())
                    }
                }
                consume(TokenType.RPAREN, "Expected ')' after arguments")
                return Expr.Call(token.text, args)
            }
            return Expr.Variable(token.text)
        }

        if (check(TokenType.LPAREN)) {
            advance()
            let expr = parseExpression()
            consume(TokenType.RPAREN, "Expected ')' after expression")
            return expr
        }

        match (_error) {
            case None =>
                _error = CompileError(ErrorStage.PARSER, "Unexpected token '${current().text}'", current().line)
            case _ => ()
        }
        advance()
        return Expr.IntLiteral(0)
    }

    /// 轻量类型推断：仅服务于解析期校验，不替代完整类型系统
    private func inferExprType(expr: Expr): String {
        match (expr) {
            case Expr.IntLiteral(_) => "Number"
            case Expr.FloatLiteral(_) => "Number"
            case Expr.BoolLiteral(_) => "Bool"
            case Expr.Variable(name) =>
                if (let Some(t) <- varTypes.get(name)) {
                    t
                } else {
                    "Unknown"
                }
            case Expr.Call(funcName, _) =>
                if (let Some(t) <- functionReturnTypes.get(funcName)) {
                    if (t == "Bool") { "Bool" } else { "Number" }
                } else {
                    "Unknown"
                }
            case Expr.Binary(_, op, _) =>
                match (op) {
                    case BinaryOp.EQ => "Bool"
                    case BinaryOp.NEQ => "Bool"
                    case BinaryOp.LT => "Bool"
                    case BinaryOp.LTE => "Bool"
                    case BinaryOp.GT => "Bool"
                    case BinaryOp.GTE => "Bool"
                    case _ => "Number"
                }
        }
    }
}
