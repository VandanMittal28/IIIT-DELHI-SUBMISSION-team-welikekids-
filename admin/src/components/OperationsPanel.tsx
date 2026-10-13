"use client";

import { useState } from "react";

/** The operations page intentionally stays focused on the volunteer response desk. */
export function OperationsPanel({ eventIds }: { eventIds: string[] }) {
  const [notice, setNotice] = useState<string | null>(null);
  return <section className="ops-card ops-wide">
    <div className="ops-heading"><div><p className="ops-kicker">IIIT Delhi volunteer desk</p><h2>Volunteer response</h2></div><span className="status-dot">Ready</span></div>
    <p className="helper">Use the scanner beside this card to validate an event pass. Attendance, announcements, reports and moderation are intentionally kept out of this focused view.</p>
    <div className="metric"><strong>{eventIds.length}</strong><span>event{eventIds.length === 1 ? "" : "s"} available for this admin account<br />Choose an event in the assignment panel below.</span></div>
    <button className="secondary" onClick={() => setNotice("All pass scans are verified by the Sidequest backend before attendance changes.")}>How scanning works</button>
    {notice && <p role="status" className="success-text">{notice}</p>}
  </section>;
}
