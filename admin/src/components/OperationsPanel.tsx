"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type Edition = { id: string; event_id: string; label: string; starts_at: string };
type Report = { id: string; edition_id: string; category: string; description: string; priority: string; status: string; created_at: string };
type Occupancy = { edition_id: string; estimated_inside: number; freshness_at: string | null };

export function OperationsPanel({ eventIds }: { eventIds: string[] }) {
  const [editions, setEditions] = useState<Edition[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [occupancy, setOccupancy] = useState<Occupancy[]>([]);
  const [editionId, setEditionId] = useState("");
  const [title, setTitle] = useState(""); const [body, setBody] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (eventIds.length === 0) { setEditions([]); setReports([]); setOccupancy([]); return; }
    const supabase = getSupabase();
    const editionResult = await supabase.from("event_editions").select("id,event_id,label,starts_at").in("event_id", eventIds).order("starts_at");
    if (editionResult.error) { setMessage(editionResult.error.message); return; }
    const rows = editionResult.data as Edition[]; setEditions(rows); setEditionId((current) => current || rows[0]?.id || "");
    if (!rows.length) return;
    const ids = rows.map((row) => row.id);
    const [reportResult, occupancyResult] = await Promise.all([
      supabase.from("reports").select("id,edition_id,category,description,priority,status,created_at").in("edition_id", ids).order("created_at", { ascending: false }),
      supabase.from("edition_occupancy").select("edition_id,estimated_inside,freshness_at").in("edition_id", ids),
    ]);
    if (reportResult.error || occupancyResult.error) setMessage(reportResult.error?.message ?? occupancyResult.error?.message ?? "Could not refresh operations.");
    else { setReports(reportResult.data as Report[]); setOccupancy(occupancyResult.data as Occupancy[]); }
  }, [eventIds]);

  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer); }, [load]);

  async function announce(event: FormEvent) {
    event.preventDefault(); setMessage(null);
    const { error } = await getSupabase().rpc("publish_announcement", { p_edition_id: editionId, p_title: title, p_body: body, p_kind: "official" });
    if (error) setMessage(`Not published: ${error.message}`); else { setMessage("Announcement persisted and delivery work queued."); setTitle(""); setBody(""); }
  }

  async function advance(report: Report) {
    const next: Record<string, string> = { submitted: "acknowledged", acknowledged: "in_progress", assigned: "in_progress", in_progress: "resolved" };
    if (!next[report.status]) return;
    const { error } = await getSupabase().rpc("transition_report", { p_report_id: report.id, p_status: next[report.status], p_assignee_id: null, p_note: "Updated from Sidequest Admin" });
    if (error) setMessage(error.message); else { setMessage("Report status persisted and the student was notified."); await load(); }
  }

  return <section className="ops-grid">
    <article className="ops-card"><div className="ops-heading"><div><p className="ops-kicker">Attendance</p><h2>Occupancy</h2></div><button className="secondary" onClick={() => void load()}>Refresh</button></div>
      {occupancy.length === 0 ? <p className="helper">No attendance transitions recorded.</p> : occupancy.map((item) => <div className="metric" key={item.edition_id}><strong>{item.estimated_inside}</strong><span>estimated inside<br />{item.freshness_at ? `Updated ${new Date(item.freshness_at).toLocaleString("en-IN")}` : "No scans yet"}</span></div>)}
    </article>
    <article className="ops-card"><p className="ops-kicker">Official updates</p><h2>Publish announcement</h2><form onSubmit={announce} className="ops-form"><label className="field">Edition<select required value={editionId} onChange={(e) => setEditionId(e.target.value)}>{editions.map((edition) => <option key={edition.id} value={edition.id}>{edition.label} · {new Date(edition.starts_at).toLocaleDateString("en-IN")}</option>)}</select></label><label className="field">Title<input required minLength={2} value={title} onChange={(e) => setTitle(e.target.value)} /></label><label className="field">Message<textarea required minLength={2} value={body} onChange={(e) => setBody(e.target.value)} /></label><button disabled={!editionId}>Publish and notify</button></form></article>
    <article className="ops-card ops-wide"><p className="ops-kicker">Assigned queue</p><h2>Reports</h2>{reports.length === 0 ? <p className="helper">No submitted reports.</p> : reports.map((report) => <div className="report-row" key={report.id}><div><strong>{report.category}</strong><p>{report.description}</p><small>{report.priority} · {report.status.replaceAll("_", " ")}</small></div>{report.status !== "resolved" && <button onClick={() => void advance(report)}>Advance status</button>}</div>)}{message && <p role="status" className={message.startsWith("Not") ? "error-text" : "success-text"}>{message}</p>}</article>
  </section>;
}
