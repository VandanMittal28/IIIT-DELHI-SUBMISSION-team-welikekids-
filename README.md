# Sidequest

**Your next starts outside class.**

Sidequest is a native SwiftUI student app and responsive Next.js admin connected to one Supabase backend.

Admin production: <https://sidequest-admin-rho.vercel.app>

## Repository

- `admin/` — organizer and volunteer web application.
- `ios/` — native student iOS application.
- `supabase/` — versioned schema, policies, and server-side operations.
- `docs/` — architecture, API, setup, and verification records.
- `PROGRESS.md` — resumable acceptance checklist and current blockers.

No operational or fictional content is bundled. An empty backend produces empty states.

## Visitor issue reports and AI triage

Issue reports are saved for organizer review. The `assess-report` Edge Function can send the visitor's category, note, and optional JPEG or PNG evidence photo to NVIDIA for a preliminary `relevant`, `uncertain`, or `irrelevant` suggestion with a short reason. This suggestion does not verify an incident or make an assignment; organizers review every report. Reports remain in the normal submitted queue if NVIDIA is not configured or an assessment fails. The prompt treats descriptions as unverified claims and prohibits identifying people or inferring intent from appearance.

To enable AI triage, set `NVIDIA_API_KEY` with `supabase secrets set NVIDIA_API_KEY=your-key` (never in the iOS app or a committed file), then deploy the `assess-report` function. `NVIDIA_VISION_MODEL` is optional; it defaults to `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`. Apply the `ai_report_triage` database migration before using the updated app or admin dashboard. Without the secret, report submission still succeeds and the organizer queue indicates that staff review is required.
