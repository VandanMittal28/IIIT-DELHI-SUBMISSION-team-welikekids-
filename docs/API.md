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

Read-only security-invoker view. It exposes only published event records and their next edition, organization, and college. Both the admin preview and iOS discovery use this projection.
