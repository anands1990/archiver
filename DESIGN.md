# Archiver — Design System

The single source of truth for how Archiver looks and feels. Any UI change
should be checkable against this document.

## The one thing to remember

> **A quiet, trustworthy librarian.**

The app does patient, long, unattended work on other people's books. It should
feel calm and precise, never busy. Every decision below serves that.

**Corollary:** Archiver's own chrome must never compete with the content it
handles. When a book is uploading, the most important thing on screen is the
book, not the progress bar.

## Aesthetic: native invisibility

Archiver is a Mac app and should read as one. Nothing custom where a system
value exists. The user should never notice the interface — only the books
moving through it.

SAFE choices (category baseline — these are what make it look like a Mac app):

- **SF Pro via semantic text styles**, never hardcoded sizes
- **System accent colour** (`Color.accentColor`) for interactive controls, so
  the app respects whatever accent the user picked in System Settings
- **Semantic system colours** for all status (green = done, red = failed), which
  adapt to light, dark, and increased contrast
- **System materials** rather than hand-painted surfaces

DELIBERATE DEPARTURES (where Archiver gets its own face, within the native
vocabulary):

- **Monochrome chrome.** Secondary text, borders and dividers are neutral; the
  only saturated colour in the app is the system accent on primary actions and
  system green/red on status. A menu-bar panel with a colourful personality is
  a panel you notice.
- **Density, not air.** A 380pt-wide panel that pads like an iPad app wastes
  the space. Archiver uses tighter margins (16pt) and row spacing (8pt) than a
  windowed app, because it is a panel that should get out of the way.

## Typography

Apple's macOS scale: **13pt body**, smallest recommended size **10pt**.
Mac does not support Dynamic Type, so semantic styles are still the right call
— weights and leading come from the system instead of being reinvented.

| Role | Style | Size/weight | Used for |
|---|---|---|---|
| Panel title | `.headline` | 13pt semibold | Header, settings section titles |
| Body | `.body` | 13pt regular | Task titles, field labels |
| Callout | `.callout` | 12pt regular | Secondary descriptions |
| Footnote | `.footnote` | 11pt regular | Row messages, status text, settings values |
| Caption | `.caption` | 10pt regular | Notes, help text, model guidance |

**Rules**
- Never below `.caption` (10pt). 9pt is a bug, not a style.
- Use `.footnote(design: .monospaced)` for paths and model names, so they read
  as machine values.
- No `textCase(.uppercase)` on tiny text — the cap height of 9–10pt uppercase
  is where the "shouting tiny label" look comes from. Section headers use
  `.headline` with normal case instead.

## Colour

Zero hardcoded colour. Everything resolves through the system so it adapts to
light, dark, reduced transparency, and increased contrast.

| Token | Value | Use |
|---|---|---|
| `AppTheme.background` | `Color(NSColor.controlBackgroundColor)` | Panel backdrop |
| `AppTheme.surface` | `background` | Card fills (elevation via borders, not fills) |
| `AppTheme.accent` | **`Color.accentColor`** | Primary actions, active state |
| `AppTheme.subtleBorder` | `Color.secondary.opacity(0.08)` | Card edges |
| `AppTheme.celebrate` | **`Color.green`** | Completion, success |
| `AppTheme.danger` | **`Color.red`** | Failures |

**Rules**
- One saturated control per context: the default action. Everything else neutral.
- Destructive actions red only when they destroy data.
- Status colours are semantic (`Color.green` / `Color.red`), never custom hex.

## Spacing

8pt grid. Margins 16pt (panel context — tighter than a windowed app's 20pt),
8pt between related controls, 16pt between groups.

| Token | Value |
|---|---|
| `Spacing.gutter` | 16pt |
| `Spacing.group` | 16pt |
| `Spacing.row` | 8pt |
| `Spacing.tight` | 4pt |

## Motion

Everything the user *does* gets an immediate response; nothing loops.

| Token | Value | Use |
|---|---|---|
| `Motion.quick` | snappy 120ms, no bounce | Press feedback |
| `Motion.standard` | ease-out 180ms | Panel swaps, cards appearing |
| `Motion.settle` | spring 300ms, bounce 0.22 | Row insertion |
| `Motion.pop` | spring 400ms, bounce 0.42 | Completion acknowledgement |

**Rules**
- No animation that runs forever. A repeating animation keeps re-rendering the
  window while the panel is open, which measured at ~100% of a CPU core and
  starved the main thread until the panel lost keyboard focus.
- Value-triggered animations only (`.animation(_, value:)`).
- Exits faster than enters; easing is always ease-out or a spring, never ease-in.
- All motion is skipped under Reduce Motion.

## Component specs

| Component | Spec |
|---|---|
| Panel | 380 × 460pt, 16pt gutters, 8pt row spacing |
| Task row | 8pt radius card, 1pt border, 12pt inner padding, 10pt gap |
| Progress bar | 6pt capsule; shimmer is a one-shot on appear, never looping |
| Buttons | Regular control size, press scale 0.96 at 120ms |
| Settings field | Label left (monospaced footnote), value right-aligned |

## Pre-landing checklist

- [ ] No font size below 10pt anywhere
- [ ] No hardcoded colour — grep `Color(red:` / `Color(white:`. The single
      exception is the progress shimmer's `.white.opacity(0.55)` highlight,
      which sits *on top of* the accent fill, so it must be light in both
      appearances
- [ ] No `repeatForever`
- [ ] Accent uses `Color.accentColor`, not `labelColor`
- [ ] All motion value-triggered
- [ ] Reads correctly in light and dark
- [ ] Idle CPU at 0%
