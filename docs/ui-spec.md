# UI Specification (Dark Theme)

## Visual Direction

HelioPulse uses a dark, layered cockpit aesthetic with strong metric focus.
The visual hierarchy is metric-first, chart-second, metadata-third.

## Core Screens

### 1) Live Cockpit

- hero metric at top: current solar input power
- two-row KPI grid: battery voltage, load current, charge stage, modeled SOC
- confidence card: accuracy state and alternator mode impact

### 2) Trends

- 24h primary line + area chart for solar input
- optional overlays for battery flow and load
- compact legend with color-coded semantic mapping

### 3) Forecast

- big runtime card
- scenario cards for conservative, realistic, optimistic
- confidence callout for drive-mode periods

## Chart Rules

- avoid hard, neon-thin lines on dark backgrounds
- use smooth interpolation for readability
- include subtle glow and soft area fill for depth
- keep axis labels low-contrast but readable
- never hide critical warning markers

## Motion Rules

- page reveal: 260ms ease-out
- KPI number transition: 220ms content transition
- chart range switch: 180ms fade + subtle slide
- no infinite decorative animation

## Accessibility

- minimum contrast target around WCAG AA for key text and controls
- large numeric typography for glance readability in bright daylight
- avoid relying on color alone for warnings; include text badge

## Theme Tokens

See design tokens in docs/design-system.md.
