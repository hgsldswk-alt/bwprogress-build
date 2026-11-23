import SwiftUI

enum Palette {
    static let accent = Color(red: 22/255, green: 129/255, blue: 158/255)
    static let action = Color(red: 13/255, green: 106/255, blue: 130/255)
    static let tint = Color(red: 218/255, green: 244/255, blue: 251/255)
    static let paper = Color(red: 240/255, green: 245/255, blue: 247/255)
    static let surface = Color(red: 247/255, green: 253/255, blue: 255/255)
    static let ink = Color(red: 34/255, green: 35/255, blue: 38/255)
    static let muted = Color(red: 82/255, green: 88/255, blue: 91/255)
    static let line = Color(red: 210/255, green: 228/255, blue: 233/255)
}

enum ActionStyle: Equatable { case plain, outline, prominent }

struct Action: View {
    var title: String
    var id: String
    var style: ActionStyle = .plain
    var run: () -> Void

    var body: some View {
        Button(action: run) {
            Text(title)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, style == .plain ? 4 : 12)
            .frame(minWidth: 44, maxWidth: style == .plain ? nil : .infinity, minHeight: 44)
            .foregroundStyle(style == .prominent ? .white : Palette.action)
            .background {
                if style != .plain {
                    RoundedRectangle(cornerRadius: 11).fill(style == .prominent ? Palette.action : Palette.surface)
                    RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line, lineWidth: style == .outline ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    private let trailing: () -> Trailing
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 38

    init(title: String, subtitle: String?, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: titleSize, weight: .medium, design: .serif))
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

struct ProgressMarks: View {
    var count: Int
    var total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5)
                    .fill(index < count ? Palette.action : Color.clear)
                    .frame(width: 20, height: 20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.accent)
                        if index < count {
                            Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    func panel() -> some View {
        background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line).allowsHitTesting(false) }
    }

    func page() -> some View {
        frame(maxWidth: 540, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }
}
