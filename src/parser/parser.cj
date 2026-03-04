package cangjie_lua.parser

import cangjie_lua.lexer.*
import std.collection.*

// ============================================================
// Parser —— 递归下降语法分析器
// 将 Token 序列解析为 AST（抽象语法树）
// 
// 文法：
//   program     → declaration* EOF
//   declaration → varDecl | funcDecl | statement
//   varDecl     → ("let" | "var") IDENTIFIER "=" expression
//   funcDecl    → "func" IDENTIFIER "(" params? ")" "{" block "}"
//   statement   → ifStmt | whileStmt | returnStmt | block | exprOrAssign
//   expression  → addition
//   addition    → multiplication (("+" | "-") multiplication)*
//   multiplication → primary (("*" | "/") primary)*
//   primary     → NUMBER | IDENTIFIER ("(" args? ")")? | "(" expression ")"
// ============================================================
public class Parser {
    private let tokens: ArrayList<Token>  // 词法单元列表
    private var pos: Int64 = 0            // 当前解析位置

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

    /// 断言当前 Token 为指定类型并消费，否则抛出异常
    private func consume(tokenType: TokenType, message: String): Token {
        if (check(tokenType)) {
            return advance()
        }
        throw Exception("${message} at line ${current().line}, got ${current().text}")
    }

    /// 解析入口：将 Token 列表解析为语句列表
    public func parse(): ArrayList<Stmt> {
        var statements = ArrayList<Stmt>()
        while (!check(TokenType.EOF)) {
            statements.add(parseDeclaration())
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

        return Stmt.VarDecl(name, isMutable, initExpr)
    }

    /// 解析函数声明：func name(params) { body }
    private func parseFuncDecl(): Stmt {
        consume(TokenType.FUNC, "Expected 'func'")
        let nameToken = consume(TokenType.IDENTIFIER, "Expected function name")
        let name = nameToken.text

        consume(TokenType.LPAREN, "Expected '(' after function name")

        var params = ArrayList<String>()
        if (!check(TokenType.RPAREN)) {
            let firstParam = consume(TokenType.IDENTIFIER, "Expected parameter name")
            params.add(firstParam.text)
            while (check(TokenType.COMMA)) {
                advance()
                let param = consume(TokenType.IDENTIFIER, "Expected parameter name")
                params.add(param.text)
            }
        }
        consume(TokenType.RPAREN, "Expected ')' after parameters")

        consume(TokenType.LBRACE, "Expected '{' before function body")
        let body = parseBlock()
        consume(TokenType.RBRACE, "Expected '}' after function body")

        return Stmt.FuncDecl(name, params, body)
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
            return Stmt.Assignment(nameToken.text, value)
        }
        let expr = parseExpression()
        return Stmt.ExprStmt(expr)
    }

    /// 解析表达式（入口，当前等价于加减运算）
    private func parseExpression(): Expr {
        return parseAddition()
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
        var left = parsePrimary()

        while (check(TokenType.STAR) || check(TokenType.SLASH)) {
            let op = if (check(TokenType.STAR)) { BinaryOp.MUL } else { BinaryOp.DIV }
            advance()
            let right = parsePrimary()
            left = Expr.Binary(Box(left), op, Box(right))
        }

        return left
    }

    /// 解析基本表达式（数字、变量、函数调用、括号表达式）
    private func parsePrimary(): Expr {
        if (check(TokenType.NUMBER)) {
            let token = advance()
            return Expr.Number(token.value)
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

        throw Exception("Unexpected token: ${current().text} at line ${current().line}")
    }
}
