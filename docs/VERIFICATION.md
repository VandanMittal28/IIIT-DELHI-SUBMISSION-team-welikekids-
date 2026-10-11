# Verification record

Verified locally on 2026-10-11 (Asia/Kolkata).

## Admin

- `npm run lint` — passed.
- `npm run build` — passed with Next.js 16.4.0 and TypeScript.
- `npm audit --omit=dev` — 0 vulnerabilities.
- Browser exercise at `http://localhost:3000` — connected organizer sign-in rendered against the authorized Supabase project with no substituted event data.
- Responsive volunteer/operations source includes camera QR decoding with manual fallback, confirmed-only scan feedback, occupancy freshness, reports, announcements, scoped management, protected uploads, and Leaflet map authoring. Authenticated exercise is blocked by the empty Auth tenant.
- Full audit — 5 high findings confined to the ESLint development dependency glob chain. The reported npm remediation is an inappropriate major downgrade; this remains an explicit tooling risk rather than a shipped runtime dependency.

## Native iOS

- Generic iOS Simulator build — passed with Swift 6, iOS 17 deployment target, and `supabase-swift` 2.55.3.
- iPhone 17 Pro simulator unit tests — 4 passed, 0 failed (event, registration/journey, route coordinate contract, profile preferences).
- Installed simulator app launched against the remote Supabase project and rendered “Nothing published yet” from the authoritative empty feed.
- Initial launch exposed an invalid Xcode URL expansion; the local `.xcconfig` URL is now escaped correctly and the relaunch remained running.
- Registration client build — passed with persistent retry IDs, shared `my_journey` reads, cancellation, and opaque QR pass rendering.
- Latest simulator launch shows five native tabs and the authoritative empty discovery state. Navigation uses MapKit, native speech, camera permission handling, and ARKit world tracking only for physically validated routes. Community, reports, inbox, follows, profile preferences, saved events, comparison, and verified reviews are connected to Supabase.
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

- Remote state: 12 public tables, 13 RLS policies, 33 public indexes, 2 privileged RPCs, 0 Auth users, and 0 colleges, organizations, or events.
- Data API: anonymous `published_event_feed` returned HTTP 200 with `[]`; anonymous `create_event` returned HTTP 401 (`permission denied`) and persisted nothing.
- Performance advisor: no missing foreign-key-index or overlapping-policy warnings remain. Unused-index notices are expected while the database is empty.
- Security advisor: two warnings identify the intentional authenticated `SECURITY DEFINER` RPCs (`create_event`, `publish_event`). Their execution is revoked from `PUBLIC` and `anon`; each requires `auth.uid()`, performs contextual authorization, and has an empty fixed `search_path`. This is an accepted, documented boundary for the transactional API—not a clean-advisor claim.

Remote authenticated authoring is still pending because the project has no Auth users. Operational content was not fabricated to bypass that prerequisite.

## Operational platform

- Hosted migrations through `notification_delivery_worker` applied and recorded in migration history.
- Anonymous landmark discovery returns HTTP 200 with an empty array. Anonymous `create_campus` and `record_attendance` return HTTP 401; no mutation is persisted.
- Operational schema includes buildings/floors/landmarks, versioned route graph and closures, attendance ledger/corrections, announcements/channels/messages/follows, report workflow/history, verified reviews, device tokens/inbox/delivery jobs, audit records, co-hosts, and saved events.
- Storage buckets for event, campus, and report media are private with scoped write policies.
- Security-advisor actionable findings from the operational migration were resolved: missing FK indexes added, server-only tables have explicit deny policies, and read-only route calculation is security invoker.
- APNs Edge Function source and service-role-only claim/complete functions are implemented. Deployment/receipt verification is blocked by unavailable Apple credentials.
- Full current migration chain executes on PostgreSQL 17. The isolated operational suite passes registration/pass issuance, idempotent entry, exit/re-entry, occupancy, report transitions, attendance-gated review/sample size, graph routing, and active-closure no-route behavior; its transaction rolls back all fixtures.
- Current hosted advisors: 0 security errors, 0 performance errors, and 0 performance warnings. The 34 security warnings are one reviewed category: authenticated callers can execute the intentionally privileged transaction RPCs described in ADR-005.

## Registration and passes

- Full migration chain executed on disposable PostgreSQL 17.
- First student received `registered` plus one opaque pass; identical request replay returned the same registration and pass.
- Second student at capacity received waitlist position 1 and no pass.
- Cancelling the confirmed student revoked that pass and promoted the waiting student with one new active pass.
- Concurrent test launched 10 registration transactions against capacity 3: exactly 3 became registered and 7 became waitlisted.
- Remote migration applied; 14 public tables all have RLS enabled.
- Remote anonymous `register_for_event` call returned HTTP 401 (`permission denied`) and persisted no data.
- Supabase performance advisor reports only unused-index informational notices on the empty project. Security advisor reports four intentional privileged RPC warnings (`create_event`, `publish_event`, `register_for_event`, `cancel_registration`) under ADR-005.
