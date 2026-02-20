# Focus iOS — UI Style Guide

Reference document for all UI patterns, tokens, and component dimensions used across the app.

---

## Colors

### Brand Palette

| Token | Hex | RGB | Usage |
|---|---|---|---|
| `appRed` | `#F81E1D` | 248, 30, 29 | Primary accent — FABs, selected states, checkmarks, pills, timeline blocks, progress bars |
| `completedPurple` | `#6110F8` | 97, 16, 248 | "All done" checkmark animation |
| `darkGray` | — | 40, 45, 46 | Log FAB background, active category pill tint |
| `lightBackground` | `#FCFCFC` | 252, 252, 252 | Focus tab main background |

### System Colors in Use

| Color | Where |
|---|---|
| `.primary` | Body text, inactive pill text |
| `.secondary` | Drag handles, hour labels, dropdown headers, separators |
| `.white` | Active pill text, close button icons, FAB icons, resize handles |
| `.black` | Shadow base color only |
| `.red` | Current-time indicator (dot + line) |
| `Color(.systemGray3)` | Schedule drawer drag handle |
| `Color(.systemGray4)` | Inactive submit checkmark bg |
| `Color(.systemGray5)` | Inactive filter pill bg, normal check button bg |
| `Color(.separator)` | Auth social button stroke |
| `Color(.secondarySystemGroupedBackground)` | Detail drawer card fills |

### Materials / Glass

| Style | Usage |
|---|---|
| `.ultraThinMaterial` | All DrawerContainer sheet backgrounds |
| `.regularMaterial` | Category dropdown overlay |
| `.glassEffect(.regular)` | Inactive pills, profile buttons, search pills, project cards, settings cards |
| `.glassEffect(.regular.tint(.appRed))` | Active commitment pills, active segmented picker, FAB |
| `.glassEffect(.regular.tint(.darkGray))` | Active category pill |

---

## Typography

### Font Families

| Family | Helper | Usage |
|---|---|---|
| **SF Pro** (system) | `.sf(size:weight:)` / `.sf(_:weight:)` | All body text, labels, captions |
| **Montserrat** | `.montserratHeader(size:weight:)` | Date navigator month/year label |
| **GolosText** | `.golosText(size:weight:)` | Section header titles |

### Type Scale

| Role | Font Call | Approx Size |
|---|---|---|
| Page title | `.sf(size: 48, weight: .bold)` | 48 |
| Section header (focus) | `.golosText(size: 30)` | 30 |
| Section header (extra) | `.golosText(size: 22)` | 22 |
| Date navigator label | `.montserratHeader(size: 24)` | 24 (20 compact) |
| Nav bar title | `.sf(.title3, weight: .medium)` | 20 |
| Drawer / sheet title | `.sf(.title2, weight: .bold)` | 22 |
| Drawer section title | `.sf(.headline, weight: .semibold)` | 17 |
| Text field placeholder | `.sf(.headline, weight: .semibold)` | 17 |
| Row title | `.sf(.body)` | 17 |
| Subtitle / secondary | `.sf(.subheadline)` | 15 |
| Picker segment label | `.sf(.subheadline, weight: .semibold)` | 15 |
| Filter pill text | `.sf(.caption, weight: .medium)` | 12 |
| Badge / tiny label | `.sf(.caption2, weight: .medium)` | 11 |
| Section count badge | `.sf(size: 10)` | 10 |
| Section chevron | `.sf(size: 8, weight: .semibold)` | 8 |

---

## Spacing & Padding

### Horizontal Padding Scale

| Value | Role | Example |
|---|---|---|
| `4` | Inner element padding | Segmented picker inner |
| `6` | Tight element spacing | Pill HStack spacing |
| `8` | Standard tight spacing | HStack spacing, filter pill gaps |
| `10` | Pill horizontal padding | Filter pills `.padding(.horizontal, 10)` |
| `12` | Medium horizontal | Row HStack spacing, search field horizontal |
| `14` | Section content | Add bar horizontal, title card horizontal |
| `16` | Standard content | Row horizontal padding, dropdown dividers, section insets |
| `20` | Page-level | Sign-in horizontal, dropdown items |
| `24` | Sheet content | Auth sheet content horizontal |
| `32` | Indented content | Task list row insets, subtask leading indent |

### Vertical Padding Scale

| Value | Role | Example |
|---|---|---|
| `2` | Minimal | Filter bar top/bottom |
| `4` | Tiny | Small pill vertical, dropdown top |
| `6` | Tight row | Subtask row vertical, capsule vertical |
| `8` | Small row | Extra section row vertical, filter pills vertical |
| `10` | Medium field | Search field vertical, dropdown header |
| `12` | Standard row | Dropdown items, subtask rows, action labels |
| `14` | Content row | Focus row vertical, task rows, settings rows |
| `16` | Card internal | Title card vertical padding |
| `20` | Section gap | Add bar bottom, section bottom |
| `24` | Page top | Settings top padding |
| `28` | Large top | Sign-in view top |
| `40` | Bottom safe area | Auth/sign-in bottom |
| `100` | Scroll clearance | Bottom of scrollable lists (above FAB) |

### Stack Spacing

| Value | Usage |
|---|---|
| `0` | No-gap stacks (dropdown, section internals) |
| `4` | Tight icon + text |
| `6` | Small element gaps |
| `8` | Standard icon + text |
| `10` | Action row icon gap |
| `12` | Card/row gaps |
| `16` | Medium section stacking |
| `20` | Section stacking |

---

## Corner Radii

| Radius | Usage |
|---|---|
| `6` | Timeline task blocks, drop previews |
| `10` | Monthly/yearly pill selection highlight |
| `12` | Standard card/field — task rows, text fields, social buttons, detail drawer cards, settings cards, calendar selection |
| `14` | Buttons (sign-in), dropdown menus |
| `16` | Inner pickers, schedule drawer container, drag cancel bar |
| `20` | Primary cards/containers — section cards, add bars, segmented picker outer, date navigator |
| `24` | Large sheet radius (sign-in bottom drawer) |
| `25` | Fully rounded button (height 50 → radius 25) |
| `Capsule` | All filter pills, edit mode action bar |
| `Circle` | FAB, add button, profile button, close/check buttons, edit mode button |
| `.continuous` | Smooth-cornered cards (section cards, project cards, schedule drawer) |

---

## Component Sizes

### Buttons

| Size | Component |
|---|---|
| `56 × 56` | FAB (Floating Action Button) |
| `44 × 44` | Delete button (detail drawer) |
| `36 × 36` | Profile pill, search pill, back/close buttons, edit mode button |
| `30 × 30` | Drawer close/check buttons, search dismiss |
| `26 × 26` | Section add button (plus circle) |

### Rows & Cards

| Height | Component |
|---|---|
| `min 70` | Parent task/list rows |
| `60` | Year button (calendar) |
| `54` | Sign-in buttons |
| `52` | Edit mode action icons |
| `50` | Auth continue button, month button |
| `min 44` | Subtask rows |
| `48` | Weekly pill frame |
| `40` | Monthly pill, yearly pill |
| `32` | Filter pills (category, commitment) |

### Fixed Dimensions

| Size | Component |
|---|---|
| `64 × 64` | Project icon frame |
| `56` width | Timeline hour label column |
| `44` width | Daily pill parent width |
| `36 × 5` | Drag handle capsule (schedule drawer) |
| `36 × 36` | Calendar day cell circle |
| `32 × 32` | Daily pill day number circle |
| `28` width | Edit action bar divider |
| `24` width | Icon frame in action/settings rows |
| `22` width | Subtask checkbox |
| `10 × 10` | Current time indicator dot |
| `8` | Timeline resize handle dot |

### Timeline

| Value | Meaning |
|---|---|
| `hourHeight: 60` | 60 points per hour |
| `totalHeight: 1440` | 24 hours × 60pt |

---

## Sheets & Drawers

### Standard Drawer (DrawerContainer)

All detail/selection sheets use the shared `DrawerModifier`:

```
Detent:      .large
Drag indicator: .visible
Background:  .ultraThinMaterial
```

Applies to: TaskDetailsDrawer, ListDetailsDrawer, ProjectDetailsDrawer, CommitSheet, RescheduleSheet, CommitmentSelectionSheet

### Schedule Drawer

- Height: 50% of parent geometry
- Background: own container styling
- Drag handle: `Color(.systemGray3)` capsule, `36 × 5`

---

## Shadows

| Name | Parameters | Usage |
|---|---|---|
| Card shadow | `color: .black.opacity(0.08), radius: 10, y: 4` | Section cards |
| FAB shadow | `radius: 4, y: 2` | FAB buttons, edit mode bar |
| Overlay shadow | `color: .black.opacity(0.15), radius: 12, y: -4` | Drag cancel bar, schedule drawer |
| Drag preview | `color: .black.opacity(0.2), radius: 12, y: 4` | Schedule drag preview |
| Dropdown shadow | `color: .black.opacity(0.2), radius: 12, y: 6` | Category dropdown menu |
| Dragged card | `color: .black.opacity(0.15), radius: 8, y: 2` | Dragged project card |
| Light shadow | `color: .black.opacity(0.06), radius: 4, y: 2` | Date navigator |

---

## Opacity Tokens

| Value | Usage |
|---|---|
| `0.001` | Invisible tap dismiss layer |
| `0.06` | Lightest shadow |
| `0.08` | Card shadows |
| `0.15` | Drag overlays, timeline block fill (`appRed.opacity(0.15)`) |
| `0.2` | Dropdown/drag-preview shadows |
| `0.3` | Auth button borders, "being dragged" block, calendar highlights |
| `0.5` | Disabled action states |
| `0.7` | Section header separators |

---

## Borders & Strokes

| Width | Color | Style | Usage |
|---|---|---|---|
| `1` | `.white` | Solid | Date navigator container |
| `1` | `Color(.separator)` | Solid | Auth social button |
| `1.5` | `.appRed` | Solid | Timeline task block, resize handle dot |
| `1.5` | `.appRed` | Dashed `[5]` | Timeline drop preview |
| `1.5` | `.white` (varying opacity) | Solid | AI button inner glow |
| `2` | `.appRed` | Solid | Selected calendar date circle |
| `2` | Focused color | Solid | Focused text field |
| `2.5` | AngularGradient | Solid | AI button outer glow |

---

## Animations

### Springs

| Parameters | Usage |
|---|---|
| `response: 0.3, dampingFraction: 0.8` | Default UI transitions (dropdown toggle, general) |
| `response: 0.35, dampingFraction: 0.85` | Add bar show/hide, Log tab filter transitions |
| `response: 0.3, dampingFraction: 0.7` | Drag state changes (bouncier) |

### Ease Curves

| Duration | Usage |
|---|---|
| `easeInOut(0.2)` | Quick state toggles (commitment filter, small changes) |
| `easeInOut(0.25)` | Task completion, row animations |
| `easeInOut(0.3)` | Section expand/collapse, date navigation |
| `easeInOut(0.35)` | Drag preview appearance |

### Continuous

| Parameters | Usage |
|---|---|
| `easeOut(0.6), repeatForever, autoreverses` | "All done" pulse |
| `linear(0.8), repeatForever` | AI sparkle rotation |

### Scale Effects

| Scale | Usage |
|---|---|
| `1.35` | "All done" checkmark pulse |
| `1.03` | Dragged items (slight enlarge) |
| `0.95` | Drag preview in cancel zone (slight shrink) |

---

## Appearance

Three modes managed by `AppearanceManager`:
- `.system` (default)
- `.light`
- `.dark`

Stored in UserDefaults key `"appAppearance"`.
