import SwiftUI

// MARK: - 场景氛围：底色 + 粒子（雪、灰、火星、雨、花瓣……）

enum ParticleKind {
    case none, dust, ember, ash, snow, rain, petal, leaf
}

struct MoodStyle {
    var top: UInt32
    var bottom: UInt32
    var glow: UInt32?
    var particle: ParticleKind
    var count: Int

    static func of(_ mood: String) -> MoodStyle {
        switch mood {
        case "dusk": return MoodStyle(top: 0x2A1F16, bottom: 0x121110, glow: 0x6B3A1A, particle: .dust, count: 40)
        case "fire": return MoodStyle(top: 0x1A100D, bottom: 0x100C0A, glow: 0x8A2A12, particle: .ember, count: 70)
        case "smoke": return MoodStyle(top: 0x1E1C19, bottom: 0x121110, glow: nil, particle: .ash, count: 50)
        case "forest": return MoodStyle(top: 0x121812, bottom: 0x0E110E, glow: nil, particle: .dust, count: 36)
        case "night": return MoodStyle(top: 0x0C0F15, bottom: 0x090A0D, glow: nil, particle: .dust, count: 14)
        case "river": return MoodStyle(top: 0x121A20, bottom: 0x0D1114, glow: 0x24323A, particle: .dust, count: 26)
        case "snow": return MoodStyle(top: 0x16191C, bottom: 0x0F1113, glow: nil, particle: .snow, count: 110)
        case "ash": return MoodStyle(top: 0x1C1816, bottom: 0x100E0D, glow: 0x3A1E14, particle: .ash, count: 90)
        case "rain": return MoodStyle(top: 0x111518, bottom: 0x0B0D0F, glow: nil, particle: .rain, count: 90)
        case "summer": return MoodStyle(top: 0x1C1A12, bottom: 0x121110, glow: 0x3A3216, particle: .dust, count: 34)
        case "autumn": return MoodStyle(top: 0x1C1610, bottom: 0x110F0C, glow: nil, particle: .leaf, count: 22)
        case "spring": return MoodStyle(top: 0x19161B, bottom: 0x110F12, glow: nil, particle: .petal, count: 28)
        case "archive": return MoodStyle(top: 0x151A1D, bottom: 0x0E1113, glow: nil, particle: .dust, count: 18)
        case "dawn": return MoodStyle(top: 0x1A1C24, bottom: 0x111114, glow: 0x2C2A3A, particle: .none, count: 0)
        default: return MoodStyle(top: 0x151412, bottom: 0x121110, glow: nil, particle: .none, count: 0)
        }
    }
}

struct AtmosphereView: View {
    let mood: String
    @Environment(\.palette) private var p
    @AppStorage(Prefs.motion) private var motion = true

    var body: some View {
        let style = MoodStyle.of(mood)
        ZStack {
            if p.isDark {
                LinearGradient(colors: [Color(hex: style.top), Color(hex: style.bottom)], startPoint: .top, endPoint: .bottom)
                if let glow = style.glow {
                    RadialGradient(colors: [Color(hex: glow, alpha: 0.55), .clear], center: .bottom, startRadius: 10, endRadius: 700)
                }
            } else {
                p.bg
                LinearGradient(colors: [Color(hex: style.top, alpha: 0.10), .clear], startPoint: .top, endPoint: .bottom)
            }
            if motion && style.particle != .none {
                ParticleField(kind: style.particle, count: style.count, dark: p.isDark)
            }
            GrainOverlay(opacity: p.isDark ? 0.06 : 0.08)
            RadialGradient(colors: [.clear, .black.opacity(p.isDark ? 0.5 : 0.10)], center: .center, startRadius: 280, endRadius: 1100)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 无状态粒子：每颗粒子的位置只由编号和时间决定，不用在内存里维护粒子数组
struct ParticleField: View {
    let kind: ParticleKind
    let count: Int
    let dark: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    var r = SplitMix(seed: UInt64(i + 1) &* 0x9E37_79B9)
                    func u() -> Double { Double(r.next() % 10_000) / 10_000 }
                    let x0 = u() * size.width
                    let y0 = u() * size.height
                    let speed = 0.5 + u()
                    let phase = u() * 6.283
                    let scale = 0.6 + u() * 1.6
                    draw(&ctx, size: size, t: t, x0: x0, y0: y0, speed: speed, phase: phase, scale: scale)
                }
            }
        }
    }

    private func wrap(_ v: Double, _ m: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, x0: Double, y0: Double,
                      speed: Double, phase: Double, scale: Double) {
        let w = size.width + 40, h = size.height + 40
        switch kind {
        case .snow:
            let x = wrap(x0 + sin(t * 0.5 + phase) * 24 + t * 6 * speed, w) - 20
            let y = wrap(y0 + t * 22 * speed, h) - 20
            let r = 1.1 * scale
            let c = dark ? Color.white.opacity(0.35 + 0.35 * speed / 1.5) : Color(hex: 0x6F695C, alpha: 0.25)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(c))
        case .ash:
            let x = wrap(x0 + sin(t * 0.35 + phase) * 34 + t * 4 * speed, w) - 20
            let y = wrap(y0 + t * 11 * speed, h) - 20
            let r = 0.9 * scale
            let c = dark ? Color(hex: 0xB9B1A2, alpha: 0.28) : Color(hex: 0x5E5546, alpha: 0.18)
            ctx.fill(Path(CGRect(x: x, y: y, width: r * 1.6, height: r)), with: .color(c))
        case .ember:
            let x = wrap(x0 + sin(t * 1.2 + phase) * 16, w) - 20
            let y = wrap(y0 - t * 28 * speed, h) - 20
            let flicker = 0.25 + 0.75 * abs(sin(t * 3 + phase))
            let r = 0.9 * scale
            let c = Color(hex: 0xFF8A3D, alpha: (dark ? 0.75 : 0.45) * flicker)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(c))
        case .dust:
            let x = wrap(x0 + t * 4 * speed + sin(t * 0.3 + phase) * 10, w) - 20
            let y = wrap(y0 - t * 2.5 * speed + cos(t * 0.25 + phase) * 8, h) - 20
            let r = 0.7 * scale
            let a = (0.10 + 0.20 * abs(sin(t * 0.5 + phase))) * (dark ? 1 : 0.6)
            let c = dark ? Color(hex: 0xE6DFCF, alpha: a) : Color(hex: 0x5E5546, alpha: a)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(c))
        case .rain:
            let x = wrap(x0 - t * 90 * speed, w) - 20
            let y = wrap(y0 + t * 620 * speed, h) - 20
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 3, y: y + 14 * scale))
            let c = dark ? Color(hex: 0xA9B6C0, alpha: 0.22) : Color(hex: 0x5E6A73, alpha: 0.22)
            ctx.stroke(path, with: .color(c), lineWidth: 1)
        case .petal, .leaf:
            let x = wrap(x0 + sin(t * 0.6 + phase) * 44 + t * 10 * speed, w) - 20
            let y = wrap(y0 + t * 18 * speed, h) - 20
            let color: Color = kind == .petal ? Color(hex: 0xE8B9C2, alpha: dark ? 0.45 : 0.55)
                                              : Color(hex: 0x9A6A32, alpha: dark ? 0.5 : 0.45)
            var petal = ctx
            petal.translateBy(x: x, y: y)
            petal.rotate(by: .radians(t * 0.8 * speed + phase))
            let rw = (kind == .petal ? 3.2 : 4.2) * scale
            petal.fill(Path(ellipseIn: CGRect(x: -rw, y: -rw * 0.45, width: rw * 2, height: rw * 0.9)), with: .color(color))
        case .none:
            break
        }
    }
}

/// 胶片颗粒：启动时生成一张噪点图，平铺叠加
struct GrainOverlay: View {
    var opacity: Double

    private static let noise: CGImage? = {
        let side = 160
        var rng = SplitMix(seed: 1418)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            let v = UInt8(truncatingIfNeeded: rng.next() % 256)
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()

    var body: some View {
        if let noise = Self.noise {
            Image(decorative: noise, scale: 1)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(opacity)
        }
    }
}

// MARK: - 印章与纸张

struct Stamp: View {
    let text: String
    var color: Color
    var angle: Double = -8
    var size: CGFloat = 15

    var body: some View {
        Text(text)
            .font(Fonts.typewriter(size).weight(.bold))
            .tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 2))
            .rotationEffect(.degrees(angle))
            .opacity(0.82)
    }
}

/// 旧纸：底色 + 淡横线 + 颗粒
struct PaperBackground: View {
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            p.paper
            Canvas { ctx, size in
                var y: CGFloat = 38
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)), with: .color(p.paperInk.opacity(0.05)))
                    y += 30
                }
            }
            GrainOverlay(opacity: 0.12)
            LinearGradient(colors: [.clear, Color(hex: 0x8A6A3A, alpha: 0.10)], startPoint: .top, endPoint: .bottom)
        }
    }
}
