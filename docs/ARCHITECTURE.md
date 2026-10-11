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

### ADR-005 — Narrow privileged RPCs are the mutation boundary

Multi-table and state-transition mutations use authenticated `SECURITY DEFINER` RPCs with an empty fixed `search_path`, explicit `auth.uid()` checks, contextual role checks, and execution revoked from `PUBLIC` and `anon`. This intentionally triggers Supabase advisor warnings and is reviewed per RPC. Direct table writes remain unavailable to clients, preventing callers from bypassing transaction and transition rules.

### ADR-006 — Edition rows serialize capacity allocation

Registration and cancellation lock the relevant `event_editions` row before counting or changing confirmed places. This creates one transaction boundary for concurrent capacity decisions without relying on client counts. Request IDs make retries safe; cancellation revokes the pass and promotes the FIFO waitlist in the same transaction.

### ADR-007 — Navigation coordinates and validation are explicit

Outdoor nodes use WGS84 latitude/longitude. Indoor nodes use floor-plan pixel coordinates plus the floor's scale, rotation, and geographic origin. Routes are calculated from a versioned graph with active closures removed. “I’m here” confirms a landmark only; it does not claim precise pose. Map/text/voice work for every published route, while ARKit arrows are enabled only when `physical_validation_complete` is true.

### ADR-008 — Attendance is a transition ledger

Opaque passes resolve server-side to a registration. `record_attendance` enforces entry → exit → optional re-entry and stores idempotent scan requests. Occupancy is derived from the ledger plus audited corrections and always carries a freshness timestamp.

### ADR-009 — Notifications are durable before delivery

User-visible notification rows and per-device delivery jobs are committed with the triggering business change. A service-role-only worker claims jobs with `SKIP LOCKED`, delivers through APNs, and records retry state with exponential backoff. The in-app inbox remains authoritative when push permission or delivery is unavailable.

### ADR-010 — Attendance ordering uses wall-clock transition time

PostgreSQL `now()` is constant for an entire transaction and cannot order multiple scans made inside that transaction. Attendance inserts therefore use `clock_timestamp()` and then order by `recorded_at, id`. The ledger remains immutable, retries remain keyed independently, and enter/exit/re-entry validation always sees the transition that was actually recorded last.

### ADR-011 — Private media is authorized by its owning record

Storage objects remain in private buckets and clients receive short-lived signed URLs. Published event covers and active published campus references are readable through record-aware policies. Draft event media is limited to event managers; report evidence is limited to the reporter and edition managers. A signed-in account alone never grants blanket media access.

### ADR-012 — Camera arrows require route geometry and explicit landmark alignment

Camera guidance derives each step bearing from the returned route node order: WGS84 bearings outdoors and floor-pixel bearings plus the stored floor rotation indoors. The student must confirm a landmark with a stored facing direction, and the AR session treats that direction as its local reference. Each visible arrow is an `ARAnchor` placed from the current tracked camera pose using the route-derived relative bearing. Floor transitions without a trustworthy bearing show text/map/voice guidance and no arrow. The entire camera mode remains unavailable until the route is marked physically validated.

## Environments

- Local source and builds do not contain credentials or operational fixtures.
- Development/staging uses an explicitly authorized Supabase project or branch.
- Production deployment, APNs, physical route validation, and App Store release require separate owner authorization and hardware credentials.
