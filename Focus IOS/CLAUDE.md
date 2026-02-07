# Focus iOS App

## Quick Reference
- **Platform**: iOS
- **Language**: Swift 5
- **Minimum Deployment Target**: iOS 26.2
- **UI Framework**: SwiftUI
- **Backend**: Supabase
- **Bundle ID**: Focus.App.Focus-IOS

## XcodeBuildMCP Integration

This project uses XcodeBuildMCP for all Xcode operations. Always use MCP tools instead of direct xcodebuild commands:

- **Build**: Use `mcp__xcodebuildmcp__xcode_build` or simulator-specific build tools
- **Test**: Use `mcp__xcodebuildmcp__xcode_test`
- **Clean**: Use `mcp__xcodebuildmcp__xcode_clean`
- **Discover Projects**: Use `mcp__xcodebuildmcp__discover_projects`

## Project Structure

```
Focus IOS/
├── Focus_IOSApp.swift          # App entry point
├── ContentView.swift           # Root view with auth routing
├── Data/
│   ├── Repositories/           # Data access layer
│   │   ├── TaskRepository.swift
│   │   ├── CategoryRepository.swift
│   │   └── CommitmentRepository.swift
│   ├── Services/
│   │   └── AuthService.swift   # Authentication state management
│   └── Supabase/
│       ├── SupabaseClient.swift
│       ├── SupabaseConfig.swift
│       └── DatabaseMigrations.sql
├── Domain/
│   └── Models/
│       ├── Task.swift          # FocusTask model (renamed to avoid Swift Task conflict)
│       ├── Category.swift
│       ├── Commitment.swift
│       └── Enums/
│           ├── Timeframe.swift # daily, weekly, monthly, yearly
│           ├── Section.swift
│           └── TaskType.swift
└── Presentation/
    ├── MainTabView.swift       # Tab navigation
    ├── Auth/
    │   ├── SignInView.swift
    │   └── SignUpView.swift
    ├── Focus/                  # Commitment-based focus view
    │   ├── FocusTabView.swift
    │   ├── FocusTabViewModel.swift
    │   ├── CommitmentSelectionSheet.swift
    │   ├── TimeframePickers.swift
    │   └── UnifiedCalendarPicker.swift
    └── Library/                # Task library management
        ├── LibraryTabView.swift
        ├── Tasks/
        │   ├── TasksListView.swift
        │   ├── TaskListViewModel.swift
        │   └── TaskDetailsDrawer.swift
        ├── Projects/
        │   └── ProjectsListView.swift
        └── Lists/
            └── ListsView.swift
```

## Coding Standards

### Swift Patterns
- Use `@Observable` macro for view models (Swift Observation framework)
- Use `async/await` for all asynchronous operations
- Follow MVVM architecture: Views → ViewModels → Repositories → Supabase

### Naming Conventions
- **Model**: Use `FocusTask` instead of `Task` to avoid Swift concurrency conflict
- **CodingKeys**: Use snake_case to match Supabase/PostgreSQL column names
- **ViewModels**: Suffix with `ViewModel` (e.g., `TaskListViewModel`)

### Supabase Integration
- All models conform to `Codable` with custom `CodingKeys`
- Repositories handle CRUD operations with proper error handling
- Row Level Security (RLS) enforced: `user_id = auth.uid()`
- Use `SupabaseClientManager.shared` for client access

## SwiftUI Patterns

### Navigation
- Tab-based navigation via `MainTabView`
- Sheet-based modals for detail views and pickers
- Use `@Environment(\.dismiss)` for dismissing sheets

### State Management
- `@Published` properties in ViewModels for reactive updates
- `@State` for local view state
- `@Binding` for two-way data flow to child views

## DO NOT

- Do NOT name any model `Task` - use `FocusTask` to avoid Swift concurrency conflicts
- Do NOT use `[String: Any]` for Encodable operations - create proper structs
- Do NOT forget `import Combine` when using `@Published` or `ObservableObject`
- Do NOT set `STRING_CATALOG_GENERATE_SYMBOLS = YES` - causes duplicate file conflicts
- Do NOT add features, refactor, or make improvements beyond what was requested

## Testing

- Test files located in `Focus IOSTests/` and `Focus IOSUITests/`
- Use Swift Testing framework for new tests
- Run tests via XcodeBuildMCP: `mcp__xcodebuildmcp__xcode_test`

## Build Verification

After making changes:
1. Build using XcodeBuildMCP to verify compilation
2. Run relevant tests
3. Check for any SwiftUI preview issues
