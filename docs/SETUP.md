# Sidequest setup

## Prerequisites

- Node.js 22 or newer.
- Xcode 16 or newer and an iOS 17+ simulator.
- XcodeGen 2.46 or newer to regenerate the checked-in Xcode project.
- Supabase CLI 2.120 or newer and an explicitly authorized Supabase project.

## Backend

1. Identify the development/staging project. The currently authorized development project ref is `dzqfsskcgaowcnbpxzzl`; do not reuse it as production without explicit authorization.
2. Link without storing database credentials in Git:

   ```sh
   npx supabase@2.120.0 login
   npx supabase@2.120.0 link --project-ref YOUR_PROJECT_REF
   npx supabase@2.120.0 db push
   ```

3. Run the Supabase security and performance advisors and resolve findings.
4. In Auth settings, configure the approved application URLs and require email confirmation for public accounts.
5. Invite the first trusted Sidequest platform administrator through Supabase Auth. After that person exists in `auth.users`, review and run `supabase/bootstrap/platform_admin.sql.example` as a trusted database operator. This bootstraps a global Sidequest role; it does not attach the person to a college or organization. Public sign-up only creates an unprivileged profile and cannot create administrator memberships. Use `initial_admin.sql.example` only when deliberately bootstrapping a separate, college-scoped administrator.
6. Deploy `create-user-profile` after applying its matching migrations so the protected function can provision student and organizer accounts. Never expose its service-role key to a client.
7. Create organizations and invitations through the admin workflows as they become available. Never seed fictional operational content into production.
8. For push delivery, configure the Edge Function secrets from `supabase/functions/.env.example`, deploy `deliver-notifications`, and schedule authenticated POST invocations only in the authorized environment. `config.toml` disables platform JWT verification for this worker because its handler verifies `DELIVERY_WEBHOOK_SECRET`. Apple Developer APNs credentials are required; Supabase injects the server key and URL rather than reading them from the committed template.

Development demo data: after the three demo Auth users exist, run `supabase/seed.sql` once in the authorized development project SQL editor (or through the Supabase SQL tool). It is idempotent and creates the IIIT Delhi events, venues, route graph, registrations, passes, volunteer assignments, announcements, messages, attendance, report, review and inbox records used by the end-to-end demo. Do not run this seed against production.

The authorized development project may contain a clearly labeled Sidequest demo college, organization, event, registration/pass, and sample route for testing. These records are not a migration or production fixture and must not be copied into a production project.

The native app exposes public student account creation using the same username convention as the admin. A username without `@` is normalized to `<username>@sidequest.local` only for the underlying Supabase Auth identity; the UI remains username/password based. A successful sign-up either starts a session immediately (only when the environment intentionally disables confirmation) or tells the student to confirm the account email and then sign in. The Auth profile trigger creates an unprivileged profile only; organization and college access still require server-authorized membership records.

The admin form accepts either an email address or a college-issued username. A username is normalized by removing spaces and appending `@sidequest.local` before Supabase Auth is called. Create the matching internal Auth email as a trusted operator; never expose this convention as a public self-registration path. Passwords belong only in Supabase Auth and must not be committed to the repository.

The Sidequest platform admin manages colleges and organizations and provisions student or organizer accounts across colleges. College creation uses the `create_college` authorization RPC and is audited; the platform role is stored in `platform_admins` and checked in RLS and server-side operations, never inferred from profile metadata. A platform admin does not silently become an organizer when creating an organization. Organizer accounts are attached to an organization and can manage only their scoped events/reports. Students receive the native iOS experience; they do not receive organizer permissions.

## Admin website

```sh
cd admin
cp .env.local.example .env.local
npm ci
npm run dev
```

Set only `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in the browser application. Never expose a Supabase secret or service-role key.

Production verification:

```sh
npm run lint
npm run build
npm audit --omit=dev
```

Deploy only to an authorized environment. Configure the same two public variables in that environment and add its URL to Supabase Auth redirects.

## Native iOS app

1. Create `ios/Config/Local.xcconfig` with the same Supabase URL and publishable key. It is ignored by Git and optionally included by `Sidequest.xcconfig`. This file must never contain a secret/service-role key.

   Xcode configuration files treat `//` as a comment. Escape the URL separator so the compiled value remains a valid HTTPS URL:

   ```xcconfig
   SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
   SUPABASE_PUBLISHABLE_KEY = sb_publishable_replace_me
   ```
2. Regenerate after changing `project.yml`:

   ```sh
   cd ios
   xcodegen generate
   open Sidequest.xcodeproj
   ```

3. Select a development team for device builds. Simulator builds do not require signing.

Command-line verification:

```sh
xcodebuild -project Sidequest.xcodeproj -scheme Sidequest \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Camera, speech, APNs registration, pass QR rendering, MapKit, and validation-gated ARKit are implemented. They still require a signed build and physical-iPhone verification; a simulator build is not evidence that camera, tracking, or push delivery works on hardware.

## Release gates

- Local: lint/build/tests and anonymous authorization checks pass.
- Staging: a trusted administrator, student, and volunteer complete the full persisted journey with authorized real content.
- Device: camera scan, voice, location, AR tracking interruption, permission denial, APNs receipt, and app restart are exercised on an iPhone.
- Production: owner authorizes the Supabase/Vercel/Apple environments, monitoring, backups, privacy disclosures, and App Store submission.

## Admin deployment

The production admin website is deployed through Vercel Git integration at `https://sidequest-admin-rho.vercel.app`. The Vercel project is `sidequest-admin`, its root directory is `admin`, and `main` is the production branch. `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` are configured for Production and Preview; neither is a privileged service-role credential.
