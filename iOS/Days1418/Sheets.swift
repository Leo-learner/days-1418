import SwiftUI

// MARK: - 新游戏

struct NewGameSheet: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var hardcore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "新的卷宗") {
                    TextAction(title: "取消") { dismiss() }
                }
                Text("一千四百一十八天，从 1941 年 6 月 21 日的傍晚开始。")
                    .font(Fonts.body(15)).foregroundStyle(p.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                let layout = sizeClass == .regular ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 12))
                layout {
                    modeCard(title: "标准", lines: ["随时存档、读档", "可以回溯到上一个抉择", "适合第一次复原"], on: !hardcore) { hardcore = false }
                    modeCard(title: "铁人", lines: ["只有自动存档", "不能回溯，一局一命", "和他们当年一样"], on: hardcore) { hardcore = true }
                }
                Text("随机数跟着存档走：同样的选择永远得到同样的结果，读档刷不出运气。")
                    .font(Fonts.ui(12)).foregroundStyle(p.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if model.autosave != nil {
                    Text("开始新的卷宗会覆盖当前的自动存档（手动存档不受影响）。")
                        .font(Fonts.ui(12)).foregroundStyle(p.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    dismiss()
                    model.newGame(hardcore: hardcore)
                } label: {
                    Text("开始")
                        .font(Fonts.bodyBold(17))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 6).fill(p.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func modeCard(title: String, lines: [String], on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(Fonts.bodyBold(18)).foregroundStyle(p.ink)
                    Spacer()
                    Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? p.accent : p.inkFaint)
                }
                ForEach(lines, id: \.self) { Text("· " + $0).font(Fonts.body(14)).foregroundStyle(p.inkDim) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? p.panelHi : p.panel))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? p.accent : p.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - 存档 / 读档

struct SlotSheet: View {
    let saving: Bool
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [Int: RunState] = [:]
    @State private var confirmSlot: Int?
    @State private var deleteSlot: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: saving ? "存档" : "读档", subtitle: saving ? nil : "长按存档位可以删除") {
                    TextAction(title: "关闭") { dismiss() }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)], spacing: 12) {
                    ForEach(0...Store.slotCount, id: \.self) { slot in
                        slotCard(slot)
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: reload)
        .confirmationDialog("覆盖这个存档位？", isPresented: Binding(get: { confirmSlot != nil }, set: { if !$0 { confirmSlot = nil } }), titleVisibility: .visible) {
            Button("覆盖", role: .destructive) {
                if let s = confirmSlot { model.save(slot: s); reload() }
                confirmSlot = nil
            }
        }
        .confirmationDialog("删除这个存档？", isPresented: Binding(get: { deleteSlot != nil }, set: { if !$0 { deleteSlot = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let s = deleteSlot { Store.delete(slot: s); reload() }
                deleteSlot = nil
            }
        }
    }

    private func reload() {
        var map: [Int: RunState] = [:]
        for s in 0...Store.slotCount { if let st = Store.load(slot: s) { map[s] = st } }
        slots = map
    }

    private func slotCard(_ slot: Int) -> some View {
        let state = slots[slot]
        let usable = saving ? slot != 0 : state != nil
        return Button {
            if saving {
                guard slot != 0 else { return }
                if state != nil { confirmSlot = slot } else { model.save(slot: slot); reload() }
            } else if state != nil {
                model.load(slot: slot)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(slot == 0 ? "自动存档" : "存档位 \(slot)").font(Fonts.ui(11, .semibold)).foregroundStyle(p.inkFaint)
                    Spacer()
                    if state?.hardcore == true { Text("铁人").font(Fonts.ui(10, .semibold)).foregroundStyle(p.accent) }
                }
                if let state {
                    Text(state.chapter.isEmpty ? "序章" : state.chapter)
                        .font(Fonts.bodyBold(14.5)).foregroundStyle(p.ink).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state.date).font(Fonts.doc(12.5)).foregroundStyle(p.inkDim).lineLimit(1)
                    Spacer(minLength: 0)
                    HStack {
                        Text(state.savedAt.formatted(date: .numeric, time: .shortened))
                        Spacer(minLength: 4)
                        Text(Self.duration(state.playSeconds))
                    }
                    .font(Fonts.ui(10.5)).foregroundStyle(p.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    Spacer(minLength: 0)
                    Text(saving && slot != 0 ? "空位 · 点一下存档" : "空").font(Fonts.body(13.5)).foregroundStyle(p.inkFaint)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 4).fill(p.panel))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.line, lineWidth: 1))
            .opacity(usable ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!usable)
        .contextMenu {
            // 自动存档不给删：它是"继续"的来源，由游戏自己管
            if slot != 0 && state != nil {
                Button("删除这个存档", systemImage: "trash", role: .destructive) { deleteSlot = slot }
            }
        }
    }

    static func duration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        return m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟"
    }
}

// MARK: - 战斗日志

struct LogSheet: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "战斗日志", subtitle: "本局 \(model.engine.state.log.count) 段 · \(SlotSheet.duration(model.engine.state.playSeconds))") {
                TextAction(title: "关闭") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            Rectangle().fill(p.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(model.engine.state.log) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                if let choice = entry.choice {
                                    Text("▸ " + choice).font(Fonts.body(14.5)).foregroundStyle(p.accent)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if !entry.header.isEmpty {
                                    Text(entry.header).font(Fonts.doc(12.5)).foregroundStyle(p.inkFaint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(entry.text.replacingOccurrences(of: "*", with: ""))
                                    .font(Fonts.body(15.5))
                                    .foregroundStyle(p.ink.opacity(0.9))
                                    .lineSpacing(7)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let last = model.engine.state.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

// MARK: - 设置

struct SettingsSheet: View {
    @EnvironmentObject private var model: GameModel
    @EnvironmentObject private var fonts: FontLoader
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.textMode) private var textMode = 0
    @AppStorage(Prefs.fontSize) private var fontSize = 17.0
    @AppStorage(Prefs.theme) private var theme = 0
    @AppStorage(Prefs.motion) private var motion = true
    @AppStorage(Prefs.hints) private var hints = true
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "设置") {
                TextAction(title: "完成", strong: true) { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)

            Form {
                Section {
                    Picker("文字出现方式", selection: $textMode) {
                        Text("逐段浮现").tag(0)
                        Text("打字机").tag(1)
                        Text("立即显示").tag(2)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("正文字号")
                            Spacer()
                            Text("\(Int(fontSize))").monospacedDigit().foregroundStyle(p.inkDim)
                        }
                        Slider(value: $fontSize, in: 15...24, step: 1)
                    }
                    Picker("配色", selection: $theme) {
                        Text("夜").tag(0)
                        Text("纸").tag(1)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("阅读")
                } footer: {
                    // 用当前这一局的真实兵力做示例，没开局就是开场的 38 人
                    Text(model.engine.interpolate("炮声停了。你数了数，还剩 {men} 个人。"))
                        .font(Fonts.body(fontSize))
                        .foregroundStyle(p.ink)
                        .lineSpacing(fontSize * 0.5)
                        .padding(.top, 10)
                }
                .listRowBackground(p.panel)

                Section("画面") {
                    Toggle("雪、灰烬、雨等动态效果", isOn: $motion)
                    Toggle("结局图鉴里显示未解锁结局的提示", isOn: $hints)
                    HStack {
                        Text("字体")
                        Spacer()
                        Text(fonts.statusText)
                            .font(.footnote)
                            .foregroundStyle(fonts.phase == .ready || fonts.isBusy ? p.inkDim : p.accent)
                            .multilineTextAlignment(.trailing)
                    }
                    if fonts.phase != .ready && !fonts.isBusy {
                        Button("重新下载字体") { fonts.start(force: true) }
                    }
                }
                .listRowBackground(p.panel)

                Section {
                    LabeledContent("结局", value: "\(model.endingCount) / \(model.story.endings.count)")
                    LabeledContent("档案", value: "\(model.docCount) / \(model.story.docs.count)")
                    // nodes 里还混着 32 个结局、41 份档案的登记节点，不算"节"
                    LabeledContent("剧本", value: "\(model.story.nodes.values.filter { !$0.isRegistry }.count) 节 · 约 \(model.story.characterCount / 1000) 千字")
                    Button("重置全部进度…", role: .destructive) { confirmReset = true }
                } header: {
                    Text("进度")
                } footer: {
                    Text("存档只在这台设备上；和 Mac 版的进度互不相通。")
                }
                .listRowBackground(p.panel)
            }
            .scrollContentBackground(.hidden)
        }
        .confirmationDialog("清空所有存档、结局和档案？此操作无法撤销。", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("全部清空", role: .destructive) {
                model.resetEverything()
                dismiss()
            }
        }
    }
}
