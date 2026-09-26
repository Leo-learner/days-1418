import Foundation

/// 命令行剧本检查器：Days1418 -check <剧本目录> [-runs N] [-seed S]
/// 1. 静态检查：断链、死路、未登记的结局/档案、疑似拼错的变量、到不了的节点
/// 2. 蒙特卡洛：带跨周目进度连续模拟 N 局，统计每个结局被走到几次
/// 另有 -walk <攻略文件>：按文件里写的选项一步步走，用来验证真结局这种长链条件
enum Checker {
    static let builtins: Set<String> = ["endings", "docs", "runs", "hardcore", "true", "false"]
    static let functions: Set<String> = ["doc", "end", "seen", "alive", "rand", "min", "max", "abs", "if"]

    static func run(directory: String, runs: Int, seed: UInt64, force: Bool = false) -> Int32 {
        let story = StoryParser.load(directory: URL(fileURLWithPath: directory, isDirectory: true))
        var errors = story.issues
        var warnings: [String] = []

        let playable = story.nodeOrder.filter { !($0.hasPrefix("ending:") || $0.hasPrefix("doc:")) }
        let endingIds = Set(story.endings.map(\.id))
        let docIds = Set(story.docs.map(\.id))
        var assigned = Set(story.initial.keys)
        for p in story.persons { assigned.formUnion([p.key + "_dead", p.key + "_met", p.key + "_away"]) }
        var read: [String: String] = [:]   // 变量名 → 第一次读到的位置
        var usedEndings = Set<String>()

        func where_(_ n: StoryNode, _ line: Int? = nil) -> String { "\(n.file):\(line ?? n.line) [\(n.id)]" }

        func scanExpr(_ e: Expr?, _ at: String, textCondition: Bool = false) {
            guard let e else { return }
            switch e {
            case .number:
                break
            case .name(let name):
                if !builtins.contains(name) && read[name] == nil { read[name] = at }
            case .unary(_, let x):
                scanExpr(x, at, textCondition: textCondition)
            case .binary(_, let l, let r):
                scanExpr(l, at, textCondition: textCondition)
                scanExpr(r, at, textCondition: textCondition)
            case .call(let fn, let args):
                if !functions.contains(fn) { errors.append("\(at) 未知函数 \(fn)()") }
                let id = args.first?.identifier ?? ""
                switch fn {
                case "doc": if !docIds.contains(id) { errors.append("\(at) doc(\(id)) 没有这份档案") }
                case "end": if !endingIds.contains(id) { errors.append("\(at) end(\(id)) 没有这个结局") }
                case "seen": if story.nodes[id] == nil { errors.append("\(at) seen(\(id)) 没有这个节点") }
                case "alive": if !story.persons.contains(where: { $0.key == id }) { errors.append("\(at) alive(\(id)) 没有这个人物") }
                default:
                    if fn == "rand" && textCondition { warnings.append("\(at) 正文/选项条件里的 rand() 恒为 0") }
                    args.forEach { scanExpr($0, at, textCondition: textCondition) }
                }
            }
        }

        func scanEffects(_ effects: [Effect], _ at: String) {
            for effect in effects {
                switch effect {
                case .assign(let name, _, let expr):
                    assigned.insert(name)
                    scanExpr(expr, at)
                case .archive(let id):
                    if !docIds.contains(id) { errors.append("\(at) archive \(id) 没有这份档案") }
                case .kill(let who):
                    assigned.insert(who + "_dead")
                case .meet(let who):
                    assigned.insert(who + "_met")
                }
            }
        }

        func scanText(_ text: String, _ at: String) {
            var rest = Substring(text)
            while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
                let inner = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
                if inner.hasPrefix("#") {
                    let key = String(inner.dropFirst())
                    if story.enums[key] == nil { errors.append("\(at) {#\(key)} 没有这个枚举") }
                    if read[key] == nil { read[key] = at }
                } else {
                    do { scanExpr(try ExprParser.parse(inner), at, textCondition: true) } catch {
                        errors.append("\(at) 插值 {\(inner)} 写错了：\(error)")
                    }
                }
                rest = rest[rest.index(after: close)...]
            }
        }

        func checkTarget(_ target: String, _ at: String) {
            if story.nodes[target] == nil { errors.append("\(at) 目标不存在：\(target)") }
            else if target.hasPrefix("ending:") || target.hasPrefix("doc:") { errors.append("\(at) 不能跳到登记节点：\(target)") }
        }

        if story.nodes[story.start] == nil { errors.append("@@start 指向的节点不存在：\(story.start)") }

        for id in playable {
            guard let n = story.nodes[id] else { continue }
            scanEffects(n.sets, where_(n))
            for a in n.archives where !docIds.contains(a) { errors.append("\(where_(n)) @archive \(a) 没有这份档案") }
            for r in n.redirects {
                scanExpr(r.cond, where_(n, r.line))
                checkTarget(r.target, where_(n, r.line))
            }
            for p in n.paras {
                scanExpr(p.cond, where_(n), textCondition: true)
                scanText(p.text, where_(n))
            }
            for c in n.choices {
                scanExpr(c.cond, where_(n, c.line), textCondition: true)
                scanEffects(c.effects, where_(n, c.line))
                scanText(c.text, where_(n, c.line))
                checkTarget(c.target, where_(n, c.line))
            }
            if let next = n.next {
                scanEffects(n.nextEffects, where_(n))
                checkTarget(next, where_(n))
                if !n.choices.isEmpty { warnings.append("\(where_(n)) 同时有选项和 ->，-> 会被忽略") }
            }
            if let e = n.ending {
                usedEndings.insert(e)
                if !endingIds.contains(e) { errors.append("\(where_(n)) @ending \(e) 没有登记") }
            }
            if !n.paras.isEmpty && n.redirects.contains(where: { $0.cond != nil }) {
                warnings.append("\(where_(n)) 有正文又有条件跳转：跳转生效时正文会被整段跳过")
            }
            let escapes = !n.choices.isEmpty || n.next != nil || n.ending != nil || n.redirects.contains { $0.cond == nil }
            if !escapes {
                if n.redirects.isEmpty { errors.append("\(where_(n)) 死路：没有选项、没有 ->、也不是结局") }
                else if n.paras.isEmpty { errors.append("\(where_(n)) 只有条件跳转，全不满足时是空白死路") }
                else { warnings.append("\(where_(n)) 条件跳转全不满足时会停在这里（没有选项）") }
            }
        }
        for e in story.endings {
            if !usedEndings.contains(e.id) { errors.append("结局 \(e.id)「\(e.title)」没有任何节点用 @ending 指向它") }
            if let d = e.doc, !docIds.contains(d) { errors.append("结局 \(e.id) 的档案 \(d) 不存在") }
        }
        for (name, at) in read.sorted(by: { $0.key < $1.key }) where !assigned.contains(name) && !name.hasPrefix("m_") {
            warnings.append("\(at) 读取了从没赋值过的变量 \(name)（拼错了？）")
        }

        // 不考虑条件的可达性
        var seenNodes: Set<String> = [story.start]
        var queue = [story.start]
        while let id = queue.popLast() {
            guard let n = story.nodes[id] else { continue }
            let targets = n.choices.map(\.target) + n.redirects.map(\.target) + (n.next.map { [$0] } ?? [])
            for t in targets where !seenNodes.contains(t) {
                seenNodes.insert(t)
                queue.append(t)
            }
        }
        let unreachable = playable.filter { !seenNodes.contains($0) }
        for id in unreachable { warnings.append("到不了的节点：\(id)（\(story.nodes[id]!.file)）") }

        // 概况
        let choiceCount = playable.reduce(0) { $0 + (story.nodes[$1]?.choices.count ?? 0) }
        print("剧本：\(story.title)")
        print("节点 \(playable.count) · 选项 \(choiceCount) · 结局 \(story.endings.count) · 档案 \(story.docs.count) · 正文约 \(story.characterCount) 字")
        for e in errors { print("✘ \(e)") }
        for w in warnings.prefix(80) { print("△ \(w)") }
        if warnings.count > 80 { print("△ ……另有 \(warnings.count - 80) 条提醒") }

        if runs > 0 && (errors.isEmpty || force) { simulate(story, runs: runs, seed: seed) }
        print(errors.isEmpty ? "✓ 静态检查通过（\(warnings.count) 条提醒）" : "✘ \(errors.count) 个错误")
        return errors.isEmpty ? 0 : 1
    }

    /// 连续模拟：前面几局解锁的档案会让后面几局出现【档案】选项。
    /// 选择策略偏向"去得少的节点"，这样能照顾到冷门分支。
    static func simulate(_ story: Story, runs: Int, seed: UInt64) {
        var rng = SplitMix(seed: seed)
        let engine = Engine(story: story, meta: Meta())
        var endingHits: [String: Int] = [:]
        var firstRun: [String: Int] = [:]
        var visits: [String: Int] = [:]
        var broken: [String: Int] = [:]
        var loops = 0
        var totalSteps = 0
        var passed = Set<String>()
        var milestones: [String: Int] = [:]

        for run in 0..<runs {
            engine.newRun(hardcore: false, seed: rng.next())
            var steps = 0
            while steps < 4000 {
                visits[engine.state.node, default: 0] += 1
                if let e = engine.state.ending {
                    endingHits[e, default: 0] += 1
                    if firstRun[e] == nil { firstRun[e] = run + 1 }
                    break
                }
                var options = engine.shownChoices().filter(\.enabled)
                // 有别的路可走时，大概率绕开直通"已经见过的结局"的选项，让模拟往深处走
                if options.count > 1 {
                    let fresh = options.filter { !leadsToKnownEnding($0, engine) }
                    if !fresh.isEmpty && rng.next() % 100 < 85 { options = fresh }
                }
                if options.isEmpty {
                    broken[engine.state.node, default: 0] += 1
                    break
                }
                let pick: ShownChoice
                if rng.next() % 100 < 55 {
                    pick = options.min { a, b in
                        visitsFor(a, engine, visits) < visitsFor(b, engine, visits)
                    }!
                } else {
                    pick = options[Int(rng.next() % UInt64(options.count))]
                }
                engine.choose(pick)
                steps += 1
            }
            if steps >= 4000 { loops += 1 }
            totalSteps += steps
            for id in engine.state.visited.keys {
                passed.insert(id)
                if id.hasSuffix("_start") || id.hasPrefix("frame_i") { milestones[id, default: 0] += 1 }
            }
        }

        let playable = story.nodeOrder.filter { !($0.hasPrefix("ending:") || $0.hasPrefix("doc:")) }
        let covered = playable.filter { passed.contains($0) }.count
        print("—— 模拟 \(runs) 局 · 平均 \(totalSteps / max(1, runs)) 步 · 节点覆盖 \(covered)/\(playable.count)")
        for e in story.endings {
            let hits = endingHits[e.id] ?? 0
            let mark = hits > 0 ? "●" : "○"
            let first = firstRun[e.id].map { "（第 \($0) 局首次）" } ?? ""
            print("\(mark) \(e.id) \(e.tier) \(e.title)：\(hits) 次\(first)")
        }
        let order = ["a1_start", "frame_i1", "a2_start", "frame_i2", "a3_start", "frame_i3", "a35_start", "a4_start", "a4_post_start"]
        print("抵达：" + order.compactMap { k in milestones[k].map { "\(k) \($0)" } }.joined(separator: " · "))
        print("档案解密 \(engine.meta.docs.count)/\(story.docs.count)")
        let missing = story.docs.filter { engine.meta.docs[$0.id] == nil }.map(\.id)
        if !missing.isEmpty { print("  没解密到：\(missing.joined(separator: " "))") }
        for (node, n) in broken.sorted(by: { $0.value > $1.value }).prefix(20) { print("✘ 卡死在 \(node)：\(n) 局") }
        if loops > 0 { print("✘ \(loops) 局超过 4000 步，可能有死循环") }
        let never = playable.filter { !passed.contains($0) }
        if !never.isEmpty { print("  模拟里一次没到过的节点 \(never.count) 个：\(never.prefix(40).joined(separator: " "))") }
    }

    private static func leadsToKnownEnding(_ c: ShownChoice, _ engine: Engine) -> Bool {
        guard let node = engine.story.nodes[engine.state.node] else { return false }
        var target = c.index < 0 ? (node.next ?? "") : node.choices[c.index].target
        for _ in 0..<6 {
            guard let n = engine.story.nodes[target] else { return false }
            if let e = n.ending { return engine.meta.endings[e] != nil }
            if n.choices.isEmpty, let next = n.next { target = next; continue }
            if let jump = n.redirects.first(where: { $0.cond == nil }) { target = jump.target; continue }
            return false
        }
        return false
    }

    private static func visitsFor(_ c: ShownChoice, _ engine: Engine, _ visits: [String: Int]) -> Int {
        guard let node = engine.story.nodes[engine.state.node] else { return 0 }
        let target = c.index < 0 ? (node.next ?? "") : node.choices[c.index].target
        return visits[target] ?? 0
    }

    /// 按攻略文件走：每行是选项文字里的一段（或 #序号）；@docs d06,d04 预置已解密档案；@seed N 固定随机数
    static func walk(directory: String, script: String) -> Int32 {
        let story = StoryParser.load(directory: URL(fileURLWithPath: directory, isDirectory: true))
        guard let text = try? String(contentsOfFile: script, encoding: .utf8) else {
            print("读不了攻略文件 \(script)")
            return 1
        }
        var meta = Meta()
        var seed: UInt64 = 1
        var steps: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            if line.hasPrefix("@docs ") {
                for d in line.dropFirst(6).split(separator: ",") { meta.docs[d.trimmingCharacters(in: .whitespaces)] = Date() }
            } else if line.hasPrefix("@endings ") {
                for e in line.dropFirst(9).split(separator: ",") { meta.endings[e.trimmingCharacters(in: .whitespaces)] = Date() }
            } else if line.hasPrefix("@seed ") {
                seed = UInt64(line.dropFirst(6).trimmingCharacters(in: .whitespaces)) ?? 1
            } else {
                steps.append(line)
            }
        }
        let engine = Engine(story: story, meta: meta)
        engine.newRun(hardcore: false, seed: seed)
        for (i, step) in steps.enumerated() {
            if engine.state.ending != nil { break }
            let options = engine.shownChoices()
            let pick: ShownChoice?
            if step.hasPrefix("#"), let n = Int(step.dropFirst()) {
                pick = options.indices.contains(n - 1) ? options[n - 1] : nil
            } else {
                pick = options.first { $0.enabled && ($0.text.contains(step) || ($0.tags.joined() + $0.text).contains(step)) }
            }
            guard let pick else {
                print("✘ 第 \(i + 1) 步在 [\(engine.state.node)] 找不到选项「\(step)」。可选：")
                for o in options { print("   \(o.enabled ? "·" : "🔒") \(o.tags.map { "【\($0)】" }.joined())\(o.text)") }
                return 1
            }
            print("[\(engine.state.node)] → \(pick.text)")
            engine.choose(pick)
        }
        let s = engine.state
        print("停在：\(s.node) \(s.ending.map { "· 结局 \($0) \(story.ending($0)?.title ?? "")" } ?? "")")
        let keys = ["men", "hum", "trauma", "susp", "rank", "post", "misha", "nurlan", "katya", "kostya_dead", "belov_dead", "f_swap", "f_love"]
        print(keys.map { "\($0)=\(engine.lookup($0))" }.joined(separator: " "))
        if engine.state.ending == nil {
            let options = engine.shownChoices()
            for o in options { print("   \(o.enabled ? "·" : "🔒") \(o.tags.map { "【\($0)】" }.joined())\(o.text)") }
        }
        return 0
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
