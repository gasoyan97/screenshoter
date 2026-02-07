import SwiftUI

// MARK: - Liquid Glass стиль (Apple-inspired)
// Полупрозрачные материалы, скругления, мягкие границы

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 16
    var material: Material = .ultraThinMaterial

    func body(content: Content) -> some View {
        content
            .background(material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
    }
}

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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.1), lineWidth: 0.5)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var backgroundColor: Color {
        if configuration.isPressed { return Color.primary.opacity(0.12) }
        if isHovered { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.04)
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 16, material: Material = .ultraThinMaterial) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, material: material))
    }
}
