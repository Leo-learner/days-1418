import SwiftUI

/// 手机上的"军人证"：从底部拉出来的面板，内容和 iPad 右侧栏共用 DossierContent
struct DossierSheet: View {
    /// 这一屏开头那排标签对应的变化。面板是读完一屏才去点的，那时 model.deltas 早过了 6 秒被清空
    let changes: [StatChange]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("轻点任一项看说明").font(Fonts.ui(11)).foregroundStyle(p.inkFaint)
                    Spacer()
                    TextAction(title: "完成", strong: true) { dismiss() }
                }
                DossierContent(pinned: Dictionary(uniqueKeysWithValues: changes.map { ($0.key, $0.delta) }))
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }
}

/// 身份、部队状况、个人属性、人物、随身物品。Mac 版靠鼠标悬停看说明，触屏上改成点一下展开。
struct DossierContent: View {
    /// 给了就用它标 +/−（手机面板）；不给就跟 Mac 侧栏一样用 model.deltas，抉择后闪 6 秒（iPad 常驻侧栏）
    var pinned: [String: Int]?
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @State private var open: Set<String> = []

    private var deltas: [String: Int] { pinned ?? model.deltas }

    var body: some View {
        let e = model.engine
        let s = model.story
        let deltas = deltas
        VStack(alignment: .leading, spacing: 20) {
            idCard(e, s)

            section("部队") {
                ForEach(s.units, id: \.key) { u in
                    let v = e.lookup(u.key)
                    explained(u.key, u.desc) {
                        if u.max == 100 {
                            MeterRow(name: u.name, value: v, maxValue: 100, text: "\(v)\(u.unit)", tint: v < 30 ? p.accent : p.khaki, delta: deltas[u.key])
                        } else {
                            ValueRow(name: u.name, text: "\(v) \(u.unit)", delta: deltas[u.key], big: u.key == "men")
                        }
                    }
                }
            }

            section("个人") {
                ForEach(s.stats, id: \.key) { st in
                    let v = e.lookup(st.key)
                    explained(st.key, st.desc) {
                        if st.max <= 10 {
                            PipRow(name: st.name, value: v, maxValue: st.max, delta: deltas[st.key])
                        } else {
                            let bad = st.key == "trauma" || st.key == "susp"
                            MeterRow(name: st.name, value: v, maxValue: st.max, text: "\(v)", tint: bad ? p.accent : p.khaki, delta: deltas[st.key])
                        }
                    }
                }
            }

            let people = s.persons.filter { e.lookup($0.key + "_met") != 0 }
            if !people.isEmpty {
                section("人物") {
                    ForEach(people, id: \.key) { person in
                        explained(person.key, person.desc) {
                            PersonRow(
                                name: person.name,
                                trust: e.lookup(person.key),
                                dead: e.lookup(person.key + "_dead") != 0,
                                away: e.lookup(person.key + "_away") != 0,
                                delta: deltas[person.key]
                            )
                        }
                    }
                }
            }

            let items = s.items.filter { e.lookup($0.key) > 0 }
            if !items.isEmpty {
                section("随身物品") {
                    ForEach(items, id: \.key) { item in
                        let n = e.lookup(item.key)
                        explained(item.key, item.desc) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("·").foregroundStyle(p.khaki)
                                Text(item.name + (n > 1 ? " ×\(n)" : ""))
                                    .font(Fonts.body(14.5))
                                    .foregroundStyle(p.ink)
                                if deltas[item.key] != nil {
                                    Text("新").font(Fonts.ui(9.5, .semibold)).foregroundStyle(p.accent)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 行本身 + 点开后在下面出现的说明文字
    private func explained<Row: View>(_ key: String, _ desc: String, @ViewBuilder row: () -> Row) -> some View {
        let isOpen = open.contains(key)
        return VStack(alignment: .leading, spacing: 5) {
            row()
            if isOpen && !desc.isEmpty {
                Text(desc)
                    .font(Fonts.body(13))
                    .foregroundStyle(p.inkFaint)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !desc.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                if isOpen { open.remove(key) } else { open.insert(key) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(desc)
    }

    private func idCard(_ e: Engine, _ s: Story) -> some View {
        let rank = s.label("rank", e.lookup("rank"))
        let post = s.label("post", e.lookup("post"))
        let parts = s.hero.components(separatedBy: "·")
        let surname = parts.last ?? s.hero
        let given = parts.dropLast().joined(separator: "·")
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("КРАСНОАРМЕЙСКАЯ КНИЖКА")
                    .font(Fonts.typewriter(8.5))
                    .tracking(1)
                    .foregroundStyle(p.paperInk.opacity(0.55))
                Spacer()
                Text("№ 1418").font(Fonts.typewriter(9)).foregroundStyle(p.stamp.opacity(0.8))
            }
            Text(surname)
                .font(Fonts.bodyBold(24))
                .foregroundStyle(p.paperInk)
            Text(given)
                .font(Fonts.doc(13))
                .foregroundStyle(p.paperInk.opacity(0.75))
            HStack(spacing: 6) {
                Text(rank).font(Fonts.bodyBold(14)).foregroundStyle(p.stamp)
                Text("·").foregroundStyle(p.paperInk.opacity(0.4))
                Text(post).font(Fonts.body(14)).foregroundStyle(p.paperInk)
                if deltas["rank"] != nil || deltas["post"] != nil {
                    Text("变动").font(Fonts.ui(9.5, .semibold)).foregroundStyle(p.stamp)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaperBackground())
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title).font(Fonts.ui(11, .semibold)).tracking(3).foregroundStyle(p.inkFaint)
                Rectangle().fill(p.line).frame(height: 1)
            }
            content()
        }
    }
}

// MARK: - 行

struct DeltaBadge: View {
    let delta: Int?
    @Environment(\.palette) private var p

    var body: some View {
        if let delta, delta != 0 {
            Text(StatChange.signed(delta))
                .font(Fonts.mono(11).weight(.bold))
                .foregroundStyle(delta > 0 ? p.khaki : p.accent)
                .transition(.opacity)
        }
    }
}

struct ValueRow: View {
    let name: String
    let text: String
    let delta: Int?
    var big = false
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(Fonts.body(14.5)).foregroundStyle(p.inkDim)
            Spacer()
            DeltaBadge(delta: delta)
            Text(text)
                .font(big ? Fonts.bodyBold(20) : Fonts.body(15))
                .foregroundStyle(p.ink)
                .monospacedDigit()
        }
    }
}

struct MeterRow: View {
    let name: String
    let value: Int
    let maxValue: Int
    let text: String
    let tint: Color
    let delta: Int?
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(Fonts.body(14.5)).foregroundStyle(p.inkDim)
                Spacer()
                DeltaBadge(delta: delta)
                Text(text).font(Fonts.body(14.5)).foregroundStyle(p.ink).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(p.line.opacity(0.7))
                    Rectangle().fill(tint)
                        .frame(width: geo.size.width * CGFloat(max(0, min(value, maxValue))) / CGFloat(max(1, maxValue)))
                }
            }
            .frame(height: 3)
            .animation(.easeOut(duration: 0.6), value: value)
        }
    }
}

struct PipRow: View {
    let name: String
    let value: Int
    let maxValue: Int
    let delta: Int?
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .center) {
            Text(name).font(Fonts.body(14.5)).foregroundStyle(p.inkDim)
            Spacer()
            DeltaBadge(delta: delta)
            HStack(spacing: 3) {
                ForEach(0..<maxValue, id: \.self) { i in
                    Rectangle()
                        .fill(i < value ? p.ink.opacity(0.85) : p.line)
                        .frame(width: 8, height: 8)
                }
            }
            Text("\(value)").font(Fonts.mono(12).weight(.bold)).foregroundStyle(p.ink).frame(width: 18, alignment: .trailing)
        }
    }
}

struct PersonRow: View {
    let name: String
    let trust: Int
    let dead: Bool
    let away: Bool
    let delta: Int?
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(Fonts.body(15))
                    .strikethrough(dead, color: p.inkFaint)
                    .foregroundStyle(dead ? p.inkFaint : p.ink)
                if dead {
                    Text("†").font(Fonts.bodyBold(13)).foregroundStyle(p.inkFaint)
                } else if away {
                    Text("不在身边").font(Fonts.ui(10)).foregroundStyle(p.inkFaint)
                }
                Spacer()
                if !dead {
                    DeltaBadge(delta: delta)
                    Text(trustWord).font(Fonts.ui(11)).foregroundStyle(p.inkFaint)
                }
            }
            if !dead {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(p.line.opacity(0.6))
                        Rectangle().fill(p.inkDim.opacity(0.8)).frame(width: geo.size.width * CGFloat(trust) / 100)
                    }
                }
                .frame(height: 2)
                .animation(.easeOut(duration: 0.6), value: trust)
            }
        }
        .opacity(dead ? 0.75 : 1)
    }

    private var trustWord: String {
        switch trust {
        case ..<20: return "敌视"
        case ..<40: return "疏远"
        case ..<60: return "一般"
        case ..<80: return "信任"
        default: return "生死之交"
        }
    }
}
