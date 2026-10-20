// Test doubles intentionally implement asynchronous ports without external IO.
// deno-lint-ignore-file require-await
import {
  type Audit,
  createHandler,
  type DocumentInsert,
  type Identity,
  type Patient,
  type Profile,
  type Receipt,
  type Scope,
  statuses,
  SubmissionError,
  type SubmissionStore,
  type User,
} from "./handler.ts";
import { CLINIC_TEMPLATES } from "./reference/documentTemplates.ts";
import {
  latestTemplateDate,
  reviewTemplateSubmission,
  todayInPh,
} from "./reference/templateChecks.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
const id = "11111111-1111-4111-8111-111111111111";
const id2 = "22222222-2222-4222-8222-222222222222";
const scopeKey = (s: Scope) =>
  JSON.stringify([s.user_id, s.operation, s.request_id]);

// TEST ONLY: no claims of production durability, duplicate policy or audit
// recovery. Receipts/data disappear with each test fixture.
class FakeStore implements SubmissionStore {
  receipts = new Map<string, Receipt>();
  busy = new Set<string>();
  documents: DocumentInsert[] = [];
  audits: (Audit & { document_id: string })[] = [];
  duplicate = false;
  failCommit = false;
  expiredCalls = 0;
  async onExpired(_scope: Scope): Promise<never> {
    this.expiredCalls++;
    throw new SubmissionError("SERVER_ERROR"); // Test-only chosen callback.
  }
  async withRequest<T>(
    scope: Scope,
    run: Parameters<SubmissionStore["withRequest"]>[1],
  ): Promise<T> {
    const key = scopeKey(scope);
    if (this.busy.has(key)) throw new SubmissionError("IN_PROGRESS");
    this.busy.add(key);
    try {
      return await run({
        lookup: async () => this.receipts.get(key) ?? { kind: "absent" },
        enforceDuplicate: async () => {
          if (this.duplicate) throw new SubmissionError("DUPLICATE_PENDING");
        },
        commitNew: async ({ fingerprint, document, audit }) => {
          if (this.failCommit) {
            throw new Error("Sensitive database detail must not escape");
          }
          const document_id = crypto.randomUUID();
          this.documents.push(document);
          this.audits.push({ ...audit, document_id });
          this.receipts.set(key, {
            kind: "complete",
            fingerprint,
            document_id,
          });
          return document_id;
        },
      }) as T;
    } finally {
      this.busy.delete(key);
    }
  }
}

function fixture() {
  const state: {
    user: User | null;
    profile: Profile | null;
    patient: Patient | null;
  } = {
    user: {
      id: "profile-uuid",
      email_confirmed_at: "2026-01-01",
      app_metadata: {},
    },
    profile: { is_active: true, accepted_privacy_at: "2026-01-01" },
    patient: {
      id: "DIFFERENT-patient-row-uuid",
      profile_id: "profile-uuid",
      first_name: "Synthetic",
      last_name: "Fixture",
      date_of_birth: "1990-01-01",
      contact_number: "fixture-contact",
      address: "fixture-address",
    },
  };
  const store = new FakeStore();
  const lookups: string[] = [];
  const identity: Identity = {
    authenticate: async (token) => token === "fixture" ? state.user : null,
    profile: async () => state.profile,
    patientByProfile: async (userId) => {
      lookups.push(userId);
      return state.patient;
    },
  };
  const handler = createHandler({ identity, store });
  return { state, store, identity, handler, lookups };
}
function body(
  templateId = "referral-form",
  requestId = id,
): Record<string, unknown> {
  const template = CLINIC_TEMPLATES.find((t) => t.id === templateId)!;
  return {
    request_id: requestId,
    template_id: templateId,
    fields: Object.fromEntries(template.fields.map((f) => [
      f.key,
      f.type === "date"
        ? todayInPh()
        : f.type === "select"
        ? f.options![0]
        : "Synthetic answer",
    ])),
  };
}
async function call(
  f: ReturnType<typeof fixture>,
  input = body(),
  token = "fixture",
) {
  const response = await f.handler(
    new Request("https://example.invalid/submit-template", {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(input),
    }),
  );
  return { status: response.status, body: await response.json() };
}

for (const template of CLINIC_TEMPLATES) {
  Deno.test(`valid ${template.id}: derived identity, metadata, one audit`, async () => {
    const f = fixture();
    const result = await call(f, body(template.id));
    equal(result.status, 200);
    equal(result.body.replayed, false);
    equal(f.lookups, ["profile-uuid"]);
    equal(f.store.documents.length, 1);
    const doc = f.store.documents[0];
    equal(doc.patient_id, "DIFFERENT-patient-row-uuid");
    equal(doc.uploader_id, "profile-uuid");
    equal(doc.status, "pending");
    equal(doc.file_type, "template");
    equal(doc.extracted_metadata.patient_name, "Synthetic Fixture");
    equal(doc.extracted_metadata.template_name, template.name);
    equal(f.store.audits.length, 1);
    equal(f.store.audits[0].user_id, "profile-uuid");
    equal(f.store.audits[0].event_type, "DOCUMENT_SUBMITTED");
    equal(f.store.audits[0].document_id, result.body.document_id);
    for (const key of ["date_of_birth", "contact_number", "address"]) {
      equal(key in doc.extracted_metadata, template.id === "patient-intake");
    }
    equal(reviewTemplateSubmission(doc.extracted_metadata).status, "passed");
  });
}
Deno.test("normalized replay preserves document and emits no audit; changed content conflicts", async () => {
  const f = fixture();
  const original = body();
  const first = await call(f, original);
  const changedSpacing = body();
  (changedSpacing.fields as Record<string, string>).referring_physician =
    " Synthetic answer ";
  const replay = await call(f, changedSpacing);
  equal(replay.body, { ...first.body, replayed: true });
  (changedSpacing.fields as Record<string, string>).referring_physician =
    "Different";
  equal(
    (await call(f, changedSpacing)).body.error_code,
    "IDEMPOTENCY_CONFLICT",
  );
  equal(f.store.documents.length, 1);
  equal(f.store.audits.length, 1);
});
Deno.test("concurrent same key creates one fixture document", async () => {
  const f = fixture();
  const results = await Promise.all([call(f), call(f)]);
  equal(f.store.documents.length, 1);
  equal(f.store.audits.length, 1);
  equal(
    results.every((r) =>
      r.status === 200 || r.body.error_code === "IN_PROGRESS"
    ),
    true,
  );
});
Deno.test("same request UUID is scoped to authenticated owner", async () => {
  const f = fixture();
  await call(f);
  f.state.user!.id = "another-profile";
  f.state.patient!.profile_id = "another-profile";
  f.state.patient!.id = "another-patient";
  equal((await call(f)).body.replayed, false);
  equal(f.store.documents.length, 2);
});
Deno.test("account gates run on initial call AND successful replay", async () => {
  const cases: [
    keyof typeof statuses,
    (f: ReturnType<typeof fixture>) => void,
  ][] = [
    ["UNAUTHENTICATED", (f) => {
      f.state.user = null;
    }],
    ["NO_PATIENT_RECORD", (f) => {
      f.state.patient = null;
    }],
    ["PROFILE_INACTIVE", (f) => {
      f.state.profile!.is_active = false;
    }],
    ["EMAIL_NOT_CONFIRMED", (f) => {
      f.state.user!.email_confirmed_at = undefined;
    }],
    ["CONSENT_REQUIRED", (f) => {
      f.state.profile!.accepted_privacy_at = null;
    }],
    ["PASSWORD_CHANGE_REQUIRED", (f) => {
      f.state.user!.app_metadata.must_change_password = true;
    }],
  ];
  for (const [code, mutate] of cases) {
    for (const replay of [false, true]) {
      const f = fixture();
      if (replay) await call(f);
      mutate(f);
      const result = await call(f);
      equal(result.status, statuses[code]);
      equal(result.body.error_code, code);
      equal(f.store.documents.length, replay ? 1 : 0);
    }
  }
});
Deno.test("identity mismatch and failed reads fail closed, not missing patient", async () => {
  const f = fixture();
  f.state.patient!.profile_id = "wrong";
  equal((await call(f)).body.error_code, "SERVER_ERROR");
  f.identity.patientByProfile = async () => {
    throw new Error("private details");
  };
  equal((await call(f)).body.error_code, "SERVER_ERROR");
  equal(f.store.documents.length, 0);
});
Deno.test("reject server columns, unknown fields/templates, malformed request", async () => {
  const f = fixture();
  for (
    const key of [
      "patient_id",
      "uploader_id",
      "status",
      "file_type",
      "file_name",
      "file_path",
      "submitted_at",
      "extracted_metadata",
    ]
  ) {
    equal(
      (await call(f, { ...body(), [key]: "approved" })).body.error_code,
      "UNKNOWN_FIELD",
    );
  }
  equal(
    (await call(f, { ...body(), template_id: "unknown" })).body.error_code,
    "UNKNOWN_TEMPLATE",
  );
  equal(
    (await call(f, { ...body(), fields: { patient_name: "spoof" } })).body
      .error_code,
    "UNKNOWN_FIELD",
  );
  equal(
    (await call(f, { ...body(), request_id: "bad" })).body.field,
    "request_id",
  );
  equal(
    (await call(f, { ...body(), fields: [] })).body.error_code,
    "FIELD_INVALID",
  );
  equal(
    (await call(f, body(), "invalid-token")).body.error_code,
    "UNAUTHENTICATED",
  );
  equal(f.store.documents.length, 0);
});
Deno.test("field boundaries, whitespace, date and choice validation", async () => {
  const cases: [string, unknown, string][] = [
    ["referring_physician", " ", "FIELD_REQUIRED"],
    ["referring_physician", "x".repeat(201), "FIELD_INVALID"],
    ["reason_for_referral", "x".repeat(2001), "FIELD_INVALID"],
    ["referral_date", "1899-12-31", "FIELD_INVALID"],
    ["referral_date", "2026-02-30", "FIELD_INVALID"],
    ["referral_date", "9999-01-01", "FIELD_INVALID"],
    ["requested_service", "invalid", "FIELD_INVALID"],
    ["referring_clinic", 42, "FIELD_INVALID"],
  ];
  for (const [key, value, code] of cases) {
    const f = fixture();
    const input = body();
    (input.fields as Record<string, unknown>)[key] = value;
    const result = await call(f, input);
    equal(result.body.error_code, code);
    equal(result.body.field, key);
    equal(f.store.documents.length, 0);
  }
  const f = fixture();
  const input = body();
  const fields = input.fields as Record<string, string>;
  fields.referring_physician = "x".repeat(200);
  fields.reason_for_referral = "x".repeat(2000);
  delete fields.referring_clinic;
  equal((await call(f, input)).status, 200);
  equal(f.store.documents[0].extracted_metadata.referring_clinic, "");
});
Deno.test("intake age boundary Manila; other forms do not impose intake age", async () => {
  const [year, month, day] = todayInPh().split("-").map(Number);
  for (const age of [17, 18, 120, 121]) {
    const f = fixture();
    f.state.patient!.date_of_birth = `${year - age}-${
      String(month).padStart(2, "0")
    }-${String(day).padStart(2, "0")}`;
    equal(
      (await call(f, body("patient-intake"))).status,
      age === 18 || age === 120 ? 200 : 403,
    );
  }
  const f = fixture();
  f.state.patient!.date_of_birth = `${year - 10}-01-01`;
  equal((await call(f)).status, 200);
});
Deno.test("declined form consent is accepted and reception flags it", async () => {
  const f = fixture();
  const input = body("procedure-consent");
  (input.fields as Record<string, string>).consent_given = "No";
  equal((await call(f, input)).status, 200);
  equal(
    reviewTemplateSubmission(f.store.documents[0].extracted_metadata).status,
    "attention",
  );
});
Deno.test("duplicate policy refusal propagates without insert; policy is fixture-only", async () => {
  const f = fixture();
  f.store.duplicate = true;
  equal(
    (await call(f, body("lab-request", id2))).body.error_code,
    "DUPLICATE_PENDING",
  );
  equal(f.store.documents.length, 0);
});
Deno.test("expired receipt delegates to required owner callback; does not become absent", async () => {
  const f = fixture();
  f.store.receipts.set(
    scopeKey({
      user_id: "profile-uuid",
      operation: "submit_template",
      request_id: id,
    }),
    { kind: "expired" },
  );
  equal((await call(f)).body.error_code, "SERVER_ERROR");
  equal(f.store.expiredCalls, 1);
  equal(f.store.documents.length, 0);
});
Deno.test("missing production store fails closed; commit errors leak no private details", async () => {
  const f = fixture();
  f.store.failCommit = true;
  const result = await call(f);
  equal(result.body.error_code, "SERVER_ERROR");
  equal(JSON.stringify(result).includes("Sensitive"), false);
  f.handler = createHandler({ identity: f.identity });
  equal((await call(f)).status, 503);
  equal(f.store.documents.length, 0);
});
Deno.test("operation scoping and persisted in-progress receipt", async () => {
  const f = fixture();
  f.store.receipts.set(JSON.stringify(["profile-uuid", "submit_upload", id]), {
    kind: "complete",
    document_id: "other-operation",
    fingerprint: "different",
  });
  equal((await call(f)).body.replayed, false);
  const g = fixture();
  g.store.receipts.set(
    scopeKey({
      user_id: "profile-uuid",
      operation: "submit_template",
      request_id: id,
    }),
    { kind: "in_progress" },
  );
  equal((await call(g)).body.error_code, "IN_PROGRESS");
  equal(g.store.documents.length, 0);
});
Deno.test("exact date boundaries and non-future dates match pinned web", async () => {
  const today = todayInPh();
  const nextDay = (date: string) =>
    new Date(Date.parse(`${date}T00:00:00Z`) + 86400000).toISOString().slice(
      0,
      10,
    );
  for (
    const [template, key, date, status] of [
      ["lab-request", "request_date", "1900-01-01", 200],
      ["lab-request", "request_date", latestTemplateDate(today), 200],
      ["lab-request", "request_date", nextDay(latestTemplateDate(today)), 400],
      ["referral-form", "referral_date", nextDay(today), 400],
      ["procedure-consent", "consent_date", nextDay(today), 400],
      ["results-release", "authorization_date", nextDay(today), 200],
    ] as const
  ) {
    const f = fixture();
    const input = body(template);
    (input.fields as Record<string, string>)[key] = date;
    equal((await call(f, input)).status, status);
  }
});
Deno.test("malformed JSON, missing bearer, and non-object body fail safely", async () => {
  const f = fixture();
  for (
    const [text, authorization, code] of [
      ["{", "Bearer fixture", "FIELD_INVALID"],
      ["null", "Bearer fixture", "FIELD_INVALID"],
      ["[]", "Bearer fixture", "FIELD_INVALID"],
      [JSON.stringify(body()), "", "UNAUTHENTICATED"],
    ]
  ) {
    const response = await f.handler(
      new Request("https://example.invalid", {
        method: "POST",
        headers: { authorization },
        body: text,
      }),
    );
    equal((await response.json()).error_code, code);
  }
  equal(f.store.documents.length, 0);
});
Deno.test({
  name: "OWNER BLOCKED: atomic cross-web/mobile duplicate integration",
  ignore: true,
  fn() {},
});
Deno.test({
  name: "OWNER BLOCKED: retention-window boundary integration",
  ignore: true,
  fn() {},
});
Deno.test({
  name: "OWNER BLOCKED: audit failure after document commit and crash recovery",
  ignore: true,
  fn() {},
});
