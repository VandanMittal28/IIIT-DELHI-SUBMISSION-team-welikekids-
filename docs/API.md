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

Authenticated, security-invoker view of the caller’s registrations, waitlist positions, event timeline, and active pass tokens. Underlying table policies are authoritative; clients refetch this view after mutations and reconnects.

## `edition_registration_summary`

Authenticated, security-invoker organizer/volunteer projection of capacity and actual registered, waitlisted, and cancelled counts. RLS prevents unrelated organizations and colleges from seeing an edition’s counts.
