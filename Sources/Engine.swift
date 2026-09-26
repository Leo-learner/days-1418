import Foundation

// MARK: - 存档里的状态

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var choice: String?
    var header: String
    var text: String
}

struct Snapshot: Codable {
    var node: String
    var vars: [String: Int]
    var rng: UInt64
    var chapter: String
    var date: String
    var place: String
    var mood: String
    var logCount: Int
    var visited: [String: Int]
    var lastChoice: String?
}

/// 一局游戏的全部状态。随机数种子也存在里面：同样的选择永远得到同样的结果，读档刷不出好运气。
struct RunState: Codable {
    var node = ""
    var vars: [String: Int] = [:]
    var rng: UInt64 = 0
    var chapter = ""
    var date = ""
    var place = ""
    var mood = ""
    var visited: [String: Int] = [:]
    var log: [LogEntry] = []
    var snapshots: [Snapshot] = []
    var lastChoice: String?
    var playSeconds: Double = 0
    var hardcore = false
    var ending: String?
    var savedAt = Date()
}

/// 跨周目的进度：结局、档案、m_ 变量
struct Meta: Codable {
    var endings: [String: Date] = [:]
    var docs: [String: Date] = [:]
    var vars: [String: Int] = [:]
    var runsStarted = 0
    var runsFinished = 0
    var unseenEndings: Set<String> = []
    var unseenDocs: Set<String> = []
}

// MARK: - 给界面用的一屏内容

struct ShownPara: Identifiable {
    let id: Int
    let style: ParaStyle
    let text: String
}

struct ShownChoice: Identifiable {
    let id: Int
    let index: Int          // 节点里的第几个选项；-1 表示"继续"
    let text: String
    let tags: [String]      // 【战术 4】【档案】这类前缀
    let enabled: Bool
    var isArchive: Bool { tags.contains("档案") }
}

struct Passage {
    let nodeId: String
    let chapter: String
    let date: String
    let place: String
    let mood: String
    let paras: [ShownPara]
    let choices: [ShownChoice]
    let ending: EndingDef?
    let lastChoice: String?
    let broken: Bool        // 剧本断头：没有选项也不是结局
}

// MARK: - 引擎

final class Engine: ExprContext {
    let story: Story
    var state = RunState()
    var meta: Meta
    private(set) var freshDocs: [String] = []       // 上一步刚解密的档案（给提示条用）
    private(set) var freshEnding = false
    private var randomAllowed = false

    init(story: Story, meta: Meta) {
        self.story = story
        self.meta = meta
    }

    // MARK: ExprContext

    func lookup(_ name: String) -> Int {
        switch name {
        case "endings": return meta.endings.count
        case "docs": return meta.docs.count
        case "runs": return meta.runsFinished
        case "hardcore": return state.hardcore ? 1 : 0
        default:
            if name.hasPrefix("m_") { return meta.vars[name] ?? 0 }
            return state.vars[name] ?? story.initial[name] ?? 0
        }
    }

    func call(_ fn: String, _ args: [Expr]) -> Int {
        func arg(_ i: Int) -> Int { args.indices.contains(i) ? args[i].value(in: self) : 0 }
        func ident(_ i: Int) -> String { args.indices.contains(i) ? (args[i].identifier ?? "") : "" }
        switch fn {
        case "doc": return meta.docs[ident(0)] != nil ? 1 : 0
        case "end": return meta.endings[ident(0)] != nil ? 1 : 0
        case "seen": return (state.visited[ident(0)] ?? 0) > 0 ? 1 : 0
        case "alive":
            let k = ident(0)
            return lookup(k + "_met") != 0 && lookup(k + "_dead") == 0 ? 1 : 0
        case "rand":
            let n = max(1, arg(0))
            return randomAllowed ? Int(nextRandom() % UInt64(n)) : 0
        case "min": return args.map { $0.value(in: self) }.min() ?? 0
        case "max": return args.map { $0.value(in: self) }.max() ?? 0
        case "abs": return abs(arg(0))
        case "if": return args.count == 3 ? (arg(0) != 0 ? arg(1) : arg(2)) : 0
        default: return 0
        }
    }

    /// SplitMix64：小、快、可复现
    private func nextRandom() -> UInt64 {
        state.rng &+= 0x9E37_79B9_7F4A_7C15
        var z = state.rng
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private func test(_ cond: Expr?) -> Bool { cond.map { $0.value(in: self) != 0 } ?? true }

    // MARK: 状态读写

    func set(_ name: String, _ value: Int) {
        var v = value
        if let range = story.bounds[name] { v = min(max(v, range.lowerBound), range.upperBound) }
        if name.hasPrefix("m_") { meta.vars[name] = v } else { state.vars[name] = v }
    }

    func apply(_ effects: [Effect]) {
        randomAllowed = true
        defer { randomAllowed = false }
        for effect in effects {
            switch effect {
            case .assign(let name, let op, let expr):
                let v = expr.value(in: self)
                switch op {
                case "+=": set(name, lookup(name) + v)
                case "-=": set(name, lookup(name) - v)
                default: set(name, v)
                }
            case .archive(let id): unlockDoc(id)
            case .kill(let who): set(who + "_dead", 1)
            case .meet(let who): set(who + "_met", 1)
            }
        }
    }

    func unlockDoc(_ id: String) {
        guard meta.docs[id] == nil else { return }
        meta.docs[id] = Date()
        meta.unseenDocs.insert(id)
        freshDocs.append(id)
    }

    // MARK: 流程

    func newRun(hardcore: Bool, seed: UInt64? = nil) {
        state = RunState()
        state.hardcore = hardcore
        state.vars = story.initial
        state.rng = seed ?? UInt64.random(in: 1...UInt64.max)
        meta.runsStarted += 1
        freshDocs = []
        freshEnding = false
        enter(story.start)
        appendLog(choice: nil)
    }

    func restore(_ saved: RunState) {
        state = saved
        freshDocs = []
        freshEnding = false
    }

    /// 进入节点：执行 @set、解密 @archive、按 @if 跳转，最后停在一个要给玩家看的节点上
    func enter(_ id: String) {
        var target = id
        for _ in 0..<64 {
            guard let node = story.nodes[target] else {
                state.node = target
                return
            }
            state.visited[target, default: 0] += 1
            apply(node.sets)
            node.archives.forEach(unlockDoc)
            if let v = node.chapter { state.chapter = v }
            if let v = node.date { state.date = v }
            if let v = node.place { state.place = v }
            if let v = node.mood { state.mood = v }

            randomAllowed = true
            let jump = node.redirects.first { test($0.cond) }
            randomAllowed = false
            if let jump {
                target = jump.target
                continue
            }
            state.node = target
            if let e = node.ending { reachEnding(e) }
            return
        }
        state.node = target
    }

    private func reachEnding(_ id: String) {
        state.ending = id
        meta.runsFinished += 1
        if meta.endings[id] == nil {
            meta.endings[id] = Date()
            meta.unseenEndings.insert(id)
            freshEnding = true
        }
        if let doc = story.ending(id)?.doc { unlockDoc(doc) }
    }

    /// 可选的选项（含锁定的）
    func shownChoices() -> [ShownChoice] {
        guard let node = story.nodes[state.node], node.ending == nil else { return [] }
        var out: [ShownChoice] = []
        for (i, c) in node.choices.enumerated() {
            let ok = test(c.cond)
            if !ok && !c.showLocked { continue }
            let (tags, text) = Engine.splitTags(interpolate(c.text))
            out.append(ShownChoice(id: out.count, index: i, text: text, tags: tags, enabled: ok))
        }
        if node.choices.isEmpty, node.next != nil {
            out.append(ShownChoice(id: 0, index: -1, text: "继续", tags: [], enabled: true))
        }
        return out
    }

    func passage() -> Passage {
        let node = story.nodes[state.node]
        var paras: [ShownPara] = []
        for p in node?.paras ?? [] where test(p.cond) {
            let text = interpolate(p.text)
            // 连续的 > 引文合成一块（纪念章纸条、命令摘录都是多行的）
            if p.style == .quote, let last = paras.last, last.style == .quote {
                paras[paras.count - 1] = ShownPara(id: last.id, style: .quote, text: last.text + "\n" + text)
            } else {
                paras.append(ShownPara(id: paras.count, style: p.style, text: text))
            }
        }
        let choices = shownChoices()
        let ending = node?.ending.flatMap { story.ending($0) }
        if node == nil {
            paras = [ShownPara(id: 0, style: .quote, text: "（剧本在这里断了：找不到节点「\(state.node)」）")]
        }
        return Passage(
            nodeId: state.node,
            chapter: state.chapter,
            date: state.date,
            place: state.place,
            mood: state.mood,
            paras: paras,
            choices: choices,
            ending: ending,
            lastChoice: state.lastChoice,
            broken: ending == nil && choices.isEmpty
        )
    }

    func choose(_ shown: ShownChoice) {
        guard let node = story.nodes[state.node], shown.enabled else { return }
        freshDocs = []
        freshEnding = false
        state.snapshots.append(Snapshot(
            node: state.node, vars: state.vars, rng: state.rng,
            chapter: state.chapter, date: state.date, place: state.place, mood: state.mood,
            logCount: state.log.count, visited: state.visited, lastChoice: state.lastChoice
        ))
        if state.snapshots.count > 300 { state.snapshots.removeFirst(state.snapshots.count - 300) }

        if shown.index < 0 {
            apply(node.nextEffects)
            state.lastChoice = nil
            enter(node.next ?? "")
        } else {
            let choice = node.choices[shown.index]
            apply(choice.effects)
            state.lastChoice = shown.text
            enter(choice.target)
        }
        appendLog(choice: state.lastChoice)
    }

    var canRewind: Bool { !state.snapshots.isEmpty && !state.hardcore }

    func rewind() {
        guard let s = state.snapshots.popLast() else { return }
        state.node = s.node
        state.vars = s.vars
        state.rng = s.rng
        state.chapter = s.chapter
        state.date = s.date
        state.place = s.place
        state.mood = s.mood
        state.visited = s.visited
        state.lastChoice = s.lastChoice
        state.ending = nil
        if state.log.count > s.logCount { state.log.removeLast(state.log.count - s.logCount) }
        freshDocs = []
        freshEnding = false
    }

    private func appendLog(choice: String?) {
        let paras = story.nodes[state.node]?.paras.filter { test($0.cond) } ?? []
        let text = paras.map { $0.style == .rule ? "——" : interpolate($0.text) }.joined(separator: "\n")
        let header = [state.date, state.place].filter { !$0.isEmpty }.joined(separator: " · ")
        state.log.append(LogEntry(choice: choice, header: header, text: text))
        if state.log.count > 800 { state.log.removeFirst(state.log.count - 800) }
    }

    // MARK: 文本

    /// {表达式} 换成数值，{#key} 换成枚举名
    func interpolate(_ s: String) -> String {
        guard s.contains("{") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{", let close = s[i...].firstIndex(of: "}") {
                let inner = s[s.index(after: i)..<close].trimmingCharacters(in: .whitespaces)
                if inner.hasPrefix("#") {
                    let key = String(inner.dropFirst())
                    out += story.label(key, lookup(key))
                } else if let e = try? ExprParser.parse(inner) {
                    out += String(e.value(in: self))
                } else {
                    out += "{\(inner)}"
                }
                i = s.index(after: close)
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }

    /// "【战术 4】【档案】翻过去" → (["战术 4", "档案"], "翻过去")
    static func splitTags(_ s: String) -> ([String], String) {
        var tags: [String] = []
        var rest = Substring(s)
        while rest.hasPrefix("【"), let close = rest.firstIndex(of: "】") {
            tags.append(String(rest[rest.index(after: rest.startIndex)..<close]))
            rest = rest[rest.index(after: close)...].drop(while: { $0 == " " })
        }
        return (tags, String(rest))
    }
}
