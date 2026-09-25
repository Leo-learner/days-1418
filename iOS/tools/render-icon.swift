// iOS 图标渲染：在 Mac 上跑，输出 1024×1024、不带透明通道的 PNG
// 用法：swiftc -parse-as-library -O render-icon.swift -o render-icon && ./render-icon <输出.png>
//
// 画面和 Mac 版图标（Sources/Icon.swift）是同一张：打字机打过字的纪念章纸条，压着一枚红色"1418"圆章。
// 区别是 iOS 的圆角由系统来切，图标本身要铺满整个方块——所以去掉 Mac 版那块带阴影的圆角底板，
// 内容整体放大 1.2 倍，让纸条和印章在手机桌面上占到差不多的比例。
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct IOSIconArt: View {
    private let ink = Color(hex: 0x2A241C)
    private let red = Color(hex: 0xC0281E)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x34312A), Color(hex: 0x12110E)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x8A6A3A, alpha: 0.20), .clear],
                           center: UnitPoint(x: 0.42, y: 0.36), startRadius: 10, endRadius: 640)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: 0xF0E6CC), Color(hex: 0xD9C9A4)], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 22) {
                    Text("ГРОМОВ  И. С.")
                        .font(.custom("American Typewriter", size: 60).weight(.bold))
                    Text("1920 · г. КАЗАНЬ")
                        .font(.custom("American Typewriter", size: 43))
                    Rectangle().fill(ink.opacity(0.5)).frame(width: 500, height: 4)
                    Rectangle().fill(ink.opacity(0.35)).frame(width: 395, height: 4)
                    Rectangle().fill(ink.opacity(0.35)).frame(width: 455, height: 4)
                }
                .foregroundStyle(ink)
                .padding(52)
            }
            .frame(width: 696, height: 456)
            .rotationEffect(.degrees(-7))
            .offset(x: -48, y: -74)
            .shadow(color: .black.opacity(0.55), radius: 22, y: 12)

            ZStack {
                Circle().stroke(red, lineWidth: 19).frame(width: 384, height: 384)
                Circle().stroke(red, lineWidth: 6).frame(width: 322, height: 322)
                Text("1418")
                    .font(.custom("American Typewriter", size: 125).weight(.bold))
                    .foregroundStyle(red)
            }
            .rotationEffect(.degrees(14))
            .offset(x: 196, y: 196)
            .opacity(0.93)
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
enum RenderIcon {
    @MainActor
    static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
        let renderer = ImageRenderer(content: IOSIconArt())
        renderer.scale = 1
        renderer.isOpaque = true
        guard let rendered = renderer.cgImage,
              let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            print("图标渲染失败")
            exit(1)
        }
        // 重画进一张没有 alpha 通道的位图：iOS 图标不允许透明
        ctx.draw(rendered, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        guard let flat = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("写不了 \(out)")
            exit(1)
        }
        CGImageDestinationAddImage(dest, flat, nil)
        exit(CGImageDestinationFinalize(dest) ? 0 : 1)
    }
}
