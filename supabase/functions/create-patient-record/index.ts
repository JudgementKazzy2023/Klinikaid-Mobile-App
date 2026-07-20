import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const requiredFields = [
  "first_name",
  "last_name",
  "date_of_birth",
  "gender",
  "contact_number",
  "address",
];

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function readRequiredString(body: Record<string, unknown>, field: string): string | null {
  const value = body[field];
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }
  return value.trim();
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed", message: "Method not allowed." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("Missing critical Supabase environment keys.");
    return jsonResponse(
      { error: "server_configuration_error", message: "Server configuration missing critical keys." },
      500,
    );
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "unauthorized", message: "Missing Authorization header." }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return jsonResponse(
      { error: "unauthorized", message: authError?.message ?? "Invalid user token." },
      401,
    );
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ error: "bad_request", message: "Invalid JSON body request." }, 400);
  }

  const missing = requiredFields.filter((field) => readRequiredString(body, field) == null);
  if (missing.length > 0) {
    return jsonResponse(
      { error: "bad_request", message: `Missing required field(s): ${missing.join(", ")}` },
      400,
    );
  }

  const dateOfBirth = readRequiredString(body, "date_of_birth")!;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateOfBirth)) {
    return jsonResponse(
      { error: "bad_request", message: "date_of_birth must be in YYYY-MM-DD format." },
      400,
    );
  }

  const gender = readRequiredString(body, "gender")!;
  if (!["male", "female", "other"].includes(gender)) {
    return jsonResponse(
      { error: "bad_request", message: "gender must be male, female, or other." },
      400,
    );
  }

  const emailValue = body["email"];
  const email = typeof emailValue === "string" && emailValue.trim().length > 0
    ? emailValue.trim()
    : user.email ?? null;

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: patient, error: insertError } = await serviceClient
    .from("patients")
    .insert({
      profile_id: user.id,
      first_name: readRequiredString(body, "first_name"),
      last_name: readRequiredString(body, "last_name"),
      date_of_birth: dateOfBirth,
      gender,
      contact_number: readRequiredString(body, "contact_number"),
      email,
      address: readRequiredString(body, "address"),
    })
    .select()
    .single();

  if (insertError) {
    console.error(`Patient insert failed for ${user.id}: ${insertError.message}`);
    const { error: deleteError } = await serviceClient.auth.admin.deleteUser(user.id);
    if (deleteError) {
      console.error(`Failed to delete auth user ${user.id}: ${deleteError.message}`);
      return jsonResponse(
        {
          error: "cleanup_failed",
          message: `Patient provisioning failed and cleanup failed: ${deleteError.message}`,
        },
        500,
      );
    }

    return jsonResponse(
      { error: "patient_insert_failed", message: `Patient provisioning failed: ${insertError.message}` },
      500,
    );
  }

  return jsonResponse({ success: true, patient }, 200);
});
