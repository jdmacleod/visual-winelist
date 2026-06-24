# iOS Design System

Token reference for the visual-winelist iOS app. Tokens are defined in
`ios/Sources/VisualWinelistIOS/Design/AppTokens.swift`.

---

## Corner Radii

| Token | Value | Usage |
|---|---|---|
| `.cornerRadiusSmall` | 6 pt | Alerts, badges, inline UI elements (degraded banner, code snippet background) |
| `.cornerRadiusMedium` | 8 pt | Overlays, info banners, warning cards (results overlay, notes incomplete, confidence warning) |
| `.cornerRadiusCard` | 10 pt | Wine bottle cards — primary content tile |
| `.cornerRadiusLarge` | 12 pt | Setup containers, instruction cards |

Use the named `CGFloat` tokens rather than literal values. Do not introduce
intermediate radii without updating this table.

---

## Colors

### Brand tokens

| Token | Hex | Usage |
|---|---|---|
| `Color.wineRed` | `#731A33` | Hero wineglass icon foreground in SetupView |

### System colors (no custom tokens)

The rest of the app uses SwiftUI adaptive system colors. They respond to
light/dark mode automatically — do not swap for custom RGBA equivalents.

| Color expression | Usage |
|---|---|
| `.orange` | Uncertainty badge background, error state icon, confidence warning icon |
| `.orange.opacity(0.85)` | Degraded backend alert banner background |
| `.orange.opacity(0.1)` | Confidence warning card background |
| `.black.opacity(0.4)` | Camera hint pill background |
| `.black.opacity(0.6)` | Price overlay pill background on wine card |
| `.black.opacity(0.82)` | Detail view image gradient bottom anchor |
| `.secondary.opacity(0.15)` | Pairing chip background |
| `.secondary.opacity(0.1)` | Notes incomplete card background |
| `.ultraThinMaterial` | Translucent overlays (results button, scan-more bar) |

### PlaceholderBottle region color system

`PlaceholderBottle.bottleColor` maps appellation text to a regional color
as a visual metaphor. The gradient runs `bottleColor.opacity(0.6)` → `bottleColor`
top-to-bottom.

| Region keyword | Color |
|---|---|
| Bordeaux, Burgundy | `.purple` |
| Napa, Sonoma | `.indigo` |
| Tuscany, Barolo | `.red` |
| Champagne, Prosecco | `.yellow.opacity(0.8)` |
| Rioja | `.orange` |
| Unknown / default | `.purple` |

---

## Typography

### Semantic scale (preferred)

SwiftUI semantic styles scale with Dynamic Type. Always prefer them over
fixed sizes for readable content.

| Style | Usage |
|---|---|
| `.caption2` | Secondary metadata — uncertainty badge label |
| `.caption2.weight(.semibold)` | Wine name on card (single line, truncated) |
| `.caption` | Inline hints, camera instructions, setup prose |
| `.caption.bold()` / `.caption.weight(.semibold)` | Section headings (TASTING NOTE, FOOD PAIRINGS, FROM THE LIST) |
| `.body` | Primary readable content — tasting notes, descriptions |
| `.subheadline` | Metadata rows, wine count label, form field labels |
| `.subheadline.bold()` | Action button labels, form section headings |
| `.callout` | Setup view descriptive subtitle |
| `.headline` | Scanning state progress message |
| `.title3` | Secondary detail headers — vintage, price, setup tagline |
| `.title3.bold()` | Wine name in detail view image overlay |

### Fixed sizes (decorative icons only)

Fixed sizes are intentional for SF Symbol icons and emoji used as decorative
elements — they should not scale with surrounding text.

| Size | Usage |
|---|---|
| 24 pt | Region flag emoji in PlaceholderBottle |
| 40 pt | Wineglass SF Symbol in PlaceholderBottle |
| 48 pt | Error triangle icon in ContentView error state |
| 56 pt | Hero wineglass icon in SetupView |

---

## Spacing

| Context | Value |
|---|---|
| Grid cell gap | 8 pt |
| Grid edge padding | 16 pt |
| Wine detail content padding | 20 pt |
| Wine detail section spacing | 20 pt |
| Setup view edge padding | 24 pt |
| Setup view section spacing | 28 pt |
| Card name overlay padding (horizontal) | 6 pt |
| Card name overlay padding (bottom) | 6 pt |
| Price overlay pill padding (horizontal) | 5 pt |
| Price overlay pill padding (vertical) | 3 pt |
| Scan-more bar horizontal padding | 16 pt |
| Scan-more bar vertical padding | 12 pt |

---

## Accessibility

- All interactive elements have an `accessibilityLabel` or derive one from
  `Label("…", systemImage:)`.
- Camera shutter: `.accessibilityLabel("Capture wine list")`
- Trash toolbar button: `.accessibilityLabel("Clear all wines")`
- Preferences toolbar button: `.accessibilityLabel("Preferences")`
- Wine grid cards: dynamic label via `cardLabel(for:)` — includes name,
  vintage, and low-confidence flag.
- Haptic feedback: medium impact on shutter tap; success notification when
  wines arrive; error notification on error state.
