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

struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline).foregroundStyle(Palette.orange)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
