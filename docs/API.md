# Shared API contract

The Supabase project URL and publishable key are client configuration. Secret/service-role keys are server-only and are not required by the current clients.

## Errors

Privileged RPCs return PostgREST errors whose `message` is a JSON object:

```json
{"code":"FORBIDDEN","message":"Organizer access is required."}
```

Clients must show an honest failure state and may retry idempotent requests. They must never infer success from a timeout.

## `create_event`

Authenticated RPC. Requires an active organizer membership for the target organization or active college-administrator membership. Creates an event and its initial edition in one transaction.

The caller creates and persists `p_client_request_id` before the first attempt and reuses it for retries. The `(created_by, client_request_id)` uniqueness constraint prevents duplicates.

Returns:

```json
{"event_id":"uuid","edition_id":"uuid","status":"draft","idempotent_replay":false}
```

## `published_event_feed`

Read-only security-invoker view. It exposes published event records and their next edition, organization, and college. RLS limits signed-out discovery to `public` visibility and applies college/organization scope for authenticated users. Both the admin preview and iOS discovery use this projection.

## `register_for_event`

Authenticated RPC with `p_edition_id` and a client-persisted `p_client_request_id`. The operation locks the edition row, checks the authoritative registration window and capacity, then atomically allocates a registration or FIFO waitlist place. A successful registration creates an opaque UUID pass containing no personal information.

The client must retain its request ID across uncertain failures and remove it only after a confirmed response. Returns:

```json
{
  "registration_id":"uuid",
  "status":"registered",
  "pass_token":"opaque-uuid",
  "waitlist_position":null,
  "idempotent_replay":false
}
```

## `cancel_registration`

Authenticated RPC with `p_registration_id`. A student may cancel only their own registration. Repeated cancellation is idempotent. The transaction revokes an active pass and, when a confirmed place is released, promotes the oldest waiting registration and issues its pass.

## `my_journey`

Authenticated, security-invoker view of the caller’s registrations, registration deadlines, waitlist positions, event timeline, and active pass tokens. Underlying table policies are authoritative; clients refetch this view after mutations and reconnects.

## `edition_registration_summary`

Authenticated, security-invoker organizer/volunteer projection of capacity and actual registered, waitlisted, and cancelled counts. RLS prevents unrelated organizations and colleges from seeing an edition’s counts.

## Navigation

- `create_campus`, `create_building`, `create_floor`, and `create_landmark` require contextual college-administrator authority.
- `create_route_draft`, `add_route_node`, and `add_route_edge` author a versioned graph. `publish_route_version` refuses an empty graph and records physical-validation state.
- `calculate_route(start, destination, accessible_only)` is read-only and uses the latest published graph. It excludes active closures and returns ordered nodes, edges, instructions, distance, floor transitions, route version, and physical-validation state. `NO_ROUTE` is an honest 404.
- `add_route_closure(edge, reason, starts, ends, client_request_id)` persists the closure, increments the campus route-change sequence, and requires clients to refetch/recalculate. The caller retains the request ID until success; a retry returns the same closure without incrementing the sequence or duplicating notifications. Students with a registered or waitlisted edition whose session on that campus overlaps the closure receive a durable `venue_change` inbox notification and an eligible push job.
- `set_venue_navigation` links each venue to a same-campus destination landmark and optional designated gate. Those identifiers are projected through discovery and `my_journey`; changing a session venue therefore changes the student’s backend-provided navigation destination without an app release.

## Attendance and occupancy

`record_attendance(pass_token, action, client_request_id)` accepts `enter`, `exit`, or `reenter`. The opaque token contains no identity data. The server validates event staff scope, the pass, the allowed state transition, and re-entry rules. `(scanned_by, client_request_id)` makes retries idempotent. `edition_occupancy` derives the current estimate and freshness from persisted transitions and audited corrections.

`correct_occupancy(edition_id, delta, reason)` stores an attributed correction; it never rewrites scan history. `get_registration_roster(edition_id)` returns the scoped registration/waitlist/pass roster only after server-side event-staff authorization.

## Reports, community, and reviews

- `submit_report` requires event access. `transition_report` enforces submitted → acknowledged → assigned/in progress → resolved, stores history, and queues a student notification.
- `add_report_attachment(report_id, storage_path)` links a previously uploaded private `report-attachments` object. The caller must be the report author, the path must be `<caller UUID>/<report UUID>/<file>`, and Storage must confirm the same owner. Repeating the link is idempotent and does not duplicate either the attachment or its audit record. Invalid ownership returns `FORBIDDEN`; an invalid path or missing upload returns `INVALID_MEDIA_PATH` or `ATTACHMENT_NOT_FOUND`.
- `get_assignable_event_staff(edition_id)` returns only staff already assigned to that edition and only after the caller passes the same server-side edition-management check used by report transitions. The admin uses it instead of accepting a manually typed account identifier.
- `publish_announcement` and `change_session_venue` commit authoritative rows before queuing delivery work.
- `post_message` requires channel access; `moderate_message` preserves the row and changes its visibility state.
- `submit_review` requires an attendance entry, supports update-by-the-same-attendee, and enforces one review per user/event. `event_review_summary` includes the actual sample size.
- `toggle_organization_follow`, `saved_events`, and `my_community_channels` persist student personalization without using profile metadata for authorization.

## Management

`create_organization`, `assign_context_role`, `assign_event_staff`, `add_event_cohost`, `update_event_details`, `approve_event`, `update_edition_capacity`, `create_event_edition`, `create_event_session`, `set_event_cover_image`, `cancel_event`, and campus/venue authoring RPCs repeat contextual authorization server-side and write audit records for sensitive actions.

`create_role_invitation` returns a one-time token whose hash—not the raw token—is stored. It is bound to a normalized email, role, organization, inviter, and seven-day expiry. `accept_role_invitation` requires a signed-in Auth user whose verified account email matches, consumes the token once, and activates the scoped membership. Neither endpoint can grant college-administrator authority.

## Notifications

`register_device_token` persists an APNs token and its sandbox/production environment. Business operations create `notifications` plus idempotent per-device delivery jobs. The student's category settings control push-job creation, while authoritative announcements, venue changes, reminders, and report updates remain in the in-app inbox. `enqueue_due_event_reminders` is service-role-only and creates at most one 24-hour event-start or saved-event registration-deadline reminder per user/edition/kind. `claim_notification_jobs` and `complete_notification_job` are also executable only by `service_role`; clients cannot forge delivery state. Claims carry a five-minute lease and attempt number, so crashed workers can be recovered while stale completions are rejected. Retryable failures use backoff; Apple terminal responses stop retrying, and invalid device-token responses deactivate only that token. The Edge Function selects the APNs endpoint per device.
