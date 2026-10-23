import { CLINIC_TEMPLATES } from "./reference/documentTemplates.ts";
import {
  todayInPh,
  validateTemplateSubmission,
} from "./reference/templateChecks.ts";
import { validateAge, validateDobDate } from "./reference/validation.ts";

export const statuses = {
  UNAUTHENTICATED: 401,
  METHOD_NOT_ALLOWED: 405,
  SERVER_DATA_INVALID: 500,
  PATIENT_ACCOUNT_REQUIRED: 403,
  NO_PATIENT_RECORD: 403,
  PROFILE_INACTIVE: 403,
  EMAIL_NOT_CONFIRMED: 403,
  CONSENT_REQUIRED: 403,
  PASSWORD_CHANGE_REQUIRED: 403,
  UNKNOWN_TEMPLATE: 400,
  UNKNOWN_FIELD: 400,
  FIELD_REQUIRED: 400,
  FIELD_INVALID: 400,
  AGE_REQUIREMENT_NOT_MET: 403,
  DUPLICATE_PENDING: 409,
  IDEMPOTENCY_CONFLICT: 409,
  IN_PROGRESS: 409,
  SERVER_ERROR: 503,
} as const;
export type Code = keyof typeof statuses;
export class SubmissionError extends Error {
  constructor(public code: Code, public field?: string) {
    super(code);
  }
}
export type User = {
  id: string;
  email_confirmed_at?: string;
  app_metadata: { must_change_password?: unknown };
};
export type Profile = {
  role: string;
  is_active: boolean;
  accepted_privacy_at: string | null;
};
export type Patient = {
  id: string;
  profile_id: string;
  first_name: string;
  last_name: string;
  date_of_birth: string | null;
  contact_number: string | null;
  address: string | null;
};
export interface Identity {
  // Must validate with Auth.getUser(token), never decode/trust JWT claims alone.
  authenticate(token: string): Promise<User | null>;
  // Errors must throw; absent rows return null. Never mask failed reads as absence.
  profile(userId: string): Promise<Profile | null>;
  patientByProfile(userId: string): Promise<Patient | null>;
}
export type Scope = {
  user_id: string;
  operation: "submit_template";
  request_id: string;
};
export type DocumentInsert = {
  patient_id: string;
  uploader_id: string;
  status: "pending";
  file_type: "template";
  file_name: string;
  file_path: string;
  extracted_metadata: Record<string, string>;
};
export type Audit = {
  user_id: string;
  event_type: "DOCUMENT_SUBMITTED";
  description: string;
};
export type Receipt =
  | { kind: "absent" }
  | { kind: "in_progress" }
  | { kind: "expired" }
  | {
    kind: "complete";
    fingerprint: string;
    document_id: string;
    first_accepted_at: string;
    expires_at: string;
  };
export interface RequestTransaction {
  lookup(): Promise<Receipt>;
  // REQUIRED OWNER DECISION: must be atomic across web + mobile, not a
  // read-then-insert query. Throw DUPLICATE_PENDING if the selected rule fails.
  enforceDuplicate(patientId: string, templateId: string): Promise<void>;
  // REQUIRED BACKEND IMPLEMENTATION: one transaction for document, attributed
  // audit including document_id, and receipt. Audit failure rolls back all three.
  // No outbox. An ambiguous response must retain the committed receipt.
  commitNew(input: {
    fingerprint: string;
    document: DocumentInsert;
    audit: Audit;
  }): Promise<string>;
}
export interface SubmissionStore {
  // Durable exclusion scoped to the full triple. Never use an isolate-local
  // mutex as the production implementation. A held key may throw IN_PROGRESS.
  withRequest<T>(
    scope: Scope,
    run: (tx: RequestTransaction) => Promise<T>,
  ): Promise<T>;
  // REQUIRED OWNER DECISION: retention/reconciliation; no default duration or
  // "expired means new submission". The adapter must preserve expiry evidence.
  onExpired(scope: Scope): Promise<never>;
}
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function reply(
  body: object,
  status = 200,
  headers: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...headers },
  });
}
const isObject = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
async function fingerprint(templateId: string, fields: Record<string, string>) {
  // Only normalized client intent: changing clocks/demographics must not
  // conflict with a retry of the same request. Field order is deterministic.
  const canonical = JSON.stringify([
    templateId,
    Object.keys(fields).sort().map((key) => [key, fields[key]]),
  ]);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
const messages: Record<Code, string> = {
  METHOD_NOT_ALLOWED: "Use POST or OPTIONS.",
  SERVER_DATA_INVALID:
    "Account information needs correction. Please contact the clinic. Do not retry until corrected.",
  PATIENT_ACCOUNT_REQUIRED: "A patient account is required.",
  UNAUTHENTICATED: "Please sign in again.",
  NO_PATIENT_RECORD: "Patient account is incomplete. Contact the clinic.",
  PROFILE_INACTIVE: "Account is inactive or unavailable. Contact the clinic.",
  EMAIL_NOT_CONFIRMED: "Please verify your email.",
  CONSENT_REQUIRED: "Please accept the privacy agreement.",
  PASSWORD_CHANGE_REQUIRED: "Please change your temporary password.",
  UNKNOWN_TEMPLATE: "This template is not supported.",
  UNKNOWN_FIELD: "The request contains an unsupported field.",
  FIELD_REQUIRED: "A required field is empty.",
  FIELD_INVALID: "A field has an invalid value.",
  AGE_REQUIREMENT_NOT_MET:
    "Patient intake requires a valid date of birth and age 18 or above.",
  DUPLICATE_PENDING: "A matching submission is already pending.",
  IDEMPOTENCY_CONFLICT:
    "This request ID belongs to different content. Reconciliation is required.",
  IN_PROGRESS:
    "This request is still being processed. Do not submit a new request.",
  SERVER_ERROR:
    "Submission could not be confirmed. Retain the request ID for reconciliation.",
};

export function createHandler(
  deps: { identity: Identity; store?: SubmissionStore; now?: () => Date },
) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (req.method !== "POST") {
      return reply(
        {
          error_code: "METHOD_NOT_ALLOWED",
          message: messages.METHOD_NOT_ALLOWED,
        },
        405,
        { Allow: "POST, OPTIONS" },
      );
    }
    try {
      const token = /^Bearer\s+(\S+)$/i.exec(
        req.headers.get("authorization") ?? "",
      )?.[1];
      if (!token) throw new SubmissionError("UNAUTHENTICATED");
      const user = await deps.identity.authenticate(token);
      if (!user) throw new SubmissionError("UNAUTHENTICATED");
      const profile = await deps.identity.profile(user.id);
      if (!profile?.is_active) throw new SubmissionError("PROFILE_INACTIVE");
      if (profile.role !== "patient") {
        throw new SubmissionError("PATIENT_ACCOUNT_REQUIRED");
      }
      const patient = await deps.identity.patientByProfile(user.id);
      if (!patient) throw new SubmissionError("NO_PATIENT_RECORD");
      // Assertion is about the lookup relationship, not UUID inequality:
      // coincidentally equal UUIDs are possible, but must never be substituted.
      if (!patient.id || patient.profile_id !== user.id) {
        throw new SubmissionError("SERVER_ERROR");
      }
      if (!user.email_confirmed_at) {
        throw new SubmissionError("EMAIL_NOT_CONFIRMED");
      }
      if (!profile.accepted_privacy_at) {
        throw new SubmissionError("CONSENT_REQUIRED");
      }
      if (user.app_metadata.must_change_password === true) {
        throw new SubmissionError("PASSWORD_CHANGE_REQUIRED");
      }

      let raw: unknown;
      try {
        raw = await req.json();
      } catch {
        throw new SubmissionError("FIELD_INVALID", "body");
      }
      if (!isObject(raw)) throw new SubmissionError("FIELD_INVALID", "body");
      const unknown = Object.keys(raw).find((k) =>
        !["request_id", "template_id", "fields"].includes(k)
      );
      // Never echo arbitrary user-provided key names (they may contain PII).
      if (unknown) throw new SubmissionError("UNKNOWN_FIELD", "body");
      if (typeof raw.request_id !== "string" || !uuid.test(raw.request_id)) {
        throw new SubmissionError("FIELD_INVALID", "request_id");
      }
      const template = CLINIC_TEMPLATES.find((t) => t.id === raw.template_id);
      if (!template) {
        throw new SubmissionError("UNKNOWN_TEMPLATE", "template_id");
      }
      if (!isObject(raw.fields)) {
        throw new SubmissionError("FIELD_INVALID", "fields");
      }
      const fields = raw.fields;
      if (
        Object.keys(fields).some((k) =>
          !template.fields.some((f) => f.key === k)
        )
      ) {
        throw new SubmissionError("UNKNOWN_FIELD", "fields");
      }
      for (const field of template.fields) {
        const value = fields[field.key];
        if (value !== undefined && typeof value !== "string") {
          throw new SubmissionError("FIELD_INVALID", field.key);
        }
        if (field.required && (typeof value !== "string" || !value.trim())) {
          throw new SubmissionError("FIELD_REQUIRED", field.key);
        }
      }
      const today = todayInPh();
      const validated = validateTemplateSubmission(
        template,
        fields as Record<string, string>,
        today,
      );
      if (!validated.valid) {
        // Locate bounds failures using the same authoritative shared validator.
        for (const field of template.fields) {
          const check = validateTemplateSubmission(
            { ...template, fields: [field] },
            { [field.key]: fields[field.key] as string },
            today,
          );
          if (!check.valid) {
            throw new SubmissionError("FIELD_INVALID", field.key);
          }
        }
        throw new SubmissionError("FIELD_INVALID", "fields");
      }
      if (template.id === "patient-intake") {
        if (
          typeof patient.date_of_birth !== "string" ||
          !validateDobDate(patient.date_of_birth).valid
        ) {
          throw new SubmissionError("SERVER_DATA_INVALID");
        }
        if (!validateAge(patient.date_of_birth).valid) {
          throw new SubmissionError("AGE_REQUIREMENT_NOT_MET", "date_of_birth");
        }
      }
      // All account gates above run again on every replay.
      if (!deps.store) throw new SubmissionError("SERVER_ERROR");
      const scope: Scope = {
        user_id: user.id,
        operation: "submit_template",
        request_id: raw.request_id.toLowerCase(),
      };
      const hash = await fingerprint(template.id, validated.fields);
      const result = await deps.store.withRequest(scope, async (tx) => {
        const receipt = await tx.lookup();
        if (receipt.kind === "expired") {
          return await deps.store!.onExpired(scope);
        }
        if (receipt.kind === "in_progress") {
          throw new SubmissionError("IN_PROGRESS");
        }
        if (receipt.kind === "complete") {
          const start = Date.parse(receipt.first_accepted_at);
          const expiry = Date.parse(receipt.expires_at);
          if (
            !Number.isFinite(start) || !Number.isFinite(expiry) ||
            expiry <= start
          ) {
            throw new SubmissionError("SERVER_ERROR");
          }
          // Half-open receipt window. Duration comes from the backend, not draft age.
          if ((deps.now?.() ?? new Date()).getTime() >= expiry) {
            return await deps.store!.onExpired(scope);
          }
          if (receipt.fingerprint !== hash) {
            throw new SubmissionError("IDEMPOTENCY_CONFLICT");
          }
          return {
            document_id: receipt.document_id,
            status: "pending",
            replayed: true,
          };
        }
        await tx.enforceDuplicate(patient.id, template.id);
        const now = deps.now?.() ?? new Date();
        // Matches web's formatting; web leaves file-name date timezone implicit.
        const date = now.toLocaleDateString("en-US", {
          year: "numeric",
          month: "short",
          day: "2-digit",
        });
        const document: DocumentInsert = {
          patient_id: patient.id,
          uploader_id: user.id,
          status: "pending",
          file_type: "template",
          file_name: `${template.name} - ${date}`,
          file_path: `template://${template.id}-${now.getTime()}`,
          extracted_metadata: {
            ...validated.fields,
            patient_name: `${patient.first_name || ""} ${
              patient.last_name || ""
            }`.trim(),
            ...(template.id === "patient-intake"
              ? {
                date_of_birth: patient.date_of_birth!,
                contact_number: patient.contact_number || "",
                address: patient.address || "",
              }
              : {}),
            template_id: template.id,
            template_name: template.name,
            submission_type: "template",
            submitted_at: now.toISOString(),
          },
        };
        const documentId = await tx.commitNew({
          fingerprint: hash,
          document,
          audit: {
            user_id: user.id,
            event_type: "DOCUMENT_SUBMITTED",
            description: `Patient submitted form template: ${template.name}`,
          },
        });
        if (!documentId) throw new SubmissionError("SERVER_ERROR");
        return { document_id: documentId, status: "pending", replayed: false };
      });
      return reply(result);
    } catch (error) {
      const safe = error instanceof SubmissionError
        ? error
        : new SubmissionError("SERVER_ERROR");
      return reply({
        error_code: safe.code,
        message: messages[safe.code],
        ...(safe.field ? { field: safe.field } : {}),
      }, statuses[safe.code]);
    }
  };
}
