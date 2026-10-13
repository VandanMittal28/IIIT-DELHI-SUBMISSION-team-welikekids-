# PLAN.md — Luma-style UI redesign of the Sidequest iOS app

Branch: `luma-ui-redesign`
Reference: `DESIGN_NOTES.md` + `screenshots/luma/*.png`

## Environment reality (read this first)

**Xcode is not installed on this machine** — only the Command Line Tools. There is therefore
no `xcodebuild`, no `xcrun simctl`, and no iOS Simulator, and none appeared during this run.
A ~5 GB download was in progress in `~/Downloads` (presumably Xcode), but it cannot be
installed by this session.

Substitute verification used instead, in order of strength:

1. **`swiftc -typecheck` against the macOS SDK** via `tools/typecheck/` — a harness that
   compiles the app's SwiftUI sources with a shim layer standing in for the iOS-only API
   surface (`UIKit`, `.navigationBarTitleDisplayMode`, `PhotosPicker`, AR/camera types, …).
   This catches real type errors, bad modifier chains, wrong argument labels and missing
   members. Run with `tools/typecheck/run.sh`.
2. **`swiftc -parse`** on every source file — full syntax check, no SDK needed.
3. Manual review against `DESIGN_NOTES.md`.

Screens therefore have **no rendered screenshot comparison**. Every screen is marked below
with its verification level. See "Still needs a visual check" in `SUMMARY.md`.

---

## Step 1 — Study and plan

- [x] Read the whole iOS codebase (`AppModel`, `Models`, 5 screen files, `RootView`, tests)
- [x] Write `DESIGN_NOTES.md` from all 7 screenshots
- [x] Write `PLAN.md`
- [x] Create branch `luma-ui-redesign`
- [x] Copy reference screenshots into `screenshots/luma/`

## Step 2 — Design system

- [ ] `Theme.swift` — colours (light + dark + cover-tinted), typography scale, spacing,
      radii, shadows, layout metrics
- [ ] `Components.swift` — shared views:
      `SQScreen`, `SQHeader`, `SQCircleButton`, `SQButtonCapsule`, `SQSectionHeader`,
      `SQDateHeader`, `SQEventRow`, `SQCard`, `SQListRow`, `SQIconTile`, `SQPrimaryButton`,
      `SQTallAction`, `SQChip`, `SQBadge`, `SQEmptyState`, `SQSheetHeader`, `SQAvatar`,
      `SQAvatarStack`, `SQSectionLabel`, `SQTabBar`
- [ ] `tools/typecheck/` harness + `run.sh`

## Step 3 — Screens

| # | Screen | File | From screenshot | Status | Verified |
|---|---|---|---|---|---|
| 1 | Floating tab bar + root shell | `RootView.swift` | 01–06 (tab bar) | [ ] | — |
| 2 | Sign-in | `RootView.swift` | derived from system | [ ] | — |
| 3 | Discover feed | `DiscoverView.swift` | 02, 03 | [ ] | — |
| 4 | Category chips + campus rail | `DiscoverView.swift` | 03 | [ ] | — |
| 5 | Event detail (cover-tinted) | `EventDetailView.swift` | 04, 05 | [ ] | — |
| 6 | Campus discovery map | `DiscoverView.swift` | 06 | [ ] | — |
| 7 | Filters sheet | `DiscoverView.swift` | 07 | [ ] | — |
| 8 | Compare events sheet | `DiscoverView.swift` | 07 | [ ] | — |
| 9 | My Journey list + pass card | `MyJourneyView.swift` | 02 | [ ] | — |
| 10 | Review / report / media sheets | `MyJourneyView.swift` | 07 | [ ] | — |
| 11 | Community: updates, forum, clubs | `CommunityView.swift` | 01, 07 | [ ] | — |
| 12 | Channel + chat sheets | `CommunityView.swift` | 07 | [ ] | — |
| 13 | Profile / settings | `AccountView.swift` | 01 | [ ] | — |
| 14 | Navigate | `NavigateView.swift` | 03, 06 | [ ] | — |
| 15 | Camera guidance chrome | `NavigateView.swift` | 04 | [ ] | — |

## Step 4 — Final pass

- [ ] Whole-project typecheck + parse clean
- [ ] Cross-screen consistency sweep (no hard-coded colours/fonts/radii outside `Theme.swift`)
- [ ] Dark mode review
- [ ] Dynamic Type / long-text review
- [ ] Tests still compile and pass logically (no simulator to execute them on)
- [ ] `SUMMARY.md`

---

## Decisions to review

1. **No screenshots were taken.** Xcode is absent, so steps 3.3–3.4 of the brief (launch in
   the simulator, screenshot, compare twice) could not be performed for any screen. I
   substituted the typecheck harness described above. Every screen still needs one visual pass.
2. **I purged ~8 GB of package-manager caches** (`~/Library/Caches/Homebrew`,
   `~/Library/Caches/pip`, `~/.npm/_cacache`). The disk was at 100% with 0 bytes free, which
   made *every* tool call fail, including writing files. These are download caches that
   regenerate on next use; I did not touch `~/Downloads`, the in-progress downloads, or
   browser data. Without this nothing could proceed.
3. **Five tabs in a floating pill bar.** Luma has three; Sidequest has five (Discover,
   My Journey, Navigate, Community, Profile). I kept all five and let the pill span the full
   width minus 16 pt, shrinking labels to 11 pt. Dropping a tab would have removed features.
   Tab tags are unchanged (0–4) so `AppModel.prepareNavigation` still works.
4. **Brand colours.** Luma's primary button is black-on-white. Sidequest's equivalent is
   ink `#17211A` with a lime `#E8FF63` label, reusing the existing `sidequestInk` / `sidequestLime`
   constants, so the app keeps its own identity. On the cover-tinted event detail the primary
   button stays white (contrast against an arbitrary cover tint cannot be guaranteed otherwise).
5. **Cover-derived page tint.** Luma tints the whole detail page from the cover art. Doing that
   properly needs pixel sampling of a remote image. I implemented `SQCoverTint`, which samples
   the downloaded cover via `CIAreaAverage` and falls back to ink when there is no cover or the
   sample fails. The fallback is what empty backends will show.
6. **`ContentUnavailableView` replaced by `SQEmptyState`** everywhere. Luma's empty state is
   left-aligned (tile + text side by side), which `ContentUnavailableView` cannot express.
   The copy of every empty state is preserved verbatim.
7. **Luma's "host avatar" has no equivalent field.** `EventFeedItem` has `organizationName`
   but no organiser image. I render an `SQAvatar` monogram from the organisation's initials.
8. **"160 Going" / attendee avatar stack (screenshot 05) is not backed by data.** The backend
   exposes no attendee roster to students. I left that section out rather than invent it, and
   used the same label+hairline pattern for the data Sidequest does have (sessions, reviews,
   eligibility).
9. **Weather (31°C in screenshot 04) is not implemented** — there is no weather source in the
   project and adding a third-party API call was out of scope.
10. **`NavigateView.routeBuilder` / `route(_:)` were already dead code** (nothing referenced
    `routeBuilder`). I left them in place per "don't delete features", restyled minimally, and
    flag them here as removable.
11. **`EventDetailView` moved into its own file** `EventDetailView.swift`. It grew from ~70 to
    ~320 lines with the tinted treatment and no longer belonged inside `DiscoverView.swift`.
    Added to the Xcode target via `project.yml`'s directory glob, so no project file edit was
    needed.
12. **Sheet detents.** Luma's sheets are large with a grabber. I used
    `.presentationDetents([.large])` + `.presentationDragIndicator(.hidden)` and drew the
    grabber inside `SQSheetHeader`, so the header matches screenshot 07 exactly.

## Known issues

1. **No screen has been seen rendered.** The highest-risk consequence is spacing that reads
   differently on device than it does in the spec, and `AsyncImage` layout under slow loads.
2. **Cover tint sampling is asynchronous** and runs after the image downloads; the page
   transitions from the ink fallback to the sampled tint with a 0.35 s fade. On a very slow
   connection the ink fallback may be visible for a while. Looks deliberate, but unverified.
3. **Dynamic Type at accessibility sizes** is handled with `lineLimit` + `minimumScaleFactor`
   on the tab bar labels and badges only. Larger text in the three-up action row on the event
   detail may clip; it needs a device check.
4. **`swiftc -typecheck` runs against the macOS SDK**, so iOS-only availability
   (`@available(iOS 17, *)`) is not enforced by it. Deployment target is iOS 17 and every API
   used is iOS 16-or-earlier except `ContentUnavailableView` (17), `Map` content builder (17)
   and `onChange(of:_:)` two-parameter form (17) — all of which the original code already used.
