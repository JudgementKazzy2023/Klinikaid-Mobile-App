import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const model = "gemini-2.5-flash";

const allowedPanels: Record<string, string[]> = {
  "Complete Blood Count (CBC)": [
    "Hemoglobin",
    "White Blood Cells (WBC)",
    "Platelets",
  ],
  "Fasting Blood Sugar (FBS)": ["Fasting Blood Sugar (FBS)"],
  "Renal Function": ["Creatinine"],
  "Lipid Profile": ["Cholesterol"],
};

const extractionPrompt = `You are extracting numeric laboratory result values from a clinic result sheet.
Return ONLY valid JSON. Do not include markdown, explanations, comments, or extra text.

Allowed panels and parameters:
- Complete Blood Count (CBC): Hemoglobin, White Blood Cells (WBC), Platelets
- Fasting Blood Sugar (FBS): Fasting Blood Sugar (FBS)
- Renal Function: Creatinine
- Lipid Profile: Cholesterol

Task:
1. Identify the most likely panel from the allowed list.
2. Extract only numeric result values for allowed parameters.
3. Preserve decimal points. Do not include units. Do not infer missing values.
4. If a value is unclear, missing, unreadable, or ambiguous, omit that parameter.
5. If no allowed lab values are readable, return {"panel": null, "values": {}}.

Expected JSON shape:
{"panel":"Complete Blood Count (CBC)","values":{"Hemoglobin":"14.2","White Blood Cells (WBC)":"7.1","Platelets":"250"}}`;

const refusalPattern = /\b(i am sorry|i'm sorry|cannot|can't|unable|illegible|unreadable|too blurry|cannot read|can't read)\b/i;
const numericPattern = /^-?\d+(\.\d+)?$/;

type ExtractedPayload = {
  panel: string | null;
  values: Record<string, string>;
};

function jsonResponse(body: object, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function stripMarkdownFences(text: string): string {
  return text
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function sanitizeExtraction(rawText: string): ExtractedPayload {
  if (!rawText || refusalPattern.test(rawText)) {
    return { panel: null, values: {} };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(stripMarkdownFences(rawText));
  } catch (_e) {
    return { panel: null, values: {} };
  }

  if (!parsed || typeof parsed !== "object") {
    return { panel: null, values: {} };
  }

  const raw = parsed as { panel?: unknown; values?: unknown };
  const rawPanel = typeof raw.panel === "string" ? raw.panel : null;
  const panel = rawPanel !== null &&
      Object.prototype.hasOwnProperty.call(allowedPanels, rawPanel)
    ? rawPanel
    : null;

  if (panel === null || !raw.values || typeof raw.values !== "object" || Array.isArray(raw.values)) {
    return { panel, values: {} };
  }

  const panelParameters = new Set(allowedPanels[panel]);
  const values: Record<string, string> = {};

  for (const [key, value] of Object.entries(raw.values as Record<string, unknown>)) {
    if (!panelParameters.has(key)) continue;
    if (typeof value !== "string" && typeof value !== "number") continue;

    const stringValue = String(value).trim();
    if (!numericPattern.test(stringValue)) continue;
    values[key] = stringValue;
  }

  return { panel, values };
}

function readImageInput(body: Record<string, unknown>): { base64: string; mimeType: string } | null {
  const directBase64 = body.image_base64;
  const directMime = body.mime_type;
  if (typeof directBase64 === "string") {
    return {
      base64: directBase64.replace(/^data:[^;]+;base64,/i, "").trim(),
      mimeType: typeof directMime === "string" && directMime.trim().length > 0
        ? directMime.trim()
        : "image/jpeg",
    };
  }

  const image = body.image;
  if (image && typeof image === "object") {
    const imageMap = image as { base64?: unknown; mime_type?: unknown; mimeType?: unknown };
    if (typeof imageMap.base64 === "string") {
      const mime = imageMap.mime_type ?? imageMap.mimeType;
      return {
        base64: imageMap.base64.replace(/^data:[^;]+;base64,/i, "").trim(),
        mimeType: typeof mime === "string" && mime.trim().length > 0 ? mime.trim() : "image/jpeg",
      };
    }
  }

  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "Missing Authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !geminiApiKey) {
      return jsonResponse({ error: "Server configuration missing critical environment keys." }, 500);
    }

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return jsonResponse(
        { error: "Invalid user token: " + (authError?.message || "unauthorized") },
        401,
      );
    }

    const { data: profile, error: profileError } = await supabaseClient
      .from("profiles")
      .select("role, department, is_active")
      .eq("id", user.id)
      .single();

    if (profileError || !profile || profile.is_active === false) {
      return jsonResponse({ error: "Active staff profile required." }, 403);
    }

    const role = profile.role;
    const department = profile.department;
    const canExtract = role === "admin" || (role === "department_staff" && department === "laboratory");
    if (!canExtract) {
      return jsonResponse({ error: "Laboratory department staff access required." }, 403);
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch (_e) {
      return jsonResponse({ error: "Invalid JSON body request." }, 400);
    }

    const imageInput = readImageInput(body);
    if (!imageInput || imageInput.base64.length === 0) {
      return jsonResponse({ error: "image_base64 is required." }, 400);
    }

    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                { text: extractionPrompt },
                {
                  inline_data: {
                    mime_type: imageInput.mimeType,
                    data: imageInput.base64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: "application/json",
          },
        }),
      },
    );

    if (!geminiResponse.ok) {
      const errorText = await geminiResponse.text();
      console.error(`Gemini extraction failed with status ${geminiResponse.status}: ${errorText}`);
      return jsonResponse({
        panel: null,
        values: {},
        tokens_used: 0,
        error: "Lab value extraction unavailable.",
      });
    }

    const geminiJson = await geminiResponse.json();
    const textContent = geminiJson.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    const tokensUsed = geminiJson.usageMetadata?.totalTokenCount ?? 0;
    const sanitized = sanitizeExtraction(textContent);

    const { error: logError } = await supabaseClient
      .from("chatbot_logs")
      .insert({
        user_id: user.id,
        session_id: "department_lab_ocr_extraction",
        user_message: "Department lab OCR extraction",
        bot_response: `Extracted panel: ${sanitized.panel ?? "none"}; values: ${Object.keys(sanitized.values).length}`,
        tokens_used: tokensUsed,
      });

    if (logError) {
      console.error(`Failed to record lab extraction usage: ${logError.message}`);
    }

    return jsonResponse({
      ...sanitized,
      tokens_used: tokensUsed,
    });
  } catch (err: any) {
    console.error(`Lab extraction function error: ${err.message || err}`);
    return jsonResponse({
      panel: null,
      values: {},
      tokens_used: 0,
      error: "Lab value extraction unavailable.",
    });
  }
});
