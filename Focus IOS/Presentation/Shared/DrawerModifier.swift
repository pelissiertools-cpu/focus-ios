import SwiftUI

struct DrawerStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(colorScheme == .dark ? .thickMaterial : .ultraThinMaterial)
    }
}

extension View {
    func drawerStyle() -> some View {
        modifier(DrawerStyle())
    }
}
