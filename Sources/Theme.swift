import SwiftUI

/// 两套配色：夜（默认）和纸。所有视图都从环境里取 palette，不写死颜色。
struct Palette {
    var bg: Color
    var panel: Color
    var panelHi: Color
    var ink: Color
    var inkDim: Color
    var inkFaint: Color
    var line: Color
    var accent: Color
    var khaki: Color
    var gold: Color
    var paper: Color
    var paperInk: Color
    var stamp: Color
    var isDark: Bool

    static let night = Palette(
        bg: Color(hex: 0x121110), panel: Color(hex: 0x1A1916), panelHi: Color(hex: 0x26241F),
        ink: Color(hex: 0xE6DFCF), inkDim: Color(hex: 0xA69E8C), inkFaint: Color(hex: 0x6F695C),
        line: Color(hex: 0x353129), accent: Color(hex: 0xB8322A), khaki: Color(hex: 0x9A8E64),
        gold: Color(hex: 0xC9A55A), paper: Color(hex: 0xE9DFC6), paperInk: Color(hex: 0x2A241C),
        stamp: Color(hex: 0xA3241B), isDark: true
    )

    static let parchment = Palette(
        bg: Color(hex: 0xE8DFCA), panel: Color(hex: 0xDED3BA), panelHi: Color(hex: 0xD2C6AA),
        ink: Color(hex: 0x241F18), inkDim: Color(hex: 0x5E5546), inkFaint: Color(hex: 0x8C826F),
        line: Color(hex: 0xBDB092), accent: Color(hex: 0x9E2A22), khaki: Color(hex: 0x6F6440),
        gold: Color(hex: 0x8C6A22), paper: Color(hex: 0xF4EDDC), paperInk: Color(hex: 0x2A241C),
        stamp: Color(hex: 0xA3241B), isDark: false
    )

    func tier(_ t: String) -> Color {
        switch t {
        case "TE": return gold
        case "GE": return Color(hex: isDark ? 0x86A860 : 0x4E6E30)
        case "NE": return Color(hex: isDark ? 0x9C9582 : 0x6B6453)
        case "SE": return Color(hex: isDark ? 0x7196AE : 0x3F6378)
        default: return Color(hex: isDark ? 0xB8453D : 0x8E2B24)
        }
    }

    static func tierName(_ t: String) -> String {
        switch t {
        case "TE": return "真结局"
        case "GE": return "好结局"
        case "NE": return "普通结局"
        case "SE": return "特殊结局"
        default: return "坏结局"
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.night
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// 正文用宋体，公文和档案用仿宋，界面小字用苹方，俄文和编号用打字机字体
enum Fonts {
    static func body(_ size: CGFloat) -> Font { .custom("Songti SC", size: size) }
    static func bodyBold(_ size: CGFloat) -> Font { .custom("Songti SC", size: size).weight(.bold) }
    static func display(_ size: CGFloat) -> Font { .custom("Songti SC", size: size).weight(.black) }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("PingFang SC", size: size).weight(weight) }
    static func doc(_ size: CGFloat) -> Font { .custom("STFangsong", size: size) }
    static func typewriter(_ size: CGFloat) -> Font { .custom("American Typewriter", size: size) }
    static func mono(_ size: CGFloat) -> Font { .custom("Courier New", size: size) }
}

enum Prefs {
    static let textMode = "textMode"     // 0 逐段浮现  1 打字机  2 立即显示
    static let fontSize = "fontSize"
    static let theme = "theme"           // 0 夜  1 纸
    static let motion = "motion"
    static let hints = "hints"
    static let sidebar = "sidebar"
}
