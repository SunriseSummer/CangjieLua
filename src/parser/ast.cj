package cangjie_lua.parser

import std.collection.*

// ============================================================
// AST（抽象语法树）节点定义
// Expr —— 表达式节点，Stmt —— 语句节点，BinaryOp —— 二元运算符。
// ============================================================

/// 表达式节点
public enum Expr {
    | Number(Float64)                           // 数字字面量
    | Variable(String)                          // 变量引用
    | Binary(Box<Expr>, BinaryOp, Box<Expr>)    // 二元运算：left op right
    | Call(String, ArrayList<Expr>)             // 函数调用：funcName(args...)
}

/// 语句节点
public enum Stmt {
    | VarDecl(String, Bool, Expr)                           // 变量声明：let/var name = expr
    | Assignment(String, Expr)                              // 赋值语句：name = expr
    | IfStmt(Expr, ArrayList<Stmt>, ArrayList<Stmt>)        // if (cond) { then } else { else }
    | WhileStmt(Expr, ArrayList<Stmt>)                      // while (cond) { body }
    | FuncDecl(String, ArrayList<String>, ArrayList<Stmt>)  // func name(params) { body }
    | ReturnStmt(Expr)                                      // return expr
    | ExprStmt(Expr)                                        // 表达式语句（如函数调用）
    | Block(ArrayList<Stmt>)                                // 代码块 { stmts }
}

/// 二元运算符
public enum BinaryOp {
    | ADD  // +
    | SUB  // -
    | MUL  // *
    | DIV  // /
}
