# TODOS

Deferred items from the v2 implementation and design reviews.

## iOS Design System (design-review 2026-06-18)

**What:** Create `DESIGN.md` documenting iOS design tokens — corner radii, color
system, and typography scale.

**Why:** The current iOS codebase uses 4 corner radii (6, 8, 10, 12pt) and ad-hoc
color values (`.purple`, `.indigo`, `.red`, `.orange.opacity(0.85)`) with no
documentation. Any contributor adding UI must guess which values to use.

**Pros:** Enables consistent UI contributions without reading all views; enables
`/design-consultation` to formalize into a real design system.

**Cons:** No user-visible impact until the first new contributor arrives.

**Context:** Observed in design review pass 5. Current tokens:
- Corner radii: 6pt (alerts/badges), 8pt (overlays/warnings), 10pt (wine cards),
  12pt (info cards in SetupView)
- Colors: `.purple`/`.indigo`/`.red` in PlaceholderBottle region system; no token
  layer; opacity values spread across files
- Type scale: mix of semantic (`.caption`, `.body`, `.title2`) and fixed sizes
  (`.system(size: 40/56)` for decorative icons)

**Depends on:** None. Can be done at any time.

---

## E2: Personal scan history

Save each scan with restaurant name + date. Requires user tagging UI at scan time.

---

## E3: Personal wine cellar

Mark wines tried/want-to-try. Requires user identity model not present in v2.

---

## E5: Purchase links

Vivino + Wine.com deep links per wine detail view.

---

## E6: Card sharing

Share wine card via iOS share sheet / AirDrop.

---

## WineObject schema sync enforcement

`shared/wine-schema.json` as single source of truth + CI check that fails on
drift between Swift/Python/TypeScript definitions. Currently documented in
`CONTRIBUTING.md` as a manual discipline.

---

## iOS reconnect behavior on long scans

SSE connection stays open 2-3.5 min. If connection drops mid-Phase 2 (notes),
client silently stops receiving notes with no "incomplete" indicator. Add
reconnect logic or at minimum show "notes may be incomplete" in WineDetailView
when the stream closed before all notes arrived.
