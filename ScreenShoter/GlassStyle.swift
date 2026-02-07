import SwiftUI

// MARK: - Apple-style UI
// Native macOS look: subtle materials, SF Symbols, minimal chrome

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 12
    var material: Material = .regularMaterial

    func body(content: Content) -> some View {
        content
            .background(material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Стиль кнопки как у native macOS menu items: лёгкий hover, без тяжёлых границ.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonStyleBody(configuration: configuration)
    }
}

private struct GlassButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed { return Color.primary.opacity(0.14) }
        if isHovered { return Color.primary.opacity(0.08) }
        return Color.clear
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 12, material: Material = .regularMaterial) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, material: material))
    }
}
