"use client";

import { useState } from "react";
import { getSupabase } from "@/lib/supabase";

type Organization = { id: string; name: string; is_active: boolean };

export function ProfileProvisioningPanel({ collegeId, organizations, onChanged }: { collegeId: string; organizations: Organization[]; onChanged(): void }) {
  const [username, setUsername] = useState("");
  const [fullName, setFullName] = useState("");
  const [password, setPassword] = useState("");
  const [organizationName, setOrganizationName] = useState("");
  const [organizationSlug, setOrganizationSlug] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function createProfile(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    const { data, error: invokeError } = await getSupabase().functions.invoke("create-user-profile", {
      body: { college_id: collegeId, username, full_name: fullName, password, profile_type: "student" },
    });
    if (invokeError) setError(invokeError.message);
    else if (data?.error) setError(data.message ?? data.error);
    else {
      setMessage(`Student profile created. Username: ${username}`);
      setUsername(""); setFullName(""); setPassword("");
    }
    setBusy(false);
  }

  async function createOrganization(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    const { data, error: createError } = await getSupabase().rpc("create_organization", {
      p_college_id: collegeId,
      p_name: organizationName.trim(),
      p_slug: organizationSlug.trim().toLowerCase(),
      p_description: null,
    });
    if (createError) setError(createError.message);
    else if (data?.persisted !== true) setError("The backend did not confirm that the organization was saved. Please retry.");
    else {
      setMessage("Organization created and confirmed by the backend.");
      setOrganizationName(""); setOrganizationSlug("");
      onChanged();
    }
    setBusy(false);
  }

  const activeOrganizations = organizations.filter((organization) => organization.is_active);

  return <section className="ops-card ops-wide">
    <div className="ops-heading"><div><p className="ops-kicker">Admin profile</p><h2>Organizations and student accounts</h2></div><span className="status-dot">IIIT Delhi scoped</span></div>
    <p className="helper">This profile is for creating organizations and student accounts. Organizer and administrator login roles are not created here.</p>
    <h3>Active organizations</h3>
    {activeOrganizations.length === 0 ? <p className="helper">No active organizations yet. Create one below.</p> : <div className="management-grid">{activeOrganizations.map((organization) => <article className="ops-form" key={organization.id}><strong>{organization.name}</strong><span className="status-dot">Active</span></article>)}</div>}
    {organizations.some((organization) => !organization.is_active) && <details><summary>Inactive organizations</summary><ul>{organizations.filter((organization) => !organization.is_active).map((organization) => <li key={organization.id}>{organization.name} · Paused</li>)}</ul></details>}
    <div className="management-grid">
      <form className="ops-form" onSubmit={createOrganization}>
        <h3>Create organization</h3>
        <label className="field">Organization name<input required minLength={2} maxLength={160} value={organizationName} onChange={event => setOrganizationName(event.target.value)} placeholder="IIIT Delhi Robotics Club" /></label>
        <label className="field">Organization ID<input required pattern="[a-z0-9-]+" value={organizationSlug} onChange={event => setOrganizationSlug(event.target.value.toLowerCase())} placeholder="robotics-club" /></label>
        <button disabled={busy}>{busy ? "Saving…" : "Create organization"}</button>
      </form>
      <form className="ops-form" onSubmit={createProfile}>
        <h3>Create student profile</h3>
        <label className="field">Username<input required minLength={3} value={username} onChange={event => setUsername(event.target.value)} placeholder="student01" autoComplete="off" /></label>
        <label className="field">Full name<input required minLength={2} value={fullName} onChange={event => setFullName(event.target.value)} placeholder="Student name" /></label>
        <label className="field">Temporary password<input required minLength={8} type="password" value={password} onChange={event => setPassword(event.target.value)} autoComplete="new-password" /></label>
        <button disabled={busy}>{busy ? "Creating…" : "Create student profile"}</button>
        <p className="helper">The password is sent directly to Supabase Auth and is never stored in the Admin UI.</p>
      </form>
    </div>
    {message && <p role="status" className="success-text">{message}</p>}
    {error && <p role="alert" className="error-text">{error}</p>}
  </section>;
}
