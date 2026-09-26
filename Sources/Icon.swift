import AppKit
import SwiftUI

/// App 图标：一张打字机打过字的纪念章纸条，压着一枚红色的"1418"圆章
struct IconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x2E2C25), Color(hex: 0x141310)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .overlay(
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 3)
                        .frame(width: 824, height: 824)
                )
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: 0xF0E6CC), Color(hex: 0xD9C9A4)], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 18) {
                    Text("ГРОМОВ  И. С.")
                        .font(.custom("American Typewriter", size: 50).weight(.bold))
                    Text("1920 · г. КАЗАНЬ")
                        .font(.custom("American Typewriter", size: 36))
                    Rectangle().fill(Color(hex: 0x2A241C, alpha: 0.5)).frame(width: 420, height: 3)
                    Rectangle().fill(Color(hex: 0x2A241C, alpha: 0.35)).frame(width: 330, height: 3)
                    Rectangle().fill(Color(hex: 0x2A241C, alpha: 0.35)).frame(width: 380, height: 3)
                }
                .foregroundStyle(Color(hex: 0x2A241C))
                .padding(44)
            }
            .frame(width: 580, height: 380)
            .rotationEffect(.degrees(-7))
            .offset(x: -40, y: -60)
            .shadow(color: .black.opacity(0.5), radius: 18, y: 10)

            ZStack {
                Circle().stroke(Color(hex: 0xC0281E), lineWidth: 16).frame(width: 320, height: 320)
                Circle().stroke(Color(hex: 0xC0281E), lineWidth: 5).frame(width: 268, height: 268)
                Text("1418")
                    .font(.custom("American Typewriter", size: 104).weight(.bold))
                    .foregroundStyle(Color(hex: 0xC0281E))
            }
            .rotationEffect(.degrees(14))
            .offset(x: 170, y: 170)
            .opacity(0.93)
        }
        .frame(width: 1024, height: 1024)
    }
}

enum IconRenderer {
    @MainActor
    static func render(to path: String) {
        let renderer = ImageRenderer(content: IconArt())
        renderer.scale = 1
        guard let cg = renderer.cgImage else {
            print("图标渲染失败")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
