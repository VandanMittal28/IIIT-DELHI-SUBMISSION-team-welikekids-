# Verification record

Verified locally and against the authorized hosted services on 2026-10-12 (Asia/Kolkata).

## Admin

- `npm run lint` — passed.
- `npm run build` — passed with Next.js 16.4.0 and TypeScript.
- `npm audit --omit=dev` — 0 vulnerabilities.
- Browser exercise at `http://localhost:3000` and `https://sidequest-admin-rho.vercel.app` — the requested username form authenticated through Supabase, loaded scoped IIIT Delhi administrator tools, retained the session across reload, and signed out successfully. No substituted event data appeared.
- Vercel production deployment — passed from the latest GitHub `main` admin release, using the `admin` root, native Next.js preset, and Production/Preview public Supabase configuration. The public deployment returned the Sidequest Admin sign-in page over HTTPS.
- Responsive volunteer/operations source includes camera QR decoding with manual fallback, confirmed-only scan feedback, occupancy freshness/corrections, reports and assignments, announcements, moderation, registration rosters, editions/co-hosts, approval/cancellation, protected uploads, and Leaflet/floor-plan graph authoring. College-admin authoring access is verified; volunteer workflows still require authorized real event content.
- The report queue now resolves protected evidence to short-lived signed links and uses a scoped server-provided event-staff directory for assignment. Admin lint and production build pass; the integration suite proves an ordinary student cannot read that directory.
- Camera QR decoding no longer relies on the optional `BarcodeDetector` API: ZXing is bundled and loaded only when the volunteer starts the camera. Lint, TypeScript, the production build, and the production dependency audit pass; physical phone scanning remains unverified.
- Full audit — 5 high findings confined to the ESLint development dependency glob chain. The reported npm remediation is an inappropriate major downgrade; this remains an explicit tooling risk rather than a shipped runtime dependency.

## Native iOS

- Generic iOS Simulator build — passed with Swift 6, iOS 17 deployment target, and `supabase-swift` 2.55.3.
- iPhone 17 Pro simulator unit tests — 5 passed, 0 failed (event, registration/journey, route coordinate contract, profile preferences, and route-derived camera bearings/alignment).
- Report evidence build — passed with native photo selection, bounded JPEG upload to the private `report-attachments` bucket, server-validated record linking, and failed-link cleanup. Physical photo-library exercise remains pending on an iPhone.
- Installed simulator app launched against the remote Supabase project and rendered “Nothing published yet” from the authoritative empty feed.
- Initial launch exposed an invalid Xcode URL expansion; the local `.xcconfig` URL is now escaped correctly and the relaunch remained running.
- Registration client build — passed with persistent retry IDs, shared `my_journey` reads, cancellation, and opaque QR pass rendering.
- Student onboarding build — passed with native email/password account creation and distinct immediate-session versus email-confirmation handling. Hosted email delivery is not claimed because no authorized student email was supplied for the test.
- Latest simulator launch shows five native tabs and the authoritative empty discovery state. Published event covers and landmark reference photos load from short-lived signed URLs when present. Navigation uses MapKit, published floor-plan imagery with stored indoor coordinates, native speech, camera permission/tracking-interruption handling, and ARKit world tracking only for physically validated routes. Camera steps derive bearings from WGS84 nodes or floor pixels plus stored rotation; arrows use tracked anchors relative to the explicitly confirmed landmark-facing reference, while unsupported transitions remain text/map/voice only. Campus map discovery, conflict/deadline warnings, Realtime-triggered refetch, community, reports, inbox, follows, profile preferences, saved events, comparison, and verified reviews are connected to Supabase.
- Physical iPhone verification — not performed. Implemented camera, ARKit, scanning, voice, location, and APNs behaviors remain unverified on hardware.

## Database

The migration was executed on a disposable PostgreSQL 17 cluster with minimal Supabase Auth role/schema equivalents:

- 12 public tables created.
- 13 RLS policies created.
- `create_event` and `publish_event` created with restricted execution grants.
- Ordinary student event creation was rejected.
- Active organizer creation succeeded.
- Repeating the same request ID returned the same event and edition; table counts remained one each.
- Publishing succeeded and exactly one record became visible through `published_event_feed` as `anon`.

The foundation and advisor-hardening migrations were also applied to authorized project `dzqfsskcgaowcnbpxzzl` on 2026-10-11.

- Remote bootstrap state: one Auth user, one IIIT Delhi college record, and one active college-administrator membership. There are no organizations or events, so the production interface presents real empty states.
- Data API: anonymous `published_event_feed` returned HTTP 200 with `[]`; anonymous `create_event` returned HTTP 401 (`permission denied`) and persisted nothing.
- Performance advisor: no missing foreign-key-index or overlapping-policy warnings remain. Unused-index notices are expected while the database is empty.
- Security advisor initially identified the intentional authenticated `SECURITY DEFINER` RPC boundary. The complete hosted schema now reports 0 errors and 43 warnings in that single reviewed category. Execution is revoked from `PUBLIC` and `anon`; every endpoint requires `auth.uid()`, performs contextual authorization, and has a fixed empty `search_path`. This is an accepted, documented boundary for the transactional API—not a clean-warning claim.

Remote authentication and scoped college-administrator reads are verified. Operational content was not fabricated; event authoring remains pending until the owner enters an authorized organization and real event.

## Operational platform

- Hosted migrations through `route_read_policy_consolidation` applied and recorded in migration history.
- Anonymous landmark discovery returns HTTP 200 with an empty array. Anonymous `create_campus` and `record_attendance` return HTTP 401; no mutation is persisted.
- Operational schema includes buildings/floors/landmarks, versioned route graph and closures, attendance ledger/corrections, announcements/channels/messages/follows, report workflow/history, verified reviews, device tokens/inbox/delivery jobs, audit records, co-hosts, and saved events.
- Storage buckets for event, campus, and report media are private with scoped writes. Published event/floor/landmark media can be signed for authorized public rendering; draft event media remains staff-scoped, and report evidence is limited to its reporter and edition managers.
- Security-advisor actionable findings from the operational migration were resolved: missing FK indexes added, server-only tables have explicit deny policies, and read-only route calculation is security invoker.
- APNs Edge Function source and service-role-only reminder/claim/complete functions are implemented. Deno type checking and three Apple-response classification tests pass. The PostgreSQL suite verifies idempotent real-record reminders, push-preference suppression with inbox persistence, venue-change categorization, expired-lease recovery, stale-attempt rejection, terminal failure recording, environment propagation, and invalid-token deactivation. Deployment and receipt verification remain blocked by unavailable Apple credentials.
- Full current migration chain executes on PostgreSQL 17. The isolated operational suite passes event update/edition/media workflows, cross-role denial, registration roster, registration/pass issuance, retry and duplicate scan behavior, exit/re-entry ordering, occupancy corrections, exact report assignment transitions, attendance-gated review/sample size, graph routing, active-closure no-route behavior, closure retry idempotency and exactly-once affected-attendee notification, and report-media cross-user denial; its transaction rolls back all fixtures.
- The attachment-linking migration and expanded suite pass on PostgreSQL 17: the report author can link only an owned object under the report-scoped path, an unrelated user is denied, and a retry returns the same attachment without a second row or audit entry. Hosted application of this migration is pending owner confirmation.
- The route-closure migrations and admin build pass locally: only a college administrator can close or reopen an edge, overlapping registered/waitlisted attendees receive one durable alert per change, routing excludes and then restores the edge, and replaying either change does not duplicate route state, alerts, or audit work. Hosted application remains pending owner confirmation.
- Message reporting passes locally across PostgreSQL, native iOS, and the admin production build: a student can link one report to a visible message, retries return that report, outsiders and self-reporting are rejected, moderation hides the message from student reads while retaining manager triage context, and the admin can hide or restore it with an audit record. Hosted application remains pending owner confirmation.
- Published event-detail verification passes locally: PostgreSQL returns the real session row with venue context, edition review summaries match the attendance-verified review record, the iOS simulator build renders current versus prior edition samples separately, and the admin production build reports ratings per edition rather than as an undifferentiated event score.
- Profile-history verification passes locally: the signed-in student sees exactly three recorded enter/exit/re-entry transitions and one submitted review through self-scoped security-invoker views, an unrelated account receives no rows, and the iOS simulator test build renders both sections and refreshes them after review submission.
- Discover filtering compiles and passes the iOS simulator test run with backend-applied category, date, college, free/maximum-price, and eligibility constraints; no client-side fictional result set is substituted.
- Co-host/staff verification passes locally: a co-host organizer receives scoped management access, the candidate directory contains the three real host/co-host members, an unrelated account cannot be assigned, assignment retry creates one row and one audit record, and the admin production build uses the candidate selector without raw UUID entry.
- Community profile navigation compiles and passes the iOS simulator test run: college pages use stored name/time zone/coordinates and list their active organizations, while organization pages use stored descriptions and persistent follow state.
- Event-update retry verification passes locally: repeated announcement and venue-change request IDs return the original result with exactly one attendee notification; repeated cancellation returns the terminal event without a second notification or audit row and records `cancelled_at`; a cross-college venue is rejected. The admin lint and production build pass with persistent request IDs.
- Report-state verification passes locally: skipped assignment, a missing assignee, and a host member not assigned to the edition are rejected; the five required history states persist in order; replaying acknowledgement adds neither history nor notification; exactly four update notifications are produced.
- The release suite exposed and fixed transaction-timestamp ambiguity in attendance ordering. Each transition now records `clock_timestamp()` and the complete suite passes.
- Expiring email-bound organization invitation creation/acceptance passes locally. Anonymous invitation creation returns HTTP 401 on the hosted project.
- Published event discovery with venue/destination columns returns HTTP 200 from the hosted API; the empty authorized database returns `[]` rather than fixtures.
- Current hosted advisors: 0 security errors, 0 performance errors, and 0 performance warnings. The 43 security warnings are one reviewed category: authenticated callers can execute the intentionally privileged transaction RPCs described in ADR-005.

## Registration and passes

- Full migration chain executed on disposable PostgreSQL 17.
- First student received `registered` plus one opaque pass; identical request replay returned the same registration and pass.
- Second student at capacity received waitlist position 1 and no pass.
- Cancelling the confirmed student revoked that pass and promoted the waiting student with one new active pass.
- Concurrent test launched 10 registration transactions against capacity 3: exactly 3 became registered and 7 became waitlisted.
- Remote migration applied; 14 public tables all have RLS enabled.
- Remote anonymous `register_for_event` call returned HTTP 401 (`permission denied`) and persisted no data.
- Supabase performance advisor reports only unused-index informational notices on the empty project. Security advisor reports four intentional privileged RPC warnings (`create_event`, `publish_event`, `register_for_event`, `cancel_registration`) under ADR-005.
