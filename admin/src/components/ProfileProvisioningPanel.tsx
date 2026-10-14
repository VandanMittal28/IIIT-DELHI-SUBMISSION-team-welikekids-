"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type College = { id: string; name: string };
type Organization = { id: string; name: string; college_id: string; is_active: boolean; head_user_id?: string | null };
type OrganizerAccount = { user_id: string; full_name: string; login_username: string | null };

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
  onChanged(): void | Promise<void>;
}) {
  const [selectedCollegeId, setSelectedCollegeId] = useState(collegeId ?? colleges[0]?.id ?? "");
  const [creatingCollege, setCreatingCollege] = useState(false);
  const [newCollegeName, setNewCollegeName] = useState("");
  const [newCollegeSlug, setNewCollegeSlug] = useState("");
  const [newCollegeTimezone, setNewCollegeTimezone] = useState("Asia/Kolkata");
  const [username, setUsername] = useState("");
  const [fullName, setFullName] = useState("");
  const [password, setPassword] = useState("");
  const [profileType, setProfileType] = useState<"student" | "organizer">("student");
  const [headSocietyId, setHeadSocietyId] = useState("");
  const [headUserId, setHeadUserId] = useState("");
  const [organizerAccounts, setOrganizerAccounts] = useState<OrganizerAccount[]>([]);
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
  const loadOrganizerAccounts = useCallback(async (targetCollegeId: string) => {
    const { data, error: directoryError } = await getSupabase().rpc("get_college_organizer_accounts", { p_college_id: targetCollegeId });
    if (directoryError) { setError(directoryError.message); return; }
    const accounts = (data ?? []) as OrganizerAccount[];
    setOrganizerAccounts(accounts);
    setHeadUserId(current => accounts.some(account => account.user_id === current) ? current : accounts[0]?.user_id ?? "");
  }, []);
  useEffect(() => {
    if (selectedCollegeId || !colleges[0]) return;
    const timer = window.setTimeout(() => setSelectedCollegeId(collegeId ?? colleges[0].id), 0);
    return () => window.clearTimeout(timer);
  }, [collegeId, colleges, selectedCollegeId]);
  useEffect(() => {
    if (!selectedCollegeId) return;
    const timer = window.setTimeout(() => { void loadOrganizerAccounts(selectedCollegeId); }, 0);
    return () => window.clearTimeout(timer);
  }, [loadOrganizerAccounts, selectedCollegeId]);

  async function createProfile(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    const { data, error: invokeError } = await getSupabase().functions.invoke("create-user-profile", {
      body: {
        college_id: selectedCollegeId,
        username,
        full_name: fullName,
        password,
        profile_type: profileType,
      },
    });
    if (invokeError) setError(invokeError.message);
    else if (data?.error) setError(data.message ?? data.error);
    else {
      setMessage(`${profileType === "student" ? "Student" : "Organizer"} account created for ${collegeName}. Username: ${username}${profileType === "organizer" ? ". Assign this ID as a society head below to grant event access." : ""}`);
      setUsername(""); setFullName(""); setPassword("");
      if (profileType === "organizer") { await loadOrganizerAccounts(selectedCollegeId); setHeadUserId(data.user_id); }
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
    else if (data?.persisted !== true) setError("The backend did not confirm that the society was saved. Please retry.");
    else {
      setMessage(`${organizationName.trim()} created under ${collegeName}.`);
      setOrganizationName(""); setOrganizationSlug("");
      await onChanged();
    }
    setBusy(false);
  }

  async function createCollege(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    const { data, error: createError } = await getSupabase().rpc("create_college", {
      p_name: newCollegeName.trim(),
      p_slug: newCollegeSlug.trim().toLowerCase(),
      p_timezone: newCollegeTimezone,
    });
    if (createError) setError(createError.message);
    else if (data?.persisted !== true || typeof data.college_id !== "string") setError("The backend did not confirm that the college was saved. Please retry.");
    else {
      await onChanged();
      setSelectedCollegeId(data.college_id);
      setCreatingCollege(false);
      setMessage(`${newCollegeName.trim()} created. You can now create its society and accounts.`);
      setNewCollegeName(""); setNewCollegeSlug(""); setNewCollegeTimezone("Asia/Kolkata");
    }
    setBusy(false);
  }

  async function assignHead(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setMessage(null);
    const society = selectedOrganizations.find(item => item.id === headSocietyId);
    const account = organizerAccounts.find(item => item.user_id === headUserId);
    if (!society || !account) { setError("Choose a society and an organizer account from this college."); setBusy(false); return; }
    const { data, error: assignError } = await getSupabase().rpc("assign_society_head", {
      p_organization_id: society.id, p_user_id: account.user_id,
    });
    if (assignError) setError(assignError.message);
    else if (data?.persisted !== true) setError("The backend did not confirm the society head assignment.");
    else { setMessage(`${account.full_name} is now the head of ${society.name} and can manage its events.`); await onChanged(); }
    setBusy(false);
  }

  const activeOrganizations = selectedOrganizations;
  const inactiveOrganizations = organizations.filter((organization) => !organization.is_active);

  return <section className="ops-card ops-wide">
    <div className="ops-heading">
      <div><p className="ops-kicker">{platformAdmin ? "Sidequest platform administration" : "College administration"}</p><h2>Colleges, societies, and accounts</h2></div>
      <span className="status-dot">{platformAdmin ? "Global platform scope" : "College scoped"}</span>
    </div>
    <p className="helper">{platformAdmin
      ? "Create colleges, societies, and college accounts, then assign an existing organizer ID as each society's head."
      : "Create student and organizer IDs for your college, create societies, then assign an organizer ID as society head."}</p>
    <label className="field">College
      <select required value={selectedCollegeId} disabled={!platformAdmin} onChange={event => { setSelectedCollegeId(event.target.value); setHeadSocietyId(""); setHeadUserId(""); }}>
        {colleges.map((college) => <option key={college.id} value={college.id}>{college.name}</option>)}
      </select>
    </label>
    {platformAdmin && <button type="button" className="secondary" onClick={() => setCreatingCollege((value) => !value)}>{creatingCollege ? "Cancel new college" : "Create a college"}</button>}
    {creatingCollege && <form className="ops-form" onSubmit={createCollege}>
      <h3>New college</h3>
      <label className="field">College name<input required minLength={2} maxLength={160} value={newCollegeName} onChange={event => { const value = event.target.value; setNewCollegeName(value); setNewCollegeSlug(value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")); }} placeholder="College name" /></label>
      <label className="field">College ID<input required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" value={newCollegeSlug} onChange={event => setNewCollegeSlug(event.target.value.toLowerCase())} placeholder="college-id" /></label>
      <label className="field">Timezone<input required value={newCollegeTimezone} onChange={event => setNewCollegeTimezone(event.target.value)} placeholder="Asia/Kolkata" /></label>
      <button disabled={busy}>{busy ? "Creating…" : "Create college and continue"}</button>
    </form>}
    <h3>Active societies</h3>
    {activeOrganizations.length === 0 ? <p className="helper">No active societies for {collegeName} yet. Create one below before assigning a head.</p> : <div className="management-grid">{activeOrganizations.map((organization) => <article className="ops-form" key={organization.id}><strong>{organization.name}</strong><span>{collegeName}</span><span className="status-dot">{organization.head_user_id ? `Head: ${organizerAccounts.find(account => account.user_id === organization.head_user_id)?.full_name ?? "Assigned"}` : "Head not assigned"}</span></article>)}</div>}
    {inactiveOrganizations.filter((organization) => organization.college_id === selectedCollegeId).length > 0 && <details><summary>Inactive societies</summary><ul>{inactiveOrganizations.filter((organization) => organization.college_id === selectedCollegeId).map((organization) => <li key={organization.id}>{organization.name} · Paused</li>)}</ul></details>}
    <div className="management-grid">
      <form className="ops-form" onSubmit={createOrganization}>
        <h3>Create society for {collegeName}</h3>
        <label className="field">Society name<input required minLength={2} maxLength={160} value={organizationName} onChange={event => setOrganizationName(event.target.value)} placeholder="Robotics Club" /></label>
        <label className="field">Society ID<input required pattern="[a-z0-9-]+" value={organizationSlug} onChange={event => setOrganizationSlug(event.target.value.toLowerCase())} placeholder="robotics-club" /></label>
        <button disabled={busy || !selectedCollegeId}>{busy ? "Saving…" : "Create society"}</button>
      </form>
      <form className="ops-form" onSubmit={createProfile}>
        <h3>Create account</h3>
        <label className="field">Account type<select value={profileType} onChange={event => setProfileType(event.target.value as "student" | "organizer") }><option value="student">Student</option><option value="organizer">Organizer ID</option></select></label>
        <label className="field">Username<input required minLength={3} value={username} onChange={event => setUsername(event.target.value)} placeholder="student01" autoComplete="off" /></label>
        <label className="field">Full name<input required minLength={2} value={fullName} onChange={event => setFullName(event.target.value)} placeholder="Account holder name" /></label>
        <label className="field">Temporary password<input required minLength={8} type="password" value={password} onChange={event => setPassword(event.target.value)} autoComplete="new-password" /></label>
        <button disabled={busy || !selectedCollegeId}>{busy ? "Creating…" : `Create ${profileType === "student" ? "student" : "organizer"} account`}</button>
        <p className="helper">Credentials are sent to Supabase Auth and are not stored in the Admin UI.</p>
      </form>
      <form className="ops-form" onSubmit={assignHead}>
        <h3>Assign society head</h3>
        <p className="helper">Choose an existing organizer ID from this college. Event access starts after this assignment.</p>
        <label className="field">Society<select required value={headSocietyId} onChange={event => setHeadSocietyId(event.target.value)}><option value="">Choose society</option>{selectedOrganizations.map(society => <option key={society.id} value={society.id}>{society.name}</option>)}</select></label>
        <label className="field">Organizer ID<select required value={headUserId} onChange={event => setHeadUserId(event.target.value)}><option value="">Choose organizer</option>{organizerAccounts.map(account => <option key={account.user_id} value={account.user_id}>{account.full_name} · {account.login_username ?? account.user_id.slice(0, 8)}</option>)}</select></label>
        <button disabled={busy || !selectedOrganizations.length || !organizerAccounts.length}>{busy ? "Assigning…" : "Assign head"}</button>
      </form>
    </div>
    {message && <p role="status" className="success-text">{message}</p>}
    {error && <p role="alert" className="error-text">{error}</p>}
  </section>;
}
