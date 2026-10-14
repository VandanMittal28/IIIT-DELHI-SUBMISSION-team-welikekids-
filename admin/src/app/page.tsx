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
  const [organizerOrganizations, setOrganizerOrganizations] = useState<Organization[]>([]);
  const [events, setEvents] = useState<EventRecord[]>([]);
  const [published, setPublished] = useState<EventRecord[]>([]);
  const [registrationSummaries, setRegistrationSummaries] = useState<RegistrationSummary[]>([]);
  const [adminCollegeIds, setAdminCollegeIds] = useState<string[]>([]);
  const [platformAdmin, setPlatformAdmin] = useState(false);
  const [colleges, setColleges] = useState<{ id: string; name: string }[]>([]);
  const [venues, setVenues] = useState<{id:string;name:string;college_id:string}[]>([]);
  const [venueId, setVenueId] = useState("");
  const [draft, setDraft] = useState<EventDraft>(emptyDraft);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [inviteCode,setInviteCode]=useState("");

  const loadData = useCallback(async (activeUser: User) => {
    const supabase = getSupabase();
    setError(null);
    const [membershipResult, adminResult, platformAdminResult] = await Promise.all([
      supabase.from("memberships")
        .select("organization_id, organizations!inner(id,name,college_id,is_active,head_user_id)")
        .eq("user_id", activeUser.id).eq("role", "organizer").eq("status", "active"),
      supabase.from("college_memberships").select("college_id")
        .eq("user_id", activeUser.id).eq("is_admin", true).eq("status", "active"),
      supabase.from("platform_admins").select("user_id").eq("user_id", activeUser.id).maybeSingle(),
    ]);
    if (membershipResult.error) throw membershipResult.error;
    if (adminResult.error) throw adminResult.error;
    if (platformAdminResult.error) throw platformAdminResult.error;
    const isPlatformAdmin = Boolean(platformAdminResult.data);
    setPlatformAdmin(isPlatformAdmin);
    const memberOrgs = membershipResult.data.flatMap((row) => {
      const value = row.organizations as unknown as Organization | Organization[];
      return Array.isArray(value) ? value : [value];
    });
    const adminCollegeIds = adminResult.data.map((row) => row.college_id);
    setAdminCollegeIds(adminCollegeIds);
    let adminOrganizations: Organization[] = [];
    if (isPlatformAdmin || adminCollegeIds.length > 0) {
      const organizationQuery = supabase.from("organizations").select("id,name,college_id,is_active,head_user_id");
      const adminOrganizationResult = isPlatformAdmin
        ? await organizationQuery.order("name")
        : await organizationQuery.in("college_id", adminCollegeIds);
      if (adminOrganizationResult.error) throw adminOrganizationResult.error;
      adminOrganizations = adminOrganizationResult.data as Organization[];
    }
    if (isPlatformAdmin) {
      const collegeResult = await supabase.from("colleges").select("id,name").order("name");
      if (collegeResult.error) throw collegeResult.error;
      setColleges(collegeResult.data);
    } else if (adminCollegeIds.length > 0) {
      const collegeResult = await supabase.from("colleges").select("id,name").in("id", adminCollegeIds).order("name");
      if (collegeResult.error) throw collegeResult.error;
      setColleges(collegeResult.data);
    }
    const orgs = Array.from(new Map([...memberOrgs, ...adminOrganizations].map((org) => [org.id, org])).values());
    setOrganizations(orgs);
    const organizerOrgs = isPlatformAdmin || adminCollegeIds.length > 0 ? [] : memberOrgs.filter(org => org.head_user_id === activeUser.id);
    setOrganizerOrganizations(organizerOrgs);
    const activeOrgs = organizerOrgs.filter((organization) => organization.is_active !== false);
    setDraft((current) => ({ ...current, organizationId: activeOrgs.some((org) => org.id === current.organizationId) ? current.organizationId : activeOrgs[0]?.id || "" }));
    const [venueResult,campusResult]=await Promise.all([
      supabase.from("venues").select("id,name,campus_id").order("name"),
      supabase.from("campuses").select("id,college_id"),
    ]);
    if(venueResult.error||campusResult.error) throw venueResult.error??campusResult.error;
    const campusColleges=new Map(campusResult.data.map((campus)=>[campus.id,campus.college_id]));
    const availableVenues=venueResult.data.flatMap((venue)=>{const college_id=campusColleges.get(venue.campus_id);return college_id?[{id:venue.id,name:venue.name,college_id}]:[]});
    setVenues(availableVenues);
    setVenueId((current)=>availableVenues.some((venue)=>venue.id===current)?current:availableVenues.find((venue)=>venue.college_id===activeOrgs[0]?.college_id)?.id??"");
    const [eventsResult, feedResult, registrationResult] = await Promise.all([
      activeOrgs.length ? supabase.from("events").select("id,title,description,category,eligibility,price_minor,status,organization_id,college_id").in("organization_id", activeOrgs.map(org => org.id)).order("created_at", { ascending: false }) : Promise.resolve({data: [], error: null}),
      activeOrgs.length ? supabase.from("published_event_feed").select("*").in("organization_id", activeOrgs.map(org => org.id)).order("starts_at", { ascending: true }).limit(8) : Promise.resolve({data: [], error: null}),
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
  const managedEventIds = useMemo(() => events.map((item) => item.id), [events]);
  const activeOrganizations = useMemo(() => organizerOrganizations.filter((organization) => organization.is_active !== false), [organizerOrganizations]);
  const selectedOrganizationCollegeId=activeOrganizations.find((organization)=>organization.id===draft.organizationId)?.college_id;
  const availableEventVenues=venues.filter((venue)=>venue.college_id===selectedOrganizationCollegeId);

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
    if (!draft.organizationId) { setError("Choose a society you organize first."); setBusy(false); return; }
    const selectedOrganization=activeOrganizations.find((organization)=>organization.id===draft.organizationId);
    if (!selectedOrganization) { setError("You need organizer access for this society."); setBusy(false); return; }
    const selectedVenue=venues.find((venue)=>venue.id===venueId&&venue.college_id===selectedOrganization?.college_id);
    if(!selectedVenue){setError("Choose a venue that belongs to the selected organization’s college.");setBusy(false);return;}
    const { data, error: createError } = await getSupabase().rpc("create_event_with_venue", {
      p_client_request_id: crypto.randomUUID(), p_organization_id: draft.organizationId,
      p_title: draft.title, p_description: draft.description, p_category: draft.category,
      p_visibility: draft.visibility, p_price_minor: Math.round(Number(draft.priceRupees) * 100),
      p_currency: "INR", p_eligibility: draft.eligibility,
      p_registration_opens_at: opens.toISOString(),
      p_registration_closes_at: closes.toISOString(),
      p_starts_at: starts.toISOString(), p_ends_at: ends.toISOString(),
      p_capacity: Number(draft.capacity), p_waitlist_enabled: draft.waitlistEnabled,
      p_venue_id: selectedVenue.id,
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
  if (!user) return <main className={styles.center}><section className={styles.authCard}><Brand /><p className={styles.eyebrow}>Sidequest access</p><h1>Make campus happen.</h1><p>Sign in with the username and password assigned to your Sidequest admin or society head account.</p><form onSubmit={signIn} className={styles.stack}><label>Username<input required autoComplete="username" value={identifier} onChange={(e) => setIdentifier(e.target.value)} /></label><label>Password<input required minLength={6} type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} /></label>{error && <Alert>{error}</Alert>}<button disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button></form></section></main>;

  return <div className={styles.shell}>
    <header className={styles.header}><Brand /><div className={styles.user}><span>{platformAdmin ? "Sidequest platform admin" : adminCollegeIds.length ? "College admin" : "Society organizer"} · {user.email?.split("@")[0]}</span><button className={styles.ghost} onClick={() => void getSupabase().auth.signOut()}>Sign out</button></div></header>
    <main className={styles.dashboard}>
      <section className={styles.hero}><div><p className={styles.eyebrow}>{platformAdmin ? "Sidequest platform control" : adminCollegeIds.length ? "College administration" : "Society events"}</p><h1>{platformAdmin ? "One platform. Every campus." : adminCollegeIds.length ? "Manage your college." : "Run your society’s events."}</h1><p>{platformAdmin ? "Manage colleges, societies, and college student accounts across Sidequest." : adminCollegeIds.length ? "Create college student and organizer accounts, set up societies, and maintain campus information." : "Create events for your society and assign college students as volunteers."}</p></div>{activeOrganizations.length > 0 && <div className={styles.stats}><span><strong>{events.length}</strong> events</span><span><strong>{published.length}</strong> live</span></div>}</section>
      {error && <Alert>{error}</Alert>}{notice && <div className={styles.notice}>{notice}</div>}
      {!platformAdmin && <nav aria-label="Dashboard sections" className={styles.dashboardNav}>{activeOrganizations.length > 0 && <><a href="#create-event">Create event</a><a href="#publishing-desk">Publishing desk</a></>}{events.length>0&&<a href="#event-operations">Volunteer & event tools</a>}{adminCollegeIds.length>0&&<a href="#campus-data">Campus map</a>}</nav>}
      {!platformAdmin && <details className={styles.panel}><summary>Have a volunteer invitation?</summary><form onSubmit={acceptInvitation} className={styles.stack}><label>One-time invitation code<input required value={inviteCode} onChange={e=>setInviteCode(e.target.value)} placeholder="Paste invitation code" /></label><button>Activate volunteer access</button></form></details>}
      {!platformAdmin && (activeOrganizations.length === 0 ? adminCollegeIds.length === 0 && <section className={styles.empty}><h2>No society organizer access yet</h2><p>Ask your college admin to create an organizer account for your society.</p></section> : <div className={styles.columns}>
        <section className={styles.panel} id="create-event"><div className={styles.panelHead}><p className={styles.eyebrow}>New event</p><h2>Create the first edition</h2></div><form onSubmit={createEvent} className={styles.formGrid}>
          <label className={styles.full}>Your society<select required value={draft.organizationId} onChange={(e) => {const organizationId=e.target.value;setDraft({ ...draft, organizationId });const collegeId=activeOrganizations.find((organization)=>organization.id===organizationId)?.college_id;setVenueId(venues.find((venue)=>venue.college_id===collegeId)?.id??"")}}>{activeOrganizations.map((org) => <option value={org.id} key={org.id}>{org.name}</option>)}</select></label>
          <label className={styles.full}>Event title<input required minLength={3} maxLength={160} value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} placeholder="Name students will recognize" /></label>
          <label className={styles.full}>Description<textarea required minLength={10} maxLength={10000} rows={4} value={draft.description} onChange={(e) => setDraft({ ...draft, description: e.target.value })} placeholder="What will happen, and who is it for?" /></label>
          <label className={styles.full}>Campus venue<select required value={venueId} onChange={(e)=>setVenueId(e.target.value)}><option value="" disabled>{availableEventVenues.length?"Choose a venue":"No venues are configured for this college"}</option>{availableEventVenues.map((venue)=><option value={venue.id} key={venue.id}>{venue.name}</option>)}</select><small>{availableEventVenues.length?"Students will see this venue on their ticket, with a direct route when campus navigation data exists.":"Add a campus and venue in Campus map before creating this event."}</small></label>
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
          <button className={styles.full} disabled={busy||availableEventVenues.length===0}>{busy ? "Saving…" : "Create event draft"}</button>
        </form></section>
        <aside className={styles.side}><section className={styles.panel} id="publishing-desk"><div className={styles.panelHead}><p className={styles.eyebrow}>Your events</p><h2>Publishing desk</h2></div>{events.length === 0 ? <p className={styles.muted}>No events yet. Your first confirmed draft will appear here.</p> : <div className={styles.list}>{events.map((item) => { const summary = registrationsByEvent.get(item.id); return <article key={item.id} className={styles.eventRow}><div><span className={styles.pill}>{item.status?.replace("_", " ")}</span><h3>{item.title}</h3><p>{item.category}</p>{summary && <p>{summary.registered_count}/{summary.capacity} registered · {summary.waitlisted_count} waiting</p>}</div>{item.status === "draft" && <button disabled={busy} onClick={() => void publishEvent(item.id)}>Publish</button>}{publishedIds.has(item.id) && <span className={styles.live}>Live</span>}</article>; })}</div>}</section>
        <section className={styles.panel}><div className={styles.panelHead}><p className={styles.eyebrow}>Student view</p><h2>Live discovery</h2></div>{published.length === 0 ? <p className={styles.muted}>No published events. Students see a useful empty state, never fictional recommendations.</p> : <div className={styles.list}>{published.map((item) => <article key={item.id} className={styles.feedCard}><p>{item.college_name} · {item.category}</p><h3>{item.title}</h3><span>{item.starts_at ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(item.starts_at)) : "Schedule pending"}</span></article>)}</div>}</section></aside>
      </div>)}
      {!platformAdmin && events.length > 0 && <section className={styles.operations} id="event-operations"><div className={styles.sectionTitle}><p className={styles.eyebrow}>Live event operations</p><h2>Volunteer and response desk</h2><p>Every action below confirms against the authoritative backend. Realtime is only a refresh signal.</p></div><div className={styles.volunteerGrid}><VolunteerScanner onRecorded={() => user && void loadData(user)} /><OperationsPanel eventIds={managedEventIds} /></div><ManagementPanel events={events} onChanged={() => user && void loadData(user)} /></section>}
      {!platformAdmin && adminCollegeIds.length > 0 && <section className={styles.operations} id="campus-data"><CampusEditor collegeIds={adminCollegeIds} /></section>}
      {platformAdmin && <section className={styles.operations}><ProfileProvisioningPanel platformAdmin colleges={colleges} organizations={organizations.map(({ id, name, college_id, is_active, head_user_id }) => ({ id, name, college_id, is_active: is_active !== false, head_user_id }))} onChanged={async () => { if (user) await loadData(user); }} /></section>}
      {!platformAdmin && adminCollegeIds.length > 0 && <section className={styles.operations}><ProfileProvisioningPanel platformAdmin={false} collegeId={adminCollegeIds[0]} colleges={colleges} organizations={organizations.map(({ id, name, college_id, is_active, head_user_id }) => ({ id, name, college_id, is_active: is_active !== false, head_user_id }))} onChanged={async () => { if (user) await loadData(user); }} /></section>}
    </main>
  </div>;
}

function Brand() { return <div className={styles.brand}><span className={styles.mark}>SQ</span><div><strong>Sidequest Admin</strong><small>Your next starts outside class.</small></div></div>; }
function Alert({ children }: { children: React.ReactNode }) { return <div role="alert" className={styles.alert}>{children}</div>; }
