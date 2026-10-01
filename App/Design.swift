import SwiftUI
import UIKit

enum TranslatorDesign {
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = adaptive(UIColor(red: 0.97, green: 0.975, blue: 0.97, alpha: 1), UIColor(red: 0.045, green: 0.065, blue: 0.105, alpha: 1))
    static let panel = adaptive(.white, UIColor(red: 0.09, green: 0.12, blue: 0.18, alpha: 1))
    static let text = Color.primary
    static let muted = Color.secondary
    static let blue = adaptive(UIColor(red: 0.16, green: 0.48, blue: 0.93, alpha: 1), UIColor(red: 0.37, green: 0.65, blue: 1, alpha: 1))
    static let purple = adaptive(UIColor(red: 0.39, green: 0.43, blue: 0.94, alpha: 1), UIColor(red: 0.61, green: 0.52, blue: 1, alpha: 1))
    static let paleBlue = adaptive(UIColor(red: 0.88, green: 0.955, blue: 1, alpha: 1), UIColor(red: 0.1, green: 0.21, blue: 0.31, alpha: 1))
    static let warmBubble = adaptive(UIColor(red: 0.975, green: 0.95, blue: 0.915, alpha: 1), UIColor(red: 0.22, green: 0.19, blue: 0.16, alpha: 1))
    static let inputBackground = adaptive(UIColor(red: 0.95, green: 0.965, blue: 0.98, alpha: 1), UIColor(red: 0.06, green: 0.085, blue: 0.13, alpha: 1))
    static let border = adaptive(UIColor(red: 0.87, green: 0.91, blue: 0.95, alpha: 1), UIColor(red: 0.2, green: 0.26, blue: 0.34, alpha: 1))
    static let success = adaptive(UIColor(red: 0.055, green: 0.45, blue: 0.31, alpha: 1), UIColor(red: 0.35, green: 0.8, blue: 0.6, alpha: 1))
    static let warning = adaptive(UIColor(red: 0.65, green: 0.37, blue: 0.055, alpha: 1), UIColor(red: 1, green: 0.7, blue: 0.32, alpha: 1))
    static let gradient = LinearGradient(colors: [blue, Color(red: 0.28, green: 0.57, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(TranslatorDesign.panel)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TranslatorDesign.border.opacity(0.65), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.025), radius: 12, x: 0, y: 4)
    }
}
extension View { func glassPanel() -> some View { modifier(GlassPanel()) } }

struct VoiceRibbon: View {
    let level: Double
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<35) { index in
                Capsule()
                    .fill(TranslatorDesign.blue.opacity(opacity(index)))
                    .frame(width: 3, height: height(index))
            }
        }.frame(maxWidth: .infinity).frame(height: 32)
            .animation(.easeOut(duration: 0.15), value: level)
            .accessibilityHidden(true)
    }
    private func height(_ index: Int) -> CGFloat {
        let envelope = sin(Double(index + 1) / 36 * .pi)
        let variation = 0.35 + abs(sin(Double(index) * 1.7)) * 0.65
        return CGFloat(4 + envelope * variation * (6 + min(max(level, 0), 1) * 22))
    }
    private func opacity(_ index: Int) -> Double {
        0.18 + sin(Double(index + 1) / 36 * .pi) * 0.72
    }
}

extension SpokenLanguage {
    var flag: String {
        switch id {
        case "zh-CN": return "🇨🇳"
        case "en-US": return "🇺🇸"
        case "he-IL": return "🇮🇱"
        case "ja-JP": return "🇯🇵"
        case "ko-KR": return "🇰🇷"
        case "fr-FR": return "🇫🇷"
        case "de-DE": return "🇩🇪"
        case "es-ES": return "🇪🇸"
        case "pt-BR": return "🇧🇷"
        case "it-IT": return "🇮🇹"
        case "ru-RU": return "🇷🇺"
        case "ar-SA": return "🇸🇦"
        case "hi-IN": return "🇮🇳"
        case "th-TH": return "🇹🇭"
        case "vi-VN": return "🇻🇳"
        case "tr-TR": return "🇹🇷"
        case "id-ID": return "🇮🇩"
        default: return "🌐"
        }
    }
}

struct LanguageGlobe: View {
    var body: some View {
        ZStack {
            Circle().fill(TranslatorDesign.paleBlue).frame(width: 154, height: 154)
            Circle().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.84, blue: 1), TranslatorDesign.blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 132, height: 132)
                .shadow(color: TranslatorDesign.blue.opacity(0.12), radius: 15, x: 0, y: 10)
            Image(systemName: "globe").font(.system(size: 112, weight: .ultraLight)).foregroundColor(.white.opacity(0.85))
            greeting("Hello", color: TranslatorDesign.blue, white: true).offset(x: -78, y: -38)
            greeting("你好", color: Color(red: 1, green: 0.43, blue: 0.4), white: true).offset(x: 77, y: -20)
            greeting("Bonjour", color: TranslatorDesign.panel, white: false).offset(x: 75, y: 48)
            greeting("Hola", color: TranslatorDesign.warmBubble, white: false).offset(x: -75, y: 52)
        }.frame(height: 188).frame(maxWidth: .infinity).accessibilityHidden(true)
    }
    private func greeting(_ text: String, color: Color, white: Bool) -> some View {
        Text(text).font(.system(size: text.count > 5 ? 14 : 17, weight: .medium))
            .foregroundColor(white ? .white : TranslatorDesign.blue)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(color).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}
