import SwiftUI

struct TitleView: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtmosphereView(mood: "snow")

            Text("1418")
                .font(Fonts.typewriter(420).weight(.bold))
                .foregroundStyle(p.ink.opacity(0.035))
                .offset(x: 470, y: 150)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 70)
                Text("ВОСТОЧНЫЙ ФРОНТ  ·  22.06.1941 — 09.05.1945")
                    .font(Fonts.typewriter(12))
                    .tracking(4)
                    .foregroundStyle(p.inkFaint)
                Text("一千四百一十八天")
                    .font(Fonts.display(70))
                    .foregroundStyle(p.ink)
                    .padding(.top, 16)
                HStack(spacing: 16) {
                    Rectangle().fill(p.accent).frame(width: 70, height: 3)
                    Text("东 线 档 案").font(Fonts.bodyBold(19)).foregroundStyle(p.inkDim)
                }
                .padding(.top, 12)
                Text("从布格河到施普雷河，一个红军排长的战争，\n和一枚写错了名字的纪念章。")
                    .font(Fonts.body(16))
                    .lineSpacing(8)
                    .foregroundStyle(p.inkDim)
                    .padding(.top, 26)

                VStack(alignment: .leading, spacing: 4) {
                    if let auto = model.autosave {
                        TitleMenuItem(title: "继续", detail: [auto.chapter, auto.date].filter { !$0.isEmpty }.joined(separator: " · ")) {
                            model.continueGame()
                        }
                    }
                    TitleMenuItem(title: "新的卷宗", detail: model.engine.meta.runsStarted == 0 ? "1941年6月21日，星期六" : "第 \(model.engine.meta.runsStarted + 1) 次复原") {
                        model.sheet = .newGame
                    }
                    TitleMenuItem(title: "读取存档", detail: nil) { model.sheet = .load }
                    TitleMenuItem(
                        title: "档案馆",
                        detail: "结局 \(model.endingCount)/\(model.story.endings.count) · 档案 \(model.docCount)/\(model.story.docs.count)",
                        badge: model.unseenCount > 0
                    ) { model.openArchive() }
                    TitleMenuItem(title: "设置", detail: nil) { model.sheet = .settings }
                    TitleMenuItem(title: "退出", detail: nil) { NSApp.terminate(nil) }
                }
                .padding(.top, 46)
                Spacer(minLength: 40)
            }
            .padding(.leading, 100)
            .frame(maxHeight: .infinity, alignment: .leading)

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Text("本作部队番号、人物与村庄均为虚构；历史背景、制度与时间线参照真实事件。")
                        .font(Fonts.ui(11))
                        .foregroundStyle(p.inkFaint)
                    Spacer()
                    if !model.story.issues.isEmpty {
                        Text("剧本有 \(model.story.issues.count) 处问题").font(Fonts.ui(11)).foregroundStyle(p.accent)
                    }
                    Text("v1.0").font(Fonts.typewriter(11)).foregroundStyle(p.inkFaint)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
        }
    }
}

struct TitleMenuItem: View {
    let title: String
    let detail: String?
    var badge = false
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title)
                    .font(Fonts.bodyBold(23))
                    .foregroundStyle(hover ? p.ink : p.ink.opacity(0.82))
                if badge {
                    Circle().fill(p.accent).frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 12 }
                }
                if let detail {
                    Text(detail)
                        .font(Fonts.ui(12))
                        .foregroundStyle(p.inkFaint)
                }
            }
            .offset(x: hover ? 10 : 0)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(p.accent)
                    .frame(width: hover ? 22 : 0, height: 2)
                    .offset(x: -22)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
    }
}
