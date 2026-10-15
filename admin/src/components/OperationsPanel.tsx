"use client";

import { useCallback, useEffect, useState } from "react";
import Image from "next/image";
import { getSupabase } from "@/lib/supabase";

type Report = { id: string; edition_id: string; category: string; description: string; priority: string; status: string; created_at: string; photos: { url: string; name: string }[]; attachmentCount: number };

/** Volunteer scanning plus the organizer's scoped report queue. */
export function OperationsPanel({ eventIds }: { eventIds: string[] }) {
  const [reports, setReports] = useState<Report[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const loadReports = useCallback(async () => {
    if (!eventIds.length) { setReports([]); return; }
    const supabase = getSupabase();
    const { data: editions, error: editionError } = await supabase.from("event_editions").select("id").in("event_id", eventIds);
    if (editionError) { setMessage(editionError.message); return; }
    const ids = (editions ?? []).map(row => row.id);
    if (!ids.length) { setReports([]); return; }
    const { data, error } = await supabase.from("reports").select("id,edition_id,category,description,priority,status,created_at").in("edition_id", ids).order("created_at", { ascending: false });
    if (error) { setMessage(error.message); return; }
    const rows = data ?? [];
    if (!rows.length) { setReports([]); setMessage(null); return; }
    const { data: attachments, error: attachmentError } = await supabase.from("report_attachments")
      .select("report_id,storage_path").in("report_id", rows.map(row => row.id));
    if (attachmentError) { setMessage(attachmentError.message); return; }
    const signed = await Promise.all((attachments ?? []).map(async attachment => {
      const { data: link, error: linkError } = await supabase.storage.from("report-attachments")
        .createSignedUrl(attachment.storage_path, 3600);
      return { reportId: attachment.report_id, name: attachment.storage_path.split("/").pop() ?? "Report photo", url: linkError ? null : link?.signedUrl ?? null };
    }));
    setReports(rows.map(row => ({ ...row, attachmentCount: signed.filter(item => item.reportId === row.id).length,
      photos: signed.filter(item => item.reportId === row.id && item.url).map(item => ({ url: item.url!, name: item.name })) })));
    setMessage(signed.some(item => !item.url) ? "Some report photos could not be opened. Refresh or check photo access." : null);
  }, [eventIds]);
  useEffect(() => { const timer = window.setTimeout(() => { void loadReports(); }, 0); return () => window.clearTimeout(timer); }, [loadReports]);
  async function acknowledge(report: Report) {
    const { error } = await getSupabase().rpc("transition_report", { p_report_id: report.id, p_status: "acknowledged", p_assignee_id: null, p_note: "Acknowledged by IIIT Delhi organizer" });
    if (error) setMessage(error.message); else { setMessage("Report acknowledged and saved."); await loadReports(); }
  }
  return <section className="ops-card ops-wide">
    <div className="ops-heading"><div><p className="ops-kicker">IIIT Delhi organizer desk</p><h2>Volunteer response and reports</h2></div><span className="status-dot">Scoped to your events</span></div>
    <p className="helper">Pass scanning and reports are limited to events this organizer manages. Every report status change is saved by the backend.</p>
    <div className="metric"><strong>{eventIds.length}</strong><span>managed event{eventIds.length === 1 ? "" : "s"}</span></div>
    <h3>Student reports</h3>
    {reports.length === 0 ? <p className="helper">No reports for your events.</p> : reports.map(report => <div className="report-row" key={report.id}><div><strong>{report.category}</strong><p>{report.description}</p><small><span className="cap">{report.priority} · {report.status.replaceAll("_", " ")}</span> · {new Date(report.created_at).toLocaleString("en-IN")}</small>{report.photos.length > 0 && <div className="report-photos">{report.photos.map(photo => <a key={photo.url} href={photo.url} target="_blank" rel="noreferrer">{/\.(jpe?g|png|webp)$/i.test(photo.name) && <Image unoptimized width={150} height={110} src={photo.url} alt={`Evidence for ${report.category}`} />}<span>Open evidence</span></a>)}</div>}{report.attachmentCount > report.photos.length && <small>Some attachments are unavailable.</small>}</div>{report.status === "submitted" && <button onClick={() => void acknowledge(report)}>Acknowledge</button>}</div>)}
    {message && <p role="status" className={message.includes("saved") ? "success-text" : "error-text"}>{message}</p>}
  </section>;
}
