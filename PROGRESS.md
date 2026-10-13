# Sidequest implementation progress

Last updated: 2026-10-13 (Asia/Kolkata)

## Acceptance checklist

- [x] Repository and configured-service audit completed.
- [x] Version-controlled Supabase foundation migration created.
- [x] Contextual college and organization roles designed without client-editable authorization metadata.
- [x] Public sign-up creates only an unprivileged profile.
- [x] Native student onboarding supports email/password account creation, handles confirmation-required responses honestly, and does not grant contextual roles.
- [x] Atomic, idempotent organizer event + first edition operation implemented.
- [x] Published event feed contract defined for both clients.
- [x] Responsive admin sign-in, honest configuration state, organizer event form, and publishing desk implemented.
- [x] Native SwiftUI app target with authentication, searchable paginated discovery, empty/error states, and event detail implemented.
- [x] Foundation and advisor-hardening migrations applied to the authorized Supabase development project; advisor findings reviewed.
- [x] Atomic registration, FIFO waitlisting, cancellation/promotion, opaque passes, organizer counts, and native My Journey implemented and deployed.
- [x] Admin authentication and scoped college-administrator access verified against the hosted backend; event authoring awaits authorized organization/event content.
- [x] Native iOS discovery and honest empty state verified against the same backend; authenticated iOS flow remains pending.
- [x] Registration, opaque pass, cancellation/promotion, and personal timeline implemented.
- [x] Campus/landmark authoring, versioned graph routing, closures, MapKit/text/voice fallback, and validation-gated ARKit implemented.
- [x] Camera pass scanning, controlled attendance transitions, derived occupancy, reports, announcements, persistent channels, verified reviews, and sample-size analytics implemented.
- [x] Volunteer QR scanning uses an in-app ZXing decoder instead of depending on the optional browser `BarcodeDetector`; denied/unavailable cameras retain manual opaque-token entry and never claim offline admission.
- [x] Organization/edition/co-host management, approval, protected media linking, registration rosters, venue changes, moderation, and audited occupancy corrections implemented.
- [x] Expiring email-bound organization role invitations with one-time acceptance implemented; public sign-up cannot grant roles.
- [x] Venue destination/designated-gate landmarks flow from admin authoring into discovery and personal navigation without rebuilding the app.
- [x] Indoor floor-plan rendering, campus map discovery, schedule-conflict/deadline warnings, Realtime invalidation/refetch, and AR tracking interruption handling implemented.
- [x] Camera prompts now derive from stored outdoor/indoor route geometry; spatial arrows require physical validation and a confirmed landmark facing reference, and use tracked AR anchors rather than a fixed decorative overlay.
- [x] Route closures use retry-stable request IDs, invalidate the campus route sequence, block graph traversal, and durably notify attendees whose scheduled campus session overlaps the closure.
- [x] Active closures are listed in the admin and can be reopened through an authorized, audited, idempotent operation that restores routing and notifies affected attendees.
- [x] Protected Storage buckets with published-media and report-evidence read boundaries, persistent notification inbox/jobs, APNs device registration, and retryable delivery worker source implemented.
- [x] Native report evidence selection/upload and an idempotent, ownership-validating attachment-link RPC implemented and locally verified.
- [x] Notification delivery leases, stale-worker protection, per-token APNs environment routing, terminal-response handling, and invalid-token deactivation implemented and locally verified.
- [x] Notification settings now govern push jobs, venue updates keep their category, and idempotent registration/event deadline reminders derive from stored records while remaining visible in the inbox.
- [x] Admin report evidence uses protected signed links, and report assignment uses a scoped real-staff selector rather than manually entered user IDs.
- [x] Students can report a specific discussion message; the source remains linked through moderation, duplicate reports are prevented, and the admin can triage, hide, or restore it.
- [x] Event details load organizer-authored session schedules, and verified review analytics distinguish the current edition from prior-edition feedback with explicit sample sizes.
- [x] Student Profile loads self-scoped persisted attendance history and submitted reviews, including updated review content after editing.
- [x] Discover filters cover category, date, college, free or maximum price, and eligibility through the authoritative backend query.
- [x] Host and co-host organizers share scoped management rights, while event staff assignment is limited to an authorized real-member selector and is retry-idempotent.
- [x] Community includes backend-backed college and organization profile pages with persistent follow controls.
- [x] Announcement, venue-change, and cancellation retries cannot duplicate authoritative notifications or audit work; venue college scope and cancellation timestamps are enforced.
- [x] Report status transitions require every specified state and an edition-assigned staff member; same-state retries are idempotent.
- [x] Existing session schedules, landmarks, and draft route edges can be edited through audited, server-authorized admin workflows; published route graphs remain immutable and suspended accounts lose edition access immediately at the database boundary.
- [x] Admin website deployed to Vercel from GitHub `main` with the `admin` root and production Supabase configuration.
- [x] Temporary college-issued username login added on top of Supabase Auth; no password is stored in source control.
- [ ] Authenticated real-data staging journey, physical-iPhone verification, APNs worker deployment, and iOS production release authorization.

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
- Volunteer scanner: production build includes `@zxing/browser` 0.1.5 with Node-22-compatible `@zxing/library` 0.21.3; the camera decoder is loaded on demand and still requires volunteer-phone camera verification.
- Full npm audit reports 5 high-severity findings in the development-only ESLint glob chain; npm currently offers only an inappropriate major downgrade. These packages are not shipped in the production bundle and remain tracked for an upstream fix.
- Admin UI: connected sign-in state exercised locally and at `https://sidequest-admin-rho.vercel.app`; no fallback data appeared.
- Production admin: the temporary username account signed in successfully, exposed only its scoped IIIT Delhi authoring tools, survived a browser reload, and signed out successfully. The password remains outside source control.
- iOS: generic iOS Simulator build passed with Swift 6 and pinned `supabase-swift` 2.55.3.
- iOS: five model/contract tests passed on iPhone 17 Pro simulator, including outdoor bearing, rotated indoor bearing, and landmark-relative camera alignment; physical-device behavior is unverified.
- iOS student account creation compiles against `supabase-swift` 2.55.3 and distinguishes immediate sessions from confirmation-required sign-ups; a real student email is still required for hosted confirmation testing.
- iOS: installed and launched against the authorized remote project. The live empty discovery state rendered after fixing Xcode's URL escaping; no fixtures were substituted.
- Database runtime verification: migrations `foundation_auth_events` and `advisor_hardening` are applied to project `dzqfsskcgaowcnbpxzzl` in `ap-southeast-1` (PostgreSQL 17.11).
- Remote bootstrap verification: one Auth user, one IIIT Delhi college record, and one active scoped college-administrator membership exist. No fictional event, organization, route, review, or analytics records were added.
- Remote Data API verification: anonymous discovery returned HTTP 200 with an empty array; anonymous `create_event` returned HTTP 401 and persisted nothing.
- Supabase performance advisor: missing foreign-key indexes and overlapping event policies resolved. Remaining notices are expected unused-index information on a new empty database.
- Supabase security advisor: 0 errors and 43 reviewed warnings remain for intentionally authenticated, `SECURITY DEFINER` transaction RPCs. All revoke `PUBLIC`/`anon`, require `auth.uid()`, repeat contextual authorization, and fix `search_path`.
- Registration migration executed on PostgreSQL 17: confirmed registration, idempotent retry, waitlisting, cancellation, pass revocation, and FIFO promotion all passed.
- Current full migration chain and operational integration suite pass on PostgreSQL 17, including attendance state/idempotency, occupancy, reports, reviews, routing, and closure invalidation.
- Report attachment integration passes locally: only the author can link an owned object at the report-scoped path, unrelated users are denied, and retrying creates neither a duplicate attachment nor a duplicate audit record. Hosted migration application remains pending explicit confirmation.
- Notification delivery integration passes locally: an expired processing lease is reclaimed, a stale completion is rejected, terminal failures stop retrying, and an invalid APNs token is deactivated. Deno type checking and three APNs classification tests pass. Hosted migration/function deployment and physical receipt remain pending.
- Reminder integration passes locally: a due reminder is created once across repeated worker runs, disabling reminder pushes suppresses its delivery job without removing the inbox record, malformed preference values are rejected, and venue changes are categorized separately from ordinary announcements.
- Report-operations integration passes locally: event managers receive only their edition's assignable staff, an ordinary student is denied, the admin production build succeeds, and protected evidence is fetched through its existing RLS boundary before short-lived signing.
- Route-closure integration passes locally: the active edge is excluded and then restored, one affected attendee notification is persisted for each change, student reopening is denied, and retries do not duplicate work.
- Message-report integration passes locally: the exact source is linked once, outsider and self-report access checks are server-side, hidden content disappears for students but remains available to managers, and moderation is auditable.
- Event-detail integration passes locally: the published schedule view returns the stored session/venue, the edition review view matches its real review row, iOS tests pass, and the admin production build shows edition-specific samples.
- Profile-history integration passes locally: the student sees their three attendance transitions and one review, an unrelated account sees neither, and the iOS simulator tests pass.
- Discover's complete filter set compiles and the iOS simulator tests pass; filtering remains server-backed and preserves honest empty/error states.
- Co-host/staff integration passes locally: co-host access succeeds, a non-member assignment is denied, candidate rows come from active host memberships, retry creates no duplicate assignment/audit, and the admin build passes.
- College and organization profile navigation compiles and the iOS simulator tests pass; profile content and follow state come from Supabase records.
- Event-update retry integration passes locally: announcements and venue changes replay by request ID, cancellation replays from locked terminal state, notification/audit counts stay at one, and the admin production build passes.
- Strict report-state integration passes locally: skip/null/unassigned cases fail, five history rows persist, and a replay does not duplicate history or notification work.
- Managed-editing integration passes locally on PostgreSQL 17: session bounds and venue college are enforced, landmark and draft-edge changes persist with audits, a student edit is denied, published route calculation uses the changed distance, and a suspended profile cannot read its prior edition channel. Admin lint and production build pass after the React component changes.
- Expanded release suite passes cross-role denial, event update/edition/media operations, registration rosters, duplicate scans, wall-clock attendance ordering, audited corrections, assigned-report states, and complete route/review behavior.
- Hosted advisors after the full schema: 0 security errors; 0 performance errors/warnings. All 43 security warnings are reviewed authenticated `SECURITY DEFINER` transaction endpoints under ADR-005.
- Concurrent capacity test: 10 simultaneous requests against capacity 3 produced exactly 3 registrations and 7 waitlist entries.
- Admin registration/capacity counts compile against the shared RLS-scoped summary; native My Journey builds with persistent request IDs and on-device QR pass rendering.
- Remote registration and operational schemas have RLS enabled. Advisors report only expected unused-index information plus the reviewed privileged-RPC warnings.
- Remote anonymous registration returned HTTP 401 and the registration, waitlist, and pass tables remained empty.
- Migration syntax executed successfully on a disposable PostgreSQL 17 cluster: 12 tables, 13 RLS policies, and 2 privileged RPCs created.
- Database behavior verified locally: ordinary student event creation denied; organizer creation succeeded; identical request replay returned the same event/edition with one row each; publish made exactly one event visible through the anonymous discovery view.

## Current blockers and next task

- Temporary access: the requested username login is active against Supabase Auth and the scoped IIIT Delhi administrator membership is verified. Replace the temporary password before sharing the site beyond this test.
- Security action: rotate the database password that was accidentally posted in chat; it was not stored or used by this implementation.
- Blocker: no authorized Apple APNs signing key/team configuration is available, so the delivery worker source is not deployed and push receipt is unverified. The durable inbox and retry jobs are deployed.
- Vercel production: `https://sidequest-admin-rho.vercel.app`, connected to GitHub `main`; pushes create deployments from the `admin` root.
- Blocker: physical route data and validation have not been supplied; no route is marked physically validated and AR behavior remains unverified.
- Hosted database: every version-controlled migration through `20261013060346_managed_schedule_route_editing.sql` is applied and visible in Supabase migration history. The APNs function itself still requires Apple credentials before deployment.
- Next: invite/bootstrap a trusted administrator, enter authorized real college/event/route data through the admin, add student and volunteer accounts, and run the complete persisted staging journey on a physical iPhone.
