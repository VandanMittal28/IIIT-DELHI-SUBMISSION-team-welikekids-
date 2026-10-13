import { createClient } from "npm:@supabase/supabase-js@2.117.3";

type ProfileType = "student" | "college_admin" | "organizer";

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
  let input: { college_id?: string; organization_id?: string; username?: string; password?: string; full_name?: string; profile_type?: ProfileType };
  try { input = await request.json(); } catch { return json({ error: "INVALID_JSON" }, 400); }
  const collegeId = input.college_id?.trim();
  const organizationId = input.organization_id?.trim();
  const username = input.username?.trim().toLowerCase().replace(/\s+/g, "");
  const fullName = input.full_name?.trim();
  const profileType = input.profile_type;
  if (!collegeId || !username || !fullName || !input.password || !profileType || !["student", "college_admin", "organizer"].includes(profileType) || (profileType === "organizer" && !organizationId)) {
    return json({ error: "INVALID_INPUT", message: "College, username, full name, profile type and password are required." }, 422);
  }
  if (!/^[a-z0-9._-]{3,64}$/.test(username) || input.password.length < 8 || fullName.length < 2) {
    return json({ error: "INVALID_INPUT", message: "Use a simple username and a password of at least 8 characters." }, 422);
  }
  const { data: adminMembership, error: membershipError } = await adminClient
    .from("college_memberships").select("college_id").eq("college_id", collegeId).eq("user_id", actorId).eq("is_admin", true).eq("status", "active").maybeSingle();
  if (membershipError) return json({ error: membershipError.message }, 500);
  if (!adminMembership) return json({ error: "FORBIDDEN", message: "Only an active college administrator can create profiles." }, 403);
  if (profileType === "organizer") {
    const { data: organization, error: organizationError } = await adminClient.from("organizations").select("id").eq("id", organizationId!).eq("college_id", collegeId).eq("is_active", true).maybeSingle();
    if (organizationError) return json({ error: organizationError.message }, 500);
    if (!organization) return json({ error: "INVALID_ORGANIZATION", message: "Choose an active organization in this college." }, 422);
  }

  const email = `${username}@sidequest.local`;
  const { data: created, error: createError } = await adminClient.auth.admin.createUser({ email, password: input.password, email_confirm: true, user_metadata: { full_name: fullName } });
  if (createError || !created.user) return json({ error: createError?.message ?? "USER_CREATE_FAILED" }, createError?.status ?? 500);
  const userId = created.user.id;
  const { error: profileError } = await adminClient.from("profiles").upsert({ id: userId, college_id: collegeId, full_name: fullName, status: "active" });
  if (profileError) { await adminClient.auth.admin.deleteUser(userId); return json({ error: profileError.message }, 500); }
  const { error: collegeError } = await adminClient.from("college_memberships").upsert({ college_id: collegeId, user_id: userId, is_admin: profileType === "college_admin", status: "active", invited_by: actorId }, { onConflict: "college_id,user_id" });
  if (collegeError) { await adminClient.auth.admin.deleteUser(userId); return json({ error: collegeError.message }, 500); }
  if (profileType === "organizer") {
    const { error: organizationMembershipError } = await adminClient.from("memberships").insert({ organization_id: organizationId, user_id: userId, role: "organizer", status: "active", invited_by: actorId });
    if (organizationMembershipError) { await adminClient.auth.admin.deleteUser(userId); return json({ error: organizationMembershipError.message }, 500); }
  }
  return json({ user_id: userId, username, profile_type: profileType, college_id: collegeId });
});
