"use client";

import { useState } from "react";
import { getSupabase } from "@/lib/supabase";

type ProfileType = "student" | "college_admin" | "organizer";
type Organization = { id: string; name: string };

export function ProfileProvisioningPanel({ collegeId, organizations }: { collegeId: string; organizations: Organization[] }) {
  const [profileType, setProfileType] = useState<ProfileType>("student");
  const [username, setUsername] = useState("");
  const [fullName, setFullName] = useState("");
  const [password, setPassword] = useState("");
  const [organizationId, setOrganizationId] = useState(organizations[0]?.id ?? "");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function createProfile(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    const { data, error: invokeError } = await getSupabase().functions.invoke("create-user-profile", {
      body: { college_id: collegeId, organization_id: organizationId || undefined, username, full_name: fullName, password, profile_type: profileType },
    });
    if (invokeError) setError(invokeError.message);
    else if (data?.error) setError(data.message ?? data.error);
    else {
      setMessage(`${profileType === "student" ? "Student" : profileType === "organizer" ? "Organizer" : "College admin"} profile created. Username: ${username}`);
      setUsername(""); setFullName(""); setPassword("");
    }
    setBusy(false);
  }

  return <section className="ops-card ops-wide">
    <div className="ops-heading"><div><p className="ops-kicker">College admin</p><h2>Create college profiles</h2></div><span className="status-dot">IIIT Delhi scoped</span></div>
    <p className="helper">The app admin creates student and organizer credentials here. Organizers belong to the selected IIIT Delhi organization and can manage its events and reports.</p>
    <form className="management-grid" onSubmit={createProfile}>
      <label className="field">Profile type<select value={profileType} onChange={event => setProfileType(event.target.value as ProfileType)}><option value="student">Student</option><option value="organizer">Organizer</option><option value="college_admin">College admin</option></select></label>
      {profileType === "organizer" && <label className="field">Organization<select required value={organizationId} onChange={event => setOrganizationId(event.target.value)}>{organizations.map(organization => <option key={organization.id} value={organization.id}>{organization.name}</option>)}</select></label>}
      <label className="field">Username<input required minLength={3} value={username} onChange={event => setUsername(event.target.value)} placeholder="student01" autoComplete="off" /></label>
      <label className="field">Full name<input required minLength={2} value={fullName} onChange={event => setFullName(event.target.value)} placeholder="Student name" /></label>
      <label className="field">Temporary password<input required minLength={8} type="password" value={password} onChange={event => setPassword(event.target.value)} autoComplete="new-password" /></label>
      <div className="ops-form"><button disabled={busy}>{busy ? "Creating…" : "Create profile"}</button><p className="helper">The password is sent directly to Supabase Auth and is never stored in the Admin UI.</p></div>
    </form>
    {message && <p role="status" className="success-text">{message}</p>}
    {error && <p role="alert" className="error-text">{error}</p>}
  </section>;
}
