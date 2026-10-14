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

`create_event_with_venue` is the organizer-facing creation contract. It uses the same request ID and schedule validation, requires a venue in the selected organization’s college, and creates the first venue session in the same transaction. A venue or session failure rolls the event and edition back together. Retrying a successful request does not create duplicate sessions.

## `published_event_feed`

Read-only security-invoker view. It exposes published event records and their next edition, organization, and college. RLS limits signed-out discovery to `public` visibility and applies college/organization scope for authenticated users. Both the admin preview and iOS discovery use this projection.

`published_event_session_schedule` exposes the organizer-authored title, times, venue, and campus for each session of a published edition. `edition_review_summary` groups only attendance-verified reviews by event and edition, preserving current-edition sample size separately from prior-edition feedback. Both are security-invoker views and never synthesize schedule or rating data.

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

`my_attendance_history` and `my_submitted_reviews` are authenticated security-invoker views filtered by `auth.uid()`. They expose only the signed-in student's persisted attendance transitions and review records for the Profile history; an unrelated account receives no rows.

## `edition_registration_summary`

Authenticated, security-invoker organizer/volunteer projection of capacity and actual registered, waitlisted, and cancelled counts. RLS prevents unrelated organizations and colleges from seeing an edition’s counts.

## Open Meetups

Casual social meetups are separate from events: no organization, pass, waitlist, attendance scan, or event channel.

- `open_meetup_feed` — authenticated security-invoker view. Returns meetups the caller is eligible for, hosts, or has joined, with venue/landmark, public host card (`host_name`, `host_headline`, `host_verified`), `participating_colleges`, `going_count`/`capacity`, `icebreaker`, `my_status`, `is_eligible`, and `is_host` (the caller hosts it). Student hosts without a host card show their chosen `host_display_name`. Attendee identities are never exposed.
- `join_open_meetup(p_meetup_id)` / `leave_open_meetup(p_meetup_id)` — act only for `auth.uid()`. Join locks the meetup row, is idempotent, enforces capacity (`MEETUP_FULL`) and college eligibility (`NOT_ELIGIBLE`). Returns `{"registration_id","status":"going|cancelled","going_count","capacity","idempotent_replay"}`.
- Eligibility uses active `college_memberships` (administrator-granted), not the self-editable `profiles.college_id`. `all_colleges` admits any student with an active college membership; `selected_colleges` always includes the host college.
- `set_meetup_host` / `revoke_meetup_host` — college administrators recognise an active member of their college as a host. Creating a meetup never grants recognition; `host_verified` becomes false when recognition is revoked or the host’s account/membership is inactive.
- `create_open_meetup(...)` — idempotent by `p_client_request_id`; allowed for the recognised host or the host college’s administrator. Venue must be on the host college campus. A predefined icebreaker is assigned when none is supplied.
- `host_open_meetup(p_client_request_id, p_college_id, p_venue_id, p_title, p_description, p_starts_at, p_ends_at, p_capacity, p_host_display_name, p_audience, p_college_ids, p_icebreaker, p_location_note)` — any active student with an active membership in `p_college_id` publishes a meetup they host. The host is always `auth.uid()` (no host parameter). Validates venue campus (`INVALID_VENUE`), schedule (future start, at most 12 hours long, within 180 days), capacity 2–500 (`INVALID_CAPACITY`), field lengths, and colleges. Idempotent by `p_client_request_id`. Students who are not recognised hosts may have at most 3 upcoming meetups (`HOSTING_LIMIT`). Never grants recognition.
- `set_open_meetup_status(p_meetup_id, 'published'|'cancelled')` — the meetup's own host (active account) or the home college administrator; cancelling releases every spot. Deleting an account cancels the upcoming meetups it hosts.

Clients have read-only table access; every write goes through these functions. `supabase/tests/open_meetups_integration.sql` covers the authorization, duplicate, capacity, and eligibility rules; `supabase/tests/student_hosted_meetups_integration.sql` covers student hosting, ownership, validation, idempotency, the hosting limit, and cancellation. `supabase/open_meetups_demo_seed.sql` is development-only demo content.

## Navigation

- `create_campus`, `create_building`, `create_floor`, and `create_landmark` require contextual college-administrator authority.
- `update_landmark` changes an existing landmark without changing its coordinate system. Outdoor landmarks continue to require WGS84 coordinates; indoor landmarks continue to require floor pixels on a floor in the same campus. Every change is audited.
- `create_route_draft`, `add_route_node`, and `add_route_edge` author a versioned graph. `publish_route_version` refuses an empty graph and records physical-validation state.
- `update_route_edge` can change geometry, instruction, distance and accessibility only while the route version is still a draft. A published route is immutable; corrections require a new version.
- `calculate_route(start, destination, accessible_only)` is read-only and uses the latest published graph. It excludes active closures and returns ordered nodes, edges, instructions, distance, floor transitions, route version, and physical-validation state. `NO_ROUTE` is an honest 404.
- `add_route_closure(edge, reason, starts, ends, client_request_id)` persists the closure, increments the campus route-change sequence, and requires clients to refetch/recalculate. The caller retains the request ID until success; a retry returns the same closure without incrementing the sequence or duplicating notifications. Students with a registered or waitlisted edition whose session on that campus overlaps the closure receive a durable `venue_change` inbox notification and an eligible push job.
- `end_route_closure(closure_id)` is college-administrator-only and ends one active closure. It advances the campus route sequence and notifies attendees with an upcoming or active session on that campus. A repeated call is an idempotent replay and does not duplicate notifications or audit entries.
- `set_venue_navigation` links each venue to a same-campus destination landmark and optional designated gate. Those identifiers are projected through discovery and `my_journey`; changing a session venue therefore changes the student’s backend-provided navigation destination without an app release.

## Attendance and occupancy

`record_attendance(pass_token, action, client_request_id)` accepts `enter`, `exit`, or `reenter`. The opaque token contains no identity data. The server validates event staff scope, the pass, the allowed state transition, and re-entry rules. `(scanned_by, client_request_id)` makes retries idempotent. `edition_occupancy` derives the current estimate and freshness from persisted transitions and audited corrections.

`correct_occupancy(edition_id, delta, reason)` stores an attributed correction; it never rewrites scan history. `get_registration_roster(edition_id)` returns the scoped registration/waitlist/pass roster only after server-side event-staff authorization.

## Reports, community, and reviews

- `submit_report` requires event access. `transition_report` enforces submitted → acknowledged → assigned → in progress → resolved without skipped states, requires an active staff assignee already assigned to the edition, stores history, and queues a student notification. Retrying the current status returns an idempotent replay without another history row or notification.
- `submit_message_report(message_id, description)` requires access to the message's edition, rejects self-reporting and newly reporting hidden content, links the exact message to the standard report workflow, and returns the original report on retry. Event managers can read the linked message after moderation; ordinary students cannot read hidden messages.
- `add_report_attachment(report_id, storage_path)` links a previously uploaded private `report-attachments` object. The caller must be the report author, the path must be `<caller UUID>/<report UUID>/<file>`, and Storage must confirm the same owner. Repeating the link is idempotent and does not duplicate either the attachment or its audit record. Invalid ownership returns `FORBIDDEN`; an invalid path or missing upload returns `INVALID_MEDIA_PATH` or `ATTACHMENT_NOT_FOUND`.
- `get_assignable_event_staff(edition_id)` returns only staff already assigned to that edition and only after the caller passes the same server-side edition-management check used by report transitions. The admin uses it instead of accepting a manually typed account identifier.
- `publish_announcement` and `change_session_venue` accept a client-retained request ID, commit authoritative rows before queuing delivery work, and return the original result on retry. Venue changes also reject a venue outside the event's college.
- `post_message` requires channel access; `moderate_message` preserves the row, changes its visibility state, and records an audit event.
- `create_discussion_thread(title, body)` lets any active signed-in profile with a selected college start a college-scoped forum thread; `reply_discussion_thread(thread_id, body)` lets active members of that same college respond. RLS prevents cross-college reads; thread/reply writes go through authenticated server-side operations.
- `event_media` lists photos only to an attendee with a confirmed registration or assigned event staff. Uploads use a private `event-attendee-media` bucket, a path bound to edition and uploader, and `add_event_media` verifies the owned Storage object before publishing it to the event gallery. Waitlisted, cancelled, signed-out, and unrelated users cannot read or upload event photos.
- `submit_review` requires an attendance entry, supports update-by-the-same-attendee, and enforces one review per user/event. `event_review_summary` includes the actual sample size.
- `toggle_organization_follow`, `saved_events`, and `my_community_channels` persist student personalization without using profile metadata for authorization.

## Management

`platform_admins` holds the trusted global Sidequest administrator role; clients may read only their own membership row. `create_college` is restricted to platform administrators and writes an audit record. `create_organization` authorizes either a platform administrator across colleges or a college administrator in that college. A platform administrator is not automatically added as an organization organizer. The protected `create-user-profile` Edge Function provisions students and organization organizers for platform admins, or in-scope accounts for a college administrator; it never creates administrator privileges.

`assign_context_role`, `assign_event_staff`, `add_event_cohost`, `update_event_details`, `approve_event`, `update_edition_capacity`, `create_event_edition`, `create_event_session`, `update_event_session`, `set_event_cover_image`, `cancel_event`, and campus/venue authoring RPCs repeat contextual authorization server-side and write audit records for sensitive actions. Session edits must remain inside their edition schedule and use a venue in the event's college. Host and co-host organizers receive the same event-management boundary. `get_event_staff_candidates(edition_id)` returns only active organizers and volunteers from those organizations; assignment rejects arbitrary account IDs and is retry-idempotent. Event cancellation locks the event and its editions, records `cancelled_at`, cancels every confirmed or waitlisted registration, cancels waitlist entries, revokes active passes, and treats every later call as a replay so notifications and audit work cannot be duplicated.

Edition discussion and announcement access also rechecks `profiles.status = 'active'` in PostgreSQL. Suspending or deleting an account therefore removes access even if its existing Auth token has not yet expired.

`create_role_invitation` returns a one-time token whose hash—not the raw token—is stored. It is bound to a normalized email, role, organization, inviter, and seven-day expiry. `accept_role_invitation` requires a signed-in Auth user whose verified account email matches, consumes the token once, and activates the scoped membership. Neither endpoint can grant college-administrator authority.

## Notifications

`register_device_token` persists an APNs token and its sandbox/production environment. Business operations create `notifications` plus idempotent per-device delivery jobs. The student's category settings control push-job creation, while authoritative announcements, venue changes, reminders, and report updates remain in the in-app inbox. `enqueue_due_event_reminders` is service-role-only and creates at most one 24-hour event-start or saved-event registration-deadline reminder per user/edition/kind. `claim_notification_jobs` and `complete_notification_job` are also executable only by `service_role`; clients cannot forge delivery state. Claims carry a five-minute lease and attempt number, so crashed workers can be recovered while stale completions are rejected. Retryable failures use backoff; Apple terminal responses stop retrying, and invalid device-token responses deactivate only that token. The Edge Function selects the APNs endpoint per device.
