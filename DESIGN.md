---
name: Medicyn
description: The Bedside Chart — a warm, kraft-and-linen Material 3 world where every screen reads as a chart clipped at someone's bedside, not a hospital monitor.
colors:
  primary: "#00685F"
  primary-container: "#008378"
  on-primary-container: "#F4FFFC"
  primary-fixed-dim: "#6BD8CB"
  secondary: "#55615F"
  secondary-container: "#D8E5E2"
  on-secondary-container: "#5B6765"
  tertiary: "#4648D4"
  tertiary-container: "#6063EE"
  surface: "#F3ECDB"
  on-surface: "#2B2318"
  on-surface-variant: "#5C4F3B"
  outline: "#8A7A5E"
  outline-variant: "#D9CBAA"
  error: "#BA1A1A"
  error-container: "#FFDAD6"
  surface-container-lowest: "#FBF7EC"
  surface-container-low: "#F6F0E1"
  surface-container: "#EDE4CE"
  surface-container-high: "#E6DBC1"
  surface-container-highest: "#DED1B0"
  chart-grid-line: "#142B2318"
  paper-grain: "#E6D9B8"
  status-pending: "#3D6FA8"
typography:
  display:
    fontFamily: "Public Sans, Roboto, sans-serif"
    fontSize: "40px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.4px"
  headline:
    fontFamily: "Public Sans, Roboto, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.33
  title:
    fontFamily: "Public Sans, Roboto, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.375
  body:
    fontFamily: "Public Sans, Roboto, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Public Sans, Roboto, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.43
    letterSpacing: "0.1px"
  chart-heading:
    fontFamily: "Public Sans, Roboto, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    fontStyle: "italic"
    letterSpacing: "0.4px"
rounded:
  sm: "12px"
  md: "16px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "20px"
  xl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.pill}"
    padding: "16px 24px"
    height: "56px"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.primary}"
    rounded: "{rounded.sm}"
    padding: "16px 24px"
    height: "56px"
  card-ambient:
    backgroundColor: "{colors.surface-container-lowest}"
    rounded: "{rounded.sm}"
    padding: "16px"
  chip:
    backgroundColor: "{colors.secondary-container}"
    textColor: "{colors.on-secondary-container}"
    rounded: "{rounded.pill}"
    padding: "8px 12px"
---

# Design System: Medicyn

## Overview

**Creative North Star: "The Bedside Chart"**

Medicyn reads as a chart clipped at someone's bedside — the object a
competent visiting nurse leaves behind, not a monitor beeping in a hospital
room. The ground shifted from the previous "Clinical Calm" system's clinical
white to a warm linen/kraft paper; cards are pages that visibly sit above
that ground, not the same material as it. Teal (`#00685F`) is carried over
unchanged from Clinical Calm as the one brand/confirming accent — a
deliberate continuity, not an oversight — but it now does its work against
warmth instead of clinical neutrality.

The system's one genuinely new structural idea is that **status is never
color alone.** Every dose status — Taken, Due, Snoozed, Missed, Not
recorded — carries its own persistent glyph mark (check / dash / ring /
triangle / ellipsis) paired with its color, echoing the way a real chart
uses a distinct symbol per entry rather than trusting ink color under a
bedside lamp. A faint, always-present ruled time-grid sits behind Today's
list — the "graticule" the eye locates against — and every dose row carries
a permanent colored tab on its leading edge, the chart's margin mark for
that entry.

Depth grew more present than Clinical Calm's flat baseline: the system's
one recurring shadow — warm ink-tinted now, not teal-tinted — reads with
more presence at rest, and cards visibly *lift* (a deeper, wider shadow)
the instant a finger touches them, on top of the inherited 2% press-scale.
Public Sans remains the only type family in the system; where a heading
wants to read as hand-marked rather than printed, it leans on italic plus a
short uneven underline stroke rather than a second face the bundled
typeface doesn't have.

**Key Characteristics:**
- Warm linen/kraft ground; cards are lighter "paper" sitting above it
- Teal stays the one brand/confirming color, inherited from Clinical Calm
- Every status = one color **and** one persistent glyph, never color alone
- A faint ruled time-grid behind Today; a colored margin tab on every dose row
- One warm-ink shadow at rest, a deeper "lift" shadow on active press
- Motion stays short (150–400ms) and fully honors reduced motion

## Colors

A warm linen-and-kraft palette built around the inherited teal accent, with
status color kept to a closed, non-reusable five-color set.

### Primary
- **Clinical Teal** (`#00685F`): brand mark, primary buttons, the FAB,
  active nav state, focus rings, and the "Taken" dose status — unchanged
  from Clinical Calm on purpose; the world around it changed, not the
  brand color itself.
- **Deep Teal** (`#008378` / `primaryContainer`): the fixed, brighter
  container tone Material derives filled selections from.
- **Seafoam** (`#6BD8CB` / `primaryFixedDim`): the accent that survives
  into dark mode (dark mode is unchanged from Clinical Calm — it still
  derives from `ColorScheme.fromSeed(primary)` rather than adopting the
  warm palette).

### Secondary
- **Slate Sage** (`#55615F`): secondary text/icon accents.
- **Pale Sage** (`#D8E5E2` / `secondaryContainer`): the selected bottom-nav
  pill and the round icon backdrop on profile menu rows.

### Tertiary
- **Indigo Alert** (`#4648D4`): reserved for exactly one job, the
  "Snoozed" dose status — paired with its ring glyph.

### Neutral
- **Linen Ground** (`#F3ECDB` / `surface`): the app background — warmer
  and a step darker than the cards floating on it, on purpose.
- **Chart Paper** (`#FBF7EC` / `surfaceContainerLowest`): card, input, and
  dialog fill — the lightest step, reading as a page above the ground.
- **Kraft Nav** (`#EDE4CE` / `surfaceContainer`): bottom navigation fill.
- **Warm Ink** (`#2B2318` / `onSurface`): primary text.
- **Muted Umber** (`#5C4F3B` / `onSurfaceVariant`): secondary text.
- **Warm Outline** (`#8A7A5E` / `outline`): default borders, inactive
  icons, and the "Not recorded" dose status.
- **Pale Kraft** (`#D9CBAA` / `outlineVariant`): low-contrast divider
  weight on outlined buttons and card borders.
- **Clinical Red** (`#BA1A1A` / `error`): Missed doses and destructive
  actions only.
- **Due Blue** (`#3D6FA8`): status-only, outside the Material role set —
  used solely for Pending/Due, paired with its dash glyph.
- **Grid Ink** (`chartGridLine`, warm ink at ~8% alpha): the ruled lines
  behind Today — ink at low alpha, not a separate hue, so it always reads
  as "the same ink, fainter."
- **Paper Grain** (`#E6D9B8`): the sparse fleck texture on the linen
  ground.

### Named Rules
**The Single Accent Rule** *(inherited from Clinical Calm)*. Teal is the
only color allowed to mean "brand" or "this succeeded." Taken is teal,
never a stock green.

**The Status-Has-a-Shape Rule** *(new)*. Every dose status carries its own
persistent glyph — check (Taken), dash (Due), ring (Snoozed), triangle
(Missed), ellipsis (Not recorded) — paired with its color everywhere the
status appears (the day list, the calendar dots, the dose feed, dose
history). Color alone is never the only signal; a status shown without its
glyph is an incomplete implementation, not a simplification.

## Typography

**Display Font:** Public Sans (Roboto, then system sans-serif, as fallback)
**Body Font:** Public Sans
**Chart-heading treatment:** Public Sans, italic, with a short hand-drawn
underline stroke beneath (see `ChartHandLetteredText` in
`core/widgets/chart_grid.dart`)

**Character:** Unchanged from Clinical Calm — one family carries the whole
hierarchy through weight and size. The one addition is a second, italic
*treatment* of the existing face (not a new face) reserved for the single
heading per screen that plays the chart's "hand-marked annotation" role —
Today and the day-list's date heading.

### Hierarchy
Unchanged from Clinical Calm: Display (700, 40px/48px, −0.4px) for hero
numbers; Headline (600–700, 22–28px) for screen/section titles; Title
(600, 16–20px) for card headers; Body (400, 14–16px) for reading text,
`bodySmall` in Muted Umber for de-emphasis; Label (600, 11–14px, tracked
out) for buttons/chips/nav.

### Named Rules
**The Phone-Size Rule** *(inherited)*. Sizes are tuned for a real handset
at 100%; bigger text is the Settings Appearance slider's job, not a
baseline bump.

**The One Annotation Rule** *(new)*. The italic hand-marked treatment is
reserved for exactly one heading role (the day-chart date heading) per
screen. It never spreads to body text, buttons, or more than one heading
at a time — its rarity is what makes it read as an annotation rather than
a font choice.

## Layout

Unchanged from Clinical Calm: `MedicynContent` caps page width at 640px
(tablets only; phones unaffected), 8px base spacing rhythm,
`VisualDensity.comfortable` globally. Top bar fixed at 64px, bottom nav
fixed at 72px with four destinations (Today, Plan, Insights, Profile).

**New:** Today (and Care) render inside `ChartPaperTexture` +
`ChartRuleLines` (`core/widgets/chart_grid.dart`) — a sparse, fixed-seed
paper-grain layer and a faint horizontal rule grid (96px pitch) painted
once behind the scrollable content.

## Elevation & Depth

Hybrid, more present than Clinical Calm at rest: `CardTheme`,
`AppBarTheme`, and `NavigationBarTheme` stay elevation 0 — tonal layering
(the `surfaceContainer*` ramp) still does most of the separation — but the
system's one recurring shadow now reads with real weight, and cards
actively **lift** on press.

### Shadow Vocabulary
- **Ambient Ink** (`0 6px 16px rgba(43, 35, 24, 0.10)` —
  `MedicynTheme.ambientShadow`): the system's one shadow at rest. Used on
  `AmbientCard`, dose rows, and (inverted) under the bottom nav. Retuned
  from Clinical Calm's teal-tinted, lighter version — warm ink now, and
  noticeably deeper.
- **Lifted Ink** (`0 10px 24px rgba(43, 35, 24, 0.15)` —
  `MedicynTheme.liftedShadow`): new. Plays only while a tappable
  `AmbientCard` is actively pressed, so touch reads as physically picking
  the page up before the tap registers. Skipped entirely under reduced
  motion.
- **Top-bar hairline** *(inherited, unchanged)*: neutral, near-invisible,
  structural rather than brand.
- **FAB** *(inherited)*: elevation 2, the system's single most-elevated
  element.

### Named Rules
**The One Shadow Rule** *(inherited, retuned)*. Ambient Ink is still the
only shadow a component gets at rest. Lifted Ink is not a second free
shadow — it exists only as the transient response to an active press.

## Shapes

Unchanged from Clinical Calm: content containers (cards, dialogs, inputs)
get 12–16px rounded rectangles; anything tappable-as-an-action (filled
buttons, FAB, chips) gets a full `StadiumBorder` pill. Circles are
reserved for avatars/icon badges.

### Named Rules
**The Two-Radius Rule** *(inherited)*. Pill for actions, 12–16px rounded
rectangle for containers. Nothing square-cornered or fully sharp.

## Components

### Buttons, Chips, Inputs
Unchanged from Clinical Calm in shape and sizing (56px filled/outlined,
48×48 text-button minimum, pill chips with no checkmark glyph, 16px
rounded filled inputs). Colors now resolve through the warm palette
automatically via `ColorScheme`.

### Cards / Containers — `AmbientCard`
The signature container, now interaction-aware:
- **Corner Style:** 12px rounded rectangle (unchanged).
- **Background:** Chart Paper (`surfaceContainerLowest`) by default.
- **Shadow Strategy:** Ambient Ink at rest; animates to Lifted Ink for the
  duration of an active press (`AnimatedContainer`, `MedicynMotion.fast`).
- **Border:** optional status accent, unchanged mechanism.
- **Internal Padding:** 16px (unchanged).

### Dose Row — `_DayDoseRow` (`reminders_home/day_dose_list.dart`)
The flagship "chart entry." New in this system:
- **Leading margin tab:** a permanent 4px colored bar on the row's leading
  edge in the row's status color — the chart's margin mark for that entry,
  present on every row regardless of whether it needs attention.
- **Soft full outline:** unchanged mechanism (rows still needing a
  response — Due/Snoozed — get a full, low-alpha outline in the status
  color), now sourced from `DayDoseStyle.color` per-status instead of a
  fixed teal.
- **Status avatar:** a ring (or filled circle for Taken) in the status
  color holding its glyph (`DayDoseStyle.glyph`), popping in with a slight
  overshoot (`Curves.easeOutBack`) whenever the status changes — most
  visibly right after a dose is marked Taken.
- **Entrance:** rows within a day fade+rise in with a small stagger (30ms
  per row, capped at 6), so a day's chart settles onto the page rather
  than appearing all at once.

### Chart Grid, Paper Texture — `core/widgets/chart_grid.dart`
Two structural/decorative primitives:
- **`ChartRuleLines`**: faint horizontal rules (Grid Ink, 96px pitch)
  behind Today's scrollable content.
- **`ChartPaperTexture`**: a sparse, fixed-seed fleck field (Paper Grain)
  giving the linen ground material texture without a bundled image asset.

### Chart Date Heading — `ChartHandLetteredText`
The day-list's date heading (e.g. "Today, Wed 3 September"): Public Sans
italic plus a short, gently uneven underline stroke in the row's ink
color at low alpha, standing in for a script face the bundled family
doesn't have. See The One Annotation Rule.

### Navigation, Progress Ring, Profile Menu Row
Unchanged in structure and behavior from Clinical Calm; colors resolve
through the warm palette.

## Do's and Don'ts

### Do:
- **Do** keep Clinical Teal as the only "brand/confirmed" color — it
  survives every future revision of this system unless a user explicitly
  changes it.
- **Do** give every dose/task status both a color *and* a glyph from the
  fixed five-mark set; never ship a status with color alone.
- **Do** reuse `MedicynTheme.ambientShadow` / `liftedShadow` exactly as
  defined rather than inventing a new shadow value per component.
- **Do** route new date/section "annotation" headings through
  `ChartHandLetteredText` rather than hand-rolling italic+underline
  inline — and keep it to one such heading per screen.
- **Do** cap page content at 640px via `MedicynContent`.

### Don't:
- **Don't** reuse Indigo Alert or Due Blue for anything other than
  Snoozed and Pending respectively, and don't add a sixth status color.
- **Don't** add a shadow anywhere beyond Ambient Ink at rest / Lifted Ink
  on press — no decorative drop shadows on flat surfaces.
- **Don't** apply the italic chart-heading treatment to more than one
  heading per screen, or to body text, buttons, or labels.
- **Don't** override the system/app text-scale value with a fixed pixel
  size anywhere — the known gap at `app/lib/main.dart:104-107` (tracked in
  PRODUCT.md's Accessibility section) is a bug, not a pattern to extend.
- **Don't** port Cupertino-style components into shared code paths — the
  platform split stays at the page-transition level.
