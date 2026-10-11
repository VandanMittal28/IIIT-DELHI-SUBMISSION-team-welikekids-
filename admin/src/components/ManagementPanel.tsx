"use client";

import { useCallback, useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { EventRecord, Organization } from "@/lib/types";

type Edition = { id:string; event_id:string; label:string; capacity:number; waitlist_enabled:boolean; reentry_allowed:boolean; starts_at:string; ends_at:string };
type Venue = { id:string; name:string; campus_id:string };

export function ManagementPanel({ events, organizations, onChanged }: { events:EventRecord[]; organizations:Organization[]; onChanged():void }) {
  const [editions,setEditions]=useState<Edition[]>([]); const [venues,setVenues]=useState<Venue[]>([]);
  const [eventId,setEventId]=useState(events[0]?.id??""); const [editionId,setEditionId]=useState(""); const [organizationId,setOrganizationId]=useState(organizations[0]?.id??"");
  const [userId,setUserId]=useState(""); const [role,setRole]=useState("event_volunteer"); const [message,setMessage]=useState<string|null>(null);
  const [sessionTitle,setSessionTitle]=useState(""); const [venueId,setVenueId]=useState(""); const [startsAt,setStartsAt]=useState(""); const [endsAt,setEndsAt]=useState("");
  const [capacity,setCapacity]=useState(""); const [waitlist,setWaitlist]=useState(true); const [reentry,setReentry]=useState(false); const [file,setFile]=useState<File|null>(null);

  const load=useCallback(async()=>{
    const supabase=getSupabase(); const ids=events.map(e=>e.id);
    const [editionResult,venueResult]=await Promise.all([
      ids.length?supabase.from("event_editions").select("id,event_id,label,capacity,waitlist_enabled,reentry_allowed,starts_at,ends_at").in("event_id",ids).order("starts_at"):Promise.resolve({data:[],error:null}),
      supabase.from("venues").select("id,name,campus_id").order("name")
    ]);
    if(editionResult.error||venueResult.error){setMessage(editionResult.error?.message??venueResult.error?.message??"Could not load management data.");return;}
    const editionRows=editionResult.data as Edition[]; setEditions(editionRows); setEditionId(current=>current||editionRows[0]?.id||"");
    const venueRows=venueResult.data as Venue[]; setVenues(venueRows); setVenueId(current=>current||venueRows[0]?.id||"");
  },[events]);
  useEffect(()=>{const timer=window.setTimeout(()=>void load(),0);return()=>window.clearTimeout(timer)},[load]);

  async function rpc(name:string,params:Record<string,unknown>,success:string){setMessage(null);const {error}=await getSupabase().rpc(name,params);if(error)setMessage(error.message);else{setMessage(success);await load();onChanged();}}
  const selectedEdition=editions.find(item=>item.id===editionId);

  async function uploadImage(){if(!file)return;const event=events.find(item=>item.id===eventId);if(!event?.college_id){setMessage("Event college is unavailable.");return;}const safe=file.name.replace(/[^a-zA-Z0-9._-]/g,"-");const path=`${event.college_id}/${event.id}/${crypto.randomUUID()}-${safe}`;const {error}=await getSupabase().storage.from("event-media").upload(path,file,{upsert:false});if(error)setMessage(error.message);else setMessage(`Image uploaded securely as ${path}.`);}

  return <section className="ops-card ops-wide"><div className="ops-heading"><div><p className="ops-kicker">Management</p><h2>People, editions and media</h2></div><span className="status-dot">Scoped permissions</span></div>
    <div className="management-grid">
      <form className="ops-form" onSubmit={(e)=>{e.preventDefault();void rpc("assign_context_role",{p_organization_id:organizationId,p_user_id:userId,p_role:role},"Invitation persisted.")}}><h3>Invite organization role</h3><label className="field">Organization<select value={organizationId} onChange={e=>setOrganizationId(e.target.value)}>{organizations.map(org=><option key={org.id} value={org.id}>{org.name}</option>)}</select></label><label className="field">Existing user ID<input required value={userId} onChange={e=>setUserId(e.target.value)} placeholder="Account UUID" /></label><label className="field">Role<select value={role} onChange={e=>setRole(e.target.value)}><option value="event_volunteer">Volunteer</option><option value="organizer">Organizer</option><option value="member">Member</option></select></label><button>Send audited invitation</button></form>
      <form className="ops-form" onSubmit={(e)=>{e.preventDefault();void rpc("assign_event_staff",{p_edition_id:editionId,p_user_id:userId,p_role:role==="organizer"?"organizer":"event_volunteer"},"Event assignment persisted.")}}><h3>Assign event staff</h3><EditionSelect editions={editions} value={editionId} setValue={setEditionId}/><label className="field">Existing user ID<input required value={userId} onChange={e=>setUserId(e.target.value)} /></label><button>Assign to edition</button></form>
      <form className="ops-form" onSubmit={(e)=>{e.preventDefault();void rpc("update_edition_capacity",{p_edition_id:editionId,p_capacity:Number(capacity),p_waitlist_enabled:waitlist,p_reentry_allowed:reentry},"Capacity rules updated.")}}><h3>Capacity and entry rules</h3><EditionSelect editions={editions} value={editionId} setValue={(value)=>{setEditionId(value);const row=editions.find(e=>e.id===value);setCapacity(String(row?.capacity??""));setWaitlist(row?.waitlist_enabled??true);setReentry(row?.reentry_allowed??false)}}/><label className="field">Capacity<input required type="number" min={1} value={capacity} onChange={e=>setCapacity(e.target.value)} placeholder={String(selectedEdition?.capacity??"")} /></label><label className="check-line"><input type="checkbox" checked={waitlist} onChange={e=>setWaitlist(e.target.checked)}/> Waitlist</label><label className="check-line"><input type="checkbox" checked={reentry} onChange={e=>setReentry(e.target.checked)}/> Re-entry</label><button>Save operational rules</button></form>
      <form className="ops-form" onSubmit={(e)=>{e.preventDefault();void rpc("create_event_session",{p_edition_id:editionId,p_venue_id:venueId||null,p_title:sessionTitle,p_starts_at:new Date(startsAt).toISOString(),p_ends_at:new Date(endsAt).toISOString()},"Session persisted.")}}><h3>Add session</h3><EditionSelect editions={editions} value={editionId} setValue={setEditionId}/><label className="field">Title<input required value={sessionTitle} onChange={e=>setSessionTitle(e.target.value)}/></label><label className="field">Venue<select value={venueId} onChange={e=>setVenueId(e.target.value)}>{venues.map(v=><option key={v.id} value={v.id}>{v.name}</option>)}</select></label><label className="field">Starts<input required type="datetime-local" value={startsAt} onChange={e=>setStartsAt(e.target.value)}/></label><label className="field">Ends<input required type="datetime-local" value={endsAt} onChange={e=>setEndsAt(e.target.value)}/></label><button>Add session</button></form>
      <div className="ops-form"><h3>Event lifecycle and media</h3><label className="field">Event<select value={eventId} onChange={e=>setEventId(e.target.value)}>{events.map(item=><option key={item.id} value={item.id}>{item.title}</option>)}</select></label><label className="field">Image<input type="file" accept="image/jpeg,image/png,image/webp" onChange={e=>setFile(e.target.files?.[0]??null)}/></label><button type="button" disabled={!file} onClick={()=>void uploadImage()}>Upload protected media</button><button type="button" className="danger" onClick={()=>{const reason=window.prompt("Cancellation reason shown to attendees");if(reason)void rpc("cancel_event",{p_event_id:eventId,p_reason:reason},"Event cancelled and attendees queued for notification.")}}>Cancel event</button></div>
    </div>{message&&<p role="status" className="success-text">{message}</p>}
  </section>;
}

function EditionSelect({editions,value,setValue}:{editions:Edition[];value:string;setValue(value:string):void}){return <label className="field">Edition<select required value={value} onChange={e=>setValue(e.target.value)}>{editions.map(item=><option key={item.id} value={item.id}>{item.label} · {new Date(item.starts_at).toLocaleDateString("en-IN")}</option>)}</select></label>}
