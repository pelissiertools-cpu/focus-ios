import SwiftUI

struct DrawerStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
    }
}

extension View {
    func drawerStyle() -> some View {
        modifier(DrawerStyle())
    }
}
