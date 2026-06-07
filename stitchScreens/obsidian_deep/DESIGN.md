---
name: Obsidian Deep
colors:
  surface: '#10141a'
  surface-dim: '#10141a'
  surface-bright: '#353940'
  surface-container-lowest: '#0a0e14'
  surface-container-low: '#181c22'
  surface-container: '#1c2026'
  surface-container-high: '#262a31'
  surface-container-highest: '#31353c'
  on-surface: '#dfe2eb'
  on-surface-variant: '#c0c7d4'
  inverse-surface: '#dfe2eb'
  inverse-on-surface: '#2d3137'
  outline: '#8b919d'
  outline-variant: '#414752'
  surface-tint: '#a2c9ff'
  primary: '#a2c9ff'
  on-primary: '#00315c'
  primary-container: '#58a6ff'
  on-primary-container: '#003a6b'
  inverse-primary: '#0060aa'
  secondary: '#67df70'
  on-secondary: '#00390d'
  secondary-container: '#27a640'
  on-secondary-container: '#00320a'
  tertiary: '#d5bbff'
  on-tertiary: '#41008b'
  tertiary-container: '#b88eff'
  on-tertiary-container: '#4c069d'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#d3e4ff'
  primary-fixed-dim: '#a2c9ff'
  on-primary-fixed: '#001c38'
  on-primary-fixed-variant: '#004882'
  secondary-fixed: '#83fc89'
  secondary-fixed-dim: '#67df70'
  on-secondary-fixed: '#002105'
  on-secondary-fixed-variant: '#005317'
  tertiary-fixed: '#ecdcff'
  tertiary-fixed-dim: '#d5bbff'
  on-tertiary-fixed: '#270058'
  on-tertiary-fixed-variant: '#5a21ab'
  background: '#10141a'
  on-background: '#dfe2eb'
  surface-variant: '#31353c'
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-mono-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
  label-mono-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 26px
    fontWeight: '600'
    lineHeight: 32px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 16px
  margin-mobile: 16px
  margin-desktop: 48px
---

## Brand & Style

This design system centers on a **Corporate / Modern** aesthetic with a heavy emphasis on developer-centric precision and visual comfort. It is designed for technical professionals who require high information density without the ocular fatigue associated with pure black backgrounds or high-vibrancy "hacker" interfaces.

The brand personality is **reliable, focused, and sophisticated**. It treats infrastructure management as a premium experience, utilizing soft-layered depth and subtle color transitions to guide the eye. By moving away from aggressive neon accents toward a palette of muted teals and slate blues, the UI maintains a "pro" tool feel while feeling approachable and calm.

## Colors

The palette is anchored in a **Deep Navy/Charcoal** spectrum rather than pure black (#000000). This reduces contrast-induced flickering and allows for more effective use of tonal layering.

- **Primary & Accents:** We use muted blues and teals. These are desaturated to ensure they don't "vibrate" against the dark backgrounds.
- **Surface Tiers:** Depth is communicated through color, not just shadows. Surfaces "rise" toward the user by becoming progressively lighter (Deep -> Surface -> Container).
- **Functional Colors:** Error and warning states should avoid high-saturation reds, opting instead for coral or soft amber to maintain the soothing visual profile.

## Typography

This design system employs a dual-font strategy to balance legibility with technical utility.

- **UI & Interface (Inter):** All navigational elements, buttons, and standard body text use Inter. It provides a clean, neutral canvas that remains legible at small sizes.
- **Technical Data (JetBrains Mono):** Any content representing code, IP addresses, server logs, or system metrics is set in JetBrains Mono. This monospaced font provides the necessary character distinction for technical accuracy (e.g., distinguishing `0` from `O`).

Weight is used sparingly to denote hierarchy, preferring size and color shifts (Primary vs. Secondary text) to maintain a refined look.

## Layout & Spacing

The layout follows a **Fluid Grid** model with a consistent 4px baseline. 

- **Mobile:** Uses a single-column layout with 16px side margins. Elements like cards span the full width minus margins.
- **Desktop/Tablet:** Transitions to a 12-column grid. Technical dashboards may use a sidebar-main configuration where the sidebar is fixed (280px) and the main content area is fluid.
- **Rhythm:** Vertical spacing between cards or logical groups should stick to 16px (md) or 24px (lg) to ensure the interface feels airy and organized despite the high density of data.

## Elevation & Depth

Visual hierarchy is established through **Tonal Layers** supplemented by **Low-contrast outlines**.

1.  **Level 0 (Base):** The `background_deep` color (#0D1117).
2.  **Level 1 (Cards/Sidebar):** The `background_surface` color (#161B22). These elements should have a subtle 1px border using a slightly lighter stroke (#30363D) to define edges.
3.  **Level 2 (Popovers/Modals):** The `background_container` color (#21262D). These use a soft ambient shadow (0px 8px 24px rgba(0,0,0,0.5)) to appear elevated.

Avoid high-glow effects. Depth should feel physical and architectural, like stacked sheets of dark slate.

## Shapes

The shape language is **Rounded**, providing a friendlier, more modern feel that softens the "cold" nature of technical data. 

- **Primary Containers:** Standard cards and input fields use a 0.5rem (8px) corner radius.
- **Interactive Elements:** Buttons and tags may scale up to 1rem (16px) for a "pill" appearance in specific contexts (like status indicators) to distinguish them from structural containers.
- **Icon Enclosures:** Small status icons or avatars should use the `rounded-lg` (1rem) setting to create a circular or near-circular frame.

## Components

### Buttons
- **Primary:** Solid `primary_color` (muted blue) with `text_primary` or a dark variant.
- **Secondary:** Ghost style with `accent_blue` borders and text.
- **Ghost/Tertiary:** No border, `text_secondary` which shifts to `text_primary` on hover.

### Cards & Lists
- Cards should have a flat `background_surface` and a subtle 1px border. No shadows for standard list items; reserve shadows for active or dragged states.
- List items use `body-md` for titles and `label-mono-sm` for metadata tags.

### Inputs
- Fields use `background_deep` for the inner area to create an "etched" look into the `background_surface` cards. 
- Focus states should use a 2px `primary_color` border with a very faint outer glow.

### Technical Chips
- Status indicators (e.g., "Online", "SSH") use small, rounded-pill shapes with low-opacity background tints of their functional color (e.g., 15% opacity Teal for "Online").

### Terminal View
- Dedicated container using `background_deep`. All text inside must be `label-mono-sm`. Use the `accent_teal` for success messages and `accent_blue` for links or commands.