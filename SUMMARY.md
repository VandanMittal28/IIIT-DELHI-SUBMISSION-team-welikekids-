# SUMMARY.md — Luma-style redesign of the Sidequest iOS app

Branch `luma-ui-redesign`, 5 commits on top of `main`.

Reference material: the seven Luma screenshots in `screenshots/luma/`, measured and written
up in `DESIGN_NOTES.md`. The running checklist and every judgement call is in `PLAN.md`.

---

## The one thing to know first

**Xcode is not installed on this machine — only the Command Line Tools.** There is no
`xcodebuild`, no `xcrun simctl` and no iOS Simulator, and none appeared during the night. So
the build-screenshot-compare loop in your step 3 could not be run for any screen, and
`screenshots/after/` is empty.

What I did instead was build a four-stage verification harness, `tools/typecheck/run.sh`:

```bash
./tools/typecheck/run.sh
```

| Stage | What it does | Covers |
|---|---|---|
| 0 | Checks every Swift file is registered in the committed `project.pbxproj` | all files |
| 1 | `swiftc -parse` — full syntax check, no SDK needed | 14 files, 100% |
| 2 | `swiftc -typecheck` against the macOS SDK, with shims for the iOS-only API and a stub `AppModel` | 10 of 13 app sources |
| 3 | Compiles and **runs** the `ModelsTests` assertions on macOS, plus new cover-tint tests | the model layer |

All four stages pass and stage 2 is warning-clean. Stage 2 proves the code is internally
consistent — correct argument labels, modifier chains, member names and types. It does **not**
prove it builds for iOS, and it cannot say anything about how a screen looks.

**So: every screen needs one visual pass.** Nothing here has been seen rendered.

Two things also had to be dealt with before any work was possible, both noted in `PLAN.md`:

- **The disk was 100% full with 0 bytes free**, which made every tool call fail, including
  writing files — and would have failed your download too. I cleared ~8 GB of package-manager
  download caches (Homebrew, pip, npm), which regenerate on next use. I did not touch
  `~/Downloads`, the in-progress downloads, or browser data.
- **XcodeGen is not installed**, but `ios/Sidequest.xcodeproj` is committed with explicit file
  references, so new Swift files would have been invisible to the build.
  `tools/sync-xcode-sources.py` registers them; it is idempotent and stage 0 enforces it.

---

## What changed, screen by screen

### Design system (new)

- **`ios/Sidequest/Theme.swift`** — every colour, type size, space, radius and shadow in the
  app, each annotated with the screenshot it came from. Three palettes: light, dark, and the
  cover-derived tint used by the event detail.
- **`ios/Sidequest/Components.swift`** — 31 shared views. The important ones are `SQEventRow`
  (the flat feed row from screenshot 02), `SQListRow` + `SQCard` (the grouped settings rows
  from 01), `SQSheet` (the grabber + circular-close + centered-title chrome from 07),
  `SQEmptyState` (the left-aligned tile-beside-text from 02) and `SQTabBar` (the floating
  capsule from every full-screen shot).

Every component reads `\.sqTint` from the environment, so the same `SQListRow` renders
dark-on-light in Profile and light-on-dark on the event detail with nothing changed at the
call site. No screen hard-codes a colour, font, radius or margin any more — only SF Symbol
glyph sizes remain inline, which is correct.

### Shell and sign-in — `RootView.swift`

The system tab bar is replaced by the floating capsule. Content scrolls underneath it and
every screen reserves 92 pt at the bottom, as Luma does. All five tabs are kept (Luma has
three) with 11 pt labels; tab tags are unchanged so `prepareNavigation` still works.
Sign-in gets the big-title treatment, wells instead of bordered fields, and the brand lockup.

### Discover — `DiscoverView.swift`

The feed is now flat on white and grouped by day, with the two-tone `17 October / Saturday`
headers from screenshot 02 and 88 pt thumbnails. Added the "Browse by Category" chip grid and
a campus rail modelled on 03's "Cities". Search moved into the header capsule (it was
`.searchable`, which needs a navigation bar these screens no longer have). Filters and
Compare became sheets in the 07 style; Compare is now reachable by long-pressing a row.

### Event detail — `EventDetailView.swift` (new file)

The most distinctive screen, and the biggest change. The whole page takes a colour sampled
from the cover art with `CIAreaAverage`, normalised into a deep band so white text stays
legible whatever the artwork, falling back to brand ink. Cover and "featured" strip share one
rounded container; the three-up Register / Save / More row matches 04; every section uses the
label + hairline pattern; the floating back and share circles cross-fade into an inline nav
bar on scroll, as in 05.

### My Journey — `MyJourneyView.swift`

Now a Luma-flat date-grouped list with an upcoming/past toggle. The pass QR, chat, photos,
report, cancel and review used to be stacked inside every list card; they moved to a pushed
detail screen with a proper ticket-styled pass. Cancelling now asks for confirmation.

### Community — `CommunityView.swift`

The segmented control became a chip row. Announcements and the inbox are grouped cards with
coloured icon tiles; event rooms and clubs are the avatar + name + subtitle rows from 07. The
chat room got a real composer with a send button and auto-scroll, and hides the floating tab
bar so the bar does not sit on top of the text field.

### Profile — `AccountView.swift`

Rebuilt as screenshot 01: a profile card, then grouped cards with coloured icon tiles under
grey section headers. The old single long `Form` is now a short scannable root, with editing
in a sheet and pushed screens for Notifications, Interests, Attendance History, Submitted
Reviews and My Reports.

### Navigate — `NavigateView.swift`, `CameraGuidanceView.swift` (new file)

Grouped cards for the route planner, menu-based landmark pickers, the photo rail for nearby
landmarks, and the fanned-thumbnail map annotation from 06. The AR and camera views moved to
their own file so the rest can be type-checked; their chrome now uses the shared components
in light-on-dark form.

---

## Decisions you should look at

The full list of 18 is in `PLAN.md` under "Decisions to review". The ones most worth a second
opinion:

1. **Four features were stranded in dead code, and I revived rather than deleted them.**
   `NavigateView` carried a `routeBuilder` form that nothing referenced, holding the **route
   map**, **spoken directions**, **floor-plan warnings** and the **"I'm lost — realign"**
   action. The explore layout had replaced the form at some point without carrying those parts
   over, so they were unreachable in the shipped app. They now live in the route preview.
   If that was deliberate rather than an oversight, this is the change to undo.
2. **Dark mode needed its own brand tokens.** Ink-on-lime disappeared against the dark
   background and lime-on-white is near-invisible, so `primaryFill`/`onPrimary` invert in dark
   mode and `accent` deepens lime to an olive in light mode. Worth confirming the olive still
   reads as Sidequest.
3. **Chat messages are now sorted oldest-first** with auto-scroll to the newest. They were
   previously reversed with no explicit sort.
4. **"160 Going", the attendee avatar stack and the weather readout are not implemented.**
   No backend data exists for any of them. I built `SQAvatarStack` so the first is ready to
   wire up, but did not invent data to fill the space.
5. **I purged ~8 GB of package-manager caches** to get the disk under 100%. Nothing of yours
   was touched, but you should know it happened.

## What is unfinished or still risky

1. **No screen has been seen rendered.** This is the headline gap. Spacing that reads right in
   the spec can read wrong on glass, and `AsyncImage` layout during loading is unverified.
2. **The floating tab bar depends on `.toolbar(.hidden, for: .tabBar)`** inside each tab's
   `NavigationStack` to suppress the system bar. That is the documented placement, but if a
   system bar shows through beneath the pill, that is the line to change.
3. **Cover tint sampling is asynchronous** — the ink fallback shows until the cover downloads,
   then fades over 0.35 s. On a slow connection the fallback may linger.
4. **The three-up action row on the event detail may clip at accessibility text sizes**
   despite `minimumScaleFactor(0.7)`.
5. **`tools/typecheck/app_model_stub.swift` must be kept in step with `AppModel.swift`.** A
   removed member fails the harness loudly; a changed default would not.
6. **The XCTest bundle itself was never executed** — stage 3 re-runs its assertions as a macOS
   binary instead, which is the closest available substitute.

## How to run it

The app is unchanged in how it builds and configures:

```bash
cp ios/Config/Sidequest.xcconfig ios/Config/Local.xcconfig
```

Put your Supabase URL and publishable key in `Local.xcconfig`, then open
`ios/Sidequest.xcodeproj` in Xcode and run the `Sidequest` scheme on an iOS 17+ simulator.
With an empty backend every screen shows its empty state, which is the fastest way to review
the new `SQEmptyState` treatment.

If you prefer to regenerate the project rather than use the committed one:

```bash
brew install xcodegen && cd ios && xcodegen generate
```

To re-run the verification harness at any time:

```bash
./tools/typecheck/run.sh
```

### Suggested review order

Open these five first — they carry most of the design and most of the risk:

1. `ios/Sidequest/Theme.swift` and `Components.swift` — if the tokens are wrong, everything is.
2. `EventDetailView.swift` — the cover tint is the most novel piece.
3. `DiscoverView.swift` — the feed is the screen you will look at most.
4. `AccountView.swift` — the biggest structural change to existing behaviour.
5. `NavigateView.swift` — check decision 1 above.
