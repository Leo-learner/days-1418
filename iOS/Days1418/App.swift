import SwiftUI
import UIKit

@main
struct Days1418App: App {
    @StateObject private var model: GameModel
    @StateObject private var fonts = FontLoader()
    @AppStorage(Prefs.theme) private var theme = 0

    init() {
        // 宋体、仿宋激活之前一律用苹方（见 Fonts.serifReady 的说明），FontLoader 就绪后再切回来
        Fonts.serifReady = false
        Self.registerDefaults()
        let story = Bundle.main.url(forResource: "story", withExtension: nil)
            ?? Bundle.main.bundleURL.appendingPathComponent("story", isDirectory: true)
        _model = StateObject(wrappedValue: GameModel(storyDirectory: story))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(fonts)
                .environment(\.palette, theme == 1 ? .parchment : .night)
        }
    }

    /// 手机屏幕窄，正文默认比 Mac 版（18）小一号；系统开了"减弱动态效果"就默认关掉粒子。
    /// 用注册默认值而不是改各处 @AppStorage 的初值：玩家在设置里改过的值永远优先。
    private static func registerDefaults() {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        UserDefaults.standard.register(defaults: [
            Prefs.fontSize: pad ? 19.0 : 17.0,
            Prefs.motion: !UIAccessibility.isReduceMotionEnabled,
        ])
    }
}

struct RootView: View {
    @EnvironmentObject private var model: GameModel
    @EnvironmentObject private var fonts: FontLoader
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var scenePhase
    @State private var launched = false

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            if launched {
                screens
                    // 宋体/仿宋激活或下载完成时整棵树重建一次：已经排好版的 Text 不会自己换字体
                    .id(fonts.generation)
                    .transition(.opacity)
            } else {
                // 启动的头一秒：和标题页同样的雪夜底子，等字体激活，免得先闪一下苹方再换成宋体
                AtmosphereView(mood: "snow")
            }
            ToastStack()
        }
        .animation(.easeInOut(duration: 0.7), value: launched)
        .animation(.easeInOut(duration: 0.6), value: fonts.generation)
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
            // 弹出面板不在上面那棵 .id() 树里：字体到位时它若正开着，也得跟着重建一次
            .id(fonts.generation)
            .environmentObject(model)
            .environmentObject(fonts)
            .environment(\.palette, p)
            .presentationBackground(p.bg)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(p.isDark ? .dark : .light)
        }
        .preferredColorScheme(p.isDark ? .dark : .light)
        .tint(p.accent)
        .task { await launch() }
        .onChange(of: fonts.phase) {
            if fonts.phase == .ready { launched = true }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.suspend()
            case .active:
                model.resume()
                fonts.retryIfNeeded()
            default:
                break
            }
        }
    }

    private var screens: some View {
        ZStack {
            switch model.screen {
            case .title: TitleView().transition(.opacity)
            case .game: GameView().transition(.opacity)
            case .ending: EndingView().transition(.opacity)
            case .archive: ArchiveView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: model.screen)
    }

    private func launch() async {
        fonts.start()
        #if DEBUG
        DebugLaunch.apply(model)
        #endif
        // 已经下载过的字体一般几百毫秒就激活好了（onChange 会提前放行）；
        // 第一次启动要下载，就不干等，先用苹方进标题页，下完再换
        try? await Task.sleep(for: .seconds(1.2))
        launched = true
    }
}

// MARK: - 提示条

struct ToastStack: View {
    @EnvironmentObject private var model: GameModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.toasts) { t in
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(p.stamp)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(Fonts.ui(11, .semibold)).foregroundStyle(p.stamp)
                        Text(t.detail).font(Fonts.doc(15)).foregroundStyle(p.paperInk).lineLimit(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PaperBackground())
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 6)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .onChange(of: model.toasts.count) { old, new in
            if new > old { Haptics.success() }
        }
    }
}

// MARK: - 模拟器自检

#if DEBUG
/// 用启动参数直接跳到某个界面，配合 `xcrun simctl io booted screenshot` 截图检查排版：
/// xcrun simctl launch booted local.leo.days1418 -screen game -node a1_start -textMode 2
/// 参数和 Mac 版的 -snapshot 自检一样：-screen title/game/archive/log/settings/load/save/newgame、
/// -node 节点、-vars "men=12,misha=80"、-unlockAll YES、-tab 1、-doc d06、-theme 1
@MainActor
enum DebugLaunch {
    static func apply(_ model: GameModel) {
        let d = UserDefaults.standard
        guard let screen = d.string(forKey: "screen") else { return }
        model.snapshotMode = true
        if d.bool(forKey: "unlockAll") { model.debugUnlockAll() }
        if screen != "title" && screen != "archive" { model.newGame(hardcore: d.bool(forKey: "hardcore"), seed: 7) }
        if let node = d.string(forKey: "node") { model.debugJump(node, vars: d.string(forKey: "vars")) }
        switch screen {
        case "archive": model.openArchive(tab: d.integer(forKey: "tab"), doc: d.string(forKey: "doc"))
        case "log": model.sheet = .log
        case "settings": model.sheet = .settings
        case "load": model.sheet = .load
        case "save": model.sheet = .save
        case "newgame": model.sheet = .newGame
        default: break
        }
    }
}
#endif
