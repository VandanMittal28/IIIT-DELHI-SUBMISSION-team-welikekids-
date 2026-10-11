"use client";

import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import type { Map as LeafletMap, Marker } from "leaflet";
import { getSupabase } from "@/lib/supabase";

type Campus = { id: string; college_id: string; name: string; latitude: number; longitude: number };
type Landmark = { id: string; campus_id: string; name: string; latitude: number | null; longitude: number | null };

export function CampusEditor({ collegeIds }: { collegeIds: string[] }) {
  const mapElement = useRef<HTMLDivElement>(null); const map = useRef<LeafletMap | null>(null); const marker = useRef<Marker | null>(null);
  const initialCoordinate = useRef({ latitude: 28.545, longitude: 77.273 });
  const [campuses, setCampuses] = useState<Campus[]>([]); const [landmarks, setLandmarks] = useState<Landmark[]>([]);
  const [collegeId, setCollegeId] = useState(collegeIds[0] ?? ""); const [campusId, setCampusId] = useState("");
  const [name, setName] = useState(""); const [latitude, setLatitude] = useState(28.545); const [longitude, setLongitude] = useState(77.273);
  const [landmarkName, setLandmarkName] = useState(""); const [facing, setFacing] = useState(""); const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(async () => {
    const supabase = getSupabase();
    const [campusResult, landmarkResult] = await Promise.all([
      collegeIds.length ? supabase.from("campuses").select("id,college_id,name,latitude,longitude").in("college_id", collegeIds).order("name") : Promise.resolve({ data: [], error: null }),
      supabase.from("landmarks").select("id,campus_id,name,latitude,longitude").eq("is_active", true).order("name"),
    ]);
    if (campusResult.error || landmarkResult.error) setMessage(campusResult.error?.message ?? landmarkResult.error?.message ?? "Could not load map data.");
    else { const rows = campusResult.data as Campus[]; setCampuses(rows); setLandmarks(landmarkResult.data as Landmark[]); setCampusId((current) => current || rows[0]?.id || ""); }
  }, [collegeIds]);
  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer); }, [load]);
  useEffect(() => {
    let cancelled = false;
    void import("leaflet").then((L) => {
      if (cancelled || !mapElement.current || map.current) return;
      const created = L.map(mapElement.current).setView([initialCoordinate.current.latitude, initialCoordinate.current.longitude], 16); map.current = created;
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "© OpenStreetMap contributors", maxZoom: 20 }).addTo(created);
      marker.current = L.marker([initialCoordinate.current.latitude, initialCoordinate.current.longitude]).addTo(created);
      created.on("click", (event: L.LeafletMouseEvent) => { setLatitude(event.latlng.lat); setLongitude(event.latlng.lng); marker.current?.setLatLng(event.latlng); });
    });
    return () => { cancelled = true; map.current?.remove(); map.current = null; };
  }, []);
  useEffect(() => { marker.current?.setLatLng([latitude, longitude]); map.current?.panTo([latitude, longitude]); }, [latitude, longitude]);

  async function createCampus(event: FormEvent) {
    event.preventDefault(); setMessage(null);
    const { error } = await getSupabase().rpc("create_campus", { p_college_id: collegeId, p_name: name, p_latitude: latitude, p_longitude: longitude });
    if (error) setMessage(error.message); else { setMessage("Campus persisted."); setName(""); await load(); }
  }
  async function createLandmark(event: FormEvent) {
    event.preventDefault(); setMessage(null);
    const { error } = await getSupabase().rpc("create_landmark", { p_campus_id: campusId, p_name: landmarkName, p_coordinate_kind: "outdoor_geographic", p_latitude: latitude, p_longitude: longitude, p_floor_id: null, p_x_pixels: null, p_y_pixels: null, p_facing_degrees: null, p_facing_instruction: facing, p_reference_photo_path: null });
    if (error) setMessage(error.message); else { setMessage("Landmark persisted. Add it to a draft route before publishing."); setLandmarkName(""); setFacing(""); await load(); }
  }

  return <section className="ops-card ops-wide"><div className="ops-heading"><div><p className="ops-kicker">Leaflet campus authoring</p><h2>Map real landmarks</h2></div><span className="status-dot">{landmarks.length} landmarks</span></div>
    <div ref={mapElement} className="leaflet-map" aria-label="Campus coordinate editor" />
    <p className="helper">Tap the map to choose a geographic coordinate. Indoor landmarks use floor-plan pixel coordinates and require a published floor transform.</p>
    <div className="authoring-columns"><form onSubmit={createCampus} className="ops-form"><h3>Create campus</h3><label className="field">College ID<select value={collegeId} onChange={(e) => setCollegeId(e.target.value)}>{collegeIds.map((id) => <option key={id}>{id}</option>)}</select></label><label className="field">Campus name<input required minLength={2} value={name} onChange={(e) => setName(e.target.value)} /></label><CoordinateFields latitude={latitude} longitude={longitude} setLatitude={setLatitude} setLongitude={setLongitude} /><button disabled={!collegeId}>Save campus</button></form>
      <form onSubmit={createLandmark} className="ops-form"><h3>Create outdoor landmark</h3><label className="field">Campus<select value={campusId} onChange={(e) => setCampusId(e.target.value)}>{campuses.map((campus) => <option key={campus.id} value={campus.id}>{campus.name}</option>)}</select></label><label className="field">Landmark name<input required minLength={2} value={landmarkName} onChange={(e) => setLandmarkName(e.target.value)} /></label><label className="field">Facing instruction<input value={facing} onChange={(e) => setFacing(e.target.value)} placeholder="Face the library entrance" /></label><button disabled={!campusId}>Save landmark</button></form></div>
    {message && <p role="status" className="success-text">{message}</p>}
  </section>;
}

function CoordinateFields({ latitude, longitude, setLatitude, setLongitude }: { latitude: number; longitude: number; setLatitude(value: number): void; setLongitude(value: number): void }) {
  return <div className="coordinate-row"><label className="field">Latitude<input required type="number" min={-90} max={90} step="any" value={latitude} onChange={(e) => setLatitude(Number(e.target.value))} /></label><label className="field">Longitude<input required type="number" min={-180} max={180} step="any" value={longitude} onChange={(e) => setLongitude(Number(e.target.value))} /></label></div>;
}
