import SwiftUI

// MARK: - 新游戏

struct NewGameSheet: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var hardcore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("新的卷宗").font(Fonts.bodyBold(24)).foregroundStyle(p.ink)
            Text("一千四百一十八天，从 1941 年 6 月 21 日的傍晚开始。")
                .font(Fonts.body(14)).foregroundStyle(p.inkDim)
            HStack(spacing: 14) {
                modeCard(title: "标准", lines: ["随时存档、读档", "可以回溯到上一个抉择", "适合第一次复原"], on: !hardcore) { hardcore = false }
                modeCard(title: "铁人", lines: ["只有自动存档", "不能回溯，一局一命", "和他们当年一样"], on: hardcore) { hardcore = true }
            }
            Text("随机数跟着存档走：同样的选择永远得到同样的结果，读档刷不出运气。")
                .font(Fonts.ui(11.5)).foregroundStyle(p.inkFaint)
            if model.autosave != nil {
                Text("开始新的卷宗会覆盖当前的自动存档（手动存档不受影响）。")
                    .font(Fonts.ui(11.5)).foregroundStyle(p.accent)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("开始") {
                    dismiss()
                    model.newGame(hardcore: hardcore)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(p.bg)
    }

    private func modeCard(title: String, lines: [String], on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(Fonts.bodyBold(18)).foregroundStyle(p.ink)
                    Spacer()
                    Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? p.accent : p.inkFaint)
                }
                ForEach(lines, id: \.self) { Text("· " + $0).font(Fonts.body(13)).foregroundStyle(p.inkDim) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? p.panelHi : p.panel))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? p.accent : p.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(saving ? "存档" : "读档").font(Fonts.bodyBold(24)).foregroundStyle(p.ink)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(0...Store.slotCount, id: \.self) { slot in
                    slotCard(slot)
                }
            }
        }
        .padding(28)
        .frame(width: 760)
        .background(p.bg)
        .onAppear(perform: reload)
        .confirmationDialog("覆盖这个存档位？", isPresented: Binding(get: { confirmSlot != nil }, set: { if !$0 { confirmSlot = nil } })) {
            Button("覆盖", role: .destructive) {
                if let s = confirmSlot { model.save(slot: s); reload() }
                confirmSlot = nil
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
                    Text(state.date).font(Fonts.doc(12.5)).foregroundStyle(p.inkDim).lineLimit(1)
                    Spacer(minLength: 0)
                    HStack {
                        Text(state.savedAt.formatted(date: .numeric, time: .shortened))
                        Spacer()
                        Text(Self.duration(state.playSeconds))
                    }
                    .font(Fonts.ui(10.5)).foregroundStyle(p.inkFaint)
                } else {
                    Spacer(minLength: 0)
                    Text(saving && slot != 0 ? "空位 · 点击存档" : "空").font(Fonts.body(13)).foregroundStyle(p.inkFaint)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 4).fill(p.panel))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.line, lineWidth: 1))
            .opacity(usable ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!usable)
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
            HStack {
                Text("战斗日志").font(Fonts.bodyBold(22)).foregroundStyle(p.ink)
                Text("本局 \(model.engine.state.log.count) 段 · \(SlotSheet.duration(model.engine.state.playSeconds))")
                    .font(Fonts.ui(11)).foregroundStyle(p.inkFaint)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(24)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(model.engine.state.log) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                if let choice = entry.choice {
                                    Text("▸ " + choice).font(Fonts.body(14)).foregroundStyle(p.accent)
                                }
                                if !entry.header.isEmpty {
                                    Text(entry.header).font(Fonts.doc(12)).foregroundStyle(p.inkFaint)
                                }
                                Text(entry.text.replacingOccurrences(of: "*", with: ""))
                                    .font(Fonts.body(15))
                                    .foregroundStyle(p.ink.opacity(0.9))
                                    .lineSpacing(7)
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(28)
                }
                .onAppear {
                    if let last = model.engine.state.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(width: 720, height: 640)
        .background(p.bg)
    }
}

// MARK: - 设置

struct SettingsSheet: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.textMode) private var textMode = 0
    @AppStorage(Prefs.fontSize) private var fontSize = 18.0
    @AppStorage(Prefs.theme) private var theme = 0
    @AppStorage(Prefs.motion) private var motion = true
    @AppStorage(Prefs.hints) private var hints = true
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置").font(Fonts.bodyBold(24)).foregroundStyle(p.ink)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Form {
                Picker("文字出现方式", selection: $textMode) {
                    Text("逐段浮现").tag(0)
                    Text("打字机").tag(1)
                    Text("立即显示").tag(2)
                }
                HStack {
                    Slider(value: $fontSize, in: 15...24, step: 1) { Text("正文字号") }
                    Text("\(Int(fontSize))").monospacedDigit().frame(width: 28)
                }
                Picker("配色", selection: $theme) {
                    Text("夜").tag(0)
                    Text("纸").tag(1)
                }
                .pickerStyle(.segmented)
                Toggle("雪、灰烬、雨等动态效果", isOn: $motion)
                Toggle("结局图鉴里显示未解锁结局的提示", isOn: $hints)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 270)

            Text("示例：炮声停了。你数了数，还剩 {men} 个人。")
                .font(Fonts.body(fontSize))
                .foregroundStyle(p.ink)
                .padding(.horizontal, 6)

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("进度：结局 \(model.endingCount)/\(model.story.endings.count)，档案 \(model.docCount)/\(model.story.docs.count)")
                        .font(Fonts.ui(12)).foregroundStyle(p.inkDim)
                    Text("剧本 \(model.story.nodes.count) 节 · 约 \(model.story.characterCount / 1000) 千字")
                        .font(Fonts.ui(11)).foregroundStyle(p.inkFaint)
                }
                Spacer()
                Button("重置全部进度…", role: .destructive) { confirmReset = true }
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(p.bg)
        .confirmationDialog("清空所有存档、结局和档案？此操作无法撤销。", isPresented: $confirmReset) {
            Button("全部清空", role: .destructive) {
                model.resetEverything()
                dismiss()
            }
        }
    }
}
