import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !geminiApiKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration missing critical environment keys." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase Client with the user's authenticated JWT context (security boundary constraint #9)
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Verify user identity using the JWT
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid user token: " + (authError?.message || "unauthorized") }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const { message, session_id } = body;

    if (!message || typeof message !== "string" || !session_id || typeof session_id !== "string") {
      return new Response(
        JSON.stringify({ error: "Message and session_id are required fields." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Enforce rate limit (20 requests/hour, keyed on user.id)
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count, error: countError } = await supabaseClient
      .from("chatbot_logs")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", oneHourAgo);

    if (countError) {
      console.error(`Rate limit check failed: ${countError.message}`);
    } else if (count !== null && count >= 20) {
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded. You can only send 20 messages per hour." }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Generate 768-dim Embedding using gemini-embedding-001 (Gap 5a)
    const embedResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${geminiApiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "models/gemini-embedding-001",
          content: {
            parts: [{ text: message }]
          },
          output_dimensionality: 768
        })
      }
    );

    if (!embedResponse.ok) {
      const err = await embedResponse.text();
      throw new Error(`Gemini Embedding API failed: ${err}`);
    }

    const embedJson = await embedResponse.json();
    const rawEmbedding = embedJson.embedding?.values;
    if (!rawEmbedding || rawEmbedding.length !== 768) {
      throw new Error(`Expected a 768-dimensional embedding, but received ${rawEmbedding?.length || 0}`);
    }

    // L2 Normalize embedding for cosine calculation safety
    const magnitude = Math.sqrt(rawEmbedding.reduce((sum: number, val: number) => sum + val * val, 0));
    const embedding = rawEmbedding.map((val: number) => val / (magnitude || 1));

    // 2. Query Postgres RPC to get matching documents
    const { data: matchedDocs, error: rpcError } = await supabaseClient.rpc(
      "match_documents",
      {
        query_embedding: embedding,
        match_threshold: 0.6,
        match_count: 5
      }
    );

    if (rpcError) {
      throw new Error(`RPC database vector query failed: ${rpcError.message}`);
    }

    // 3. Format Context
    let contextText = "";
    if (matchedDocs && matchedDocs.length > 0) {
      contextText = matchedDocs
        .map((doc: any) => `Source: ${doc.title}\nContent: ${doc.content}`)
        .join("\n\n");
    } else {
      contextText = "No relevant clinic documentation found.";
    }

    // 4. Verbatim system prompt (Gap 1)
    const systemPrompt = `You are the KlinikAid clinic assistant representing Bloodcare Medical Laboratory (Burgos, Rodriguez, Rizal, PH).
Your primary task is to answer patient inquiries based ONLY on the provided clinic context.

CRITICAL SAFETY RULES:
1. Under no circumstances are you to provide a medical diagnosis, suggest treatments, prescribe medication, analyze test results, or interpret clinical values. If a patient asks a medical or clinical question (e.g. interpreting lab results, symptoms, or treatment options), you must respond EXACTLY with:
   "I cannot provide medical advice or interpret laboratory results. Please consult a doctor or speak with our clinic staff."
2. You must only answer questions using the information provided in the "Clinic Context" below. Do not assume, extrapolate, or use outside knowledge.
3. If the answer to the user's question cannot be found in the provided context, you must respond EXACTLY with:
   "I am sorry, but I do not have information about that. Please contact Bloodcare Medical Laboratory directly."

Clinic Context:
${contextText}`;

    // 5. Generate content using gemini-2.5-flash
    const chatResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiApiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [{ text: message }]
            }
          ],
          systemInstruction: {
            parts: [{ text: systemPrompt }]
          }
        })
      }
    );

    if (!chatResponse.ok) {
      const err = await chatResponse.text();
      throw new Error(`Gemini Text Generation API failed: ${err}`);
    }

    const chatJson = await chatResponse.json();
    const botResponse = chatJson.candidates?.[0]?.content?.parts?.[0]?.text || "No response generated.";
    const tokensUsed = chatJson.usageMetadata?.totalTokenCount || 0;

    // 6. Log transaction to chatbot_logs using the user's authenticated supabaseClient (Gap 4)
    const { data: logRow, error: logError } = await supabaseClient
      .from("chatbot_logs")
      .insert({
        user_id: user.id,
        session_id: session_id || "default_session",
        user_message: message,
        bot_response: botResponse,
        tokens_used: tokensUsed
      })
      .select()
      .single();

    if (logError) {
      console.error(`Failed to record chatbot interaction to database logs: ${logError.message}`);
    }

    // Return answer JSON payload
    return new Response(
      JSON.stringify({
        response: botResponse,
        log_id: logRow?.id
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );

  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message || "An internal error occurred." }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );
  }
});
