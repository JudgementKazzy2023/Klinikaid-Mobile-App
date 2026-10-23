// REVIEW ONLY. No production SubmissionStore is wired. Do not deploy.
// Same Deno serve + Supabase Auth validation pattern as extract-lab-values.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { corsHeaders, createHandler, SubmissionError } from "./handler.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({
        error_code: "METHOD_NOT_ALLOWED",
        message: "Use POST or OPTIONS.",
      }),
      {
        status: 405,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          Allow: "POST, OPTIONS",
        },
      },
    );
  }
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return new Response(
      JSON.stringify({
        error_code: "SERVER_ERROR",
        message: "Submission service is unavailable.",
      }),
      {
        status: 503,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const auth = createClient(url, anonKey, options);
  const admin = createClient(url, serviceKey, options);
  return await createHandler({
    identity: {
      async authenticate(token) {
        // Remote validation, not locally decoded claims or client metadata.
        const { data, error } = await auth.auth.getUser(token);
        if (error) {
          if (
            error.status === 400 || error.status === 401 || error.status === 403
          ) return null;
          throw new SubmissionError("SERVER_ERROR");
        }
        return data.user
          ? {
            id: data.user.id,
            email_confirmed_at: data.user.email_confirmed_at,
            app_metadata: {
              must_change_password: data.user.app_metadata.must_change_password,
            },
          }
          : null;
      },
      async patientByProfile(userId) {
        const { data, error } = await admin.from("patients")
          .select(
            "id, profile_id, first_name, last_name, date_of_birth, contact_number, address",
          )
          .eq("profile_id", userId).maybeSingle();
        if (error) throw new SubmissionError("SERVER_ERROR");
        return data;
      },
      async profile(userId) {
        const { data, error } = await admin.from("profiles")
          .select("role, is_active, accepted_privacy_at").eq("id", userId)
          .maybeSingle();
        if (error) throw new SubmissionError("SERVER_ERROR");
        return data;
      },
    },
    // Deliberately absent: durable owner-approved retention, duplicate and
    // audit-recovery adapter. Valid requests fail closed with SERVER_ERROR.
  })(req);
}

if (import.meta.main) serve(handler);
