# Antigravity Task — Apply Web Team's Design System to Mobile App

> **Task type:** visual refactor only — no business logic, navigation, or backend
> changes.
> **Companion docs:** `MASTER_CONTEXT.md` (governance), `klinikaid_mobile_guide.md`
> (feature scope), `web_reference/schema.sql` (backend contract).
> **Scope:** complete theme swap from current dark indigo aesthetic to the web team's
> light cream + forest green palette. Every screen needs updating.

---

## Goal

Adopt the web team's design system (from `Setsuna-guwah/KlinikAid`'s
`src/app/globals.css` and `tailwind.config.ts`) so a patient using both apps sees a
consistent visual identity. The web team forces light mode
(`style={{ colorScheme: 'light' }}` in their root layout); the mobile app currently
runs a dark indigo theme from Phase 2. This task aligns them.

---

## Design Tokens to Adopt

### Colors

| Token | HSL | Hex | Usage |
| :---- | :---- | :---- | :---- |
| background | `36 53% 93%` | `#F6EBD4` | Scaffold / page background |
| foreground | `222.2 84% 4.9%` | `#0A0E1A` | Primary text |
| primary | `133 21% 31%` | `#3F6146` | Buttons, links, active states |
| primary-foreground | `36 53% 98%` | `#FAF7EF` | Text on primary buttons |
| card | `0 0% 100%` | `#FFFFFF` | Card / sheet backgrounds |
| card-foreground | `222.2 84% 4.9%` | `#0A0E1A` | Text inside cards |
| secondary | `36 30% 88%` | `#E6DDCC` | Inactive button bg, chip bg |
| secondary-foreground | `222.2 47.4% 11.2%` | `#0F172A` | Text on secondary |
| muted | `36 30% 90%` | `#EAE2D2` | Muted backgrounds |
| muted-foreground | `215.4 16.3% 46.9%` | `#64748B` | Hint text, captions |
| accent | `36 30% 88%` | `#E6DDCC` | Hover / focus highlights |
| destructive | `0 84.2% 60.2%` | `#EF4444` | Error / danger states |
| border | `36 20% 80%` | `#D5CDBF` | Card borders, dividers |
| input-border | `36 20% 80%` | `#D5CDBF` | Form input borders |
| ring | `133 21% 31%` | `#3F6146` | Focus rings (same as primary) |
| accentBlue-600 | - | `#1F6DD2` | Charts / info accent (secondary) |

### Typography

- **Font family:** `Inter` (Google Fonts). Replaces the current `Outfit`.
- Use the `google_fonts` package: `GoogleFonts.inter(...)` and
  `GoogleFonts.interTextTheme(...)`.

### Border radius

- Default radius: **12px** (matches web's `--radius: 0.75rem`)
- Use **8px** for small inputs
- Use **16px** for prominent cards

---

## Steps to Execute

### 1. Update the app theme file
File: likely `lib/app/theme.dart` or `lib/core/theme/...`

- Define a `ThemeData` with `brightness: Brightness.light`.
- Set `colorScheme` using the tokens above (`ColorScheme.fromSeed` is NOT
  appropriate here — use explicit color assignments to match the web tokens
  exactly).
- Set `scaffoldBackgroundColor: Color(0xFFF6EBD4)`.
- Configure `ElevatedButtonTheme` with primary background, primary-foreground text,
  12px radius, no elevation.
- Configure `CardTheme` with white background, 12px radius, subtle 1px border in
  the border color.
- Configure `InputDecorationTheme` with white fill, 8px radius, border in the
  input-border color, focused border in primary color.
- Use `GoogleFonts.interTextTheme()` with the foreground color.

### 2. Audit every `Color(...)` usage across `lib/features/`

Search for and replace:
- `Color(0xFF0B0E14)` (current dark slate background)
- `Color(0xFF2E5BFF)` (current indigo primary)
- `Color(0xFF9E00FF)` (current purple chatbot accent)
- Any other hardcoded dark-theme colors

Replace with **semantic** `Theme.of(context).colorScheme.X` references. **Do NOT
hardcode the new colors either** — go through the theme.

### 3. Update specific screens

| Screen | Treatment |
| :---- | :---- |
| Login / Register | Cream background, white card containing the form, forest-green primary button, Inter font throughout. |
| Consent | Cream background, white card with privacy text, forest-green Accept button. |
| Onboarding | Cream background, white card sections, forest-green Submit button. |
| Dashboard | Cream background, white feature tiles with the border color, forest-green for icon accents and primary CTAs. |
| Chatbot | Cream background, white user-message bubbles with subtle border, forest-green AI-message bubbles with white text. This is intentional — forest-green AI bubbles match the brand identity even though it deviates from typical chat UIs. |
| Submit / OCR | Cream background, white card for image preview, forest-green Submit button, destructive red for any error states. |
| Records / Queue / Status | Cream background, white cards with status badges per the spec below. |

### 4. Status badge colors

| Status | Background | Foreground |
| :---- | :---- | :---- |
| `pending` | secondary `#E6DDCC` | foreground `#0A0E1A` |
| `approved` | primary `#3F6146` | primary-foreground `#FAF7EF` |
| `rejected` | destructive `#EF4444` | destructive-foreground (white) |

### 5. Remove all references to the old theme

- The previous "premium dark-themed" indigo palette
- The `Outfit` font (replace ALL instances with `Inter`)
- The purple `#9E00FF` chatbot accent (replace with primary forest green)

### 6. Status bar

Change to **light mode** (dark icons on light background). Use
`SystemUiOverlayStyle.dark` in the `MaterialApp`, or set per-screen.

### 7. Verify

Run:
```
puro flutter analyze
```
Confirm **zero new warnings**.

Run:
```
puro flutter test
```
Confirm tests **still pass**.

---

## Out of Scope

This is a **pure visual refactor.** Do NOT:

- Change any business logic, navigation flow, or data-layer code
- Modify the Edge Function or any backend code
- Modify the database schema or RLS policies
- Touch the agent's prior Phase 0-6 implementations beyond their colors and fonts

---

## Documentation Updates (Required Part of This Task)

1. **`lib/app/theme.dart`** — add a top-of-file comment block:
   ```dart
   // Design tokens adopted from the KlinikAid web team's globals.css (light
   // theme). Forest green primary (#3F6146) on warm cream background
   // (#F6EBD4). Inter typography. Aligned 2026-06-11.
   ```

2. **`web_reference/migration_notes.md`** — create the file if it doesn't exist;
   add:
   ```
   2026-06-11: Mobile app visual theme aligned with web team's light cream +
   forest-green palette. Replaces prior dark indigo theme from Phase 2.
   ```

---

## Verification Checklist (Exit Criteria)

- [ ] All five main screens render with the new palette (Login, Dashboard,
      Chatbot, Submit, Records).
- [ ] No instance of `Color(0xFF0B0E14)`, `Color(0xFF2E5BFF)`, or
      `Color(0xFF9E00FF)` remains in `lib/`.
- [ ] No instance of `GoogleFonts.outfit()` or `'Outfit'` font family remains.
- [ ] App builds and launches without theme-related runtime errors.
- [ ] `puro flutter analyze` returns no new warnings.
- [ ] `puro flutter test` passes.

---

## When Complete

Report back with:

- A **walkthrough.md** following the Phase Completion Report template in
  `MASTER_CONTEXT.md` section 6.2
- **Screenshots** of the Login, Dashboard, and Chatbot screens in the new theme
- Confirmation that **`flutter analyze` is clean and tests pass**

The reviewer will check that the implementation matches the web's tokens exactly
(no "close but not quite right" colors) and that no business logic changed.
