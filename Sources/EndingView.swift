import SwiftUI

struct EndingView: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p
    @AppStorage(Prefs.fontSize) private var fontSize = 18.0
    @State private var showDoc = false
    @State private var appeared = false

    var body: some View {
        if let passage = model.passage, let ending = passage.ending {
            let doc = ending.doc.flatMap { model.story.doc($0) }
            let tint = p.tier(ending.tier)
            ZStack {
                Color.black.opacity(p.isDark ? 1 : 0.0).ignoresSafeArea()
                AtmosphereView(mood: passage.mood).opacity(p.isDark ? 0.55 : 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            header(passage, ending, tint)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 12)

                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(passage.paras) { para in
                                    ParaView(para: para, limit: nil, fontSize: fontSize)
                                }
                            }
                            .frame(maxWidth: 680, alignment: .leading)
                            .padding(.top, 34)
                            .opacity(appeared ? 1 : 0)

                            if let doc {
                                if showDoc {
                                    VStack(spacing: 14) {
                                        Text("这不是一个人的结局。档案里写着它真正属于谁。")
                                            .font(Fonts.body(14))
                                            .foregroundStyle(p.inkDim)
                                        DocCard(doc: doc)
                                            .frame(maxWidth: 640)
                                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                                    }
                                    .padding(.top, 30)
                                    .id("doc")
                                    .onAppear { model.markSeen(doc: doc.id) }
                                } else {
                                    Button {
                                        withAnimation(.spring(duration: 0.7)) { showDoc = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            withAnimation(.easeInOut(duration: 0.8)) { proxy.scrollTo("doc", anchor: .top) }
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "seal")
                                            Text("解密档案 № \(doc.id.uppercased())")
                                        }
                                        .font(Fonts.bodyBold(16))
                                        .foregroundStyle(p.stamp)
                                        .padding(.horizontal, 22)
                                        .padding(.vertical, 11)
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.stamp, lineWidth: 1.5))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 30)
                                }
                            }

                            footer(ending)
                                .padding(.top, 40)
                        }
                        .padding(.horizontal, 60)
                        .padding(.top, 80)
                        .padding(.bottom, 60)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .onAppear {
                model.markSeen(ending: ending.id)
                showDoc = model.snapshotMode
                withAnimation(.easeOut(duration: 1.4)) { appeared = true }
            }
            .onChange(of: model.passageVersion) {
                showDoc = false
            }
        }
    }

    private func header(_ passage: Passage, _ ending: EndingDef, _ tint: Color) -> some View {
        VStack(spacing: 12) {
            Text("\(ending.tier) · \(Palette.tierName(ending.tier))")
                .font(Fonts.typewriter(13).weight(.bold))
                .tracking(4)
                .foregroundStyle(tint)
            Text(ending.title)
                .font(Fonts.display(58))
                .foregroundStyle(p.ink)
            Rectangle().fill(tint).frame(width: 80, height: 2)
            Text([passage.date, passage.place].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                .font(Fonts.doc(14))
                .foregroundStyle(p.inkFaint)
        }
    }

    private func footer(_ ending: EndingDef) -> some View {
        VStack(spacing: 18) {
            Text("结局 \(model.endingCount) / \(model.story.endings.count)  ·  档案 \(model.docCount) / \(model.story.docs.count)")
                .font(Fonts.ui(12))
                .foregroundStyle(p.inkFaint)
            HStack(spacing: 14) {
                if model.canRewind {
                    EndingButton(title: "回到上一个抉择", icon: "arrow.uturn.backward") { model.rewind() }
                }
                EndingButton(title: "档案馆", icon: "archivebox") { model.openArchive() }
                EndingButton(title: "新的卷宗", icon: "doc.badge.plus") { model.sheet = .newGame }
                EndingButton(title: "返回标题", icon: "house") { model.backToTitle() }
            }
        }
    }
}

struct EndingButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(Fonts.body(14.5))
            }
            .foregroundStyle(hover ? p.ink : p.inkDim)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 4).fill(hover ? p.panelHi : p.panel.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 解密档案：一张旧纸，仿宋字，右上角盖"已解密"章
struct DocCard: View {
    let doc: DocDef
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(doc.kind)
                    .font(Fonts.doc(13))
                    .foregroundStyle(p.paperInk.opacity(0.6))
                if doc.isKey {
                    Text("关键档案").font(Fonts.ui(10, .semibold)).foregroundStyle(p.stamp)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(p.stamp, lineWidth: 1))
                }
                Spacer()
                Text("№ \(doc.id.uppercased())")
                    .font(Fonts.typewriter(12))
                    .foregroundStyle(p.paperInk.opacity(0.55))
            }
            Text(doc.title)
                .font(Fonts.bodyBold(21))
                .foregroundStyle(p.paperInk)
                .fixedSize(horizontal: false, vertical: true)
            if let who = doc.who {
                Text(who).font(Fonts.doc(14)).foregroundStyle(p.stamp)
            }
            if !doc.source.isEmpty {
                Text(doc.source)
                    .font(Fonts.doc(12.5))
                    .foregroundStyle(p.paperInk.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(p.paperInk.opacity(0.25)).frame(height: 1).padding(.vertical, 4)
            ForEach(Array(doc.paras.enumerated()), id: \.offset) { _, para in
                if para.style == .rule {
                    Rectangle().fill(p.paperInk.opacity(0.15)).frame(height: 1).padding(.vertical, 6)
                } else {
                    Text(para.text)
                        .font(Fonts.doc(16))
                        .foregroundStyle(p.paperInk)
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, para.style == .quote ? 18 : 0)
                }
            }
            if !doc.date.isEmpty {
                HStack {
                    Spacer()
                    Text(doc.date).font(Fonts.doc(13.5)).foregroundStyle(p.paperInk.opacity(0.7))
                }
                .padding(.top, 6)
            }
        }
        .padding(30)
        .background(PaperBackground())
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(alignment: .topTrailing) {
            Stamp(text: "РАССЕКРЕЧЕНО", color: p.stamp, angle: -9, size: 13)
                .padding(.top, 74)
                .padding(.trailing, 30)
        }
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .textSelection(.enabled)
    }
}
