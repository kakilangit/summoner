# Themes

DaisyUI-compatible color and layout token sets stored in the database. Users switch themes from **Settings > Themes**. Custom themes are installed by uploading a `.zip` file.

## theme.json Format

```json
{
  "name": "midnight-purple",
  "display_name": "Midnight Purple",
  "color_scheme": "dark",
  "author": "Your Name",
  "version": "1.0.0",
  "tokens": {
    "color-base-100": "oklch(25% 0.02 280)",
    "color-base-200": "oklch(20% 0.018 280)",
    "color-base-300": "oklch(15% 0.015 280)",
    "color-base-content": "oklch(95% 0.01 280)",
    "color-primary": "oklch(65% 0.25 300)",
    "color-primary-content": "oklch(98% 0.01 300)",
    "color-secondary": "oklch(55% 0.2 260)",
    "color-secondary-content": "oklch(98% 0.01 260)",
    "color-accent": "oklch(70% 0.2 330)",
    "color-accent-content": "oklch(98% 0.01 330)",
    "color-neutral": "oklch(35% 0.03 280)",
    "color-neutral-content": "oklch(95% 0.005 280)",
    "color-info": "oklch(60% 0.15 240)",
    "color-info-content": "oklch(98% 0.01 240)",
    "color-success": "oklch(65% 0.15 150)",
    "color-success-content": "oklch(98% 0.01 150)",
    "color-warning": "oklch(70% 0.18 60)",
    "color-warning-content": "oklch(98% 0.02 60)",
    "color-error": "oklch(60% 0.25 20)",
    "color-error-content": "oklch(98% 0.01 20)",
    "radius-selector": "0.25rem",
    "radius-field": "0.25rem",
    "radius-box": "0.75rem",
    "size-selector": "0.25rem",
    "size-field": "0.25rem",
    "border": "1px",
    "depth": "1",
    "noise": "0"
  }
}
```

## Color Tokens (20)

All color values must use `oklch(L C H)` format.

| Token | Description |
|-------|-------------|
| `color-base-100` | Main background color |
| `color-base-200` | Slightly darker background (cards, sidebars) |
| `color-base-300` | Darkest background tier (borders, dividers) |
| `color-base-content` | Default text color on base backgrounds |
| `color-primary` | Primary brand / action color |
| `color-primary-content` | Text on primary backgrounds |
| `color-secondary` | Secondary action color |
| `color-secondary-content` | Text on secondary backgrounds |
| `color-accent` | Accent / highlight color |
| `color-accent-content` | Text on accent backgrounds |
| `color-neutral` | Neutral / muted color (badges, subtle UI) |
| `color-neutral-content` | Text on neutral backgrounds |
| `color-info` | Informational state color |
| `color-info-content` | Text on info backgrounds |
| `color-success` | Success state color |
| `color-success-content` | Text on success backgrounds |
| `color-warning` | Warning state color |
| `color-warning-content` | Text on warning backgrounds |
| `color-error` | Error / danger state color |
| `color-error-content` | Text on error backgrounds |

## Layout Tokens (8)

| Token | Format | Description |
|-------|--------|-------------|
| `radius-selector` | CSS length | Border radius for checkboxes, radios, toggles |
| `radius-field` | CSS length | Border radius for inputs, selects, textareas |
| `radius-box` | CSS length | Border radius for cards, modals, alerts |
| `size-selector` | CSS length | Size scale for selectors |
| `size-field` | CSS length | Size scale for fields |
| `border` | CSS length | Default border width |
| `depth` | 0-5 | Shadow depth level |
| `noise` | 0-1 | Background noise texture (0=off, 1=on) |

## Constraints

- **Name**: lowercase kebab-case, 2-64 characters, unique
- **Display name**: max 100 characters, no HTML
- **Color scheme**: `"dark"` or `"light"`
- **Tokens**: exactly 28 (20 color + 8 layout)
- **Zip size**: max 1 MB, max 5 entries
- **Max themes**: 50 per installation
- **Built-in themes** cannot be deleted

## Security

All token values are validated against allowlisted patterns. Color values must match `oklch()` format exactly. Layout values must be simple CSS lengths or integers. Display names and author fields reject HTML characters. This prevents CSS injection attacks.
