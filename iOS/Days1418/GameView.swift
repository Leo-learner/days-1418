import SwiftUI

struct GameView: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(Prefs.fontSize) private var fontSize = 17.0
    @AppStorage(Prefs.textMode) private var textMode = 0
    @AppStorage(Prefs.sidebar) private var showSidebar = true
    @State private var revealed = 0
    @State private var typed = Int.max
    @State private var revealTask: Task<Void, Never>?
    @State private var showDossier = false
    @State private var changes: [StatChange] = []   // 上一个抉择带来的全部变化
    @State private var choosing = false              // passageVersion 这次变化是不是玩家点选项引起的

    var body: some View {
        if let passage = model.passage {
            let wide = sizeClass == .regular
            GeometryReader { geo in
                let sidebar = wide && showSidebar
                // 七个按钮全摆开再加上章节名，游戏栏得有 720pt；iPad 竖屏开着侧栏只剩五百多，就把次要按钮收进菜单
                let roomy = wide && geo.size.width - (sidebar ? 300 : 0) >= 720
                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        AtmosphereView(mood: passage.mood)
                        VStack(spacing: 0) {
                            GameTopBar(passage: passage, wide: wide, roomy: roomy, showSidebar: $showSidebar) {
                                showDossier = true
                            }
                            story(passage, wide: wide)
                        }
                    }
                    if sidebar {
                        ScrollView {
                            DossierContent()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 20)
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: 300)
                        .background(p.panel.opacity(p.isDark ? 0.96 : 0.9).ignoresSafeArea())
                        .overlay(alignment: .leading) { Rectangle().fill(p.line).frame(width: 1).ignoresSafeArea() }
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            .sheet(isPresented: $showDossier) {
                DossierSheet(changes: changes)
                    .environmentObject(model)
                    .environment(\.palette, p)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(p.panel)
                    .preferredColorScheme(p.isDark ? .dark : .light)
            }
            .onAppear { startReveal() }
            .onChange(of: model.passageVersion) {
                captureChanges()
                startReveal()
            }
            .onDisappear { revealTask?.cancel() }
        }
    }

    private func story(_ passage: Passage, wide: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    if let last = passage.lastChoice {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("▸").foregroundStyle(p.accent)
                            Text(last).italic()
                        }
                        .font(Fonts.body(fontSize - 3))
                        .foregroundStyle(p.inkFaint)
                        .padding(.bottom, changes.isEmpty ? 22 : 12)
                    }
                    if !changes.isEmpty {
                        ChangeStrip(all: changes) {
                            if wide {
                                withAnimation(.easeInOut(duration: 0.3)) { showSidebar = true }
                            } else {
                                showDossier = true
                            }
                        }
                        .padding(.bottom, 22)
                    }
                    ForEach(passage.paras.prefix(revealed)) { para in
                        ParaView(para: para, limit: para.id == revealed - 1 && typed != Int.max ? typed : nil, fontSize: fontSize)
                            .id(para.id)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    if allRevealed(passage) {
                        ChoiceList(choices: passage.choices, fontSize: fontSize, broken: passage.broken, pick: choose)
                            .padding(.top, 18)
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 48)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, wide ? 56 : 22)
                .padding(.top, wide ? 26 : 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { revealAll(passage) }
            }
            .scrollIndicators(.hidden)
            .onChange(of: revealed) {
                // 大屏跟着新浮现的段落往下滚；手机一屏装不下一整节，自动滚会把还没读完的开头推出屏幕，交给手指
                if wide && revealed > 1 {
                    withAnimation(.easeOut(duration: 0.6)) { proxy.scrollTo(revealed - 1, anchor: .bottom) }
                }
            }
            .onChange(of: model.passageVersion) {
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private func choose(_ choice: ShownChoice) {
        guard choice.enabled else { return }
        choosing = true
        model.choose(choice)
        // 走进结局那一下是重的；震动放在这里而不是结局页的 onAppear，从档案馆翻回结局页时就不会再震
        if model.screen == .ending { Haptics.ending() } else { Haptics.choice() }
    }

    /// 只有玩家亲手点的选项才挂变化标签：回溯、读档、继续游戏时 model.deltas 里是上一次抉择的旧账
    private func captureChanges() {
        changes = choosing ? StatChange.all(from: model.deltas, engine: model.engine, story: model.story) : []
        choosing = false
    }

    private func allRevealed(_ passage: Passage) -> Bool {
        revealed >= passage.paras.count && typed == Int.max
    }

    private func startReveal() {
        revealTask?.cancel()
        guard let passage = model.passage else { return }
        if textMode == 2 || model.snapshotMode || passage.paras.isEmpty {
            revealed = passage.paras.count
            typed = Int.max
            return
        }
        revealed = 0
        typed = Int.max
        let version = model.passageVersion
        let mode = textMode
        revealTask = Task { @MainActor in
            for (i, para) in passage.paras.enumerated() {
                guard !Task.isCancelled, version == model.passageVersion else { return }
                if mode == 1 {
                    typed = 0
                    withAnimation(.easeOut(duration: 0.2)) { revealed = i + 1 }
                    let total = para.text.count
                    while typed < total {
                        try? await Task.sleep(for: .milliseconds(24))
                        guard !Task.isCancelled else { return }
                        typed += 2
                    }
                    typed = Int.max
                    try? await Task.sleep(for: .milliseconds(160))
                } else {
                    withAnimation(.easeOut(duration: 0.55)) { revealed = i + 1 }
                    let delay = min(1.25, 0.3 + Double(para.text.count) / 160)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    private func revealAll(_ passage: Passage) {
        guard !allRevealed(passage) else { return }
        revealTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            revealed = passage.paras.count
            typed = Int.max
        }
    }
}

// MARK: - 顶栏

struct GameTopBar: View {
    let passage: Passage
    let wide: Bool      // iPad 宽屏：军人证是右侧栏，按钮切换它的显隐；否则是底部弹出的面板
    let roomy: Bool     // 游戏栏够宽：日志、档案馆、存读档各占一个按钮；否则收进"更多"菜单
    @Binding var showSidebar: Bool
    let openDossier: () -> Void
    @EnvironmentObject private var model: GameModel
    @EnvironmentObject private var fonts: FontLoader
    @Environment(\.palette) private var p
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // 地点常常很长（"布列斯特以北 · 距边境十一公里 · 步兵第427团夏季营地"）：平时截成一行，点一下展开
            VStack(alignment: .leading, spacing: 3) {
                Text(chapterLine)
                    .font(Fonts.bodyBold(wide ? 14 : 13.5))
                    .foregroundStyle(p.inkDim)
                    .lineLimit(expanded ? 3 : 1)
                Text([passage.date, passage.place].filter { !$0.isEmpty }.joined(separator: roomy ? "  ·  " : " · "))
                    .font(Fonts.doc(12.5))
                    .foregroundStyle(p.inkFaint)
                    .lineLimit(expanded ? 4 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            .onChange(of: model.passageVersion) { expanded = false }

            if model.isHardcore {
                Text("铁人").font(Fonts.ui(10, .semibold)).foregroundStyle(p.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.accent, lineWidth: 1))
                    .padding(.horizontal, 4)
            }
            Button { model.rewind() } label: { BarIcon(icon: "arrow.uturn.backward", enabled: model.canRewind) }
                .buttonStyle(PressAware())
                .disabled(!model.canRewind)
                .keyboardShortcut("z")
                .accessibilityLabel("回溯到上一个抉择")
            if roomy {
                wideButtons
            } else {
                Button {
                    if wide {
                        withAnimation(.easeInOut(duration: 0.3)) { showSidebar.toggle() }
                    } else {
                        openDossier()
                    }
                } label: {
                    BarIcon(icon: wide ? "sidebar.right" : "person.text.rectangle")
                }
                .buttonStyle(PressAware())
                .accessibilityLabel("军人证")
                moreMenu
            }
        }
        .padding(.leading, wide ? 24 : 18)
        .padding(.trailing, wide ? 14 : 6)
        .padding(.vertical, 6)
        .background(
            LinearGradient(colors: [p.bg.opacity(0.94), p.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    /// 章节名是"第二卷 · 伏尔加　第十一章 地下室的孩子"（中间是全角空格）。
    /// 手机（和开着侧栏的 iPad 竖屏）顶栏放不下整句，收起时只留全角空格后面那半——卷名很久才变一次，章名才是眼下在哪
    private var chapterLine: String {
        guard !roomy, !expanded, let gap = passage.chapter.range(of: "　") else { return passage.chapter }
        return String(passage.chapter[gap.upperBound...])
    }

    @ViewBuilder private var wideButtons: some View {
        Button { model.sheet = .log } label: { BarIcon(icon: "text.book.closed") }
            .buttonStyle(PressAware()).keyboardShortcut("l").accessibilityLabel("战斗日志")
        Button { model.openArchive() } label: { BarIcon(icon: "archivebox", badge: model.unseenCount > 0) }
            .buttonStyle(PressAware()).keyboardShortcut("d").accessibilityLabel("档案馆")
        Button { model.sheet = .save } label: { BarIcon(icon: "square.and.arrow.down", enabled: !model.isHardcore) }
            .buttonStyle(PressAware()).disabled(model.isHardcore).keyboardShortcut("s").accessibilityLabel("存档")
        Button { model.sheet = .load } label: { BarIcon(icon: "folder") }
            .buttonStyle(PressAware()).keyboardShortcut("o").accessibilityLabel("读档")
        Button { withAnimation(.easeInOut(duration: 0.3)) { showSidebar.toggle() } } label: { BarIcon(icon: "sidebar.right") }
            .buttonStyle(PressAware()).accessibilityLabel("军人证")
        moreMenu
    }

    private var moreMenu: some View {
        Menu {
            if !roomy {
                Button { model.sheet = .log } label: { Label("战斗日志", systemImage: "text.book.closed") }
                Button { model.openArchive() } label: {
                    Label(model.unseenCount > 0 ? "档案馆 · \(model.unseenCount) 项新内容" : "档案馆", systemImage: "archivebox")
                }
                Divider()
                Button { model.sheet = .save } label: { Label("存档", systemImage: "square.and.arrow.down") }
                    .disabled(model.isHardcore)
                Button { model.sheet = .load } label: { Label("读档", systemImage: "folder") }
                Divider()
            }
            Button { model.sheet = .settings } label: { Label("设置", systemImage: "gearshape") }
            Button { model.backToTitle() } label: { Label("返回标题", systemImage: "house") }
            // 宋体没到位时在这里交代一声（玩的时候看不到标题页底下那行字），点一下立刻重试
            if fonts.phase != .ready {
                Divider()
                Button { fonts.start(force: true) } label: {
                    Label(fonts.menuStatus, systemImage: fonts.phase == .waitingForWiFi ? "wifi" : "textformat")
                }
                .disabled(fonts.isBusy)
            }
        } label: {
            BarIcon(icon: "ellipsis.circle", badge: !roomy && model.unseenCount > 0)
        }
        .accessibilityLabel("更多")
    }
}

// MARK: - 变化标签

/// 正文开头的一排小标签："兵力 −4 人"、"米沙·列文 信任 +5"。点一下打开军人证。
struct ChangeStrip: View {
    let all: [StatChange]
    let open: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        let shown = pickHeadlineChanges(all)
        let hidden = all.count - shown.count
        Button(action: open) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(shown) { change in
                    Text(change.label)
                        .font(Fonts.ui(11.5, .medium))
                        .foregroundStyle(color(change.tone))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(color(change.tone).opacity(0.55), lineWidth: 1))
                }
                if hidden > 0 {
                    Text("另 \(hidden) 项 ›")
                        .font(Fonts.ui(11.5))
                        .foregroundStyle(p.inkFaint)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("这次抉择的影响：" + all.map(\.label).joined(separator: "，"))
        .accessibilityHint("打开军人证")
    }

    private func color(_ tone: StatChange.Tone) -> Color {
        switch tone {
        case .good: return p.khaki
        case .bad: return p.accent
        case .neutral: return p.gold
        }
    }
}

// MARK: - 正文

struct ParaView: View {
    let para: ShownPara
    let limit: Int?
    let fontSize: Double
    @Environment(\.palette) private var p
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        switch para.style {
        case .rule:
            HStack(spacing: 14) {
                Rectangle().fill(p.line).frame(width: 60, height: 1)
                Text("✦").font(.system(size: 9)).foregroundStyle(p.inkFaint)
                Rectangle().fill(p.line).frame(width: 60, height: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        case .quote:
            Text(visible)
                .font(Fonts.doc(fontSize))
                .foregroundStyle(p.ink.opacity(0.92))
                .lineSpacing(fontSize * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
                .padding(.horizontal, sizeClass == .regular ? 20 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.panel.opacity(0.72))
                .overlay(alignment: .leading) { Rectangle().fill(p.khaki).frame(width: 2) }
                .padding(.bottom, fontSize * 0.9)
        case .normal:
            Text(attributed)
                .font(Fonts.body(fontSize))
                .foregroundStyle(p.ink)
                .lineSpacing(fontSize * 0.62)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, fontSize * 0.95)
        }
    }

    private var visible: String {
        guard let limit else { return para.text }
        return String(para.text.prefix(limit))
    }

    /// 支持 **加粗** 和 *强调*；打字机模式下还没打完的段落按纯文本显示
    private var attributed: AttributedString {
        if limit != nil { return AttributedString(visible.replacingOccurrences(of: "*", with: "")) }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: para.text, options: options)) ?? AttributedString(para.text)
    }
}

// MARK: - 选项

struct ChoiceList: View {
    let choices: [ShownChoice]
    let fontSize: Double
    let broken: Bool
    let pick: (ShownChoice) -> Void
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { i, choice in
                Button { pick(choice) } label: {
                    ChoiceLabel(choice: choice, number: i + 1, fontSize: fontSize)
                }
                .buttonStyle(PressAware())
                .disabled(!choice.enabled)
                // iPad 接实体键盘时按数字键选（和 Mac 版一样）
                .keyboardShortcut(i < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: []) : nil)
                .accessibilityLabel(([choice.tags.joined(separator: "，"), choice.text] + (choice.enabled ? [] : ["条件不足"]))
                    .filter { !$0.isEmpty }.joined(separator: "，"))
            }
            if broken {
                Text("（这里的剧本还没写完——你可以回溯，或回到标题。）")
                    .font(Fonts.body(fontSize - 2))
                    .foregroundStyle(p.inkFaint)
                Button("回到标题") { model.backToTitle() }
                    .font(Fonts.body(fontSize - 1))
            }
        }
    }
}

struct ChoiceLabel: View {
    let choice: ShownChoice
    let number: Int
    let fontSize: Double
    @Environment(\.palette) private var p
    @Environment(\.buttonPressed) private var pressed

    var body: some View {
        let lit = pressed && choice.enabled
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(Fonts.mono(13).weight(.bold))
                .foregroundStyle(lit ? p.accent : p.inkFaint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 7) {
                if !choice.tags.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 5) {
                        ForEach(choice.tags, id: \.self) { tag in TagChip(tag: tag, enabled: choice.enabled) }
                    }
                }
                Text(choice.text)
                    .font(Fonts.body(fontSize - 1))
                    .foregroundStyle(choice.enabled ? p.ink : p.inkFaint)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !choice.enabled {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(p.inkFaint)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(lit ? p.panelHi.opacity(0.95) : p.panel.opacity(0.72))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(choice.isArchive ? p.stamp : p.accent)
                .frame(width: 3)
                .opacity(lit || choice.isArchive ? 1 : 0)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(choice.isArchive ? p.stamp.opacity(0.55) : p.line, lineWidth: 1)
        )
        .scaleEffect(lit ? 0.985 : 1)
        .animation(.easeOut(duration: 0.12), value: lit)
        .contentShape(Rectangle())
    }
}

struct TagChip: View {
    let tag: String
    let enabled: Bool
    @Environment(\.palette) private var p

    var body: some View {
        let archive = tag == "档案"
        HStack(spacing: 4) {
            if archive { Image(systemName: "seal.fill").font(.system(size: 9)) }
            Text(tag).font(Fonts.ui(10.5, .semibold))
        }
        .foregroundStyle(archive ? p.stamp : (enabled ? p.khaki : p.inkFaint))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(archive ? p.stamp : (enabled ? p.khaki : p.inkFaint), lineWidth: 1))
    }
}
