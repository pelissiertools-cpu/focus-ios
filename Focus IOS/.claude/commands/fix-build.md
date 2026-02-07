# Fix Build Errors

Analyze and fix build errors in the Focus iOS project.

## Instructions

1. First, attempt to build using XcodeBuildMCP
2. Parse the error output to identify:
   - File path and line number
   - Error type (syntax, type mismatch, missing import, etc.)
   - Error message

3. For each error, apply the appropriate fix:

### Common Fixes

**Missing Combine import**
- Symptom: "Type does not conform to protocol 'ObservableObject'"
- Fix: Add `import Combine`

**Task naming conflict**
- Symptom: "trailing closure passed to parameter of type 'any Decoder'"
- Fix: Rename model to `FocusTask`

**Encodable with [String: Any]**
- Symptom: "[String: Any] cannot conform to Encodable"
- Fix: Create proper struct with CodingKeys

**Actor isolation**
- Symptom: "Main actor-isolated static property"
- Fix: Mark as `nonisolated(unsafe) static let shared`

4. After applying fixes, rebuild to verify

5. Repeat until build succeeds
