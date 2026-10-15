---
name: Nova Toll
description: A warm map-led express-lane trip planner
colors:
  ink: "#172b45"
  muted: "#536477"
  paper: "#f3f0e8"
  white: "#fffefa"
  line: "#d7dddF"
  coral: "#be4a35"
  coral-hover: "#a33b2b"
  teal: "#136b6c"
  tint: "#e6efec"
  focus: "#ad422f"
  control-line: "#adb8bf"
  control-hover: "#e7eeeb"
  tabs-surface: "#e6e5df"
  notice-surface: "#f6e8d5"
  notice-ink: "#6a4717"
typography:
  body:
    fontFamily: "DM, Arial, sans-serif"
    fontSize: "16px"
    lineHeight: 1.5
  display:
    fontFamily: "Manrope, DM, sans-serif"
    fontSize: "clamp(26px, 3vw, 38px)"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Manrope, DM, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    letterSpacing: "-0.02em"
  amount:
    fontFamily: "Manrope, DM, sans-serif"
    fontSize: "clamp(40px, 6vw, 66px)"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.04em"
  label:
    fontFamily: "DM, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 600
rounded:
  control: "7px"
  tab-track: "10px"
  panel: "12px"
  map: "14px"
spacing:
  tight: "8px"
  control-block: "11px"
  control-inline: "14px"
  panel: "28px"
  columns: "36px"
components:
  button-primary:
    backgroundColor: "{colors.coral}"
    textColor: "{colors.white}"
    rounded: "{rounded.control}"
    padding: "11px 14px"
  button-secondary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    rounded: "{rounded.control}"
    padding: "11px 14px"
  field:
    backgroundColor: "{colors.white}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "11px 14px"
  form-panel:
    backgroundColor: "{colors.white}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    padding: "28px"
  tab-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    rounded: "{rounded.control}"
    padding: "10px 24px"
---

# Design System: Nova Toll

## Overview

**Creative North Star: "Plan your passage"**

A warm paper interface frames a supplied regional map and a focused trip-planning sequence. Navy establishes structure, coral marks the destination and forward actions, and teal supports links and status. Three exclusive panels keep map selection, manual setup, and price review distinct.

**Key Characteristics:**
- Warm paper, navy structure, coral actions, and teal supporting accents.
- Self-hosted DM Sans body and Manrope bold headings and amounts.
- A full image map with approximate interactive ramp overlays.
- Separate route selection and price review surfaces.

## Colors

### Primary
Navy ink anchors headings, selected tabs, entry A markers, and secondary actions. Coral identifies destination B and primary progress actions. Teal supports links and the small operator-pricing status dot.

### Neutral
Warm paper surrounds off-white bordered surfaces. Muted blue-gray text carries hints, timestamps, and supporting information. Thin pale borders organize controls, trip summaries, and component legs.

### Secondary
Warm parchment notices carry brown explanatory text. Focus uses a warm red outline.

**The Qualified Status Rule.** Pair every coverage or freshness condition with explicit readable text.

## Typography

DM Sans regular is self-hosted as the CSS family `DM` in `/assets/body.ttf`. Manrope bold is self-hosted in `/assets/display.ttf` and used for headings, brand, and amounts. Font display swaps preserve readable fallbacks. No previous system-display defect is inherited by this implementation.

The hero uses the display role, section headings the title role, and smaller headings 17px. Route names use 19px and wrap long names. Supporting copy uses 13px. Amounts use tabular numerals; unavailable totals reduce to 32px. On mobile the amount is 48px.

**The Price Truth Rule.** Give full totals and incomplete or unavailable states distinct text; a known subtotal never masquerades as the complete amount.

## Layout

The top bar and main container center within 1320px. Desktop main padding is 30px 28px 48px. Map is a full-width primary surface. Manual and results panels use a flexible main column plus a 340px supporting column with a 36px gap. Only the active tab panel is visible.

At 800px and below, main padding becomes 24px 16px 36px; tabs fill available width and hide their numeric prefixes. Manual and results columns stack with a 20px gap. Panel padding reduces to 22px. Map tools and bottom actions stack, and primary progress actions expand to full width. The form retains two columns with designated full-width entry and exit fields.

Desktop map height is the smaller of 72svh and 760px, with a 430px minimum. Mobile height is 61svh with a 390px minimum. These minimums can exceed short viewports; they describe the implementation rather than a promise that the map always fits on screen.

## Elevation & Depth

Borders and tonal surfaces carry most structure. Search results use a soft navy-tinted dropdown shadow; map zoom controls have a smaller soft shadow. The artwork remains a distinct clipped image plane. Focus uses a three-pixel outline with three-pixel offset.

**The Local Elevation Rule.** Reserve shadows for floating search results and map controls.

## Shapes

Controls use gently curved corners; tabs and selection panels use slightly larger corners, ordinary panels larger again, and the map the largest. A/B markers and the brand compass use circular geometry. Keep background art clipped to the map frame.

## Components

### Navigation
Map, Manual / GPS, and Toll estimate form an exclusive accessible tab set. The selected tab uses navy with white text on a muted track. Keyboard selection, selected state, and panel relationships stay synchronized. Tab transitions and a subtle four-pixel panel arrival are enabled only without reduced-motion preference.

### Buttons and Fields
Primary actions are coral with a darker hover; secondary actions are navy with a lighter navy hover. Ordinary controls are off-white with a thin gray border and a 46px minimum height. Disabled controls use 0.55 opacity. Labeled native selects retain recognizable behavior. Keyboard focus remains visible.

### Trip Summary
A bordered two-stop strip shows entry A in navy and exit B in coral. Each stop can return selection to that stage; clear trip is a quieter action. Long names wrap. Mobile preserves two stop columns and moves clear below them.

### Image Map and Ramp Dots
Use the user-supplied full map image without substituting a metro diagram. Preserve the visible not-to-scale, approximate-position, and historical-artwork context. Dots are hand-calibrated to drawn roads, not geographic survey points. Default usable dots are off-white with navy outlines; unavailable choices are gray. Selected A uses navy and B coral, with white letters and outlines. Marker hit areas and selected-marker dimensions remain screen-sized under zoom. Nearby ambiguous taps reveal an explicit choice list.

Pan and pinch manipulate a bounded transform viewport; dragging does not select markers. Full map fits the artwork. Keyboard and modifier-wheel controls supplement touch. Search results float above the image. Keep map controls pinned at top right and credit at bottom left. The image's historical status labels must never acquire live-status styling or authority.

### Results and Saved Trips
A separate estimate panel emphasizes one trip and one amount, followed by qualification, component legs, fetch and rate timestamps, and actions. Partial totals identify a known subtotal in supporting text. Common trips appear in the adjacent column or below on mobile with load and delete actions. Empty results explain the next step.

## Do's and Don'ts

### Do:
- **Do** preserve exclusive task panels and labeled native route controls.
- **Do** pair every amount with source, freshness, and completeness context.
- **Do** preserve supplied-map provenance and approximate-position language.
- **Do** keep keyboard focus and non-touch map controls available.

### Don't:
- **Don't** present historical image annotations as current road status.
- **Don't** present image-calibrated dots as surveyed navigation coordinates.
- **Don't** show a known subtotal as a complete trip price.
- **Don't** claim browser visual or device gesture verification from source inspection.
