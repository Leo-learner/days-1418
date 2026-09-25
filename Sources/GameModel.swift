import SwiftUI

/// 界面和引擎之间的桥：所有按钮都调这里，这里负责自动存档、跨周目进度落盘、数值变化提示
@MainActor
final class GameModel: ObservableObject {
    enum Screen: Equatable { case title, game, ending, archive }

    enum Sheet: String, Identifiable {
        case newGame, save, load, log, settings
        var id: String { rawValue }
    }

    struct Toast: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    @Published var screen: Screen = .title
    @Published var passage: Passage?
    @Published var sheet: Sheet?
    @Published var toasts: [Toast] = []
    @Published var deltas: [String: Int] = [:]
    @Published var passageVersion = 0
    @Published var archiveTab = 0
    @Published var archiveDoc: String?
    @Published private(set) var autosave: RunState?
    @Published var snapshotMode = false

    let story: Story
    let engine: Engine
    private var archiveBack: Screen = .title
    private var lastTick = Date()
    private var suspendedAt: Date?
    private var deltaTask: Task<Void, Never>?

    init(storyDirectory: URL) {
        story = StoryParser.load(directory: storyDirectory)
        engine = Engine(story: story, meta: Store.loadMeta())
        autosave = Store.load(slot: 0)
        for issue in story.issues.prefix(20) { NSLog("剧本问题：%@", issue) }
    }

    // MARK: 统计

    var endingCount: Int { engine.meta.endings.count }
    var docCount: Int { engine.meta.docs.count }
    var unseenCount: Int { engine.meta.unseenDocs.count + engine.meta.unseenEndings.count }
    var canRewind: Bool { engine.canRewind && (screen == .game || screen == .ending) }
    var isHardcore: Bool { engine.state.hardcore }

    // MARK: 流程

    func newGame(hardcore: Bool, seed: UInt64? = nil) {
        engine.newRun(hardcore: hardcore, seed: seed)
        lastTick = Date()
        refresh()
        screen = engine.state.ending == nil ? .game : .ending
        writeAutosave()
    }

    func continueGame() {
        guard let saved = Store.load(slot: 0) else { return }
        engine.restore(saved)
        lastTick = Date()
        refresh()
        screen = saved.ending == nil ? .game : .ending
    }

    func choose(_ choice: ShownChoice) {
        guard choice.enabled else { return }
        let before = engine.state.vars
        tick()
        engine.choose(choice)
        showDeltas(from: before)
        refresh()
        if engine.state.ending != nil {
            reachedEnding()
        } else {
            writeAutosave()
        }
    }

    func rewind() {
        guard engine.canRewind else { return }
        engine.rewind()
        refresh()
        screen = .game
        writeAutosave()
    }

    func save(slot: Int) {
        guard !engine.state.hardcore else { return }
        tick()
        Store.save(engine.state, slot: slot)
        toast("已存档", "存档位 \(slot) · \(engine.state.date)")
    }

    func load(slot: Int) {
        guard let saved = Store.load(slot: slot) else { return }
        engine.restore(saved)
        lastTick = Date()
        refresh()
        screen = saved.ending == nil ? .game : .ending
        sheet = nil
    }

    func backToTitle() {
        if screen == .game {
            tick()
            writeAutosave()
        }
        screen = .title
    }

    func openArchive(tab: Int = 0, doc: String? = nil) {
        if screen != .archive { archiveBack = screen }
        archiveTab = tab
        archiveDoc = doc
        screen = .archive
    }

    func closeArchive() {
        screen = archiveBack == .archive ? .title : archiveBack
    }

    func markSeen(ending id: String) {
        guard engine.meta.unseenEndings.remove(id) != nil else { return }
        Store.saveMeta(engine.meta)
        objectWillChange.send()
    }

    func markSeen(doc id: String) {
        guard engine.meta.unseenDocs.remove(id) != nil else { return }
        Store.saveMeta(engine.meta)
        objectWillChange.send()
    }

    func resetEverything() {
        Store.wipe()
        engine.meta = Meta()
        autosave = nil
        passage = nil
        screen = .title
    }

    // MARK: 前后台（iOS 用；Mac 版窗口不会被挂起，不调用）

    /// 切到后台：把这段游戏时长记上，再写一次自动存档——之后被系统杀掉也不丢
    func suspend() {
        guard suspendedAt == nil else { return }
        if screen == .game {
            tick()
            writeAutosave()
        }
        suspendedAt = Date()
    }

    /// 回到前台：后台那段时间不算游戏时长。只认 suspend() 之后的那一次，
    /// 拉一下控制中心这种"没进后台"的打断不会把之前没记账的时间清掉
    func resume() {
        guard suspendedAt != nil else { return }
        suspendedAt = nil
        lastTick = Date()
    }

    // MARK: 内部

    private func reachedEnding() {
        // 铁人模式一局一命：结局后删掉自动存档。标准模式把自动存档留在最后一个抉择之前。
        if engine.state.hardcore {
            Store.delete(slot: 0)
            autosave = nil
        } else {
            let ended = engine.state
            engine.rewind()
            Store.save(engine.state, slot: 0)
            autosave = engine.state
            engine.restore(ended)
        }
        Store.saveMeta(engine.meta)
        screen = .ending
    }

    private func writeAutosave() {
        Store.save(engine.state, slot: 0)
        Store.saveMeta(engine.meta)
        autosave = engine.state
    }

    private func refresh() {
        let fresh = engine.freshDocs
        let endingDoc = engine.state.ending.flatMap { story.ending($0)?.doc }
        passage = engine.passage()
        passageVersion += 1
        for id in fresh where id != endingDoc {
            if let doc = story.doc(id) { toast("档案已解密", "《\(doc.title)》") }
        }
    }

    private func tick() {
        let now = Date()
        engine.state.playSeconds += min(600, now.timeIntervalSince(lastTick))
        lastTick = now
    }

    func toast(_ title: String, _ detail: String) {
        let t = Toast(title: title, detail: detail)
        withAnimation(.spring(duration: 0.4)) { toasts.append(t) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            withAnimation(.easeOut(duration: 0.4)) { toasts.removeAll { $0.id == t.id } }
        }
    }

    private func showDeltas(from before: [String: Int]) {
        var keys = story.stats.map(\.key) + story.units.map(\.key) + story.persons.map(\.key) + story.items.map(\.key)
        keys += ["rank", "post"]
        var changed: [String: Int] = [:]
        for k in keys {
            let old = before[k] ?? story.initial[k] ?? 0
            let new = engine.lookup(k)
            if old != new { changed[k] = new - old }
        }
        deltas = changed
        deltaTask?.cancel()
        deltaTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { withAnimation { deltas = [:] } }
        }
    }

    // MARK: 自检用

    func debugUnlockAll() {
        for e in story.endings { engine.meta.endings[e.id] = Date() }
        for d in story.docs { engine.meta.docs[d.id] = Date() }
    }

    func debugJump(_ node: String, vars: String?) {
        for pair in (vars ?? "").split(separator: ",") {
            let kv = pair.split(separator: "=")
            if kv.count == 2, let v = Int(kv[1]) { engine.set(String(kv[0]), v) }
        }
        engine.enter(node)
        refresh()
        screen = engine.state.ending == nil ? .game : .ending
    }
}
