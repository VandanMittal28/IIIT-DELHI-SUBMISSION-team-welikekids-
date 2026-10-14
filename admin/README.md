# Sidequest Admin

Responsive Next.js application for college administrators, organization organizers, and event volunteers.

The connected application supports event authoring/publishing/cancellation, editions and sessions, capacity and re-entry rules, role invitations and volunteer assignments, protected media uploads, camera pass scanning, occupancy, announcements, reports, and Leaflet campus/landmark authoring. Empty authorized scopes remain honest empty states.

See [`../docs/SETUP.md`](../docs/SETUP.md) for configuration. The app intentionally shows a setup state when backend configuration is absent and never substitutes sample operational data.

## Design system

`src/app/globals.css` holds the token layer — colours, radii, shadows, spacing
and the type scale — plus the shared primitives (`.ops-card`, `.field`,
`.status-dot`, `.danger-zone`, buttons). `src/app/page.module.css` holds page
layout only. Nothing else should hard-code a colour, radius, shadow or space.

The scale is the web port of [`../DESIGN_NOTES.md`](../DESIGN_NOTES.md), the
measured Luma reference used for the iOS redesign, so both surfaces read as one
product: flat white cards on a grouped background, 22px radii, hairline
separators, grey as a type colour, and the Sidequest ink/lime brand kept for
accents. A dark palette follows `prefers-color-scheme`.

One constraint worth remembering: a rule written in `globals.css` cannot target
a CSS-module class name, because those are hashed at build time. Rules for
`.formGrid`, `.volunteerGrid`, `.dashboardNav` and friends belong in
`page.module.css`.
