# DESIGN_NOTES.md — Luma iOS visual reference

Permanent reference for the `luma-ui-redesign` branch. Every measurement below was read off
the seven reference screenshots in `screenshots/luma/`. Screenshots are 920×1992 px captures
of a ~393×852 pt iPhone (≈2.34 px per pt at the capture scale used here), so **px values in the
images were divided by ~2.34 to get the pt values quoted below**, then rounded to the nearest
sensible 2 pt step. Treat the pt values as the spec.

Brand substitution rule for this project: **copy the layout, scale and chrome, never the brand.**
Luma's purple blob avatar, "luma" wordmark and black/white accent are replaced by Sidequest's
ink (`#17211A`) and lime (`#E8FF63`).

---

## Global design language (derived from all 7 screenshots)

### Palette — light
| Token | Hex | Where it is used |
|---|---|---|
| Grouped background | `#F2F2F6` | Settings page behind the cards (01) |
| Plain background | `#FFFFFF` | Home / Discover scroll background (02, 03) |
| Surface (card) | `#FFFFFF` | Settings cards, sheets, chips |
| Surface alt / tile | `#EFEFF2` | Empty-state tile (02), grouped icon wells, time badge (07) |
| Text primary | `#0B0B0C` | Titles, row labels |
| Text secondary | `#8A8A8E` | "View Profile", meta rows, section headers (01) |
| Text tertiary | `#B0B0B5` | "/ Saturday", "Popular Events", "Nearby" (02, 03) |
| Separator | `#E5E5EA` | Inset hairlines inside cards and between discover rows |
| Destructive | `#FF3B30` | "Sold Out" text, Sign Out |
| Destructive wash | `#FFE8EA` | "Sold Out" capsule background |

### Palette — tinted dark (event detail, 04 & 05)
The whole screen adopts a dark tint sampled from the cover art (here a deep desaturated
purple ≈ `#3B3457`, with the top of the screen slightly lighter ≈ `#443C63` and the bottom
settling to ≈ `#332E4D`). Foreground is white at varying opacity:

| Role | Value |
|---|---|
| Page background | cover-derived tint, darkened; vertical gradient top → bottom |
| Text primary | `white` |
| Text secondary | `white` @ 60% |
| Text tertiary / section labels | `white` @ 45% |
| Separator | `white` @ 15% |
| Translucent control fill | `white` @ 14% |
| Primary button | solid `white` fill, near-black label |

### Corner radii
| Element | Radius |
|---|---|
| Settings / grouped card | 22 |
| Cover image, city card | 20 |
| Sheet top corners | 22 |
| Map card, category chip | 14–16 |
| Event row thumbnail | 12 |
| Colored settings icon tile | 8 |
| "Sold Out" badge | 8 |
| Circles / pills | fully rounded |

All rounded rectangles are drawn with `.continuous` (Apple's squircle) — visible on the
settings cards and the cover image in 04.

### Spacing
- Page horizontal margin: **20 pt** everywhere (cards, rows, headers all align to it).
- Card internal horizontal padding: **16 pt**.
- Section header → first card below it: **12 pt**.
- Card → next section header: **28 pt**.
- Between event rows in a date group: **20 pt**.
- Between date groups: **28 pt**.
- Settings row height: **56 pt**; divider is inset to start at the label's x-origin.

### Typography (SF Pro, default design — *not* rounded)
| Role | Size / weight | Seen in |
|---|---|---|
| Screen title / wordmark | 30 bold | "Discover" (03) |
| Large event title | 34 bold, tight leading | 04 |
| Section title | 26 bold | "Picked for You", "Browse by Category", "Cities" |
| Nav bar title (centered) | 22 bold | "Settings" (01), "Start Chat" (07) |
| Group / date header | 22 bold | "17 October" (02) |
| Row title | 20 semibold, max 2 lines | event titles in list (02, 03) |
| Settings row label | 20 regular | 01 |
| Body / meta | 17 regular | times, venues, "active a while ago" |
| Small meta | 15 regular | — |
| Badge | 13 semibold | "Sold Out" (03) |

Luma pairs a **bold black** fragment with a **tertiary-grey** fragment in one line — e.g.
`17 October` + ` / Saturday`, and `New Delhi` + `Popular Events` stacked. Reproduce this
two-tone pairing; it is one of the most recognisable parts of the look.

### Shadows
- Card: black @ 6%, radius 18, y-offset 6.
- Floating chrome (tab bar, header capsule, circular buttons): black @ 10%, radius 24, y 8.

### Floating tab bar (01, 02, 03, 04, 05, 06)
- A **capsule that floats over the content**, not a bar attached to the bottom edge.
- Insets: ~20 pt from the left/right screen edges on 3 items, ~20 pt above the home indicator.
- Height ≈ 64 pt. Fill is a light translucent material (`#F2F2F2` @ ~85% + blur); on the
  tinted-dark event detail it becomes the dark tint @ ~70% + blur, with a 1 pt white @ 12% ring.
- The **selected** item gets its own inner capsule in a slightly deeper grey (`#E6E6EA`),
  roughly the item's width × 52 pt, with the icon filled and the label in primary text.
- Unselected items: grey `#8A8A8E`, outline-style icon, same label size (15 regular).
- Content scrolls *underneath* the bar (visible in 01 where "Sign Out" is half-hidden, and in
  03 where the city cards show through) — so screens need bottom content inset ≈ 92 pt.

### Circular chrome buttons (01, 04, 06, 07)
- Diameter **44 pt** on sheets (07), **48 pt** floating over content (04, 06), white fill
  in light contexts, `white @ 14%` in the tinted-dark context.
- Icon ~20 pt, `semibold` weight.
- When two live together in the top-right they share **one capsule** rather than sitting as
  two separate circles (02 "+ / bell", 03 "map / search", 05 "ticket / share").

---

## 01 — Settings (`screenshots/luma/01-settings.png`)

**Structure:** scroll view of grouped white cards on `#F2F2F6`, centered nav title, floating tab bar.

- **Nav bar**: 48 pt white circle with `chevron.left` at the leading edge, x=20; title "Settings"
  22 bold centered on the screen (not on the remaining space).
- **Card 1 (profile)**, radius 22, margin 20:
  - Row A, height ~80: 56 pt circular avatar at x=16 inside the card, 14 pt gap, then a
    two-line stack — name 22 bold `#0B0B0C`, "View Profile" 17 regular `#8A8A8E` — and a
    trailing `chevron.right` 15 semibold in `#C4C4C8` at x = card width − 16.
  - Inset hairline `#E5E5EA` starting at the x of the name text (i.e. 86 pt from card leading).
  - Row B, height 56: "Edit Profile" 20 regular + chevron.
- **28 pt gap**, then **card 2** with two icon rows: Account Settings, Payment.
- **Section header "Preferences"**: 20 semibold `#8A8A8E`, left-aligned to the 20 pt page
  margin + 16 pt card inset (so ~36 pt from the screen edge), 12 pt above its card.
- **Card 3**: Notifications (red `#FF3B30` bell), Permissions (green `#34C759` shield-check),
  Appearance (pink `#FF2D78` palette).
- **Section header "Resources"**, then **card 4**: Contact Support (blue envelope),
  Rate in App Store (yellow star), Instagram, X — the last two use a trailing
  `arrow.up.right` in `#C4C4C8` instead of a chevron, marking an external link.
- **Icon tile**: 32×32, radius 8, saturated flat fill, white glyph ~17 pt. Leading inset 16 pt
  inside the card; label starts 14 pt after the tile.
- Sign Out sits in its own final card with a red icon and red label.

**Port to Sidequest:** this is the model for the **Profile / Account** screen. The existing
`Form` becomes these grouped cards; each `Section` becomes one card with a grey header above it.

---

## 02 — Home / Your Events (`screenshots/luma/02-home.png`)

**Structure:** white background, large left-aligned header, then date-grouped event rows.

- **Header row** (y ≈ 60–100): 44 pt avatar, 10 pt gap, wordmark 30 bold; trailing a single
  white capsule (height 56, radius 28) holding `plus` and `bell` 22 pt glyphs, 28 pt apart.
  The bell carries an 10 pt `#FF3B30` dot at its top-right.
- **"Your Events"** 26 bold + a 20 pt `chevron.right` immediately after the text (not pinned
  to the trailing edge) — the chevron hugs the title, which is a Luma signature.
- **Empty state** (the key one to copy): a **left-aligned horizontal pair** —
  - 80×80 tile, radius 20, fill `#EFEFF2`, centered ticket glyph 34 pt in `#C9C9CE`;
  - 20 pt gap;
  - message 20 regular `#8A8A8E`, up to 3 lines, *not* centered.
  This replaces SwiftUI's centered `ContentUnavailableView` everywhere in the app.
- **"Picked for You"** 26 bold, and directly beneath it **"Nearby"** 26 regular `#B0B0B5`
  followed by a 17 pt `chevron.up.chevron.down` — a selector rendered as a subdued second line.
- **Date header**: `17 October` 22 bold `#0B0B0C` + `  / Saturday` 22 regular `#B0B0B5`
  on the same baseline.
- **Event row**, total height ~96:
  - 88×88 thumbnail, radius 12, `scaledToFill` + clip;
  - 16 pt gap;
  - column: host line (20 pt avatar circle + host name 17 regular `#8A8A8E`, 8 pt apart),
    4 pt, title 20 semibold max 2 lines with tight leading, 8 pt, meta line.
  - **Meta line**: `clock` 15 pt `#B0B0B5` + 6 pt + time 17 regular `#8A8A8E` + 16 pt +
    `mappin.circle`/location glyph + 6 pt + venue 17 regular `#8A8A8E`.
- Rows are flat on the background — **no card, no border, no shadow**.

**Port to Sidequest:** this is the model for **Discover's feed** and **My Journey's list**.

---

## 03 — Discover (`screenshots/luma/03-discover.png`)

- **Header**: avatar + "Discover" 30 bold; trailing capsule with `map` and
  `magnifyingglass`.
- **"New Delhi"** 26 bold + `chevron.right`; **"Popular Events"** 26 regular `#B0B0B5` beneath.
- **Horizontally paged carousel**: each page is a *column of 3 event rows* occupying ~92% of
  the width, with the next page peeking ~8% at the right edge. 16 pt between pages.
  - Rows here are the 02 row minus the venue, plus a trailing **"Sold Out"** badge aligned to
    the host line: 13 semibold `#FF3B30` on `#FFE8EA`, radius 8, padding 8×4.
  - A `#E5E5EA` hairline separates rows **inset to the text column** (starts at thumb width +
    gap = 104 pt), with ~20 pt of air above and below it.
- **"Browse by Category"** 26 bold. Chips in a 2-row horizontally scrolling grid:
  white fill, 1 pt `#E5E5EA` border, radius 14, height 56, inner padding 16 pt,
  colored 24 pt glyph + 10 pt gap + label 20 regular `#0B0B0C`. Each category owns a hue
  (Family pink-violet, Tech blue, Food & Drink orange, Books yellow, Games brown, AI pink,
  Running green).
- **"Cities"** 26 bold + chevron; horizontally scrolling photo cards, radius 20,
  ≈ 200×230, with a 44 pt translucent-white glass circle holding a landmark glyph at the
  card's top-left, inset 14 pt.

**Port to Sidequest:** the paged carousel becomes "Picked for you" over the event feed;
category chips drive `model.categoryFilter`; the Cities rail becomes a **campus/college rail**.

---

## 04 — Event detail, top (`screenshots/luma/04-event-detail-top.png`)

**The single most distinctive screen.** The whole page is tinted from the cover art.

- Background: vertical gradient of the cover-derived tint — top ≈ `#443C63`, bottom ≈ `#332E4D`.
- **Floating chrome**, no nav bar yet: 48 pt `white @ 14%` circles at x=20 and trailing,
  y ≈ 60. `chevron.left` and `square.and.arrow.up`.
- **Cover card**: full width − 40, 1:1 aspect, radius 20, `scaledToFill`, clipped.
- **Attached banner** directly under the cover, sharing its bottom corners: height 44,
  `white @ 10%` fill, centered "🌿 Featured in New Delhi 🌿" 17 regular white @ 85%.
  Implemented as a single rounded container holding image + banner, so the corners stay joined.
- 20 pt gap, **title** 34 bold white, tight leading (line spacing ≈ −2), up to 3 lines.
- 6 pt, **date/time line** `Sat, 17 Oct, 3:00 PM - 6:00 PM` 22 regular `white @ 60%`.
- 20 pt, **action row** — three equal-width buttons, height 88, radius 14, 12 pt apart:
  - **Register** — solid white fill, `#0B0B0C` content. 26 pt glyph above a 20 regular label,
    10 pt apart, both centered.
  - **Contact**, **More** — `white @ 14%` fill, white content, same internal layout.
- 28 pt, **section label** "Location" 20 regular `white @ 45%`, then a `white @ 15%` hairline
  with 12 pt of air above the content.
- **Location block**: name 24 regular white; address 20 regular `white @ 55%` wrapping to
  4 lines; trailing a `sun.max` glyph over "31°C" 20 regular white.
- Tab bar is present and takes the dark tint.

**Port to Sidequest:** the registration CTA takes the white "Register" slot; Save and Share
take the two translucent slots. Sessions / reviews / eligibility become further labelled
sections using the same label + hairline pattern.

---

## 05 — Event detail, scrolled (`screenshots/luma/05-event-detail-scrolled.png`)

- **Inline nav bar fades in on scroll**: back circle (48 pt, `white @ 14%`), truncated title
  20 semibold white, trailing **capsule** with `ticket` and `share` glyphs. The whole bar sits
  on a blurred tint; content scrolls behind it.
- **Map card**: full width − 40, height 230, radius 16.
- **"Host"** label left and **"Contact"** right on one line, both 20 regular `white @ 45%`,
  then a hairline. (A section label may carry a trailing action — reuse this.)
- **Host row**: 56 pt avatar, 14 pt gap, name 22 regular white over subtitle 20 regular
  `white @ 55%`; trailing social glyphs 22 pt `white @ 70%`, 20 pt apart.
- **"160 Going"** 22 regular white, then a hairline.
- **Avatar stack**: 44 pt circles overlapping by 14 pt, each with a 2 pt ring in the page tint;
  after four, a `white @ 18%` circle with "+156" 15 semibold. Then a names sentence,
  20 regular white, 2 lines, ending "…and 156 more".
- **"About Event"** label + hairline, then body copy 24 semibold white with generous leading
  (≈ 8 pt). Luma sets the event description noticeably **larger and heavier than normal body
  text** — worth copying.

---

## 06 — Discover map (`screenshots/luma/06-map.png`)

- Full-bleed `Map`, ignoring safe areas, with the floating tab bar on top.
- **Floating circular buttons**: back at top-left, a filter/list button (3 stacked lines,
  shortest at the bottom) at top-right. Both 48 pt, **white** fill (not translucent — the map
  is light), shadow black @ 10% r 24 y 8.
- **Locate button**: 56 pt white circle with a filled navigation arrow, bottom-right, inset
  20 pt, sitting ~20 pt above the tab bar.
- **Cluster annotation**: 2–3 event thumbnails ~56 pt, radius 8, each with a 2 pt white border
  and a soft shadow, **fanned** (rotated roughly −8°, 0°, +8°) and overlapping by ~20 pt;
  under them a centered title 17 semibold `#0B0B0C` over 2 lines, then "+12 more"
  17 regular `#8A8A8E`.

**Port to Sidequest:** `CampusDiscoveryMap` and the `Navigate` map adopt the floating-circle
chrome; campus markers adopt the fanned-thumbnail annotation (falling back to a single tile).

---

## 07 — Start Chat sheet (`screenshots/luma/07-start-chat-sheet.png`)

**The model for every sheet in the app.**

- Presented over a dimmed, slightly scaled-down parent. 22 pt top corners, white.
- 5×36 pt grabber in `#D5D5DA`, 8 pt from the top.
- **Header row**, height 72: 44 pt `#EFEFF2` circle with `xmark` 17 semibold `#0B0B0C` at the
  leading edge; title 22 bold centered **on the screen**; 44 pt `#EFEFF2` circle with
  `magnifyingglass` trailing.
- **Lead row**: 56 pt `#EFEFF2` circle holding a 24 pt `person.2.fill` in `#8A8A8E`,
  16 pt gap, "Create Group Chat" 20 regular, trailing chevron.
- **Section header** "Suggested" 17 regular `#8A8A8E`, 20 pt above / 10 pt below.
- **Person rows**, height 68, **no dividers**: 56 pt avatar, 16 pt gap, name 20 regular
  `#0B0B0C` with an optional **time badge** right after it (13 regular `#8A8A8E` on
  `#EFEFF2`, radius 8, padding 8×3), then subtitle "active a while ago" 17 regular `#8A8A8E`.

**Port to Sidequest:** filters, review, report, new-thread, compare and event-photo sheets all
get the grabber + circular-X + centered-title header, and grouped white cards on `#F2F2F6`.

---

## Derived rules the screenshots imply but never state

1. **Nothing is centered except nav titles.** Headers, empty states and section labels are all
   left-aligned to the 20 pt margin.
2. **Grey is a type colour, not a background.** Secondary information is conveyed with
   `#8A8A8E`/`#B0B0B5` text at the *same size* as the primary text, rather than smaller text.
3. **Two-tone single lines** (bold black + grey continuation) appear in date headers, city
   headers and section subtitles.
4. **Cards only where rows need grouping** (settings, sheets). Feeds are flat.
5. **Chrome floats.** Tab bar, nav buttons and header capsules all sit over the content with a
   shadow, and content is inset at the bottom (≈ 92 pt) rather than clipped.
6. **Icon colour is categorical.** Settings glyphs and category chips each carry their own hue;
   this is the only place saturated colour appears in light mode.

## Sidequest brand substitutions

| Luma | Sidequest |
|---|---|
| Purple blob avatar | Lime-on-ink "SQ" monogram, same 44/56 pt circles |
| "luma✦" wordmark | "Sidequest" 30 bold + lime sparkle |
| Black primary button | Ink `#17211A` fill, lime `#E8FF63` label |
| White button on dark detail | kept white (needed for contrast), ink label |
| Luma social rows | IIIT Delhi operations / support rows |
| Accent for selected tab | Ink fill + lime glyph |
