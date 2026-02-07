# Create New Model

Create a new domain model that integrates with Supabase.

## Arguments
- `$ARGUMENTS` - Model name and fields (e.g., "Note: title, content, taskId")

## Instructions

1. Create the model in `Domain/Models/`

2. Follow the existing pattern from FocusTask or Commitment:
   - Conform to `Codable` and `Identifiable`
   - Include `id: UUID` and `userId: UUID`
   - Add `createdDate` and `modifiedDate` as appropriate
   - Define `CodingKeys` with snake_case mapping

3. Create a corresponding repository in `Data/Repositories/`

4. Add RLS policy to DatabaseMigrations.sql

## Template

```swift
import Foundation

struct {ModelName}: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    // Add other properties
    let createdDate: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        // Map other properties
        case createdDate = "created_date"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        // Other parameters
        createdDate: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        // Assign other properties
        self.createdDate = createdDate
    }
}
```
