import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import {
  createCreatePatientRecordHandler,
  jsonResponse,
  type ServiceClient,
  type UserClient,
} from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !anonKey || !serviceRoleKey) {
  console.error("Missing critical Supabase environment keys.");
  serve(() =>
    jsonResponse(
      { error: "server_configuration_error", message: "Server configuration missing critical keys." },
      500,
    )
  );
} else {
  const serviceClient = createClient(supabaseUrl, serviceRoleKey) as unknown as ServiceClient;

  serve(
    createCreatePatientRecordHandler({
      createUserClient: (authHeader: string) =>
        createClient(supabaseUrl, anonKey, {
          global: { headers: { Authorization: authHeader } },
        }) as unknown as UserClient,
      serviceClient,
    }),
  );
}
