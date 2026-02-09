import SwiftUI

struct DrawerStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.fraction(0.75)])
            .presentationDragIndicator(.visible)
    }
}

extension View {
    func drawerStyle() -> some View {
        modifier(DrawerStyle())
    }
}
