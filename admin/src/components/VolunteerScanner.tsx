"use client";

import { useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";

type ScanAction = "enter" | "exit" | "reenter";
type ScannerProps = { onRecorded?: () => void };

export function VolunteerScanner({ onRecorded }: ScannerProps) {
  const video = useRef<HTMLVideoElement>(null);
  const stream = useRef<MediaStream | null>(null);
  const requestIds = useRef(new Map<string, string>());
  const [token, setToken] = useState("");
  const [action, setAction] = useState<ScanAction>("enter");
  const [cameraMessage, setCameraMessage] = useState("Camera is off. Manual opaque-token entry remains available.");
  const [result, setResult] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => () => stream.current?.getTracks().forEach((track) => track.stop()), []);

  async function startCamera() {
    setResult(null);
    try {
      stream.current = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false });
      if (video.current) { video.current.srcObject = stream.current; await video.current.play(); }
      setCameraMessage("Camera active. Align a Sidequest event-pass QR inside the frame.");
      const Detector = (window as unknown as { BarcodeDetector?: new (options: { formats: string[] }) => { detect(source: CanvasImageSource): Promise<Array<{ rawValue: string }>> } }).BarcodeDetector;
      if (!Detector) { setCameraMessage("This browser cannot decode QR codes. Use the manual token field below."); return; }
      const detector = new Detector({ formats: ["qr_code"] });
      const poll = async () => {
        if (!video.current || !stream.current?.active) return;
        try { const codes = await detector.detect(video.current); if (codes[0]?.rawValue) { setToken(codes[0].rawValue); stopCamera(); return; } } catch { /* a frame can fail while the camera warms up */ }
        requestAnimationFrame(poll);
      };
      requestAnimationFrame(poll);
    } catch (error) {
      setCameraMessage(error instanceof Error ? `Camera unavailable: ${error.message}. Use manual token entry.` : "Camera permission was denied. Use manual token entry.");
    }
  }

  function stopCamera() {
    stream.current?.getTracks().forEach((track) => track.stop()); stream.current = null;
    setCameraMessage("Camera stopped.");
  }

  async function record() {
    const normalized = token.trim().toLowerCase();
    if (!normalized) return;
    setBusy(true); setResult(null);
    const key = `${normalized}:${action}`;
    const requestId = requestIds.current.get(key) ?? crypto.randomUUID();
    requestIds.current.set(key, requestId);
    const { data, error } = await getSupabase().rpc("record_attendance", {
      p_pass_token: normalized, p_action: action, p_client_request_id: requestId,
    });
    if (error) setResult(`Not recorded: ${error.message}`);
    else {
      requestIds.current.delete(key);
      const response = data as { estimated_inside?: number; idempotent_replay?: boolean };
      setResult(`${response.idempotent_replay ? "Already confirmed" : "Recorded"}. Estimated inside: ${response.estimated_inside ?? 0}.`);
      setToken(""); onRecorded?.();
    }
    setBusy(false);
  }

  return <section className="ops-card">
    <div className="ops-heading"><div><p className="ops-kicker">Volunteer mode</p><h2>Scan event pass</h2></div><span className="status-dot">Live backend</span></div>
    <video ref={video} muted playsInline className="scanner-video" />
    <p className="helper">{cameraMessage}</p>
    <div className="button-row"><button type="button" onClick={() => void startCamera()}>Start camera</button><button type="button" className="secondary" onClick={stopCamera}>Stop</button></div>
    <label className="field">Opaque pass token<input value={token} onChange={(event) => setToken(event.target.value)} placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" /></label>
    <label className="field">Attendance action<select value={action} onChange={(event) => setAction(event.target.value as ScanAction)}><option value="enter">Entry</option><option value="exit">Exit</option><option value="reenter">Re-entry</option></select></label>
    <button type="button" disabled={busy || !token.trim()} onClick={() => void record()}>{busy ? "Validating…" : "Validate and record"}</button>
    {result && <p role="status" className={result.startsWith("Not") ? "error-text" : "success-text"}>{result}</p>}
    <p className="helper">No offline scan is shown as admitted. Duplicate requests reuse the same backend operation ID.</p>
  </section>;
}
