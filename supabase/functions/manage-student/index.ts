// Money Moves NYC — facilitator actions that need admin rights.
//   POST { action: "reset_pin", student_id, new_pin }  → sets a new 6-digit PIN
//   POST { action: "remove",    student_id }           → deletes the student's login and all their data
// The caller must be signed in as the facilitator who runs that student's class.
// Deploy: supabase functions deploy manage-student   (see README)
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // Who is calling?
  const asCaller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: userErr } = await asCaller.auth.getUser();
  if (userErr || !user) return json({ error: "not_signed_in" }, 401);

  let body: { action?: string; student_id?: string; new_pin?: string };
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const { action, student_id, new_pin } = body;
  if (!student_id || !/^[0-9a-f-]{36}$/i.test(student_id)) return json({ error: "bad_student" }, 400);

  // Is the caller the facilitator of this student's class?
  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data: row, error: rowErr } = await admin
    .from("students")
    .select("user_id, classes!inner(facilitator_id)")
    .eq("user_id", student_id)
    .maybeSingle();
  // deno-lint-ignore no-explicit-any
  const facilitatorId = (row as any)?.classes?.facilitator_id;
  if (rowErr || !row || facilitatorId !== user.id) return json({ error: "not_allowed" }, 403);

  if (action === "reset_pin") {
    if (!new_pin || !/^\d{6}$/.test(new_pin)) return json({ error: "pin_must_be_6_digits" }, 400);
    const { error } = await admin.auth.admin.updateUserById(student_id, { password: new_pin });
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true });
  }
  if (action === "remove") {
    const { error } = await admin.auth.admin.deleteUser(student_id);
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true });
  }
  return json({ error: "unknown_action" }, 400);
});
