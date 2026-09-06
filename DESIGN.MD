DESIGN REFERENCE
Source: Fontpair Playground
URL: https://fontpair.co/playground/epilogue-baskervville?icons=1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TYPOGRAPHY RULES:
→ Use Epilogue for ALL headings (h1–h4), display text, and hero copy
→ Use Baskervville for ALL body text, captions, labels, and UI copy
→ Do NOT substitute with Inter, system-ui, Georgia, or any fallback font
→ Apply a typographic scale: hero 48–64px, h1 36px, h2 28px, h3 22px, body 16px, caption 13px
→ Font weight: 400 for body, 500–600 for headings — do not use 700+ unless explicitly needed
→ Letter spacing: slightly loose on headings (-0.01em to 0), normal on body

FONTS:
| Role | Font | Weights | Stylesheet URL |
|------|------|---------|----------------|
| Headings | Epilogue | 400, 500, 600 | `https://fonts.googleapis.com/css2?family=Epilogue:wght@400;500;600&display=swap` |
| Body | Baskervville | 400, 500 | `https://fonts.googleapis.com/css2?family=Baskervville:wght@400;500&display=swap` |

LOADING RULE:
→ Load these via <link rel="stylesheet"> tags in the route head (e.g. index.html <head> or react-helmet),
  NOT via CSS @import in styles.css. Tailwind v4 / Lightning CSS cannot resolve remote @import URLs
  and will silently fall back to system fonts.
→ Add the following tags exactly:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Epilogue:wght@400;500;600&display=swap">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Baskervville:wght@400;500&display=swap">
```

TYPOGRAPHY TOKENS:
→ Map each font to a CSS custom property so components reference the token, NOT the raw font name:

```css
:root {
  --font-heading: 'Epilogue', sans-serif;
  --font-body: 'Baskervville', sans-serif;
}
```

→ In Tailwind config, expose these as: `fontFamily: { heading: 'var(--font-heading)', sans: 'var(--font-body)' }`
→ Use `font-heading` on headings/display and `font-sans` (or `font-body`) on body text — never hardcode the font name in components.

COLOR RULES:
→ Background / Surface: #FFFFFF — use for page backgrounds and card surfaces
→ Foreground: #161616 — use for primary text, headings, and neutral icons
→ Foreground Muted: #3A3A3A — use for secondary text, placeholders, and metadata
→ Primary: #00296B — the main brand and action color; use for CTAs, active states, links, and key UI accents
→ Primary Hover: #003F88 — use for hover states on primary actions and links
→ Primary Focus: #00509D — use for focus rings and small interaction highlights
→ Secondary: #FDC500 — use sparingly for small decorative or navigational accents, such as a scrollbar thumb or a compact progress marker
→ Secondary Hover: #FFD500 — use only as the interactive state of a permitted secondary accent
→ Border: #E2E8F0 — use for dividers, input borders, and card outlines
→ Blue is the dominant brand color. Yellow must remain a subtle accent and must NOT be used for primary actions, large surfaces, body text, or headings
→ Do NOT introduce colors outside this palette (no Tailwind defaults like blue-500 or gray-400)
→ Do NOT use pure black (#000000) — use #161616 as the darkest neutral value
→ Do NOT repurpose brand colors for success, warning, error, or destructive states; define dedicated semantic tokens before those states are implemented

COLOR TOKENS:
→ Components must reference semantic CSS custom properties, never raw hex values:

```css
:root {
  --color-background: #FFFFFF;
  --color-surface: #FFFFFF;
  --color-foreground: #161616;
  --color-foreground-muted: #3A3A3A;
  --color-primary: #00296B;
  --color-primary-hover: #003F88;
  --color-primary-focus: #00509D;
  --color-brand-secondary: #FDC500;
  --color-brand-secondary-hover: #FFD500;
  --color-border: #E2E8F0;
}
```


ICON RULES:
→ Use Feather Icons exclusively for all icons
→ Install via: https://feathericons.com
→ Do NOT use Heroicons, Lucide, or any other icon library
→ Match icon size to surrounding text scale (16px inline, 20px UI, 24px feature icons)

COMPONENT RULES:
→ Primary buttons must use Primary (#00296B) background with #FFFFFF text and Primary Hover (#003F88) on hover, rounded-md
→ Every card must use Border (#E2E8F0) outline, Background (#FFFFFF) surface, consistent padding (16–24px)
→ Every input must use Border (#E2E8F0) outline, Foreground Muted placeholder text
→ Every link must use Primary (#00296B), Primary Hover (#003F88) on hover — no underline by default
→ Focused interactive elements must use Primary Focus (#00509D) for the focus ring
→ Secondary yellow may appear only in small accents; do not create yellow button variants or large yellow component surfaces


FRAMEWORK RULES:
→ Use shadcn/ui components with Tailwind CSS
→ Map semantic tokens: primary → #00296B, primary-hover → #003F88, ring → #00509D, foreground → #161616, muted-foreground → #3A3A3A, background/card → #FFFFFF, border → #E2E8F0
→ Expose the restrained yellow accents as brand-secondary → #FDC500 and brand-secondary-hover → #FFD500; do NOT map them to a default component variant that creates large yellow surfaces
→ Fonts: reference --font-heading and --font-body tokens defined above — do NOT re-declare or @import the font families elsewhere
→ Do NOT use Tailwind's default color scales — all colors must reference the semantic tokens above

OUTPUT RULES:
→ Every component must reference the design tokens — no hardcoded arbitrary values
→ Do not introduce UI elements, colors, or fonts not specified in this file
→ The final output must feel cohesive — as if designed by one person with one system
→ When in doubt, use less decoration, not more
