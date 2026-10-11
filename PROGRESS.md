# Sidequest implementation progress

Last updated: 2026-10-11 (Asia/Kolkata)

## Acceptance checklist

- [x] Repository and configured-service audit completed.
- [x] Version-controlled Supabase foundation migration created.
- [x] Contextual college and organization roles designed without client-editable authorization metadata.
- [x] Public sign-up creates only an unprivileged profile.
- [x] Atomic, idempotent organizer event + first edition operation implemented.
- [x] Published event feed contract defined for both clients.
- [x] Responsive admin sign-in, honest configuration state, organizer event form, and publishing desk implemented.
- [x] Native SwiftUI app target with authentication, searchable paginated discovery, empty/error states, and event detail implemented.
- [x] Foundation and advisor-hardening migrations applied to the authorized Supabase development project; advisor findings reviewed.
- [x] Atomic registration, FIFO waitlisting, cancellation/promotion, opaque passes, organizer counts, and native My Journey implemented and deployed.
- [ ] Admin authentication and event authoring verified against the backend.
- [x] Native iOS discovery and honest empty state verified against the same backend; authenticated iOS flow remains pending.
- [x] Registration, opaque pass, cancellation/promotion, and personal timeline implemented.
- [x] Campus/landmark authoring, versioned graph routing, closures, MapKit/text/voice fallback, and validation-gated ARKit implemented.
- [x] Camera pass scanning, controlled attendance transitions, derived occupancy, reports, announcements, persistent channels, verified reviews, and sample-size analytics implemented.
- [x] Organization/edition/co-host management, approval, protected media linking, registration rosters, venue changes, moderation, and audited occupancy corrections implemented.
- [x] Expiring email-bound organization role invitations with one-time acceptance implemented; public sign-up cannot grant roles.
- [x] Venue destination/designated-gate landmarks flow from admin authoring into discovery and personal navigation without rebuilding the app.
- [x] Indoor floor-plan rendering, campus map discovery, schedule-conflict/deadline warnings, Realtime invalidation/refetch, and AR tracking interruption handling implemented.
- [x] Protected Storage buckets with published-media and report-evidence read boundaries, persistent notification inbox/jobs, APNs device registration, and retryable delivery worker source implemented.
- [ ] Authenticated real-data staging journey, physical-iPhone verification, APNs worker deployment, public admin deployment, and production release authorization.

## Completed slice acceptance criteria

1. A signed-out or ordinary student cannot create an event.
2. An active organizer can create a draft event and first edition in one transaction.
3. Retrying with the same request ID does not create duplicates.
4. Only published events appear in student discovery.
5. Empty and failed discovery requests are represented honestly.
6. Concurrent registrations never exceed stored edition capacity.
7. A retry with the same request ID returns the same registration and pass.
8. Full editions allocate FIFO waitlist places; cancellation promotes one waiter atomically.
9. Students can refetch registrations and opaque passes after restart through `my_journey`.
10. Anonymous clients cannot register or read private journey data.

## Verification evidence

- Repository remote inspected: reachable, empty repository.
- Supabase official changelog and current Auth/RLS/Swift references reviewed on 2026-10-11.
- Local tools: Xcode 27.0, Swift 6.4, Node 22.23.1.
- Production npm dependency audit: 0 known vulnerabilities before adding Supabase packages.
- Admin: ESLint passed; Next.js 16.4.0 production build passed; production dependency audit reports 0 vulnerabilities.
- Full npm audit reports 5 high-severity findings in the development-only ESLint glob chain; npm currently offers only an inappropriate major downgrade. These packages are not shipped in the production bundle and remain tracked for an upstream fix.
- Admin UI: connected sign-in state exercised in the in-app browser; no fallback data appeared.
- iOS: generic iOS Simulator build passed with Swift 6 and pinned `supabase-swift` 2.55.3.
- iOS: four model/contract tests passed on iPhone 17 Pro simulator; physical-device behavior is unverified.
- iOS: installed and launched against the authorized remote project. The live empty discovery state rendered after fixing Xcode's URL escaping; no fixtures were substituted.
- Database runtime verification: migrations `foundation_auth_events` and `advisor_hardening` are applied to project `dzqfsskcgaowcnbpxzzl` in `ap-southeast-1` (PostgreSQL 17.11).
- Remote catalog verification: 12 public tables, 13 RLS policies, 33 public indexes, two privileged RPCs, and zero operational records or Auth users.
- Remote Data API verification: anonymous discovery returned HTTP 200 with an empty array; anonymous `create_event` returned HTTP 401 and persisted nothing.
- Supabase performance advisor: missing foreign-key indexes and overlapping event policies resolved. Remaining notices are expected unused-index information on a new empty database.
- Supabase security advisor: 0 errors and 43 reviewed warnings remain for intentionally authenticated, `SECURITY DEFINER` transaction RPCs. All revoke `PUBLIC`/`anon`, require `auth.uid()`, repeat contextual authorization, and fix `search_path`.
- Registration migration executed on PostgreSQL 17: confirmed registration, idempotent retry, waitlisting, cancellation, pass revocation, and FIFO promotion all passed.
- Current full migration chain and operational integration suite pass on PostgreSQL 17, including attendance state/idempotency, occupancy, reports, reviews, routing, and closure invalidation.
- Expanded release suite passes cross-role denial, event update/edition/media operations, registration rosters, duplicate scans, wall-clock attendance ordering, audited corrections, assigned-report states, and complete route/review behavior.
- Hosted advisors after the full schema: 0 security errors; 0 performance errors/warnings. All 43 security warnings are reviewed authenticated `SECURITY DEFINER` transaction endpoints under ADR-005.
- Concurrent capacity test: 10 simultaneous requests against capacity 3 produced exactly 3 registrations and 7 waitlist entries.
- Admin registration/capacity counts compile against the shared RLS-scoped summary; native My Journey builds with persistent request IDs and on-device QR pass rendering.
- Remote registration and operational schemas have RLS enabled. Advisors report only expected unused-index information plus the reviewed privileged-RPC warnings.
- Remote anonymous registration returned HTTP 401 and the registration, waitlist, and pass tables remained empty.
- Migration syntax executed successfully on a disposable PostgreSQL 17 cluster: 12 tables, 13 RLS policies, and 2 privileged RPCs created.
- Database behavior verified locally: ordinary student event creation denied; organizer creation succeeded; identical request replay returned the same event/edition with one row each; publish made exactly one event visible through the anonymous discovery view.

## Current blockers and next task

- Blocker: the authorized project has no Auth users. A trusted initial administrator must be invited through Supabase Auth before the real organizer-create → student-discover journey can be exercised. No password should be shared in chat.
- Security action: rotate the database password that was accidentally posted in chat; it was not stored or used by this implementation.
- Blocker: no authorized Apple APNs signing key/team configuration is available, so the delivery worker source is not deployed and push receipt is unverified. The durable inbox and retry jobs are deployed.
- Blocker: no authorized Vercel or other public web deployment target was supplied. Admin is verified locally at `http://localhost:3000` only.
- Blocker: physical route data and validation have not been supplied; no route is marked physically validated and AR behavior remains unverified.
- Next: invite/bootstrap a trusted administrator, enter authorized real college/event/route data through the admin, add student and volunteer accounts, and run the complete persisted staging journey on a physical iPhone.
