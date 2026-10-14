import { createClient } from "npm:@supabase/supabase-js@2.117.3";

type ProfileType = "student" | "organizer";

function json(body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  if (!token || !serviceKey || !url) return json({ error: "NOT_CONFIGURED" }, 503);
  const adminClient = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await adminClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "UNAUTHENTICATED" }, 401);
  const actorId = authData.user.id;
  let input: { college_id?: string; username?: string; password?: string; full_name?: string; profile_type?: ProfileType };
  try { input = await request.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }
  const collegeId = input.college_id?.trim();
  const username = input.username?.trim().toLowerCase().replace(/\s+/g, "");
  const fullName = input.full_name?.trim();
  const profileType = input.profile_type;
  if (!collegeId || !username || !fullName || !input.password || !profileType || !["student", "organizer"].includes(profileType)) {
    return json({ error: "INVALID_INPUT", message: "College, username, full name, profile type and password are required." }, 422);
  }
  if (!/^[a-z0-9._-]{3,64}$/.test(username) || input.password.length < 8 || fullName.length < 2) {
    return json({ error: "INVALID_INPUT", message: "Use a simple username and a password of at least 8 characters." }, 422);
  }
  const [{ data: platformAdmin, error: platformError }, { data: collegeAdmin, error: collegeError }] = await Promise.all([
    adminClient.from("platform_admins").select("user_id").eq("user_id", actorId).maybeSingle(),
    adminClient.from("college_memberships").select("college_id").eq("college_id", collegeId).eq("user_id", actorId).eq("is_admin", true).eq("status", "active").maybeSingle(),
  ]);
  if (platformError || collegeError) return json({ error: platformError?.message ?? collegeError?.message }, 500);
  if (!platformAdmin && !collegeAdmin) return json({ error: "FORBIDDEN", message: "Sidequest platform administrator access or active administrator access for this college is required." }, 403);
  const email = `${username}@sidequest.local`;
  const { data: created, error: createError } = await adminClient.auth.admin.createUser({ email, password: input.password, email_confirm: true, user_metadata: { full_name: fullName } });
  if (createError || !created.user) return json({ error: createError?.message ?? "USER_CREATE_FAILED" }, createError?.status ?? 500);
  const userId = created.user.id;
  const { error: profileError } = await adminClient.from("profiles").upsert({ id: userId, college_id: collegeId, full_name: fullName, status: "active", account_type: profileType, login_username: username });
  if (profileError) { await adminClient.auth.admin.deleteUser(userId); return json({ error: profileError.message }, 500); }
  const { error: newCollegeError } = await adminClient.from("college_memberships").upsert({ college_id: collegeId, user_id: userId, is_admin: false, status: "active", invited_by: actorId }, { onConflict: "college_id,user_id" });
  if (newCollegeError) { await adminClient.auth.admin.deleteUser(userId); return json({ error: newCollegeError.message }, 500); }
  return json({ user_id: userId, username, profile_type: profileType, college_id: collegeId, society_head_assigned: false, provisioned_by_platform_admin: Boolean(platformAdmin) });
});
