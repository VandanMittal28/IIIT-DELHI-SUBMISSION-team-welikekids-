# Sidequest architecture

## Decision log

### ADR-001 — PostgreSQL is the authorization and transaction boundary

All contextual roles are stored in `college_memberships`, `memberships`, and event assignments. Row-level security protects reads, and privileged mutations use narrowly granted database functions that repeat authorization checks. User-editable Auth metadata is never an authority source. This keeps the Next.js and iOS clients on one contract.

### ADR-002 — Events and editions are separate

An event holds durable identity and organizer metadata. An edition holds capacity and registration/event dates. This supports recurring events without copying organization identity or review history. The first edition is created atomically with the event.

### ADR-003 — Realtime is an invalidation signal

Clients subscribe for update signals, then refetch authoritative rows. Durable state and notification jobs remain in PostgreSQL, so reconnects cannot lose the record of truth.

### ADR-004 — Native iOS, shared backend projection

The student app is SwiftUI and uses native MapKit, camera, speech, and ARKit APIs. The web admin is Next.js/TypeScript. Both read the security-invoker `published_event_feed` projection and call versioned transactional operations.

## Environments

- Local source and builds do not contain credentials or operational fixtures.
- Development/staging uses an explicitly authorized Supabase project or branch.
- Production deployment, APNs, physical route validation, and App Store release require separate owner authorization and hardware credentials.
