import SwiftUI

/// 右侧"军人证"：身份、部队状况、个人属性、人物、随身物品
struct SidebarView: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        let e = model.engine
        let s = model.story
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                idCard(e, s)

                section("部队") {
                    ForEach(s.units, id: \.key) { u in
                        let v = e.lookup(u.key)
                        if u.max == 100 {
                            MeterRow(name: u.name, value: v, maxValue: 100, text: "\(v)\(u.unit)", tint: v < 30 ? p.accent : p.khaki, delta: model.deltas[u.key], help: u.desc)
                        } else {
                            ValueRow(name: u.name, text: "\(v) \(u.unit)", delta: model.deltas[u.key], help: u.desc, big: u.key == "men")
                        }
                    }
                }

                section("个人") {
                    ForEach(s.stats, id: \.key) { st in
                        let v = e.lookup(st.key)
                        if st.max <= 10 {
                            PipRow(name: st.name, value: v, maxValue: st.max, delta: model.deltas[st.key], help: st.desc)
                        } else {
                            let bad = st.key == "trauma" || st.key == "susp"
                            MeterRow(name: st.name, value: v, maxValue: st.max, text: "\(v)", tint: bad ? p.accent : p.khaki, delta: model.deltas[st.key], help: st.desc)
                        }
                    }
                }

                let people = s.persons.filter { e.lookup($0.key + "_met") != 0 }
                if !people.isEmpty {
                    section("人物") {
                        ForEach(people, id: \.key) { person in
                            PersonRow(
                                name: person.name,
                                desc: person.desc,
                                trust: e.lookup(person.key),
                                dead: e.lookup(person.key + "_dead") != 0,
                                away: e.lookup(person.key + "_away") != 0,
                                delta: model.deltas[person.key]
                            )
                        }
                    }
                }

                let items = s.items.filter { e.lookup($0.key) > 0 }
                if !items.isEmpty {
                    section("随身物品") {
                        ForEach(items, id: \.key) { item in
                            let n = e.lookup(item.key)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("·").foregroundStyle(p.khaki)
                                Text(item.name + (n > 1 ? " ×\(n)" : ""))
                                    .font(Fonts.body(13.5))
                                    .foregroundStyle(p.ink)
                                if model.deltas[item.key] != nil {
                                    Text("新").font(Fonts.ui(9, .semibold)).foregroundStyle(p.accent)
                                }
                            }
                            .help(item.desc)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 62)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(p.panel.opacity(p.isDark ? 0.96 : 0.9))
        .overlay(alignment: .leading) { Rectangle().fill(p.line).frame(width: 1) }
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
                Text(rank).font(Fonts.bodyBold(13.5)).foregroundStyle(p.stamp)
                Text("·").foregroundStyle(p.paperInk.opacity(0.4))
                Text(post).font(Fonts.body(13.5)).foregroundStyle(p.paperInk)
                if model.deltas["rank"] != nil || model.deltas["post"] != nil {
                    Text("变动").font(Fonts.ui(9, .semibold)).foregroundStyle(p.stamp)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(title).font(Fonts.ui(11, .semibold)).tracking(3).foregroundStyle(p.inkFaint)
                Rectangle().fill(p.line).frame(height: 1)
            }
            content()
        }
    }
}

struct DeltaBadge: View {
    let delta: Int?
    @Environment(\.palette) private var p

    var body: some View {
        if let delta, delta != 0 {
            Text(delta > 0 ? "+\(delta)" : "\(delta)")
                .font(Fonts.mono(10.5).weight(.bold))
                .foregroundStyle(delta > 0 ? p.khaki : p.accent)
                .transition(.opacity)
        }
    }
}

struct ValueRow: View {
    let name: String
    let text: String
    let delta: Int?
    let help: String
    var big = false
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(Fonts.body(13.5)).foregroundStyle(p.inkDim)
            Spacer()
            DeltaBadge(delta: delta)
            Text(text)
                .font(big ? Fonts.bodyBold(19) : Fonts.body(14))
                .foregroundStyle(p.ink)
                .monospacedDigit()
        }
        .help(help)
    }
}

struct MeterRow: View {
    let name: String
    let value: Int
    let maxValue: Int
    let text: String
    let tint: Color
    let delta: Int?
    let help: String
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(Fonts.body(13.5)).foregroundStyle(p.inkDim)
                Spacer()
                DeltaBadge(delta: delta)
                Text(text).font(Fonts.body(13.5)).foregroundStyle(p.ink).monospacedDigit()
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
        .help(help)
    }
}

struct PipRow: View {
    let name: String
    let value: Int
    let maxValue: Int
    let delta: Int?
    let help: String
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .center) {
            Text(name).font(Fonts.body(13.5)).foregroundStyle(p.inkDim)
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
        .help(help)
    }
}

struct PersonRow: View {
    let name: String
    let desc: String
    let trust: Int
    let dead: Bool
    let away: Bool
    let delta: Int?
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(Fonts.body(14))
                    .strikethrough(dead, color: p.inkFaint)
                    .foregroundStyle(dead ? p.inkFaint : p.ink)
                if dead {
                    Text("†").font(Fonts.bodyBold(13)).foregroundStyle(p.inkFaint)
                } else if away {
                    Text("不在身边").font(Fonts.ui(9.5)).foregroundStyle(p.inkFaint)
                }
                Spacer()
                if !dead {
                    DeltaBadge(delta: delta)
                    Text(trustWord).font(Fonts.ui(10.5)).foregroundStyle(p.inkFaint)
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
        .help(desc)
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
