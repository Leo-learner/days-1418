import Foundation

// MARK: - 剧本数据模型

enum ParaStyle: String, Codable {
    case normal   // 普通叙述
    case quote    // 公文、信件、命令——用仿宋排
    case rule     // 场景分隔
}

struct Para {
    var cond: Expr?
    var style: ParaStyle
    var text: String
}

struct Choice {
    var cond: Expr?
    var showLocked: Bool     // 条件不满足时是否显示为"锁定"
    var text: String
    var target: String
    var effects: [Effect]
    var line: Int
}

struct Redirect {
    var cond: Expr?
    var target: String
    var line: Int
}

struct StoryNode {
    let id: String
    let file: String
    let line: Int
    var chapter: String?
    var date: String?
    var place: String?
    var mood: String?
    var act: Int?
    var sets: [Effect] = []
    var redirects: [Redirect] = []
    var ending: String?
    var archives: [String] = []
    var paras: [Para] = []
    var choices: [Choice] = []
    var next: String?
    var nextEffects: [Effect] = []
    var props: [String: String] = [:]   // 结局 / 档案登记节点的附加字段

    var isRegistry: Bool { id.hasPrefix("ending:") || id.hasPrefix("doc:") }
}

struct EndingDef: Identifiable {
    let id: String
    var tier: String
    var title: String
    var act: Int
    var doc: String?
    var hint: String
    var order: Int
}

struct DocDef: Identifiable {
    let id: String
    var title: String
    var source: String
    var date: String
    var kind: String
    var who: String?
    var isKey: Bool
    var paras: [Para]
    var order: Int
}

struct StatDef {
    let key: String
    let name: String
    let desc: String
    let initial: Int
    let min: Int
    let max: Int
    let unit: String
}

struct PersonDef {
    let key: String
    let name: String
    let desc: String
}

struct ItemDef {
    let key: String
    let name: String
    let desc: String
}

final class Story {
    var title = "一千四百一十八天"
    var hero = "伊利亚·谢尔盖耶维奇·格罗莫夫"
    var start = ""
    var nodes: [String: StoryNode] = [:]
    var nodeOrder: [String] = []
    var stats: [StatDef] = []        // 个人属性
    var units: [StatDef] = []        // 部队状况
    var persons: [PersonDef] = []
    var items: [ItemDef] = []
    var enums: [String: [String]] = [:]
    var initial: [String: Int] = [:]
    var bounds: [String: ClosedRange<Int>] = [:]
    var endings: [EndingDef] = []
    var docs: [DocDef] = []
    var issues: [String] = []
    var characterCount = 0

    private var endingIndex: [String: Int] = [:]
    private var docIndex: [String: Int] = [:]

    func ending(_ id: String) -> EndingDef? { endingIndex[id].map { endings[$0] } }
    func doc(_ id: String) -> DocDef? { docIndex[id].map { docs[$0] } }

    func label(_ key: String, _ value: Int) -> String {
        guard let labels = enums[key], labels.indices.contains(value) else { return "\(value)" }
        return labels[value]
    }

    fileprivate func buildIndexes() {
        endings.sort { $0.order < $1.order }
        docs.sort { $0.order < $1.order }
        endingIndex = Dictionary(uniqueKeysWithValues: endings.enumerated().map { ($1.id, $0) })
        docIndex = Dictionary(uniqueKeysWithValues: docs.enumerated().map { ($1.id, $0) })
    }
}

// MARK: - 解析器

enum StoryParser {
    static func load(directory: URL) -> Story {
        let story = Story()
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "story" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if files.isEmpty { story.issues.append("在 \(directory.path) 里没找到任何 .story 剧本") }
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                story.issues.append("读不了 \(url.lastPathComponent)")
                continue
            }
            parse(text, file: url.lastPathComponent, into: story)
        }
        finalize(story)
        return story
    }

    static func parse(_ text: String, file: String, into story: Story) {
        var current: StoryNode?

        func flush() {
            guard let node = current else { return }
            if story.nodes[node.id] != nil {
                story.issues.append("\(file):\(node.line) 节点重名：\(node.id)")
            } else {
                story.nodeOrder.append(node.id)
            }
            story.nodes[node.id] = node
            current = nil
        }

        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let ln = index + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            do {
                if line.hasPrefix("@@") {
                    try parseDeclaration(line, story)
                    continue
                }
                if line.hasPrefix("===") {
                    flush()
                    let id = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { throw ScriptError("=== 后面缺节点名") }
                    current = StoryNode(id: id, file: file, line: ln)
                    continue
                }
                guard var node = current else {
                    story.issues.append("\(file):\(ln) 这一行不属于任何节点：\(line.prefix(24))")
                    continue
                }
                if line.hasPrefix("@") {
                    try parseDirective(line, &node, ln)
                } else if line.hasPrefix("* ") || line.hasPrefix("+ ") {
                    node.choices.append(try parseChoice(line, ln))
                } else if line.hasPrefix("->") {
                    var tail = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    if let bar = tail.firstIndex(of: "|") {
                        node.nextEffects = try Effect.parseList(String(tail[tail.index(after: bar)...]))
                        tail = tail[..<bar].trimmingCharacters(in: .whitespaces)
                    }
                    node.next = tail
                } else {
                    let para = try parsePara(line)
                    story.characterCount += para.text.count
                    node.paras.append(para)
                }
                current = node
            } catch {
                story.issues.append("\(file):\(ln) \(error)")
            }
        }
        flush()
    }

    private static func splitHead(_ s: Substring) -> (String, String) {
        guard let sp = s.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return (String(s), "") }
        return (String(s[..<sp]), s[sp...].trimmingCharacters(in: .whitespaces))
    }

    private static func parseDeclaration(_ line: String, _ story: Story) throws {
        let (keyword, value) = splitHead(line.dropFirst(2))
        let f = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        switch keyword {
        case "title":
            story.title = value
        case "start":
            story.start = value
        case "hero":
            story.hero = value
        case "stat", "unit":
            // key | 名称 | 说明 | 初值 | 下限 | 上限 [| 单位]
            guard f.count >= 6, let ini = Int(f[3]), let lo = Int(f[4]), let hi = Int(f[5]) else {
                throw ScriptError("@@\(keyword) 需要 6 个字段：\(value)")
            }
            let def = StatDef(key: f[0], name: f[1], desc: f[2], initial: ini, min: lo, max: hi, unit: f.count > 6 ? f[6] : "")
            if keyword == "stat" { story.stats.append(def) } else { story.units.append(def) }
            story.initial[f[0]] = ini
            story.bounds[f[0]] = lo...hi
        case "person":
            // key | 名字 | 说明 | 初始信任
            guard f.count >= 4, let trust = Int(f[3]) else { throw ScriptError("@@person 需要 4 个字段：\(value)") }
            story.persons.append(PersonDef(key: f[0], name: f[1], desc: f[2]))
            story.initial[f[0]] = trust
            story.bounds[f[0]] = 0...100
        case "item":
            guard f.count >= 2 else { throw ScriptError("@@item 至少要有 key 和名称") }
            story.items.append(ItemDef(key: f[0], name: f[1], desc: f.count > 2 ? f[2] : ""))
        case "enum":
            guard f.count >= 2 else { throw ScriptError("@@enum 至少要有一个标签") }
            story.enums[f[0]] = Array(f.dropFirst())
        case "var":
            let parts = value.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let v = Int(parts[1]) else { throw ScriptError("@@var 写法：@@var key = 值") }
            story.initial[parts[0]] = v
        case "bound":
            guard f.count == 3, let lo = Int(f[1]), let hi = Int(f[2]) else { throw ScriptError("@@bound 写法：key | 下限 | 上限") }
            story.bounds[f[0]] = lo...hi
        default:
            throw ScriptError("不认识的声明 @@\(keyword)")
        }
    }

    private static func parseDirective(_ line: String, _ node: inout StoryNode, _ ln: Int) throws {
        let (key, value) = splitHead(line.dropFirst())
        switch key {
        case "chapter": node.chapter = value
        case "date": node.date = value
        case "place": node.place = value
        case "mood": node.mood = value
        case "act": node.act = Int(value)
        case "set": node.sets += try Effect.parseList(value)
        case "if":
            guard let arrow = value.range(of: "->", options: .backwards) else { throw ScriptError("@if 缺少 -> 目标") }
            let cond = value[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            let target = value[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            node.redirects.append(Redirect(cond: try ExprParser.parse(cond), target: target, line: ln))
        case "goto":
            node.redirects.append(Redirect(cond: nil, target: value, line: ln))
        case "ending":
            node.ending = value
        case "archive":
            node.archives.append(value)
        default:
            node.props[key] = value
        }
    }

    private static func parseChoice(_ line: String, _ ln: Int) throws -> Choice {
        let locked = line.hasPrefix("+")
        var rest = line.dropFirst(1).trimmingCharacters(in: .whitespaces)
        var cond: Expr?
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { throw ScriptError("选项条件的 [ ] 没有闭合") }
            let source = rest[rest.index(after: rest.startIndex)..<close]
            cond = try ExprParser.parse(String(source))
            rest = rest[rest.index(after: close)...].trimmingCharacters(in: .whitespaces)
        }
        guard let arrow = rest.range(of: "->", options: .backwards) else { throw ScriptError("选项缺少 -> 目标") }
        let text = rest[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        var tail = rest[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        var effects: [Effect] = []
        if let bar = tail.firstIndex(of: "|") {
            effects = try Effect.parseList(String(tail[tail.index(after: bar)...]))
            tail = tail[..<bar].trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty, !tail.isEmpty else { throw ScriptError("选项文字或目标为空") }
        return Choice(cond: cond, showLocked: locked, text: text, target: tail, effects: effects, line: ln)
    }

    private static func parsePara(_ line: String) throws -> Para {
        var rest = Substring(line)
        var cond: Expr?
        if rest.hasPrefix("[?") {
            guard let close = rest.firstIndex(of: "]") else { throw ScriptError("条件段落的 [? ] 没有闭合") }
            let source = rest[rest.index(rest.startIndex, offsetBy: 2)..<close].trimmingCharacters(in: .whitespaces)
            cond = try ExprParser.parse(source)
            rest = Substring(rest[rest.index(after: close)...].trimmingCharacters(in: .whitespaces))
        }
        if rest == "---" { return Para(cond: cond, style: .rule, text: "") }
        if rest.hasPrefix(">") {
            return Para(cond: cond, style: .quote, text: rest.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        return Para(cond: cond, style: .normal, text: String(rest))
    }

    /// 把 ending:xx / doc:xx 登记节点整理成结局表和档案表
    private static func finalize(_ story: Story) {
        for id in story.nodeOrder {
            guard let n = story.nodes[id] else { continue }
            if id.hasPrefix("ending:") {
                let eid = String(id.dropFirst("ending:".count))
                story.endings.append(EndingDef(
                    id: eid,
                    tier: n.props["tier"] ?? "BE",
                    title: n.props["title"] ?? eid,
                    act: n.act ?? 0,
                    doc: n.props["doc"],
                    hint: n.props["hint"] ?? "",
                    order: Int(n.props["order"] ?? "") ?? story.endings.count * 10
                ))
            } else if id.hasPrefix("doc:") {
                let did = String(id.dropFirst("doc:".count))
                story.docs.append(DocDef(
                    id: did,
                    title: n.props["title"] ?? did,
                    source: n.props["source"] ?? "",
                    date: n.date ?? "",
                    kind: n.props["kind"] ?? "档案",
                    who: n.props["who"],
                    isKey: n.props["key"].map { $0 != "0" } ?? false,
                    paras: n.paras,
                    order: Int(n.props["order"] ?? "") ?? story.docs.count * 10
                ))
            }
        }
        story.buildIndexes()
    }
}
