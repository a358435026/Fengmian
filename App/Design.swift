import SwiftUI

enum TranslatorDesign {
    static let background = Color(red: 0.02, green: 0.04, blue: 0.11)
    static let panel = Color(red: 0.055, green: 0.09, blue: 0.18)
    static let blue = Color(red: 0.22, green: 0.51, blue: 1)
    static let purple = Color(red: 0.55, green: 0.36, blue: 0.97)
    static let gradient = LinearGradient(colors: [blue, purple], startPoint: .leading, endPoint: .trailing)
}
struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).background(TranslatorDesign.panel)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(TranslatorDesign.blue.opacity(0.23), lineWidth: 1))
            .cornerRadius(20)
    }
}
extension View { func glassPanel() -> some View { modifier(GlassPanel()) } }
struct VoiceRibbon: View {
    let level: Double
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                for step in 0...100 {
                    let x = width * Double(step) / 100
                    let envelope = sin(Double(step) / 100 * .pi)
                    let y = 23 + sin(Double(step) / 100 * .pi * 3) * envelope * (9 + level * 17)
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }.stroke(TranslatorDesign.gradient, lineWidth: 2)
                .shadow(color: TranslatorDesign.blue.opacity(0.6), radius: 9)
        }.frame(height: 46).accessibilityHidden(true)
    }
}
