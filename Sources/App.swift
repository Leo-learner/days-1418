import AppKit
import SwiftUI

@main
enum Entry {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        // 命令行工具用 "-键 值" 形式：-check <剧本目录> [-runs N] [-seed S]、-walk <攻略> [-story 目录]、-render-icon <png>
        if let dir = value(after: "-check", in: args) {
            let runs = value(after: "-runs", in: args).flatMap { Int($0) } ?? 3000
            let seed = value(after: "-seed", in: args).flatMap { UInt64($0) } ?? 42
            exit(Checker.run(directory: dir, runs: runs, seed: seed, force: args.contains("-force")))
        }
        if let script = value(after: "-walk", in: args) {
            exit(Checker.walk(directory: storyDirectory().path, script: script))
        }
        if let path = value(after: "-render-icon", in: args) {
            IconRenderer.render(to: path)
            exit(0)
        }
        Days1418App.main()
    }

    static func storyDirectory() -> URL {
        if let custom = UserDefaults.standard.string(forKey: "story") {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return (Bundle.main.resourceURL ?? URL(fileURLWithPath: "."))
            .appendingPathComponent("story", isDirectory: true)
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}

struct Days1418App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = GameModel(storyDirectory: Entry.storyDirectory())
    @AppStorage(Prefs.theme) private var theme = 0

    var body: some Scene {
        Window("一千四百一十八天", id: "main") {
            RootView()
                .environmentObject(model)
                .environment(\.palette, theme == 1 ? .parchment : .night)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands { GameCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct GameCommands: Commands {
    @ObservedObject var model: GameModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新的卷宗…") { model.sheet = .newGame }
                .keyboardShortcut("n")
            Button("继续上次的进度") { model.continueGame() }
                .disabled(model.autosave == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("存档…") { model.sheet = .save }
                .keyboardShortcut("s")
                .disabled(model.screen != .game || model.isHardcore)
            Button("读档…") { model.sheet = .load }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("回溯到上一个抉择") { model.rewind() }
                .keyboardShortcut("z")
                .disabled(!model.canRewind)
        }
        CommandMenu("战役") {
            Button("战斗日志") { model.sheet = .log }
                .keyboardShortcut("l")
                .disabled(model.passage == nil)
            Button("档案馆") { model.openArchive() }
                .keyboardShortcut("d")
            Divider()
            Button("返回标题") { model.backToTitle() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { model.sheet = .settings }
                .keyboardShortcut(",")
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            switch model.screen {
            case .title: TitleView().transition(.opacity)
            case .game: GameView().transition(.opacity)
            case .ending: EndingView().transition(.opacity)
            case .archive: ArchiveView().transition(.opacity)
            }
            ToastStack()
        }
        .animation(.easeInOut(duration: 0.5), value: model.screen)
        .sheet(item: $model.sheet) { sheet in
            Group {
                switch sheet {
                case .newGame: NewGameSheet()
                case .save: SlotSheet(saving: true)
                case .load: SlotSheet(saving: false)
                case .log: LogSheet()
                case .settings: SettingsSheet()
                }
            }
            .environmentObject(model)
            .environment(\.palette, p)
        }
        .preferredColorScheme(p.isDark ? .dark : .light)
        .onAppear { SelfCheck.runIfRequested(model) }
    }
}

struct ToastStack: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(model.toasts) { t in
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(p.stamp)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(Fonts.ui(11, .semibold)).foregroundStyle(p.stamp)
                        Text(t.detail).font(Fonts.doc(15)).foregroundStyle(p.paperInk)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PaperBackground())
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 64)
        .padding(.trailing, 24)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .allowsHitTesting(false)
    }
}

/// 自检：本机没有屏幕录制权限，就让 App 自己把窗口画成 PNG。
/// 用法：open App --args -snapshot /tmp/a.png -screen game -node a1_start -vars "men=12" -datadir /tmp/d1418 -textMode 2
@MainActor
enum SelfCheck {
    static func runIfRequested(_ model: GameModel) {
        let d = UserDefaults.standard
        guard let path = d.string(forKey: "snapshot") else { return }
        model.snapshotMode = true
        let screen = d.string(forKey: "screen") ?? "title"
        if d.bool(forKey: "unlockAll") { model.debugUnlockAll() }
        if screen != "title" && screen != "archive" { model.newGame(hardcore: false, seed: 7) }
        if let node = d.string(forKey: "node") { model.debugJump(node, vars: d.string(forKey: "vars")) }
        switch screen {
        case "archive": model.openArchive(tab: d.integer(forKey: "tab"), doc: d.string(forKey: "doc"))
        case "log": model.sheet = .log
        case "settings": model.sheet = .settings
        case "load": model.sheet = .load
        case "newgame": model.sheet = .newGame
        default: break
        }
        let wait = d.double(forKey: "wait") > 0 ? d.double(forKey: "wait") : 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { capture(to: path) }
    }

    static func capture(to path: String) {
        defer { NSApp.terminate(nil) }
        let windows = NSApp.windows.filter(\.isVisible)
        guard let window = windows.first(where: { $0.sheetParent != nil }) ?? windows.first,
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
