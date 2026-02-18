//
//  DragHandleView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-08.
//

import SwiftUI

/// Shared drag handle icon used across all sections (Focus, Log).
/// Visual-only — attach `.onDrag` or `.onMove` at the call site.
struct DragHandleView: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.montserrat(.subheadline))
            .foregroundColor(.secondary)
    }
}
     
