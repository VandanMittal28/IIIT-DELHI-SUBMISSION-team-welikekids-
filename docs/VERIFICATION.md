# Verification record

Verified locally on 2026-10-11 (Asia/Kolkata).

## Admin

- `npm run lint` — passed.
- `npm run build` — passed with Next.js 16.4.0 and TypeScript.
- `npm audit --omit=dev` — 0 vulnerabilities.
- Browser exercise at `http://localhost:3000` — setup state rendered correctly with no backend and no substituted event data.
- Full audit — 5 high findings confined to the ESLint development dependency glob chain. The reported npm remediation is an inappropriate major downgrade; this remains an explicit tooling risk rather than a shipped runtime dependency.

## Native iOS

- Generic iOS Simulator build — passed with Swift 6, iOS 17 deployment target, and `supabase-swift` 2.55.3.
- iPhone 17 Pro simulator unit test — 1 passed, 0 failed.
- Physical iPhone verification — not performed. Camera, ARKit, scanning, voice, location, notifications, and device persistence are not yet implemented or verified.

## Database

The migration was executed on a disposable PostgreSQL 17 cluster with minimal Supabase Auth role/schema equivalents:

- 12 public tables created.
- 13 RLS policies created.
- `create_event` and `publish_event` created with restricted execution grants.
- Ordinary student event creation was rejected.
- Active organizer creation succeeded.
- Repeating the same request ID returned the same event and edition; table counts remained one each.
- Publishing succeeded and exactly one record became visible through `published_event_feed` as `anon`.

This validates SQL structure and core transaction/authorization behavior locally. It does not replace applying the migration, running Supabase advisors, and testing Auth/Data API behavior on the authorized Sidequest project.
