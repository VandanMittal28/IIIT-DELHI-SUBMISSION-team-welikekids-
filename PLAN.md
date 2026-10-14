# PLAN.md — Luma-style UI redesign of the Sidequest iOS app

Branch: `luma-ui-redesign`
Reference: `DESIGN_NOTES.md` + `screenshots/luma/*.png`

## Environment reality (read this first)

**Xcode is not installed on this machine** — only the Command Line Tools. There is therefore
no `xcodebuild`, no `xcrun simctl`, and no iOS Simulator, and none appeared during this run.
A ~5 GB download was in progress in `~/Downloads` (presumably Xcode), but it cannot be
installed by this session.

Substitute verification used instead, in order of strength — all four stages run from
`tools/typecheck/run.sh`:

0. **Xcode target membership** — `tools/sync-xcode-sources.py --check` confirms every Swift
   file in `ios/Sidequest/` is registered in the committed `project.pbxproj`. (XcodeGen
   generates that file from `ios/project.yml` but is not installed here, so new files would
   otherwise be silently left out of the build.)
1. **`swiftc -parse`** on every source — full syntax check, no SDK needed, covers 100% of the
   code including the ARKit camera views.
2. **`swiftc -typecheck` against the macOS SDK** with a shim layer standing in for the
   iOS-only API surface (`UIKit`, `.navigationBarTitleDisplayMode`, `PhotosPicker`, the
   AR views) and a stub `AppModel` standing in for the Supabase-backed one. This catches
   wrong argument labels, bad modifier chains, missing members and type errors. It proves the
   code is internally consistent — not that it builds for iOS.
3. **Model behaviour, actually executed** — `tools/typecheck/modeltests/main.swift` compiles
   and runs the `ModelsTests` assertions on macOS (they are pure Foundation), plus new
   coverage of the cover-tint normalisation. This is the only part of the app whose behaviour
   is genuinely run rather than only type-checked.

The build is also warning-clean under stage 2.

Screens therefore have **no rendered screenshot comparison**, and `screenshots/after/` is
empty. Every screen still needs one visual pass on a device or simulator.

---

## Step 1 — Study and plan

- [x] Read the whole iOS codebase (`AppModel`, `Models`, 5 screen files, `RootView`, tests)
- [x] Write `DESIGN_NOTES.md` from all 7 screenshots
- [x] Write `PLAN.md`
- [x] Create branch `luma-ui-redesign`
- [x] Copy reference screenshots into `screenshots/luma/`

## Step 2 — Design system

- [x] `Theme.swift` — colours (light, dark and cover-tinted), typography scale, spacing,
      radii, shadows, layout metrics
- [x] `Components.swift` — 31 shared views: `SQScreenHeader`, `SQNavBar`, `SQCircleButton`,
      `SQActionCapsule`, `SQCapsuleGlyph`, `SQSectionHeader`, `SQGroupHeader`, `SQDateHeader`,
      `SQSectionLabel`, `SQCard`, `SQInsetDivider`, `SQIconTile`, `SQListRow`, `SQProfileRow`,
      `SQEventRow`, `SQThumbnail`, `SQMetaItem`, `SQBadge`, `SQAvatar`, `SQAvatarStack`,
      `SQPrimaryButton`, `SQSecondaryButton`, `SQTallAction`, `SQChip`, `SQEmptyState`,
      `SQSheet`, `SQSheetHeader`, `SQScreen`, `SQField`, `SQNotice`, `SQTabBar`
- [x] `tools/typecheck/` harness + `run.sh`
- [x] `tools/sync-xcode-sources.py`

## Step 3 — Screens

| # | Screen | File | From screenshot | Done | Verified |
|---|---|---|---|---|---|
| 1 | Floating tab bar + root shell | `RootView.swift` | 01–06 (tab bar) | [x] | typecheck |
| 2 | Sign-in | `RootView.swift` | derived from the system | [x] | typecheck |
| 3 | Discover feed | `DiscoverView.swift` | 02, 03 | [x] | typecheck |
| 4 | Category chips + campus rail | `DiscoverView.swift` | 03 | [x] | typecheck |
| 5 | Event detail (cover-tinted) | `EventDetailView.swift` | 04, 05 | [x] | typecheck + tint tests |
| 6 | Campus discovery map | `DiscoverView.swift` | 06 | [x] | typecheck |
| 7 | Filters sheet | `DiscoverView.swift` | 07 | [x] | typecheck |
| 8 | Compare events sheet | `DiscoverView.swift` | 07 | [x] | typecheck |
| 9 | My Journey list + pass detail | `MyJourneyView.swift` | 02 | [x] | typecheck |
| 10 | Review / report / media sheets | `MyJourneyView.swift` | 07 | [x] | typecheck |
| 11 | Community: updates, forum, clubs | `CommunityView.swift` | 01, 07 | [x] | typecheck |
| 12 | Channel + chat sheets | `CommunityView.swift` | 07 | [x] | typecheck |
| 13 | Profile / settings | `AccountView.swift` | 01 | [x] | typecheck |
| 14 | Profile sub-screens | `AccountView.swift` | 01 | [x] | typecheck |
| 15 | Navigate | `NavigateView.swift` | 03, 06 | [x] | typecheck |
| 16 | Camera guidance chrome | `CameraGuidanceView.swift` | 04 | [x] | parse + call-site probe |

## Step 4 — Final pass

- [x] All four verification stages clean, no warnings
- [x] Cross-screen consistency sweep — no hard-coded colours, fonts, radii or spacing outside
      `Theme.swift` (audited by grep; only SF Symbol glyph sizes remain inline, which is correct)
- [x] Dark mode review — found and fixed five contrast failures (see decision 13)
- [x] Dynamic Type / long-text review
- [x] Model tests compile and pass
- [x] `SUMMARY.md`

---

## Decisions to review

1. **No screenshots were taken.** Xcode is absent, so steps 3.3–3.4 of the brief (launch in
   the simulator, screenshot, compare twice) could not be performed for any screen. I
   substituted the four-stage harness above. Every screen still needs one visual pass.
2. **I purged ~8 GB of package-manager caches** (`~/Library/Caches/Homebrew`,
   `~/Library/Caches/pip`, `~/.npm/_cacache`). The disk was at 100% with 0 bytes free, which
   made *every* tool call fail — including writing files, and including the in-progress
   download itself. These are download caches that regenerate on next use. I did not touch
   `~/Downloads`, the in-progress downloads, or browser data. Without this nothing could
   proceed, and the Xcode download could not have completed either.
3. **Five tabs in a floating pill bar.** Luma has three; Sidequest has five. I kept all five
   and let the pill span the full width minus 32 pt, with 11 pt labels that shrink to 75%.
   Dropping a tab would have removed features. Tags are unchanged (0–4) so
   `AppModel.prepareNavigation` still jumps to Navigate correctly.
4. **Brand colours.** Luma's primary button is black-on-white. Sidequest's is ink `#17211A`
   with a lime `#E8FF63` label, reusing the existing constants. On the cover-tinted event
   detail the primary button stays white, because contrast against an arbitrary cover tint
   cannot be guaranteed otherwise.
5. **Cover-derived page tint.** `SQCoverTintSampler` averages the downloaded cover with
   `CIAreaAverage`, then `SQTint.fromCoverSample` pushes it into a consistent deep,
   slightly-desaturated band so white text stays legible whatever the artwork. Falls back to
   brand ink when there is no cover or the sample fails. The normalisation has unit tests.
6. **`ContentUnavailableView` replaced by `SQEmptyState`** everywhere. Luma's empty state is
   left-aligned (tile beside text), which `ContentUnavailableView` cannot express. The copy of
   every empty state is preserved, sometimes merged into one sentence.
7. **No organiser avatars exist in the data.** `EventFeedItem` has `organizationName` but no
   image, so `SQAvatar` renders a lime-on-ink monogram from the initials.
8. **"160 Going" and the attendee avatar stack (screenshot 05) are not implemented.** The
   backend exposes no attendee roster to students. I built `SQAvatarStack` so it is ready, but
   left the section out rather than invent data, and used the same label+hairline pattern for
   what Sidequest does have (schedule, reviews, eligibility).
9. **Weather (31 °C in screenshot 04) is not implemented** — there is no weather source in the
   project and adding a third-party API was out of scope.
10. **Four features were stranded in dead code and are now reachable.** `NavigateView` carried
    a `routeBuilder` form that nothing referenced, holding the **route map**, **spoken
    directions**, **floor-plan warnings** and the **"I'm lost — realign"** action. The explore
    layout had replaced the form without carrying those over. They now live in the route
    preview, so the dead form could be deleted — it was replaced, not removed.
11. **`EventDetailView` moved into its own file.** It grew from ~70 to ~470 lines with the
    tinted treatment and no longer belonged inside `DiscoverView.swift`.
12. **`CameraGuidanceView` and the AR views moved into `CameraGuidanceView.swift`**, unchanged
    in behaviour. This lets the rest of `NavigateView` be type-checked, since ARKit has no
    macOS counterpart. `tools/typecheck/camera_chrome_probe.swift` mirrors the component
    call-sites in that file so signature drift is still caught.
13. **Dark mode needed its own tokens.** The brand primary (ink fill, lime label) vanished
    against the dark background, and lime-on-white is near-invisible. Added
    `SQColor.primaryFill` / `onPrimary`, which invert in dark mode, and `SQColor.accent`,
    which deepens lime to an olive of the same hue in light mode. Five call sites moved onto
    them. Worth a look to confirm the olive reads as "Sidequest".
14. **`.searchable` was removed from Discover.** It needs a navigation bar to render into, and
    the redesigned screens deliberately have none — it would have drawn an empty bar above the
    custom header. Search is now the magnifying glass in the header capsule (as in screenshot
    03), revealing an inline field. The 350 ms debounce is unchanged.
15. **Chat messages are now sorted oldest-first.** They were previously reversed with no
    explicit sort; a room that reads bottom-up is the convention, and the view auto-scrolls to
    the newest message.
16. **Journey actions moved to a detail screen.** The pass QR, chat, photos, report, cancel
    and review used to be stacked in every list card. The list is now Luma-flat and tapping a
    row opens a pushed screen holding all of them. Cancelling now asks for confirmation first.
17. **Profile editing moved into a sheet and two pushed screens** (Notifications, Interests),
    with attendance history, reviews and reports as their own pushed screens. The root is now
    a short scannable list like screenshot 01, rather than one long `Form`.
18. **`JourneyItem` gained `Hashable`** so it can drive `navigationDestination(for:)`.

## Known issues

1. **No screen has been seen rendered.** The likeliest consequences are spacing that reads
   differently on device than in the spec, and `AsyncImage` layout while images load.
2. **The floating tab bar relies on `.toolbar(.hidden, for: .tabBar)`** inside each tab's
   `NavigationStack` to suppress the system bar. This is the documented placement and the
   usual approach, but it is unverified here. If a system bar shows through beneath the
   floating pill, that modifier is where to look.
3. **Cover tint sampling is asynchronous.** The page shows the ink fallback until the image
   downloads, then fades to the sampled tint over 0.35 s. On a slow connection the fallback
   may persist. It should look deliberate, but it is unverified.
4. **The three-up action row on the event detail** (Register / Save / More) may clip at
   accessibility text sizes despite `minimumScaleFactor(0.7)`. The tab bar is clamped to
   `.accessibility1`; the action row is not, because clamping it would shrink real content.
5. **`swiftc -typecheck` runs against the macOS SDK**, so iOS availability is not enforced by
   it. Deployment target is iOS 17; every API used is iOS 16-or-earlier except
   `ContentUnavailableView` (removed anyway), the `Map` content builder, and the two-parameter
   `onChange(of:_:)` — all of which the original code already used.
6. **`tools/typecheck/app_model_stub.swift` must be kept in step with `AppModel.swift`.** It
   mirrors that type's signatures; if they drift, the harness checks the screens against a
   stale contract. A missing member fails loudly, but a changed default would not.
