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
5. Invite the first trusted administrator through Supabase Auth. After that person exists in `auth.users`, review and run `supabase/bootstrap/initial_admin.sql.example` as a trusted database operator. Public sign-up only creates a profile; it cannot create staff or administrator memberships.
6. Create organizations and invitations through the admin workflows as they become available. Never seed fictional operational content into production.

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

Camera, location, speech, APNs, pass scanning, and ARKit require later connected workflows and physical-iPhone verification. A simulator build is not evidence those capabilities work on hardware.
