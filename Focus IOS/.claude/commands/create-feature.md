# Create New Feature

Scaffold a new feature following the project's MVVM architecture.

## Arguments
- `$ARGUMENTS` - Feature name (e.g., "Settings", "Profile")

## Instructions

1. Create the feature directory structure:
   ```
   Presentation/{FeatureName}/
   ├── {FeatureName}View.swift
   └── {FeatureName}ViewModel.swift
   ```

2. Follow existing patterns from FocusTabView/FocusTabViewModel

3. Use @Observable for the ViewModel

4. Connect to existing repositories if data access is needed

5. Add navigation to MainTabView if it's a new tab

## Template Patterns

### ViewModel
```swift
import Foundation
import Observation

@Observable
class {FeatureName}ViewModel {
    // State properties

    // Dependencies (repositories)

    // Methods
}
```

### View
```swift
import SwiftUI

struct {FeatureName}View: View {
    @State private var viewModel = {FeatureName}ViewModel()

    var body: some View {
        // View content
    }
}
```
