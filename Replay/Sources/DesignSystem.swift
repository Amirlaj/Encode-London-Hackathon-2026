import SwiftUI

enum Palette {
    static let background = Color(red: 0.965, green: 0.965, blue: 0.943)
    static let ink = Color(red: 0.075, green: 0.19, blue: 0.16)
    static let muted = Color(red: 0.40, green: 0.46, blue: 0.42)
    static let accent = Color(red: 0.79, green: 0.93, blue: 0.39)
    static let line = Color(red: 0.87, green: 0.89, blue: 0.85)
    static let orange = Color(red: 0.80, green: 0.38, blue: 0.18)
}

struct PrimaryButtonStyle: ButtonStyle {
    var light = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(light ? Palette.ink : .white)
            .background(light ? Palette.accent : Palette.ink, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Palette.ink)
            .background(.white.opacity(configuration.isPressed ? 0.5 : 0.9), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.8).foregroundStyle(Palette.muted)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ActivitySelector: View {
    @Binding var selected: Activity
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Activity.allCases) { activity in
                    Button { selected = activity } label: {
                        HStack(spacing: 7) {
                            Image(systemName: activity.symbol)
                            Text(activity == .other ? "Other" : activity.rawValue)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 15).padding(.vertical, 12)
                        .foregroundStyle(selected == activity ? .white : Palette.ink)
                        .background(selected == activity ? Palette.ink : .white, in: Capsule())
                        .overlay(Capsule().stroke(selected == activity ? Palette.ink : Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("activity-\(activity.rawValue)")
                        .accessibilityAddTraits(selected == activity ? .isSelected : [])
                }
            }
        }
    }
}

struct CourtArt: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Color(red: 0.15, green: 0.32, blue: 0.25)
                Canvas { context, size in
                    let rect = CGRect(x: size.width * 0.23, y: -size.height * 0.15, width: size.width * 0.64, height: size.height * 1.35)
                    context.translateBy(x: size.width * 0.5, y: size.height * 0.5)
                    context.rotate(by: .degrees(22))
                    context.translateBy(x: -size.width * 0.5, y: -size.height * 0.5)
                    context.fill(Path(rect), with: .color(Color(red: 0.24, green: 0.43, blue: 0.33)))
                    let court = rect.insetBy(dx: 14, dy: 14)
                    context.stroke(Path(court), with: .color(.white.opacity(0.55)), lineWidth: 1.5)
                    var lines = Path()
                    lines.move(to: CGPoint(x: court.minX + 21, y: court.minY))
                    lines.addLine(to: CGPoint(x: court.minX + 21, y: court.maxY))
                    lines.move(to: CGPoint(x: court.maxX - 21, y: court.minY))
                    lines.addLine(to: CGPoint(x: court.maxX - 21, y: court.maxY))
                    for fraction in [0.28, 0.5, 0.72] {
                        let y = court.minY + court.height * fraction
                        lines.move(to: CGPoint(x: court.minX, y: y))
                        lines.addLine(to: CGPoint(x: court.maxX, y: y))
                    }
                    lines.move(to: CGPoint(x: court.midX, y: court.minY + court.height * 0.28))
                    lines.addLine(to: CGPoint(x: court.midX, y: court.minY + court.height * 0.72))
                    context.stroke(lines, with: .color(.white.opacity(0.55)), lineWidth: 1.3)
                    let net = CGRect(x: court.minX - 5, y: court.midY - 3, width: court.width + 10, height: 6)
                    context.fill(Path(net), with: .color(.black.opacity(0.28)))
                }
                LinearGradient(colors: [Palette.ink.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                Circle().fill(.black.opacity(0.16)).frame(width: 38, height: 12).rotationEffect(.degrees(-25)).position(x: width * 0.73 + 9, y: height * 0.73 + 10)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 12, height: 22).rotationEffect(.degrees(30)).position(x: width * 0.73, y: height * 0.73)
                Circle().fill(Color(red: 0.82, green: 0.64, blue: 0.47)).frame(width: 9, height: 9).position(x: width * 0.73 - 1, y: height * 0.73 - 10)
                Circle().stroke(Palette.accent, lineWidth: 2).frame(width: 12, height: 15).rotationEffect(.degrees(25)).position(x: width * 0.73 + 18, y: height * 0.73 - 2)
                Circle().fill(Palette.accent).frame(width: 5, height: 5).position(x: width * 0.63, y: height * 0.27)
                Path { path in
                    path.move(to: CGPoint(x: width * 0.63, y: height * 0.27))
                    path.addQuadCurve(to: CGPoint(x: width * 0.77, y: height * 0.62), control: CGPoint(x: width * 0.94, y: height * 0.35))
                }.stroke(Palette.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline).foregroundStyle(Palette.orange)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
