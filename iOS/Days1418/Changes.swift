import Foundation

/// 一次抉择带来的一项变化，已经翻译成玩家看得懂的话。
/// Mac 版右边常驻"军人证"侧栏，数值一变旁边就跳 +/-；手机上侧栏收进了弹出面板，
/// 所以每一屏正文开头挂一排小标签，告诉玩家上一个抉择改变了什么。
struct StatChange: Identifiable, Equatable {
    enum Kind: Int, Comparable {
        case rank      // 军衔、职务
        case unit      // 兵力、伤员、弹药、口粮、士气
        case person    // 某个人对你的信任
        case stat      // 指挥、战术、胆识、人性、创伤、嫌疑、上级信任
        case item      // 随身物品

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    enum Tone { case good, bad, neutral }

    let key: String       // 剧本里的变量名：men、misha、trauma、i_chess……
    let kind: Kind
    let name: String      // 显示名：兵力、米沙·列文、创伤、折叠象棋……
    let delta: Int        // 变化量（新值 − 旧值）
    let range: Int        // 这个数值的量程（上限 − 下限）：同样 +5，放在 0–10 的战术上和 0–100 的人性上分量完全不同
    let tone: Tone        // 对玩家是好事、坏事还是说不上
    let label: String     // 芯片上的整句："兵力 −4 人"、"米沙·列文 信任 +5"、"获得 折叠象棋"

    var id: String { key }
}

extension StatChange {
    /// 这些数值是越高越糟
    private static let risingIsBad: Set<String> = ["trauma", "susp", "wounded"]

    /// 把 GameModel.deltas（变量名 → 变化量）翻译成 StatChange 列表，顺序和军人证里一致
    static func all(from deltas: [String: Int], engine: Engine, story: Story) -> [StatChange] {
        guard !deltas.isEmpty else { return [] }
        var out: [StatChange] = []

        func tone(_ key: String, _ d: Int) -> Tone {
            (d > 0) != risingIsBad.contains(key) ? .good : .bad
        }

        for key in ["rank", "post"] {
            guard let d = deltas[key], d != 0 else { continue }
            let now = story.label(key, engine.lookup(key))
            let label = key == "post" ? "职务 \(now)" : (d > 0 ? "晋升 \(now)" : "降为 \(now)")
            out.append(StatChange(key: key, kind: .rank, name: key == "rank" ? "军衔" : "职务", delta: d,
                                  range: max(1, (story.enums[key]?.count ?? 1) - 1),
                                  tone: key == "rank" ? (d > 0 ? .good : .bad) : .neutral, label: label))
        }
        for u in story.units {
            guard let d = deltas[u.key], d != 0 else { continue }
            let amount = u.unit == "%" ? "\(signed(d))%" : (u.unit.isEmpty ? signed(d) : "\(signed(d)) \(u.unit)")
            out.append(StatChange(key: u.key, kind: .unit, name: u.name, delta: d, range: u.max - u.min,
                                  tone: tone(u.key, d), label: "\(u.name) \(amount)"))
        }
        for person in story.persons {
            guard let d = deltas[person.key], d != 0 else { continue }
            out.append(StatChange(key: person.key, kind: .person, name: person.name, delta: d, range: 100,
                                  tone: tone(person.key, d), label: "\(person.name) 信任 \(signed(d))"))
        }
        for s in story.stats {
            guard let d = deltas[s.key], d != 0 else { continue }
            out.append(StatChange(key: s.key, kind: .stat, name: s.name, delta: d, range: s.max - s.min,
                                  tone: tone(s.key, d), label: "\(s.name) \(signed(d))"))
        }
        for item in story.items {
            guard let d = deltas[item.key], d != 0 else { continue }
            out.append(StatChange(key: item.key, kind: .item, name: item.name, delta: d, range: 1,
                                  tone: .neutral, label: d > 0 ? "获得 \(item.name)" : "失去 \(item.name)"))
        }
        return out
    }

    /// 用真正的减号（−）而不是连字符，数字对齐也好看些
    static func signed(_ d: Int) -> String { d > 0 ? "+\(d)" : "−\(-d)" }
}

/// 手机顶上只有窄窄一条地方。这里决定：一次抉择引起的全部变化里，哪些值得立刻告诉玩家、按什么顺序。
/// 没挑上的不会丢——标签条末尾会出一个"另 N 项"，点开就是完整的军人证。
///
/// - Parameter all: 这次抉择引起的全部变化，已按 军衔 → 部队 → 人物 → 个人 → 物品 排好
/// - Returns: 要显示在正文开头的那几项，按显示顺序
func pickHeadlineChanges(_ all: [StatChange]) -> [StatChange] {
    // TODO: 挑选规则还没定。现在是全部照搬（战斗场面一次能变六七项，会折成两三行）。
    return all
}
