---
name: Obsidian Mint
colors:
  surface: '#111416'
  surface-dim: '#111416'
  surface-bright: '#37393c'
  surface-container-lowest: '#0c0f11'
  surface-container-low: '#191c1e'
  surface-container: '#1d2022'
  surface-container-high: '#272a2c'
  surface-container-highest: '#323537'
  on-surface: '#e1e2e5'
  on-surface-variant: '#bccabf'
  inverse-surface: '#e1e2e5'
  inverse-on-surface: '#2e3133'
  outline: '#86948a'
  outline-variant: '#3d4a41'
  surface-tint: '#53de9e'
  primary: '#53de9e'
  on-primary: '#003822'
  primary-container: '#00b074'
  on-primary-container: '#003a23'
  inverse-primary: '#006c46'
  secondary: '#c2c7cc'
  on-secondary: '#2c3135'
  secondary-container: '#42474c'
  on-secondary-container: '#b1b6bb'
  tertiary: '#ffb3b1'
  on-tertiary: '#650714'
  tertiary-container: '#f27374'
  on-tertiary-container: '#680a16'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#73fbb8'
  primary-fixed-dim: '#53de9e'
  on-primary-fixed: '#002112'
  on-primary-fixed-variant: '#005233'
  secondary-fixed: '#dfe3e8'
  secondary-fixed-dim: '#c2c7cc'
  on-secondary-fixed: '#171c20'
  on-secondary-fixed-variant: '#42474c'
  tertiary-fixed: '#ffdad8'
  tertiary-fixed-dim: '#ffb3b1'
  on-tertiary-fixed: '#410007'
  on-tertiary-fixed-variant: '#852128'
  background: '#111416'
  on-background: '#e1e2e5'
  surface-variant: '#323537'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-base:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base-unit: 8px
  padding-standard: 16px
  padding-tight: 8px
  padding-wide: 24px
  gutter: 16px
  margin-mobile: 16px
  margin-desktop: 32px
---

## Brand & Style

The design system is anchored in a philosophy of **Tactile Minimalism**. It targets high-end users who value privacy, precision, and a focused communication environment. The aesthetic is "Dark-Mode First," drawing inspiration from modern mobile operating systems that prioritize content through depth and subtle luminosity rather than excessive color.

The emotional response should be one of **sophisticated security**. By utilizing a deep, obsidian-based palette and a singular, vibrant mint accent, the UI feels both biologically calm and technologically advanced. The design style leans into **Glassmorphism** for overlays and **Tonal Layering** for structural depth, ensuring the interface feels like a physical object carved from dark glass.

## Colors

This design system utilizes a high-contrast, limited palette to maintain a premium feel. 

- **Primary (Emerald Mint):** Reserved strictly for action-oriented states, unread indicators, and active selection markers. It serves as the "heartbeat" of the interface.
- **Base (Obsidian Black):** The #0F1214 background provides a pure, non-distracting canvas that minimizes eye strain and maximizes OLED efficiency.
- **Surface (Elevated Grey):** #1A1F23 is used for sidebars, input containers, and message bubbles to create a clear visual hierarchy against the base.
- **Status Colors:** Use a muted Red (#EF4444) for destructive actions and a soft Amber (#F59E0B) for warnings, ensuring they do not overpower the Primary Emerald.

## Typography

The typography system relies on **Inter** for its exceptional legibility in low-light environments. The scale is built on a tight ratio to ensure information density remains high without feeling cluttered.

- **Headlines:** Use tighter letter spacing and semi-bold weights to anchor views like "Settings" or "Contact Info."
- **Message Text:** Set at `body-base` for primary chat bubbles to ensure maximum readability.
- **Meta-data:** Timestamps and "Read" receipts use `label-md` in secondary text colors.
- **Navigational Labels:** Use `label-caps` for section headers in the sidebar to create clear categorical breaks.

## Layout & Spacing

The layout is governed by a **strict 8px grid system**. This ensures all components—from avatars to message bubbles—align perfectly.

- **Chat Feed:** Mobile views utilize full-width layouts with 16px horizontal margins. Desktop views transition to a three-pane fixed-fluid layout: a 280px fixed sidebar, a flexible chat thread, and an optional 320px fixed info panel.
- **Interaction Zones:** Tap targets must be a minimum of 44x44px.
- **Gutters:** Standardized 16px spacing between different message groups, while individual messages within a cluster use 4px spacing to indicate continuity.

## Elevation & Depth

In this design system, depth is communicated via **Tonal Layers** and **Subtle Inner Glows** rather than traditional drop shadows.

- **Level 0 (Base):** #0F1214. Used for the main application background.
- **Level 1 (Surface):** #1A1F23. Used for the sidebar and the message input area.
- **Level 2 (Float):** A slightly lighter variant of the surface with a 1px `border_subtle` stroke. Used for context menus and tooltips.
- **Overlays:** Modals and bottom sheets utilize a `backdrop-filter: blur(20px)` with a 60% opacity fill of the Base color to maintain a sense of place.
- **Active Indicators:** Emerald Mint elements should have a soft, low-spread outer glow (0px 4px 12px rgba(0, 176, 116, 0.2)) to simulate a light-emitting diode.

## Shapes

The shape language is characterized by **Soft Geometric** forms.

- **Standard Elements:** Buttons, cards, and input fields use a 12px radius.
- **Message Bubbles:** Use a 16px radius. For grouped messages, the "middle" messages should have their corner radii reduced to 4px on the tail-side to visually group the sender's stream.
- **Avatars:** Strictly circular (50% radius) to contrast against the predominantly rectangular UI elements.
- **Icons:** Use a 2px stroke weight with rounded caps and joins to match the soft corners of the containers.

## Components

### Buttons
- **Primary:** Background in Emerald Mint, text in Obsidian Black (Semi-bold).
- **Secondary:** Background in Surface (#1A1F23), 1px border in #2D3439, text in White.
- **Ghost:** No background, Emerald Mint text for actions, Secondary Text for navigation.

### Message Bubbles
- **Sender:** Surface (#1A1F23) with white text. 1px subtle top-border to catch light.
- **Receiver:** Emerald Mint with Obsidian Black text (or a very dark deep green tint) to make the user's primary focus clear.

### Input Fields
- **Chat Input:** A pill-shaped container with a #1A1F23 background. Icons for "Attach" and "Emoji" should be secondary text color, turning Primary Emerald on active interaction.

### Chips & Badges
- **Unread Badge:** Small, circular Emerald Mint badge with Obsidian Black digit.
- **Status Chip:** 8px height, circular, utilizing a pulsing animation for "Live" or "Typing" states.

### Lists
- **Contact List:** 72px height per row. 12px spacing between the avatar and the text stack. A 1px bottom border (#2D3439) should be used, inset by 16px to avoid touching the screen edges.