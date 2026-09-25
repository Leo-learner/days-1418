import CoreText
import Network
import os
import SwiftUI

/// 正文的宋体（Songti SC）和公文的仿宋（STFangsong）在 iOS 上不是内置字体，是系统的"按需下载"字体：
/// 第一次要联网从 Apple 下载（宋体包约 44 MB、仿宋约 11 MB），之后每次启动还得再"激活"一次，
/// 否则本进程看不见它们——激活不走网络，一秒之内完成。
/// 字体没到位之前，Fonts.body/doc 退回苹方（见 Fonts.serifReady），游戏照样能玩。
///
/// 真机实测（2026-09-25，iPhone Air，5G）：蜂窝网络下请求一直卡住不动，所以额外盯着网络：
/// 卡在蜂窝网络时明说"要等 Wi-Fi"，Wi-Fi 一连上就作废旧请求、重新发一次。
@MainActor
final class FontLoader: ObservableObject {
    enum Phase: Equatable {
        case activating          // 启动时正在激活，或刚开始向系统查询
        case downloading(Int)    // 下载中，百分比
        case waitingForWiFi      // 卡住了，而且眼下走的是蜂窝网络：连上 Wi-Fi 自动重试
        case offline             // 没有网络：联网后自动重试
        case ready
        case failed              // 系统回了失败：回到前台或网络变化时重试
    }

    @Published private(set) var phase: Phase = .activating
    /// 字体可用之后加一；RootView 拿它做 .id()，让所有已经排好版的文字重新排一遍
    @Published private(set) var generation = 0

    /// 用 PostScript 名请求；Theme.swift 里按族名 "Songti SC" 取字，粗体、特粗由 .weight() 挑
    static let postScriptNames = ["STSongti-SC-Regular", "STSongti-SC-Bold", "STSongti-SC-Black", "STFangsong"]

    private var attempt = 0
    private var stalls = 0
    /// 最新一次请求的编号。CoreText 的回调在后台线程上，要靠它判断"我是不是已经被新请求取代了"，所以单独上锁
    private let latestAttempt = OSAllocatedUnfairLock(initialState: 0)
    private var running = false
    private var path: NWPath?
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(path) }
        }
        monitor.start(queue: DispatchQueue(label: "local.leo.days1418.fonts.network"))
    }

    var statusText: String {
        switch phase {
        case .activating: return "正在准备宋体与仿宋…"
        case .downloading(let percent): return "首次启动，正在下载宋体与仿宋 \(percent)%"
        case .waitingForWiFi: return "宋体与仿宋在蜂窝网络下下载不动，连上 Wi-Fi 会自动继续；现在先用苹方"
        case .offline: return "没有网络，暂用苹方；联网后会自动下载宋体与仿宋"
        case .ready: return "宋体 · 仿宋 已就绪"
        case .failed: return "字体没能下载，暂用苹方（换个网络或回到游戏时会自动重试）"
        }
    }

    /// 游戏里"更多"菜单用的短句
    var menuStatus: String {
        switch phase {
        case .activating: return "宋体准备中…"
        case .downloading(let percent): return "宋体下载中 \(percent)%"
        case .waitingForWiFi: return "宋体要等连上 Wi-Fi"
        case .offline: return "宋体要等联网"
        case .ready: return "宋体已就绪"
        case .failed: return "宋体下载失败 · 点此重试"
        }
    }

    var isBusy: Bool {
        switch phase {
        case .activating, .downloading: return true
        default: return false
        }
    }

    /// 发起（或重新发起）请求。force 为 true 时不管上一次还在不在等，直接作废它另起一次
    func start(force: Bool = false) {
        guard phase != .ready, force || !running else { return }
        if Self.allAvailable() {
            finish()
            return
        }
        attempt += 1
        stalls = 0
        let current = attempt
        latestAttempt.withLock { $0 = current }
        running = true
        if !isBusy { setPhase(.activating) }
        trace("第 \(current) 次请求（网络：\(pathDescription)）")

        let latest = latestAttempt
        let descriptors = Self.postScriptNames.map {
            CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary)
        } as CFArray
        // 回调在后台队列上：先把要用的值取出来，再切回主线程碰 @Published
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors, nil) { [weak self] state, info in
            let dict = info as NSDictionary
            let percent = (dict[kCTFontDescriptorMatchingPercentage] as? NSNumber)?.intValue
            let error = (dict[kCTFontDescriptorMatchingError] as? NSError).map { "\($0.domain) \($0.code) \($0.localizedDescription)" }
            Task { @MainActor in self?.handle(state, percent: percent, error: error, attempt: current) }
            // 返回 false 就是让 CoreText 取消这次请求：已经被新请求取代的旧请求没必要再挂着
            return latest.withLock { $0 == current }
        }
    }

    /// 回到前台时调用：之前失败了、或者请求已经不在了，就再试一次
    func retryIfNeeded() {
        guard phase != .ready else { return }
        if phase == .failed || !running { start(force: true) }
    }

    private func handle(_ state: CTFontDescriptorMatchingState, percent: Int?, error: String?, attempt: Int) {
        guard attempt == self.attempt else { return }
        switch state {
        case .willBeginDownloading:
            trace("开始下载")
        case .downloading:
            stalls = 0
            setPhase(.downloading(max(0, min(100, percent ?? 0))))
        case .didFinishDownloading:
            trace("一个字体包下载完成")
        case .stalled:
            // 网络正常时也会偶尔冒一下 stalled（模拟器上见过），只有眼下不在 Wi-Fi 上才当真。
            // 卡在蜂窝网络时它每秒来两次：日志只记第一次和之后每一分钟
            stalls += 1
            if stalls == 1 || stalls % 120 == 0 { trace("卡住 ×\(stalls)（网络：\(pathDescription)）") }
            if !onWiFi { setPhase(hasNetwork ? .waitingForWiFi : .offline) }
        case .didFailWithError:
            trace("失败：\(error ?? "没有错误信息")")
        case .didFinish:
            trace("请求结束")
            finish()
        default:
            break
        }
    }

    /// @Published 不去重，同一个值反复赋也会让所有观察它的视图重算一遍——卡住时每秒两次，没必要
    private func setPhase(_ new: Phase) {
        if phase != new { phase = new }
    }

    private func finish() {
        running = false
        if Self.allAvailable() {
            // 先把 Fonts 切到宋体/仿宋，再让 RootView 重建：重建时每段文字要的就是新的字体描述
            Fonts.serifReady = true
            phase = .ready
            generation += 1
            trace("宋体与仿宋就绪")
        } else {
            setPhase(!hasNetwork ? .offline : (onWiFi ? .failed : .waitingForWiFi))
            trace("请求结束但字体仍不可用（网络：\(pathDescription)）")
        }
    }

    private func networkChanged(_ newPath: NWPath) {
        let hadWiFi = onWiFi
        let hadNetwork = hasNetwork
        path = newPath
        trace("网络：\(pathDescription)")
        guard phase != .ready else { return }
        // 卡在蜂窝网络的请求，换到 Wi-Fi 后未必会自己动起来；没网时发的请求也一样。直接重发
        let gotWiFi = onWiFi && !hadWiFi && (phase == .waitingForWiFi || phase == .failed)
        let gotNetwork = hasNetwork && !hadNetwork && phase == .offline
        if gotWiFi || gotNetwork { start(force: true) }
    }

    private var hasNetwork: Bool { path?.status == .satisfied }
    /// 系统字体包只在 Wi-Fi（或有线）上下，蜂窝网络上一律卡住。按网卡类型判断，不能只看 isExpensive：
    /// 5G 开了"允许更多数据"时系统把 5G 标成不计费（真机上就是这样），但字体照样不下。连别人的手机热点也不算
    private var onWiFi: Bool {
        guard let path, path.status == .satisfied else { return false }
        let wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        return wifi && !path.usesInterfaceType(.cellular) && !path.isExpensive
    }

    private var pathDescription: String {
        guard let path else { return "未知" }
        guard path.status == .satisfied else { return "无网络" }
        var parts: [String] = []
        if path.usesInterfaceType(.wifi) { parts.append("Wi-Fi") }
        if path.usesInterfaceType(.cellular) { parts.append("蜂窝") }
        if path.usesInterfaceType(.wiredEthernet) { parts.append("有线") }
        if path.isExpensive { parts.append("计费") }
        if path.isConstrained { parts.append("低数据模式") }
        return parts.isEmpty ? "其他" : parts.joined(separator: "·")
    }

    private static func allAvailable() -> Bool {
        postScriptNames.allSatisfy { name in
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            return CTFontCopyPostScriptName(font) as String == name
        }
    }

    // MARK: 诊断

    private static let log = Logger(subsystem: "local.leo.days1418", category: "fonts")
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    /// 下载过程同时记进系统日志和 Caches/fonts.log（最多留 32 KB）。真机上拷回来看：
    /// xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer
    ///   --domain-identifier local.leo.days1418 --source Library/Caches/fonts.log --destination fonts.log
    private func trace(_ message: String) {
        Self.log.info("\(message, privacy: .public)")
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("fonts.log") else { return }
        let line = Self.clock.string(from: Date()) + " " + message + "\n"
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 32_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
