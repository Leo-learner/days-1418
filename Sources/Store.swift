import Foundation

/// 存档、跨周目进度都放在 ~/Library/Application Support/Days1418/
/// 自检和测试时用 -datadir 指到别处，免得弄脏玩家的真存档。
enum Store {
    static let directory: URL = {
        let custom = UserDefaults.standard.string(forKey: "datadir")
        let url = custom.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Days1418", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let slotCount = 8   // 手动存档位 1...8；0 号是自动存档

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func loadMeta() -> Meta {
        guard let data = try? Data(contentsOf: url("meta.json")),
              let meta = try? decoder.decode(Meta.self, from: data) else { return Meta() }
        return meta
    }

    static func saveMeta(_ meta: Meta) {
        guard let data = try? encoder.encode(meta) else { return }
        try? data.write(to: url("meta.json"), options: .atomic)
    }

    static func save(_ state: RunState, slot: Int) {
        var copy = state
        copy.savedAt = Date()
        guard let data = try? encoder.encode(copy) else { return }
        try? data.write(to: url("slot\(slot).json"), options: .atomic)
    }

    static func load(slot: Int) -> RunState? {
        guard let data = try? Data(contentsOf: url("slot\(slot).json")) else { return nil }
        return try? decoder.decode(RunState.self, from: data)
    }

    static func delete(slot: Int) {
        try? FileManager.default.removeItem(at: url("slot\(slot).json"))
    }

    /// 清空所有进度（设置里"重置"用）
    static func wipe() {
        for slot in 0...slotCount { delete(slot: slot) }
        try? FileManager.default.removeItem(at: url("meta.json"))
    }
}
