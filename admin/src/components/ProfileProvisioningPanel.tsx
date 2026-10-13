"use client";

import { useMemo, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type College = { id: string; name: string };
type Organization = { id: string; name: string; college_id: string; is_active: boolean };

export function ProfileProvisioningPanel({
  platformAdmin,
  collegeId,
  colleges,
  organizations,
  onChanged,
}: {
  platformAdmin: boolean;
  collegeId?: string;
  colleges: College[];
  organizations: Organization[];
  onChanged(): void;
}) {
  const [selectedCollegeId, setSelectedCollegeId] = useState(collegeId ?? colleges[0]?.id ?? "");
  const [username, setUsername] = useState("");
  const [fullName, setFullName] = useState("");
  const [password, setPassword] = useState("");
  const [profileType, setProfileType] = useState<"student" | "organizer">("student");
  const [organizationId, setOrganizationId] = useState("");
  const [organizationName, setOrganizationName] = useState("");
  const [organizationSlug, setOrganizationSlug] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const selectedOrganizations = useMemo(
    () => organizations.filter((organization) => organization.college_id === selectedCollegeId && organization.is_active),
    [organizations, selectedCollegeId],
  );
  const collegeName = colleges.find((college) => college.id === selectedCollegeId)?.name ?? "Selected college";

  async function createProfile(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    if (profileType === "organizer" && !organizationId) {
      setError("Choose an active organization for this organizer account."); setBusy(false); return;
    }
    const { data, error: invokeError } = await getSupabase().functions.invoke("create-user-profile", {
      body: {
        college_id: selectedCollegeId,
        organization_id: profileType === "organizer" ? organizationId : undefined,
        username,
        full_name: fullName,
        password,
        profile_type: profileType,
      },
    });
    if (invokeError) setError(invokeError.message);
    else if (data?.error) setError(data.message ?? data.error);
    else {
      setMessage(`${profileType === "student" ? "Student" : "Organizer"} account created for ${collegeName}. Username: ${username}`);
      setUsername(""); setFullName(""); setPassword(""); setOrganizationId("");
    }
    setBusy(false);
  }

  async function createOrganization(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    const { data, error: createError } = await getSupabase().rpc("create_organization", {
      p_college_id: selectedCollegeId,
      p_name: organizationName.trim(),
      p_slug: organizationSlug.trim().toLowerCase(),
      p_description: null,
    });
    if (createError) setError(createError.message);
    else if (data?.persisted !== true) setError("The backend did not confirm that the organization was saved. Please retry.");
    else {
      setMessage(`${organizationName.trim()} created under ${collegeName}.`);
      setOrganizationName(""); setOrganizationSlug("");
      onChanged();
    }
    setBusy(false);
  }

  const activeOrganizations = organizations.filter((organization) => organization.is_active);
  const inactiveOrganizations = organizations.filter((organization) => !organization.is_active);

  return <section className="ops-card ops-wide">
    <div className="ops-heading">
      <div><p className="ops-kicker">{platformAdmin ? "Sidequest platform administration" : "College administration"}</p><h2>Colleges, organizations, and accounts</h2></div>
      <span className="status-dot">{platformAdmin ? "Global platform scope" : "College scoped"}</span>
    </div>
    <p className="helper">{platformAdmin
      ? "Manage Sidequest across colleges. College organizers keep their own scoped event and volunteer tools; this account does not automatically become an organizer."
      : "Manage organizations and student or organizer accounts only within your authorized college."}</p>
    <label className="field">College
      <select required value={selectedCollegeId} disabled={!platformAdmin} onChange={event => { setSelectedCollegeId(event.target.value); setOrganizationId(""); }}>
        {colleges.map((college) => <option key={college.id} value={college.id}>{college.name}</option>)}
      </select>
    </label>
    <h3>Active organizations</h3>
    {activeOrganizations.length === 0 ? <p className="helper">No active organizations yet. Create one below.</p> : <div className="management-grid">{activeOrganizations.map((organization) => <article className="ops-form" key={organization.id}><strong>{organization.name}</strong><span>{colleges.find((college) => college.id === organization.college_id)?.name}</span><span className="status-dot">Active</span></article>)}</div>}
    {inactiveOrganizations.length > 0 && <details><summary>Inactive organizations</summary><ul>{inactiveOrganizations.map((organization) => <li key={organization.id}>{organization.name} · {colleges.find((college) => college.id === organization.college_id)?.name ?? "College"} · Paused</li>)}</ul></details>}
    <div className="management-grid">
      <form className="ops-form" onSubmit={createOrganization}>
        <h3>Create organization</h3>
        <label className="field">Organization name<input required minLength={2} maxLength={160} value={organizationName} onChange={event => setOrganizationName(event.target.value)} placeholder="Robotics Club" /></label>
        <label className="field">Organization ID<input required pattern="[a-z0-9-]+" value={organizationSlug} onChange={event => setOrganizationSlug(event.target.value.toLowerCase())} placeholder="robotics-club" /></label>
        <button disabled={busy || !selectedCollegeId}>{busy ? "Saving…" : "Create organization"}</button>
      </form>
      <form className="ops-form" onSubmit={createProfile}>
        <h3>Create account</h3>
        <label className="field">Account type<select value={profileType} onChange={event => { setProfileType(event.target.value as "student" | "organizer"); setOrganizationId(""); }}><option value="student">Student</option><option value="organizer">Organization organizer</option></select></label>
        {profileType === "organizer" && <label className="field">Organization<select required value={organizationId} onChange={event => setOrganizationId(event.target.value)}><option value="">Choose active organization</option>{selectedOrganizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name}</option>)}</select></label>}
        <label className="field">Username<input required minLength={3} value={username} onChange={event => setUsername(event.target.value)} placeholder="student01" autoComplete="off" /></label>
        <label className="field">Full name<input required minLength={2} value={fullName} onChange={event => setFullName(event.target.value)} placeholder="Account holder name" /></label>
        <label className="field">Temporary password<input required minLength={8} type="password" value={password} onChange={event => setPassword(event.target.value)} autoComplete="new-password" /></label>
        <button disabled={busy || !selectedCollegeId || (profileType === "organizer" && selectedOrganizations.length === 0)}>{busy ? "Creating…" : `Create ${profileType === "student" ? "student" : "organizer"} account`}</button>
        <p className="helper">Credentials are sent to Supabase Auth and are not stored in the Admin UI.</p>
      </form>
    </div>
    {message && <p role="status" className="success-text">{message}</p>}
    {error && <p role="alert" className="error-text">{error}</p>}
  </section>;
}
