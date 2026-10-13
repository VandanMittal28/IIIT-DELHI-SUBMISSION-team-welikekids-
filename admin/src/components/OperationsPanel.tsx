"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type Edition = { id: string; event_id: string; label: string; starts_at: string };
type ReportAttachment = { id: string; report_id: string; storage_path: string; signed_url?: string };
type Report = { id: string; edition_id: string; category: string; description: string; priority: string; status: string; created_at: string; reported_message_id:string|null; reported_message?:DiscussionMessage; attachments: ReportAttachment[] };
type AssignableStaff = { user_id: string; full_name: string; role: string };
type Occupancy = { edition_id: string; estimated_inside: number; freshness_at: string | null };
type DiscussionMessage = { id:string; body:string; status:string; created_at:string; channel_id:string };
type ReviewSummary = { event_id:string; edition_id:string; sample_size:number; average_rating:number };

export function OperationsPanel({ eventIds }: { eventIds: string[] }) {
  const [editions, setEditions] = useState<Edition[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [occupancy, setOccupancy] = useState<Occupancy[]>([]);
  const [editionId, setEditionId] = useState("");
  const [title, setTitle] = useState(""); const [body, setBody] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [discussion,setDiscussion]=useState<DiscussionMessage[]>([]); const [reviews,setReviews]=useState<ReviewSummary[]>([]);
  const [staffByEdition,setStaffByEdition]=useState<Record<string,AssignableStaff[]>>({});
  const [assigneeByReport,setAssigneeByReport]=useState<Record<string,string>>({});

  const load = useCallback(async () => {
    if (eventIds.length === 0) { setEditions([]); setReports([]); setOccupancy([]); return; }
    const supabase = getSupabase();
    const editionResult = await supabase.from("event_editions").select("id,event_id,label,starts_at").in("event_id", eventIds).order("starts_at");
    if (editionResult.error) { setMessage(editionResult.error.message); return; }
    const rows = editionResult.data as Edition[]; setEditions(rows); setEditionId((current) => current || rows[0]?.id || "");
    if (!rows.length) return;
    const ids = rows.map((row) => row.id);
    const channelResult=await supabase.from("channels").select("id").in("edition_id",ids);
    const channelIds=(channelResult.data??[]).map(row=>row.id);
    const [reportResult, occupancyResult, discussionResult, reviewResult] = await Promise.all([
      supabase.from("reports").select("id,edition_id,category,description,priority,status,created_at,reported_message_id").in("edition_id", ids).order("created_at", { ascending: false }),
      supabase.from("edition_occupancy").select("edition_id,estimated_inside,freshness_at").in("edition_id", ids),
      channelIds.length?supabase.from("messages").select("id,body,status,created_at,channel_id").in("channel_id",channelIds).order("created_at",{ascending:false}).limit(50):Promise.resolve({data:[],error:null}),
      supabase.from("edition_review_summary").select("event_id,edition_id,sample_size,average_rating").in("event_id",eventIds),
    ]);
    if (reportResult.error || occupancyResult.error || discussionResult.error || reviewResult.error || channelResult.error) { setMessage(reportResult.error?.message ?? occupancyResult.error?.message ?? discussionResult.error?.message ?? reviewResult.error?.message ?? channelResult.error?.message ?? "Could not refresh operations."); return; }
    const reportRows=reportResult.data as Omit<Report,"attachments">[];
    const reportedMessageIds=reportRows.flatMap(report=>report.reported_message_id?[report.reported_message_id]:[]);
    const [attachmentResult,reportedMessageResult]=await Promise.all([
      reportRows.length?supabase.from("report_attachments").select("id,report_id,storage_path").in("report_id",reportRows.map(report=>report.id)):Promise.resolve({data:[],error:null}),
      reportedMessageIds.length?supabase.from("messages").select("id,body,status,created_at,channel_id").in("id",reportedMessageIds):Promise.resolve({data:[],error:null}),
    ]);
    if(attachmentResult.error||reportedMessageResult.error){setMessage(`Could not load report context: ${attachmentResult.error?.message??reportedMessageResult.error?.message}`);return;}
    const attachments=await Promise.all((attachmentResult.data as ReportAttachment[]).map(async attachment=>{
      const {data}=await supabase.storage.from("report-attachments").createSignedUrl(attachment.storage_path,900);
      return {...attachment,signed_url:data?.signedUrl};
    }));
    const staffResults=await Promise.all(rows.map(async edition=>({editionId:edition.id,result:await supabase.rpc("get_assignable_event_staff",{p_edition_id:edition.id})})));
    const staffError=staffResults.find(item=>item.result.error)?.result.error;
    if(staffError){setMessage(`Could not load assignable staff: ${staffError.message}`);return;}
    const reportedMessages=reportedMessageResult.data as DiscussionMessage[];
    setReports(reportRows.map(report=>({...report,reported_message:reportedMessages.find(item=>item.id===report.reported_message_id),attachments:attachments.filter(attachment=>attachment.report_id===report.id)})));
    setStaffByEdition(Object.fromEntries(staffResults.map(item=>[item.editionId,item.result.data as AssignableStaff[]])));
    setOccupancy(occupancyResult.data as Occupancy[]); setDiscussion(discussionResult.data as DiscussionMessage[]); setReviews(reviewResult.data as ReviewSummary[]);
  }, [eventIds]);

  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer); }, [load]);
  useEffect(()=>{const supabase=getSupabase();const channel=supabase.channel(`admin-operations-${eventIds.join("-")}`).on("postgres_changes",{event:"*",schema:"public",table:"reports"},()=>void load()).on("postgres_changes",{event:"*",schema:"public",table:"attendance_transitions"},()=>void load()).on("postgres_changes",{event:"*",schema:"public",table:"messages"},()=>void load()).subscribe();return()=>{void supabase.removeChannel(channel)}},[eventIds,load]);

  async function announce(event: FormEvent) {
    event.preventDefault(); setMessage(null);
    const { error } = await getSupabase().rpc("publish_announcement", { p_edition_id: editionId, p_title: title, p_body: body, p_kind: "official" });
    if (error) setMessage(`Not published: ${error.message}`); else { setMessage("Announcement persisted and delivery work queued."); setTitle(""); setBody(""); }
  }

  async function advance(report: Report) {
    const next: Record<string, string> = { submitted: "acknowledged", acknowledged: "assigned", assigned: "in_progress", in_progress: "resolved" };
    if (!next[report.status]) return;
    const assignee=next[report.status]==="assigned"?assigneeByReport[report.id]:null;
    if(next[report.status]==="assigned"&&!assignee){setMessage("Choose an assigned event staff member before assigning this report.");return;}
    const { error } = await getSupabase().rpc("transition_report", { p_report_id: report.id, p_status: next[report.status], p_assignee_id: assignee, p_note: "Updated from Sidequest Admin" });
    if (error) setMessage(error.message); else { setMessage("Report status persisted and the student was notified."); await load(); }
  }

  async function moderateMessage(messageId:string,status:"visible"|"hidden") {
    const {error}=await getSupabase().rpc("moderate_message",{p_message_id:messageId,p_status:status});
    if(error)setMessage(error.message);else{setMessage(status==="hidden"?"Message hidden and moderation audit persisted.":"Message restored and moderation audit persisted.");await load();}
  }

  return <section className="ops-grid">
    <article className="ops-card"><div className="ops-heading"><div><p className="ops-kicker">Attendance</p><h2>Occupancy</h2></div><button className="secondary" onClick={() => void load()}>Refresh</button></div>
      {occupancy.length === 0 ? <p className="helper">No attendance transitions recorded.</p> : occupancy.map((item) => <div className="metric" key={item.edition_id}><strong>{item.estimated_inside}</strong><span>estimated inside<br />{item.freshness_at ? `Updated ${new Date(item.freshness_at).toLocaleString("en-IN")}` : "No scans yet"}</span></div>)}
      <button className="secondary" disabled={!editionId} onClick={()=>{const delta=window.prompt("Correction amount, such as -1 or 2");const reason=window.prompt("Auditable reason (at least 5 characters)");if(delta&&reason)void getSupabase().rpc("correct_occupancy",{p_edition_id:editionId,p_delta:Number(delta),p_reason:reason}).then(({error})=>{if(error)setMessage(error.message);else{setMessage("Audited occupancy correction persisted.");void load()}})}}>Record correction</button>
    </article>
    <article className="ops-card"><p className="ops-kicker">Official updates</p><h2>Publish announcement</h2><form onSubmit={announce} className="ops-form"><label className="field">Edition<select required value={editionId} onChange={(e) => setEditionId(e.target.value)}>{editions.map((edition) => <option key={edition.id} value={edition.id}>{edition.label} · {new Date(edition.starts_at).toLocaleDateString("en-IN")}</option>)}</select></label><label className="field">Title<input required minLength={2} value={title} onChange={(e) => setTitle(e.target.value)} /></label><label className="field">Message<textarea required minLength={2} value={body} onChange={(e) => setBody(e.target.value)} /></label><button disabled={!editionId}>Publish and notify</button></form></article>
    <article className="ops-card ops-wide"><p className="ops-kicker">Assigned queue</p><h2>Reports</h2>{reports.length === 0 ? <p className="helper">No submitted reports.</p> : reports.map((report) => <div className="report-row" key={report.id}><div><strong>{report.category}</strong><p>{report.description}</p>{report.reported_message&&<blockquote>Reported message: “{report.reported_message.body}” <small>· {report.reported_message.status}</small></blockquote>}<small>{report.priority} · {report.status.replaceAll("_", " ")}</small>{report.attachments.length>0&&<div className="evidence-links">{report.attachments.map((attachment,index)=>attachment.signed_url?<a key={attachment.id} href={attachment.signed_url} target="_blank" rel="noreferrer">Open evidence {index+1}</a>:<span key={attachment.id} className="error-text">Evidence {index+1} unavailable</span>)}</div>}</div><div className="report-actions">{report.reported_message?.status==="visible"&&<button className="secondary" onClick={()=>void moderateMessage(report.reported_message_id??"","hidden")}>Hide reported message</button>}{report.status==="acknowledged"&&<select aria-label={`Assignee for ${report.category}`} value={assigneeByReport[report.id]??""} onChange={event=>setAssigneeByReport(current=>({...current,[report.id]:event.target.value}))}><option value="">Choose assignee</option>{(staffByEdition[report.edition_id]??[]).map(staff=><option key={`${staff.user_id}-${staff.role}`} value={staff.user_id}>{staff.full_name} · {staff.role.replaceAll("_"," ")}</option>)}</select>}{report.status !== "resolved" && <button onClick={() => void advance(report)}>{({submitted:"Acknowledge",acknowledged:"Assign",assigned:"Start work",in_progress:"Resolve"} as Record<string,string>)[report.status]??"Advance"}</button>}</div></div>)}{message && <p role="status" className={message.startsWith("Not")||message.startsWith("Could")||message.startsWith("Choose") ? "error-text" : "success-text"}>{message}</p>}</article>
    <article className="ops-card"><p className="ops-kicker">Discussion moderation</p><h2>Recent messages</h2>{discussion.length===0?<p className="helper">No discussion messages.</p>:discussion.map(item=><div className="report-row" key={item.id}><div><p>{item.body}</p><small>{item.status} · {new Date(item.created_at).toLocaleString("en-IN")}</small></div><button className="secondary" onClick={()=>void moderateMessage(item.id,item.status==="visible"?"hidden":"visible")}>{item.status==="visible"?"Hide":"Restore"}</button></div>)}</article>
    <article className="ops-card"><p className="ops-kicker">Verified feedback</p><h2>Review insight by edition</h2>{reviews.length===0?<p className="helper">No eligible reviews yet.</p>:reviews.map(item=><div className="metric" key={item.edition_id}><strong>{Number(item.average_rating).toFixed(1)}</strong><span>{editions.find(edition=>edition.id===item.edition_id)?.label??"Edition"}<br />{item.sample_size} verified {item.sample_size===1?"review":"reviews"}</span></div>)}</article>
  </section>;
}
