import Foundation

/// 剧本里的条件和数值表达式：整数、变量、四则运算、比较、&& || !、函数调用。
/// 所有值都是整数，布尔值用 0/1 表示——剧本作者只需要记住"非零即真"。
indirect enum Expr {
    case number(Int)
    case name(String)
    case unary(String, Expr)
    case binary(String, Expr, Expr)
    case call(String, [Expr])

    /// doc(d06)、seen(a1_start) 这类函数的参数是裸标识符，不当变量求值
    var identifier: String? {
        if case .name(let s) = self { return s }
        return nil
    }

    func value(in ctx: ExprContext) -> Int {
        switch self {
        case .number(let n):
            return n
        case .name(let s):
            return ctx.lookup(s)
        case .unary(let op, let e):
            let v = e.value(in: ctx)
            return op == "!" ? (v == 0 ? 1 : 0) : -v
        case .binary(let op, let l, let r):
            if op == "&&" { return l.value(in: ctx) != 0 && r.value(in: ctx) != 0 ? 1 : 0 }
            if op == "||" { return l.value(in: ctx) != 0 || r.value(in: ctx) != 0 ? 1 : 0 }
            let a = l.value(in: ctx), b = r.value(in: ctx)
            switch op {
            case "+": return a &+ b
            case "-": return a &- b
            case "*": return a &* b
            case "/": return b == 0 ? 0 : a / b
            case "%": return b == 0 ? 0 : a % b
            case "==": return a == b ? 1 : 0
            case "!=": return a != b ? 1 : 0
            case "<": return a < b ? 1 : 0
            case "<=": return a <= b ? 1 : 0
            case ">": return a > b ? 1 : 0
            case ">=": return a >= b ? 1 : 0
            default: return 0
            }
        case .call(let fn, let args):
            return ctx.call(fn, args)
        }
    }

    /// 深度优先走一遍语法树，检查器用它收集变量名和函数调用
    func visit(_ body: (Expr) -> Void) {
        body(self)
        switch self {
        case .unary(_, let e): e.visit(body)
        case .binary(_, let l, let r): l.visit(body); r.visit(body)
        case .call(_, let args): args.forEach { $0.visit(body) }
        default: break
        }
    }
}

protocol ExprContext: AnyObject {
    func lookup(_ name: String) -> Int
    func call(_ fn: String, _ args: [Expr]) -> Int
}

struct ScriptError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum ExprParser {
    enum Token: Equatable {
        case number(Int)
        case ident(String)
        case op(String)
        case end
    }

    private static let precedence: [String: Int] = [
        "||": 1, "&&": 2,
        "==": 3, "!=": 3,
        "<": 4, "<=": 4, ">": 4, ">=": 4,
        "+": 5, "-": 5,
        "*": 6, "/": 6, "%": 6,
    ]

    static func parse(_ source: String) throws -> Expr {
        var state = State(tokens: try tokenize(source))
        let expr = try state.parse(minPrecedence: 1)
        guard state.peek == .end else { throw ScriptError("表达式后面多了东西：\(source)") }
        return expr
    }

    static func tokenize(_ source: String) throws -> [Token] {
        var out: [Token] = []
        let cs = Array(source)
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if c == " " || c == "\t" { i += 1; continue }
            if c.isASCII && c.isNumber {
                var j = i
                while j < cs.count, cs[j].isASCII, cs[j].isNumber { j += 1 }
                out.append(.number(Int(String(cs[i..<j])) ?? 0))
                i = j
                continue
            }
            if c.isASCII && (c.isLetter || c == "_") {
                var j = i
                while j < cs.count, cs[j].isASCII, cs[j].isLetter || cs[j].isNumber || cs[j] == "_" { j += 1 }
                out.append(.ident(String(cs[i..<j])))
                i = j
                continue
            }
            if i + 1 < cs.count {
                let two = String(cs[i...i + 1])
                if ["==", "!=", "<=", ">=", "&&", "||"].contains(two) {
                    out.append(.op(two))
                    i += 2
                    continue
                }
            }
            if "+-*/%<>!(),".contains(c) {
                out.append(.op(String(c)))
                i += 1
                continue
            }
            throw ScriptError("表达式里有认不出的字符「\(c)」：\(source)")
        }
        out.append(.end)
        return out
    }

    private struct State {
        var tokens: [Token]
        var pos = 0

        var peek: Token { tokens[pos] }

        mutating func next() -> Token {
            let t = tokens[pos]
            if pos < tokens.count - 1 { pos += 1 }
            return t
        }

        // 优先级爬升；同级左结合
        mutating func parse(minPrecedence: Int) throws -> Expr {
            var lhs = try parseUnary()
            while case .op(let op) = peek, let p = ExprParser.precedence[op], p >= minPrecedence {
                _ = next()
                let rhs = try parse(minPrecedence: p + 1)
                lhs = .binary(op, lhs, rhs)
            }
            return lhs
        }

        mutating func parseUnary() throws -> Expr {
            if case .op(let op) = peek, op == "!" || op == "-" {
                _ = next()
                return .unary(op, try parseUnary())
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> Expr {
            switch next() {
            case .number(let n):
                return .number(n)
            case .ident(let name):
                if name == "true" { return .number(1) }
                if name == "false" { return .number(0) }
                guard peek == .op("(") else { return .name(name) }
                _ = next()
                var args: [Expr] = []
                if peek == .op(")") {
                    _ = next()
                    return .call(name, args)
                }
                while true {
                    args.append(try parse(minPrecedence: 1))
                    let t = next()
                    if t == .op(")") { break }
                    guard t == .op(",") else { throw ScriptError("函数 \(name)(…) 的参数写法不对") }
                }
                return .call(name, args)
            case .op("("):
                let e = try parse(minPrecedence: 1)
                guard next() == .op(")") else { throw ScriptError("括号没有闭合") }
                return e
            default:
                throw ScriptError("表达式不完整")
            }
        }
    }
}

/// 进入节点或做出选择时执行的效果
enum Effect {
    case assign(String, String, Expr)   // 变量、运算符（= += -=）、值
    case archive(String)                // 解密一份档案
    case kill(String)                   // 某人阵亡：key_dead = 1
    case meet(String)                   // 认识某人：key_met = 1

    static func parseList(_ source: String) throws -> [Effect] {
        var out: [Effect] = []
        for raw in source.split(separator: ";") {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            out.append(try parseOne(s))
        }
        return out
    }

    private static func parseOne(_ s: String) throws -> Effect {
        for keyword in ["archive", "kill", "meet"] where s.hasPrefix(keyword + " ") {
            let arg = s.dropFirst(keyword.count + 1).trimmingCharacters(in: .whitespaces)
            guard !arg.isEmpty else { throw ScriptError("\(keyword) 后面缺少名字") }
            switch keyword {
            case "archive": return .archive(arg)
            case "kill": return .kill(arg)
            default: return .meet(arg)
            }
        }
        let chars = Array(s)
        for i in chars.indices where chars[i] == "=" {
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if next == "=" || prev == "=" || prev == "!" || prev == "<" || prev == ">" { continue }
            var op = "="
            var lhsEnd = i
            if prev == "+" || prev == "-" {
                op = String(prev!) + "="
                lhsEnd = i - 1
            }
            let name = String(chars[0..<lhsEnd]).trimmingCharacters(in: .whitespaces)
            let rhs = String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw ScriptError("赋值左边不是变量名：\(s)")
            }
            return .assign(name, op, try ExprParser.parse(rhs))
        }
        throw ScriptError("看不懂的效果：\(s)")
    }
}
