import SwiftUI

struct GameView: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @AppStorage(Prefs.fontSize) private var fontSize = 18.0
    @AppStorage(Prefs.textMode) private var textMode = 0
    @AppStorage(Prefs.sidebar) private var showSidebar = true
    @State private var revealed = 0
    @State private var typed = Int.max
    @State private var revealTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        if let passage = model.passage {
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    AtmosphereView(mood: passage.mood)
                    VStack(spacing: 0) {
                        GameTopBar(passage: passage, showSidebar: $showSidebar)
                        story(passage)
                    }
                }
                if showSidebar {
                    SidebarView()
                        .frame(width: 304)
                        .transition(.move(edge: .trailing))
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handleKey(press, passage) }
            .onAppear {
                focused = true
                startReveal()
            }
            .onChange(of: model.passageVersion) { startReveal() }
            .onDisappear { revealTask?.cancel() }
        }
    }

    private func story(_ passage: Passage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let last = passage.lastChoice {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("▸").foregroundStyle(p.accent)
                            Text(last).italic()
                        }
                        .font(Fonts.body(fontSize - 3))
                        .foregroundStyle(p.inkFaint)
                        .padding(.bottom, 22)
                    }
                    ForEach(passage.paras.prefix(revealed)) { para in
                        ParaView(
                            para: para,
                            limit: para.id == revealed - 1 && typed != Int.max ? typed : nil,
                            fontSize: fontSize
                        )
                        .id(para.id)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    if allRevealed(passage) {
                        ChoiceList(choices: passage.choices, fontSize: fontSize, broken: passage.broken) { choice in
                            model.choose(choice)
                        }
                        .padding(.top, 18)
                        .transition(.opacity)
                    }
                    Color.clear.frame(height: 60).id("bottom")
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 34)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { revealAll(passage) }
            }
            .scrollIndicators(.hidden)
            .onChange(of: revealed) {
                if revealed > 1 {
                    withAnimation(.easeOut(duration: 0.6)) { proxy.scrollTo(revealed - 1, anchor: .bottom) }
                } else {
                    proxy.scrollTo(0, anchor: .top)
                }
            }
            .onChange(of: model.passageVersion) {
                proxy.scrollTo(0, anchor: .top)
            }
        }
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

    private func handleKey(_ press: KeyPress, _ passage: Passage) -> KeyPress.Result {
        if press.key == .space || press.key == .return {
            if !allRevealed(passage) {
                revealAll(passage)
            } else if passage.choices.count == 1, let only = passage.choices.first, only.enabled {
                model.choose(only)
            }
            return .handled
        }
        if let n = Int(press.characters), n >= 1, n <= passage.choices.count {
            guard allRevealed(passage) else {
                revealAll(passage)
                return .handled
            }
            let choice = passage.choices[n - 1]
            if choice.enabled { model.choose(choice) }
            return .handled
        }
        return .ignored
    }
}

// MARK: - 顶栏

struct GameTopBar: View {
    let passage: Passage
    @Binding var showSidebar: Bool
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(passage.chapter)
                    .font(Fonts.bodyBold(14))
                    .foregroundStyle(p.inkDim)
                    .lineLimit(1)
                Text([passage.date, passage.place].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(Fonts.doc(13))
                    .foregroundStyle(p.inkFaint)
                    .lineLimit(1)
            }
            Spacer()
            if model.isHardcore {
                Text("铁人").font(Fonts.ui(10, .semibold)).foregroundStyle(p.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.accent, lineWidth: 1))
            }
            BarButton(icon: "arrow.uturn.backward", tip: "回溯到上一个抉择（⌘Z）", enabled: model.canRewind) { model.rewind() }
            BarButton(icon: "text.book.closed", tip: "战斗日志（⌘L）") { model.sheet = .log }
            BarButton(icon: "archivebox", tip: "档案馆（⌘D）", badge: model.unseenCount > 0) { model.openArchive() }
            BarButton(icon: "square.and.arrow.down", tip: "存档（⌘S）", enabled: !model.isHardcore) { model.sheet = .save }
            BarButton(icon: "folder", tip: "读档（⌘O）") { model.sheet = .load }
            BarButton(icon: "sidebar.right", tip: "军人证") { withAnimation(.easeInOut(duration: 0.3)) { showSidebar.toggle() } }
            BarButton(icon: "house", tip: "返回标题") { model.backToTitle() }
        }
        .padding(.leading, 86)
        .padding(.trailing, 20)
        .frame(height: 58)
        .background(
            LinearGradient(colors: [p.bg.opacity(0.92), p.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
        )
    }
}

struct BarButton: View {
    let icon: String
    let tip: String
    var enabled = true
    var badge = false
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(enabled ? (hover ? p.ink : p.inkDim) : p.inkFaint.opacity(0.5))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover && enabled ? p.panelHi : .clear))
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(p.accent).frame(width: 6, height: 6).offset(x: -4, y: 4) }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(tip)
        .onHover { hover = $0 }
    }
}

// MARK: - 正文

struct ParaView: View {
    let para: ShownPara
    let limit: Int?
    let fontSize: Double
    @Environment(\.palette) private var p

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
                .padding(.horizontal, 20)
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
                .textSelection(.enabled)
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
                ChoiceButton(choice: choice, number: i + 1, fontSize: fontSize) { pick(choice) }
            }
            if broken {
                Text("（这里的剧本还没写完——你可以回溯，或回到标题。）")
                    .font(Fonts.body(fontSize - 2))
                    .foregroundStyle(p.inkFaint)
                Button("回到标题") { model.backToTitle() }
            }
        }
    }
}

struct ChoiceButton: View {
    let choice: ShownChoice
    let number: Int
    let fontSize: Double
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(number)")
                    .font(Fonts.mono(13).weight(.bold))
                    .foregroundStyle(hover && choice.enabled ? p.accent : p.inkFaint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 7) {
                    if !choice.tags.isEmpty {
                        HStack(spacing: 6) {
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
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hover && choice.enabled ? p.panelHi.opacity(0.95) : p.panel.opacity(0.72))
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(choice.isArchive ? p.stamp : p.accent)
                    .frame(width: 3)
                    .opacity((hover && choice.enabled) || choice.isArchive ? 1 : 0)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(choice.isArchive ? p.stamp.opacity(0.55) : p.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!choice.enabled)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
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
