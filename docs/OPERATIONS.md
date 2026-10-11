# Operations, monitoring, and recovery

## Monitoring

- Review Supabase Auth, Data API, Storage, Realtime, Edge Function, and Postgres logs for sustained error-rate changes.
- Run security and performance advisors after every schema migration.
- Alert on failed notification delivery jobs, registration-function errors, repeated invalid pass scans, and route-version publication failures.
- Application dashboards must report record timestamps and sample sizes; realtime signals alone are never treated as durable truth.

## Backups

Confirm the selected Supabase plan's backup retention before staging or production launch. Enable point-in-time recovery when required by the operational recovery objective. Export storage objects separately when platform backup coverage does not include them.

## Restore drill

1. Restore into a non-production project or branch.
2. Confirm migration history and run database advisors.
3. Validate Auth-to-profile linkage, storage policy access, registrations, attendance transitions, notification jobs, and audit records.
4. Point test clients at the restored project's publishable configuration.
5. Exercise the critical journey before approving a production recovery.

Never test restore procedures by overwriting the live production project.

## Notification delivery

Deploy `supabase/functions/deliver-notifications` only after securely configuring the variables shown in `supabase/functions/.env.example`. Invoke it from an authorized Supabase Cron/HTTP schedule using `DELIVERY_WEBHOOK_SECRET`. APNs private keys and the service-role key are never client configuration. A 503 `NOT_CONFIGURED` response is a failure, not simulated delivery.

## Route changes

Publishing a route retires the previous published version. Adding a closure increments `campuses.route_change_sequence`; clients treat Realtime as an invalidation signal and calculate again from the stored graph. Physical validators must record notes and set `physical_validation_complete` only after walking the route with a real device.
