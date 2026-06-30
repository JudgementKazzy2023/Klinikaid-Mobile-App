import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Fallback assessment to return gracefully on Gemini timeout, failure, or configuration error.
const fallbackAssessment = {
  score: 50,
  verdict: "marginal",
  issues: [
    {
      type: "other",
      severity: "low",
      description: "Quality assessment unavailable. Receptionist will review.",
    },
  ],
};

interface Issue {
  type: "blur" | "illegible_text" | "incomplete_info" | "low_text_density" | "other";
  severity: "low" | "medium" | "high";
  description: string;
}

/**
 * Resolves the quality verdict programmatically based on score and issue severity.
 * 
 * Verdict Precedence Rules (worst applicable verdict wins):
 * 1. poor: If score < 50 OR any issue has severity === "high"
 * 2. marginal: If the poor condition is false AND (score < 80 OR any issue has severity === "medium")
 * 3. good: If all the above conditions are false (score >= 80 AND no high or medium severity issues)
 */
function resolveVerdict(score: number, issues: Issue[]): "good" | "marginal" | "poor" {
  if (score < 50 || issues.some((i) => i.severity === "high")) {
    return "poor";
  }
  if (score < 80 || issues.some((i) => i.severity === "medium")) {
    return "marginal";
  }
  return "good";
}

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. JWT Authentication Guard
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.warn("Authorization header missing.");
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !geminiApiKey) {
      console.error("Server environment variables are missing configuration.");
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
      console.warn(`User token verification failed: ${authError?.message || "unauthorized"}`);
      return new Response(
        JSON.stringify({ error: "Invalid user token: " + (authError?.message || "unauthorized") }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Parse request payload
    let body;
    try {
      body = await req.json();
    } catch (_e) {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body request." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { ocr_text, patient_name } = body;
    if (ocr_text === undefined || ocr_text === null) {
      return new Response(
        JSON.stringify({ error: "ocr_text is a required field." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const pName = patient_name || "Unknown Patient";

    // 3. Setup Gemini API prompt and system instructions
    const systemInstruction = 
      "You are a document quality assessor for a medical clinic intake system. " +
      "A patient submitted a document via their mobile app. The extracted OCR text is provided by the user. " +
      "Assess the quality of the document's capture (NOT the document content itself).\n\n" +
      "Focus on:\n" +
      "- Is the OCR text complete and coherent, or does it appear truncated, missing information, or fragmented?\n" +
      "- Are there signs the image was blurry, glared, or cropped (e.g., partial words, garbled characters, very low text count/density)?\n" +
      "- Is the text legible enough for a clinic receptionist to read and process?\n\n" +
      "Do NOT:\n" +
      "- Judge whether the document is a medical referral, lab result, ID, or another type.\n" +
      "- Judge whether dates are recent, old, or expired.\n" +
      "- Judge whether required fields are present (this is the receptionist's job).\n" +
      "- Refuse to assess if the document type is unusual.\n\n" +
      "Descriptions should be short patient-facing strings, max ~15 words each, written in the second person (e.g., 'Your document...');";

    const promptText = 
      `Expected patient name (for context only; do NOT use as a rejection criterion): ${pName}\n\n` +
      `OCR text to assess:\n` +
      `---\n` +
      `${ocr_text}\n` +
      `---`;

    // Setup 10-second timeout using AbortController
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    try {
      // Call Gemini API using gemini-2.5-flash with structured JSON response schema
      const geminiResponse = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiApiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          signal: controller.signal,
          body: JSON.stringify({
            contents: [
              {
                role: "user",
                parts: [{ text: promptText }]
              }
            ],
            systemInstruction: {
              parts: [{ text: systemInstruction }]
            },
            generationConfig: {
              responseMimeType: "application/json",
              responseSchema: {
                type: "OBJECT",
                properties: {
                  score: {
                    type: "INTEGER",
                    description: "An overall capture quality/legibility score from 0 to 100."
                  },
                  issues: {
                    type: "ARRAY",
                    description: "List of visual/capture quality issues detected in the document text.",
                    items: {
                      type: "OBJECT",
                      properties: {
                        type: {
                          type: "STRING",
                          enum: ["blur", "illegible_text", "incomplete_info", "low_text_density", "other"]
                        },
                        severity: {
                          type: "STRING",
                          enum: ["low", "medium", "high"]
                        },
                        description: {
                          type: "STRING",
                          description: "Short patient-facing string explaining the issue (max ~15 words, e.g. 'Your document...')"
                        }
                      },
                      required: ["type", "severity", "description"]
                    }
                  }
                },
                required: ["score", "issues"]
              }
            }
          })
        }
      );

      clearTimeout(timeoutId);

      if (!geminiResponse.ok) {
        const errorText = await geminiResponse.text();
        console.error(`Gemini API call failed with status ${geminiResponse.status}: ${errorText}`);
        return new Response(
          JSON.stringify(fallbackAssessment),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const geminiJson = await geminiResponse.json();
      const textContent = geminiJson.candidates?.[0]?.content?.parts?.[0]?.text;
      
      if (!textContent) {
        console.error("Gemini API response did not contain candidates or text parts.");
        return new Response(
          JSON.stringify(fallbackAssessment),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Parse JSON payload returned from Gemini
      const assessmentResult = JSON.parse(textContent);
      
      let score = typeof assessmentResult.score === "number" ? assessmentResult.score : 50;
      score = Math.max(0, Math.min(100, Math.round(score)));
      
      const rawIssues = Array.isArray(assessmentResult.issues) ? assessmentResult.issues : [];
      const issues: Issue[] = rawIssues.map((issue: any) => ({
        type: ["blur", "illegible_text", "incomplete_info", "low_text_density", "other"].includes(issue.type)
          ? issue.type
          : "other",
        severity: ["low", "medium", "high"].includes(issue.severity)
          ? issue.severity
          : "low",
        description: typeof issue.description === "string" ? issue.description.substring(0, 150) : "Your document contains a minor quality issue.",
      }));

      // Programmatic verdict mapping
      const verdict = resolveVerdict(score, issues);

      return new Response(
        JSON.stringify({
          score,
          verdict,
          issues,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );

    } catch (e: any) {
      clearTimeout(timeoutId);
      if (e.name === "AbortError") {
        console.error("Gemini API call timed out (> 10s). Returning fallback assessment.");
      } else {
        console.error(`Gemini API call exception: ${e.message || e}`);
      }
      return new Response(
        JSON.stringify(fallbackAssessment),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

  } catch (err: any) {
    console.error(`Internal Edge Function handler exception: ${err.message || err}`);
    return new Response(
      JSON.stringify(fallbackAssessment),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
