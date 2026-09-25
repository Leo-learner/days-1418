import SwiftUI
import UIKit

// MARK: - 触感

/// 抉择是轻轻一下，结局是重重一下，解密档案是"成功"——震动只留给真正有分量的时刻
@MainActor
enum Haptics {
    static func choice() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func ending() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - 按下态

/// Mac 版的"鼠标移上去就亮"在触屏上没有对应物，这里换成"手指按下去就亮"：
/// 按钮样式只负责把 isPressed 放进环境，具体怎么亮由标签视图自己决定。
struct PressAware: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.buttonPressed, configuration.isPressed)
    }
}

private struct ButtonPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var buttonPressed: Bool {
        get { self[ButtonPressedKey.self] }
        set { self[ButtonPressedKey.self] = newValue }
    }
}

// MARK: - 自动换行

/// 标签、数值变化这类小芯片的横排：一行放不下就折到下一行
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        let height = rows.last.map { row in row.map { $0.y + $0.size.height }.max() ?? 0 } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for item in row {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + item.y),
                                           proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct Item {
        let index: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGSize
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [[Item]] {
        var rows: [[Item]] = [[]]
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                rows.append([])
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            rows[rows.count - 1].append(Item(index: i, x: x, y: y, size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return rows
    }
}

// MARK: - 顶端渐隐

extension View {
    /// 全屏滚动的页面（结局、标题）没有顶栏，正文往上滚会从时间、电量底下穿过去。
    /// 不往上盖一层底色（背景是渐变加粒子，盖什么颜色都对不齐），而是给滚动内容本身加遮罩：
    /// 遮罩从安全区上沿开始，先渐隐 24pt 再实心；安全区以上没有遮罩，内容在那里就看不见了。
    /// 底部让遮罩越过安全区，内容照常能滚到 Home 条底下。
    func fadesUnderStatusBar(_ height: CGFloat = 24) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
                Color.black
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - 小部件

/// 顶栏上的图标按钮：44pt 见方的点按区域，右上角可带红点
struct BarIcon: View {
    let icon: String
    var enabled = true
    var badge = false
    @Environment(\.palette) private var p
    @Environment(\.buttonPressed) private var pressed

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(enabled ? (pressed ? p.ink : p.inkDim) : p.inkFaint.opacity(0.5))
            .frame(width: 40, height: 40)
            .background(Circle().fill(pressed && enabled ? p.panelHi : .clear))
            .overlay(alignment: .topTrailing) {
                if badge { Circle().fill(p.accent).frame(width: 7, height: 7).offset(x: -7, y: 8) }
            }
            .contentShape(Rectangle())
    }
}

/// 弹出面板的标题行
struct SheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(Fonts.bodyBold(22)).foregroundStyle(p.ink)
            if let subtitle {
                Text(subtitle).font(Fonts.ui(11)).foregroundStyle(p.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// 面板右上角的纯文字按钮（关闭、取消、完成）
struct TextAction: View {
    let title: String
    var strong = false
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(title, action: action)
            .font(strong ? Fonts.ui(16, .semibold) : Fonts.ui(16))
            .foregroundStyle(strong ? p.accent : p.inkDim)
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}
