import SwiftUI

/// 档案馆：结局图鉴 + 解密档案
struct ArchiveView: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            AtmosphereView(mood: "archive")
            VStack(spacing: 0) {
                header
                Group {
                    if model.archiveTab == 0 { EndingGallery() } else { DocBrowser() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        let keyDocs = model.story.docs.filter(\.isKey)
        let keyFound = keyDocs.filter { model.engine.meta.docs[$0.id] != nil }.count
        let percent = model.story.docs.isEmpty ? 0 : model.docCount * 100 / model.story.docs.count
        return HStack(alignment: .center, spacing: 22) {
            Button { model.closeArchive() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .font(Fonts.body(14))
                .foregroundStyle(p.inkDim)
            }
            .buttonStyle(.plain)
            Text("档案馆").font(Fonts.bodyBold(22)).foregroundStyle(p.ink)
            Picker("", selection: $model.archiveTab) {
                Text("结局图鉴 \(model.endingCount)/\(model.story.endings.count)").tag(0)
                Text("解密档案 \(model.docCount)/\(model.story.docs.count)").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 330)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("真相复原 \(percent)%").font(Fonts.bodyBold(14)).foregroundStyle(p.ink)
                Text("关键档案 \(keyFound)/\(keyDocs.count)").font(Fonts.ui(11)).foregroundStyle(keyFound == keyDocs.count ? p.gold : p.inkFaint)
            }
        }
        .padding(.leading, 90)
        .padding(.trailing, 28)
        .frame(height: 64)
        .background(p.bg.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
    }
}

struct EndingGallery: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @AppStorage(Prefs.hints) private var hints = true

    private let acts: [(Int, String)] = [
        (1, "第一卷 · 包围圈 · 1941"),
        (2, "第二卷 · 伏尔加 · 1942—1943"),
        (3, "第三卷 · 大河 · 1943—1944"),
        (4, "第四卷 · 柏林 · 1945"),
        (5, "尾声 · 1946 年以后"),
        (0, "卷宗之外"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                ForEach(acts, id: \.0) { act, title in
                    let list = model.story.endings.filter { $0.act == act }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Text(title).font(Fonts.bodyBold(16)).foregroundStyle(p.inkDim)
                                Rectangle().fill(p.line).frame(height: 1)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)], spacing: 14) {
                                ForEach(list) { ending in
                                    EndingCard(ending: ending, showHint: hints || model.engine.meta.runsFinished > 0)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .scrollIndicators(.hidden)
    }
}

struct EndingCard: View {
    let ending: EndingDef
    let showHint: Bool
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        let date = model.engine.meta.endings[ending.id]
        let unlocked = date != nil
        let isNew = model.engine.meta.unseenEndings.contains(ending.id)
        let tint = p.tier(ending.tier)
        Button {
            guard unlocked else { return }
            model.markSeen(ending: ending.id)
            if let doc = ending.doc { model.openArchive(tab: 1, doc: doc) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(ending.tier).font(Fonts.typewriter(12).weight(.bold)).foregroundStyle(unlocked ? tint : p.inkFaint)
                    Text(Palette.tierName(ending.tier)).font(Fonts.ui(10.5)).foregroundStyle(p.inkFaint)
                    Spacer()
                    if isNew { Text("新").font(Fonts.ui(10, .semibold)).foregroundStyle(p.accent) }
                    Text(ending.id.uppercased()).font(Fonts.typewriter(10)).foregroundStyle(p.inkFaint)
                }
                Text(unlocked ? ending.title : "？？？")
                    .font(Fonts.bodyBold(19))
                    .foregroundStyle(unlocked ? p.ink : p.inkFaint)
                if unlocked, let date {
                    Text("首次抵达 " + date.formatted(date: .abbreviated, time: .omitted))
                        .font(Fonts.ui(10.5))
                        .foregroundStyle(p.inkFaint)
                } else if showHint {
                    Text(ending.hint)
                        .font(Fonts.body(12.5))
                        .foregroundStyle(p.inkFaint)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 4).fill(unlocked ? p.panel : p.panel.opacity(0.45)))
            .overlay(alignment: .top) {
                Rectangle().fill(unlocked ? tint : p.line).frame(height: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(hover && unlocked ? tint.opacity(0.6) : p.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct DocBrowser: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.story.docs) { doc in
                        row(doc)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .frame(width: 330)
            .background(p.panel.opacity(0.7))
            .overlay(alignment: .trailing) { Rectangle().fill(p.line).frame(width: 1) }

            ScrollView {
                Group {
                    if let id = model.archiveDoc, let doc = model.story.doc(id) {
                        if model.engine.meta.docs[id] != nil {
                            DocCard(doc: doc)
                                .onAppear { model.markSeen(doc: id) }
                        } else {
                            lockedCard(doc)
                        }
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "archivebox").font(.system(size: 34)).foregroundStyle(p.inkFaint)
                            Text("从左边选一份档案").font(Fonts.body(15)).foregroundStyle(p.inkFaint)
                            Text("每一个结局，都是某个人真实的结局。")
                                .font(Fonts.body(13))
                                .foregroundStyle(p.inkFaint.opacity(0.8))
                        }
                        .padding(.top, 140)
                    }
                }
                .frame(maxWidth: 660)
                .padding(40)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ doc: DocDef) -> some View {
        let unlocked = model.engine.meta.docs[doc.id] != nil
        let selected = model.archiveDoc == doc.id
        let isNew = model.engine.meta.unseenDocs.contains(doc.id)
        return Button {
            model.archiveDoc = doc.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(doc.id.uppercased())
                    .font(Fonts.typewriter(10.5))
                    .foregroundStyle(p.inkFaint)
                    .frame(width: 58, alignment: .leading)
                if unlocked {
                    Text(doc.title)
                        .font(Fonts.body(14))
                        .foregroundStyle(selected ? p.ink : p.inkDim)
                        .lineLimit(1)
                } else {
                    Text(String(repeating: "█", count: max(4, min(12, doc.title.count))))
                        .font(Fonts.body(12))
                        .foregroundStyle(p.line)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if doc.isKey { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(unlocked ? p.gold : p.inkFaint) }
                if isNew { Circle().fill(p.accent).frame(width: 6, height: 6) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(selected ? p.panelHi : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func lockedCard(_ doc: DocDef) -> some View {
        let source = model.story.endings.first { $0.doc == doc.id }
        return VStack(alignment: .leading, spacing: 14) {
            Text("№ \(doc.id.uppercased())").font(Fonts.typewriter(12)).foregroundStyle(p.paperInk.opacity(0.5))
            ForEach(0..<7, id: \.self) { i in
                Rectangle().fill(p.paperInk.opacity(0.82)).frame(width: CGFloat([380, 440, 300, 420, 360, 250, 400][i]), height: 13)
            }
            Text(source.map { "某一次复原走到结局「\(model.engine.meta.endings[$0.id] != nil ? $0.title : "？？？")」时，这份档案会解密。" }
                 ?? "这份档案藏在某一次复原的路上。")
                .font(Fonts.doc(14))
                .foregroundStyle(p.paperInk.opacity(0.65))
                .padding(.top, 10)
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaperBackground())
        .overlay(alignment: .topTrailing) {
            Stamp(text: "СЕКРЕТНО", color: p.stamp, angle: 7, size: 15).padding(26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
