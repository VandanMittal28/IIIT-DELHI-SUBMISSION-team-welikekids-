"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { backendConfiguration, getSupabase } from "@/lib/supabase";
import type { EventDraft, EventRecord, Organization, RegistrationSummary } from "@/lib/types";
import styles from "./page.module.css";
import { VolunteerScanner } from "@/components/VolunteerScanner";
import { OperationsPanel } from "@/components/OperationsPanel";
import { CampusEditor } from "@/components/CampusEditor";
import { ManagementPanel } from "@/components/ManagementPanel";
import { ProfileProvisioningPanel } from "@/components/ProfileProvisioningPanel";

const emptyDraft: EventDraft = {
  organizationId: "", title: "", description: "", category: "", visibility: "public",
  priceRupees: "0", eligibility: "", registrationOpensAt: "", registrationClosesAt: "",
  startsAt: "", endsAt: "", capacity: "", waitlistEnabled: true,
};

function messageFrom(error: unknown) {
  if (error && typeof error === "object" && "message" in error) {
    const raw = String(error.message);
    try { return (JSON.parse(raw) as { message?: string }).message ?? raw; } catch { return raw; }
  }
  return "Something went wrong. Please try again.";
}

function authEmail(identifier: string) {
  const normalized = identifier.trim().toLowerCase();
  return normalized.includes("@") ? normalized : `${normalized.replace(/\s+/g, "")}@sidequest.local`;
}

export default function Home() {
  const configured = backendConfiguration().isConfigured;
  const [user, setUser] = useState<User | null>(null);
  const [authReady, setAuthReady] = useState(!configured);
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [events, setEvents] = useState<EventRecord[]>([]);
  const [published, setPublished] = useState<EventRecord[]>([]);
  const [registrationSummaries, setRegistrationSummaries] = useState<RegistrationSummary[]>([]);
  const [adminCollegeIds, setAdminCollegeIds] = useState<string[]>([]);
  const [draft, setDraft] = useState<EventDraft>(emptyDraft);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [inviteCode,setInviteCode]=useState("");

  const loadData = useCallback(async (activeUser: User) => {
    const supabase = getSupabase();
    setError(null);
    const [membershipResult, adminResult] = await Promise.all([
      supabase.from("memberships")
        .select("organization_id, organizations!inner(id,name,college_id,is_active)")
        .eq("user_id", activeUser.id).eq("role", "organizer").eq("status", "active"),
      supabase.from("college_memberships").select("college_id")
        .eq("user_id", activeUser.id).eq("is_admin", true).eq("status", "active"),
    ]);
    if (membershipResult.error) throw membershipResult.error;
    if (adminResult.error) throw adminResult.error;
    const memberOrgs = membershipResult.data.flatMap((row) => {
      const value = row.organizations as unknown as Organization | Organization[];
      return Array.isArray(value) ? value : [value];
    });
    const adminCollegeIds = adminResult.data.map((row) => row.college_id);
    setAdminCollegeIds(adminCollegeIds);
    const adminOrganizations = adminCollegeIds.length > 0
      ? await supabase.from("organizations").select("id,name,college_id,is_active").in("college_id", adminCollegeIds)
      : { data: [] as Organization[], error: null };
    if (adminOrganizations.error) throw adminOrganizations.error;
    const orgs = Array.from(new Map([...memberOrgs, ...(adminOrganizations.data as Organization[])].map((org) => [org.id, org])).values());
    setOrganizations(orgs);
    const activeOrgs = orgs.filter((organization) => organization.is_active !== false);
    setDraft((current) => ({ ...current, organizationId: activeOrgs.some((org) => org.id === current.organizationId) ? current.organizationId : activeOrgs[0]?.id || "" }));
    const [eventsResult, feedResult, registrationResult] = await Promise.all([
      supabase.from("events").select("id,title,description,category,eligibility,price_minor,status,organization_id,college_id").order("created_at", { ascending: false }),
      supabase.from("published_event_feed").select("*").order("starts_at", { ascending: true }).limit(8),
      supabase.from("edition_registration_summary").select("edition_id,event_id,capacity,registered_count,waitlisted_count,cancelled_count"),
    ]);
    if (eventsResult.error) throw eventsResult.error;
    if (feedResult.error) throw feedResult.error;
    if (registrationResult.error) throw registrationResult.error;
    setEvents(eventsResult.data as EventRecord[]);
    setPublished(feedResult.data as EventRecord[]);
    setRegistrationSummaries(registrationResult.data as RegistrationSummary[]);
  }, []);

  useEffect(() => {
    if (!configured) return;
    const supabase = getSupabase();
    void supabase.auth.getUser().then(({ data }) => {
      setUser(data.user); setAuthReady(true);
      if (data.user) void loadData(data.user).catch((reason) => setError(messageFrom(reason)));
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null));
    return () => listener.subscription.unsubscribe();
  }, [configured, loadData]);

  const publishedIds = useMemo(() => new Set(published.map((event) => event.id)), [published]);
  const registrationsByEvent = useMemo(() => new Map(registrationSummaries.map((summary) => [summary.event_id, summary])), [registrationSummaries]);
  const registeredTotal = useMemo(() => registrationSummaries.reduce((total, item) => total + item.registered_count, 0), [registrationSummaries]);
  const waitlistedTotal = useMemo(() => registrationSummaries.reduce((total, item) => total + item.waitlisted_count, 0), [registrationSummaries]);
  const managedEventIds = useMemo(() => events.map((item) => item.id), [events]);
  const activeOrganizations = useMemo(() => organizations.filter((organization) => organization.is_active !== false), [organizations]);

  async function signIn(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null);
    const { data, error: signInError } = await getSupabase().auth.signInWithPassword({ email: authEmail(identifier), password });
    if (signInError) setError(messageFrom(signInError));
    else if (data.user) {
      setUser(data.user);
      try { await loadData(data.user); } catch (reason) { setError(messageFrom(reason)); }
    }
    setBusy(false);
  }

  async function createEvent(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setNotice(null);
    const opens = new Date(draft.registrationOpensAt);
    const closes = new Date(draft.registrationClosesAt);
    const starts = new Date(draft.startsAt);
    const ends = new Date(draft.endsAt);
    if ([opens, closes, starts, ends].some((value) => Number.isNaN(value.getTime()))) {
      setError("Enter all registration and event dates before creating the event."); setBusy(false); return;
    }
    if (!(opens < closes && closes <= ends && starts < ends)) {
      setError("Check the schedule: registration must open before it closes, and the event must end after it starts."); setBusy(false); return;
    }
    if (!draft.organizationId) { setError("Choose the IIIT Delhi organization first."); setBusy(false); return; }
    const { data, error: createError } = await getSupabase().rpc("create_event", {
      p_client_request_id: crypto.randomUUID(), p_organization_id: draft.organizationId,
      p_title: draft.title, p_description: draft.description, p_category: draft.category,
      p_visibility: draft.visibility, p_price_minor: Math.round(Number(draft.priceRupees) * 100),
      p_currency: "INR", p_eligibility: draft.eligibility,
      p_registration_opens_at: opens.toISOString(),
      p_registration_closes_at: closes.toISOString(),
      p_starts_at: starts.toISOString(), p_ends_at: ends.toISOString(),
      p_capacity: Number(draft.capacity), p_waitlist_enabled: draft.waitlistEnabled,
    });
    if (createError) setError(messageFrom(createError));
    else {
      setNotice(`Draft confirmed by the backend. Event ${String(data.event_id).slice(0, 8)}…`);
      setDraft({ ...emptyDraft, organizationId: draft.organizationId });
      if (user) await loadData(user);
    }
    setBusy(false);
  }

  async function publishEvent(eventId: string) {
    setBusy(true); setError(null); setNotice(null);
    const { data, error: publishError } = await getSupabase().rpc("publish_event", { p_event_id: eventId });
    if (publishError) setError(messageFrom(publishError));
    else {
      setNotice(data.status === "published" ? "Event published to student discovery." : "Event submitted for college approval.");
      if (user) await loadData(user);
    }
    setBusy(false);
  }

  async function acceptInvitation(event:FormEvent){event.preventDefault();setError(null);const{error:acceptError}=await getSupabase().rpc("accept_role_invitation",{p_token:inviteCode});if(acceptError)setError(messageFrom(acceptError));else if(user){setNotice("Invitation accepted. Your scoped access is active.");setInviteCode("");await loadData(user)}}

  if (!configured) return <main className={styles.center}><section className={styles.authCard}><Brand /><p className={styles.eyebrow}>Setup required</p><h1>Connect the Sidequest backend</h1><p>Copy <code>.env.local.example</code> to <code>.env.local</code> and add the authorized Supabase URL and publishable key. No demo data will be substituted.</p></section></main>;
  if (!authReady) return <main className={styles.center}><p>Checking your session…</p></main>;
  if (!user) return <main className={styles.center}><section className={styles.authCard}><Brand /><p className={styles.eyebrow}>Organizer access</p><h1>Make campus happen.</h1><p>Sign in with the username and password assigned by your college administrator.</p><form onSubmit={signIn} className={styles.stack}><label>Username<input required autoComplete="username" value={identifier} onChange={(e) => setIdentifier(e.target.value)} /></label><label>Password<input required minLength={6} type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} /></label>{error && <Alert>{error}</Alert>}<button disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button></form></section></main>;

  return <div className={styles.shell}>
    <header className={styles.header}><Brand /><div className={styles.user}><span>IIIT Delhi · {user.email?.split("@")[0]}</span><button className={styles.ghost} onClick={() => void getSupabase().auth.signOut()}>Sign out</button></div></header>
    <main className={styles.dashboard}>
      <section className={styles.hero}><div><p className={styles.eyebrow}>IIIT Delhi operations</p><h1>Campus events, made simple.</h1><p>Create an event, choose an IIIT Delhi venue, assign volunteers, and publish it to students.</p></div><div className={styles.stats}><span><strong>{events.length}</strong> events</span><span><strong>{published.length}</strong> live</span></div></section>
      {error && <Alert>{error}</Alert>}{notice && <div className={styles.notice}>{notice}</div>}
      <details className={styles.panel}><summary>Have a volunteer invitation?</summary><form onSubmit={acceptInvitation} className={styles.stack}><label>One-time invitation code<input required value={inviteCode} onChange={e=>setInviteCode(e.target.value)} placeholder="Paste invitation code" /></label><button>Activate volunteer access</button></form></details>
      {activeOrganizations.length === 0 ? <section className={styles.empty}><h2>{adminCollegeIds.length > 0 ? "Create your first organization" : "No organizer access yet"}</h2><p>{adminCollegeIds.length > 0 ? "Your college administrator access is active. Create an authorized organization below to begin managing events." : "Your account is valid, but it has no active organizer membership. Ask a college administrator to invite you; Sidequest will not grant access from profile metadata."}</p></section> : <div className={styles.columns}>
        <section className={styles.panel}><div className={styles.panelHead}><p className={styles.eyebrow}>New event</p><h2>Create the first edition</h2></div><form onSubmit={createEvent} className={styles.formGrid}>
          <label className={styles.full}>Active organization<select required value={draft.organizationId} onChange={(e) => setDraft({ ...draft, organizationId: e.target.value })}>{activeOrganizations.map((org) => <option value={org.id} key={org.id}>{org.name}</option>)}</select></label>
          <label className={styles.full}>Event title<input required minLength={3} maxLength={160} value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} placeholder="Name students will recognize" /></label>
          <label className={styles.full}>Description<textarea required minLength={10} maxLength={10000} rows={4} value={draft.description} onChange={(e) => setDraft({ ...draft, description: e.target.value })} placeholder="What will happen, and who is it for?" /></label>
          <label>Category<input required value={draft.category} onChange={(e) => setDraft({ ...draft, category: e.target.value })} placeholder="Workshop" /></label>
          <label>Visibility<select value={draft.visibility} onChange={(e) => setDraft({ ...draft, visibility: e.target.value as EventDraft["visibility"] })}><option value="public">Public</option><option value="college_only">College only</option><option value="organization_only">Organization only</option></select></label>
          <label>Price (₹)<input required min={0} step="0.01" type="number" value={draft.priceRupees} onChange={(e) => setDraft({ ...draft, priceRupees: e.target.value })} /></label>
          <label>Capacity<input required min={1} type="number" value={draft.capacity} onChange={(e) => setDraft({ ...draft, capacity: e.target.value })} /></label>
          <label>Registration opens<input required type="datetime-local" value={draft.registrationOpensAt} onChange={(e) => setDraft({ ...draft, registrationOpensAt: e.target.value })} /></label>
          <label>Registration closes<input required type="datetime-local" value={draft.registrationClosesAt} onChange={(e) => setDraft({ ...draft, registrationClosesAt: e.target.value })} /></label>
          <label>Starts<input required type="datetime-local" value={draft.startsAt} onChange={(e) => setDraft({ ...draft, startsAt: e.target.value })} /></label>
          <label>Ends<input required type="datetime-local" value={draft.endsAt} onChange={(e) => setDraft({ ...draft, endsAt: e.target.value })} /></label>
          <label className={styles.full}>Eligibility<input value={draft.eligibility} onChange={(e) => setDraft({ ...draft, eligibility: e.target.value })} placeholder="Leave blank if everyone is eligible" /></label>
          <label className={`${styles.full} ${styles.check}`}><input type="checkbox" checked={draft.waitlistEnabled} onChange={(e) => setDraft({ ...draft, waitlistEnabled: e.target.checked })} /> Enable waitlist when capacity is reached</label>
          <button className={styles.full} disabled={busy}>{busy ? "Saving…" : "Create draft"}</button>
        </form></section>
        <aside className={styles.side}><section className={styles.panel}><div className={styles.panelHead}><p className={styles.eyebrow}>Your events</p><h2>Publishing desk</h2></div>{events.length === 0 ? <p className={styles.muted}>No events yet. Your first confirmed draft will appear here.</p> : <div className={styles.list}>{events.map((item) => { const summary = registrationsByEvent.get(item.id); return <article key={item.id} className={styles.eventRow}><div><span className={styles.pill}>{item.status?.replace("_", " ")}</span><h3>{item.title}</h3><p>{item.category}</p>{summary && <p>{summary.registered_count}/{summary.capacity} registered · {summary.waitlisted_count} waiting</p>}</div>{item.status === "draft" && <button disabled={busy} onClick={() => void publishEvent(item.id)}>Publish</button>}{publishedIds.has(item.id) && <span className={styles.live}>Live</span>}</article>; })}</div>}</section>
        <section className={styles.panel}><div className={styles.panelHead}><p className={styles.eyebrow}>Student view</p><h2>Live discovery</h2></div>{published.length === 0 ? <p className={styles.muted}>No published events. Students see a useful empty state, never fictional recommendations.</p> : <div className={styles.list}>{published.map((item) => <article key={item.id} className={styles.feedCard}><p>{item.college_name} · {item.category}</p><h3>{item.title}</h3><span>{item.starts_at ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(item.starts_at)) : "Schedule pending"}</span></article>)}</div>}</section></aside>
      </div>}
      {events.length > 0 && <section className={styles.operations}><div className={styles.sectionTitle}><p className={styles.eyebrow}>Live event operations</p><h2>Volunteer and response desk</h2><p>Every action below confirms against the authoritative backend. Realtime is only a refresh signal.</p></div><div className={styles.volunteerGrid}><VolunteerScanner onRecorded={() => user && void loadData(user)} /><OperationsPanel eventIds={managedEventIds} /></div><ManagementPanel events={events} organizations={organizations} onChanged={() => user && void loadData(user)} /></section>}
      {adminCollegeIds.length > 0 && <section className={styles.operations}><CampusEditor collegeIds={adminCollegeIds} /></section>}
      {adminCollegeIds.length > 0 && <section className={styles.operations}><ProfileProvisioningPanel collegeId={adminCollegeIds[0]} organizations={organizations.filter((organization) => organization.college_id === adminCollegeIds[0]).map(({ id, name, is_active }) => ({ id, name, is_active: is_active !== false }))} onChanged={() => user && void loadData(user)} /></section>}
    </main>
  </div>;
}

function Brand() { return <div className={styles.brand}><span className={styles.mark}>IIIT</span><div><strong>Sidequest · IIIT Delhi</strong><small>Your next starts outside class.</small></div></div>; }
function Alert({ children }: { children: React.ReactNode }) { return <div role="alert" className={styles.alert}>{children}</div>; }
