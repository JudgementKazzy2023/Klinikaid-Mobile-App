/**
 * Request handling for the `create-patient-record` edge function.
 *
 * The logic lives in its own module so it can be exercised with mocked
 * Supabase clients (`handler_test.ts`) instead of the live backend. `index.ts`
 * stays the entry point and only wires the real clients in.
 *
 * The field rules mirror the web registration form (`src/app/(auth)/register/
 * actions.ts` and `src/lib/validation.ts` of the web app), so a registration
 * the web accepts is accepted here as well.
 */

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export interface QueryError {
  message: string;
}

export interface QueryResult<T> {
  data: T | null;
  error: QueryError | null;
}

export type Row = Record<string, unknown>;

export interface AuthUser {
  id: string;
  email?: string | null;
  created_at?: string | null;
}

export interface SelectBuilder extends PromiseLike<QueryResult<Row[]>> {
  eq(column: string, value: string): SelectBuilder;
  limit(count: number): SelectBuilder;
}

export interface InsertBuilder {
  select(columns?: string): { single(): PromiseLike<QueryResult<Row>> };
}

export interface TableBuilder {
  select(columns?: string): SelectBuilder;
  insert(values: Row): InsertBuilder;
}

export interface UserClient {
  auth: {
    getUser(): PromiseLike<{
      data: { user: AuthUser | null } | null;
      error: QueryError | null;
    }>;
  };
}

export interface ServiceClient {
  from(table: string): TableBuilder;
  auth: {
    admin: {
      deleteUser(id: string): PromiseLike<{ error: QueryError | null }>;
    };
  };
}

export interface HandlerDeps {
  /** Per-request client bound to the caller's Authorization header. */
  createUserClient: (authHeader: string) => UserClient;
  /** Service-role client used for the privileged reads and the insert. */
  serviceClient: ServiceClient;
  /** Clock, injectable so the tests can pin "now". */
  now?: () => Date;
}

export function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const requiredFields = [
  "first_name",
  "last_name",
  "date_of_birth",
  "gender",
  "contact_number",
  "address",
];

const genders = ["male", "female", "other"];

// Web rules (src/lib/validation.ts) kept here so the function accepts exactly
// what the web registration form accepts.
const NAME_REGEX = /^[A-Za-zÀ-ÿ\s\-'.]+$/;
const NAME_MIN = 2;
const NAME_MAX = 100;
const CONTACT_REGEX = /^09\d{9}$/;
const CONTACT_INTERNATIONAL_REGEX = /^\+639\d{9}$/;
const CONTACT_REQUIREMENT_TEXT =
  "Contact number must be a valid Philippine mobile number (e.g. 09171234567).";
const ADDRESS_MAX = 255;
const MAX_DOB_AGE_YEARS = 120;
const MIN_REGISTRATION_AGE = 18;

// An account may only be deleted while it is still the fresh signup this
// function was called for. Anything older is a working account.
const BRAND_NEW_ACCOUNT_WINDOW_MS = 15 * 60 * 1000;

export interface CalendarDate {
  year: number;
  month: number;
  day: number;
}

export interface PatientRegistration {
  firstName: string;
  lastName: string;
  dateOfBirth: string;
  gender: string;
  contactNumber: string;
  address: string;
}

export type ValidationOutcome =
  | { ok: true; value: PatientRegistration }
  | { ok: false; error: string };

/** Today in Asia/Manila, the calendar the web registration uses. */
export function todayInManila(now: Date): CalendarDate {
  const manila = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  return {
    year: manila.getUTCFullYear(),
    month: manila.getUTCMonth() + 1,
    day: manila.getUTCDate(),
  };
}

function compareDates(left: CalendarDate, right: CalendarDate): number {
  if (left.year !== right.year) return left.year - right.year;
  if (left.month !== right.month) return left.month - right.month;
  return left.day - right.day;
}

export function validateName(name: string, label: string): string | null {
  const trimmed = name.trim();
  if (trimmed.length < NAME_MIN) {
    return `${label} must be at least ${NAME_MIN} characters.`;
  }
  if (trimmed.length > NAME_MAX) {
    return `${label} must be no more than ${NAME_MAX} characters.`;
  }
  if (!NAME_REGEX.test(trimmed)) {
    return `${label} may only contain letters, spaces, hyphens, apostrophes, or periods.`;
  }
  return null;
}

export function validateDateOfBirth(value: string, today: CalendarDate): string | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    return "Invalid date of birth format.";
  }

  const date: CalendarDate = {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
  };

  const parsed = new Date(Date.UTC(date.year, date.month - 1, date.day));
  if (
    parsed.getUTCFullYear() !== date.year ||
    parsed.getUTCMonth() !== date.month - 1 ||
    parsed.getUTCDate() !== date.day
  ) {
    return "Invalid date of birth.";
  }

  if (compareDates(date, today) > 0) {
    return "Date of birth cannot be in the future.";
  }

  const cutoff: CalendarDate = {
    year: today.year - MAX_DOB_AGE_YEARS,
    month: today.month,
    day: today.day,
  };
  if (compareDates(date, cutoff) < 0) {
    return `Date of birth cannot be more than ${MAX_DOB_AGE_YEARS} years in the past.`;
  }

  let age = today.year - date.year;
  const hasBirthdayPassed = today.month > date.month ||
    (today.month === date.month && today.day >= date.day);
  if (!hasBirthdayPassed) {
    age -= 1;
  }
  if (age < MIN_REGISTRATION_AGE) {
    return `Registration is restricted to individuals ${MIN_REGISTRATION_AGE} years old and above.`;
  }

  return null;
}

export function validateContactNumber(contactNumber: string): string | null {
  const trimmed = contactNumber.trim();
  if (!CONTACT_REGEX.test(trimmed) && !CONTACT_INTERNATIONAL_REGEX.test(trimmed)) {
    return CONTACT_REQUIREMENT_TEXT;
  }
  return null;
}

/** The web stores the `09` form; the mobile client also accepts `+639`. */
export function normalizeContactNumber(contactNumber: string): string {
  const trimmed = contactNumber.trim();
  return CONTACT_INTERNATIONAL_REGEX.test(trimmed)
    ? `0${trimmed.substring(3)}`
    : trimmed;
}

export function validateAddress(address: string): string | null {
  const trimmed = address.trim();
  if (trimmed.length === 0) {
    return "Address is required.";
  }
  if (trimmed.length > ADDRESS_MAX) {
    return `Address must be no more than ${ADDRESS_MAX} characters.`;
  }
  return null;
}

function readRequiredString(body: Record<string, unknown>, field: string): string | null {
  const value = body[field];
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

export function validatePatientRegistration(
  body: Record<string, unknown>,
  today: CalendarDate,
): ValidationOutcome {
  const missing = requiredFields.filter((field) => readRequiredString(body, field) === null);
  if (missing.length > 0) {
    return { ok: false, error: `Missing required field(s): ${missing.join(", ")}` };
  }

  const firstName = readRequiredString(body, "first_name")!;
  const lastName = readRequiredString(body, "last_name")!;
  const dateOfBirth = readRequiredString(body, "date_of_birth")!;
  const gender = readRequiredString(body, "gender")!;
  const contactNumber = readRequiredString(body, "contact_number")!;
  const address = readRequiredString(body, "address")!;

  const errors: string[] = [];

  const firstNameError = validateName(firstName, "First name");
  if (firstNameError) errors.push(firstNameError);

  const lastNameError = validateName(lastName, "Last name");
  if (lastNameError) errors.push(lastNameError);

  const dateOfBirthError = validateDateOfBirth(dateOfBirth, today);
  if (dateOfBirthError) errors.push(dateOfBirthError);

  if (!genders.includes(gender)) {
    errors.push("Select a valid gender");
  }

  const contactNumberError = validateContactNumber(contactNumber);
  if (contactNumberError) errors.push(contactNumberError);

  const addressError = validateAddress(address);
  if (addressError) errors.push(addressError);

  if (errors.length > 0) {
    return { ok: false, error: errors.join(". ") };
  }

  return {
    ok: true,
    value: {
      firstName,
      lastName,
      dateOfBirth,
      gender,
      contactNumber: normalizeContactNumber(contactNumber),
      address,
    },
  };
}

/**
 * True when the account was created moments ago, i.e. it is the signup this
 * call belongs to. An account of unknown age is never brand new, so it is
 * never deleted.
 */
export function isBrandNewAccount(user: AuthUser, now: Date): boolean {
  const createdAt = Date.parse(user.created_at ?? "");
  if (!Number.isFinite(createdAt)) {
    return false;
  }
  const age = now.getTime() - createdAt;
  return age >= 0 && age <= BRAND_NEW_ACCOUNT_WINDOW_MS;
}

async function findPatientByProfileId(
  serviceClient: ServiceClient,
  profileId: string,
): Promise<QueryResult<Row[]>> {
  return await serviceClient
    .from("patients")
    .select("*")
    .eq("profile_id", profileId)
    .limit(2);
}

export function createCreatePatientRecordHandler(
  deps: HandlerDeps,
): (req: Request) => Promise<Response> {
  const now = deps.now ?? (() => new Date());

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    if (req.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed", message: "Method not allowed." }, 405);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "unauthorized", message: "Missing Authorization header." }, 401);
    }

    const userClient = deps.createUserClient(authHeader);
    const { data: userData, error: authError } = await userClient.auth.getUser();
    const user = userData?.user ?? null;
    if (authError || !user) {
      return jsonResponse(
        { error: "unauthorized", message: authError?.message ?? "Invalid user token." },
        401,
      );
    }

    const serviceClient = deps.serviceClient;

    // Only a patient account owns a patient record. A staff account calling
    // this function is refused and never touched.
    const profileResult = await serviceClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .limit(1);
    if (profileResult.error) {
      console.error(`Profile lookup failed for ${user.id}: ${profileResult.error.message}`);
      return jsonResponse(
        { error: "profile_lookup_failed", message: "Could not verify the account role." },
        500,
      );
    }

    const profile = profileResult.data?.[0] ?? null;
    if (!profile) {
      return jsonResponse(
        { error: "forbidden", message: "No patient profile is associated with this account." },
        403,
      );
    }
    if (profile.role !== "patient") {
      return jsonResponse(
        { error: "forbidden", message: "Only patient accounts can create a patient record." },
        403,
      );
    }

    // The row may already exist: a retry after a dropped connection, or a
    // repeated call. Return it instead of writing a second row.
    const existingResult = await findPatientByProfileId(serviceClient, user.id);
    if (existingResult.error) {
      console.error(`Patient lookup failed for ${user.id}: ${existingResult.error.message}`);
      return jsonResponse(
        { error: "patient_lookup_failed", message: "Could not read the patient record." },
        500,
      );
    }

    const existing = existingResult.data?.[0] ?? null;
    if (existing) {
      return jsonResponse({ success: true, patient: existing, created: false }, 200);
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch (_e) {
      return jsonResponse({ error: "bad_request", message: "Invalid JSON body request." }, 400);
    }

    // `null` and arrays are valid JSON but not a request body; they would
    // otherwise blow up in readRequiredString and fail with a 500.
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      return jsonResponse({ error: "bad_request", message: "Invalid JSON body request." }, 400);
    }

    const validation = validatePatientRegistration(body, todayInManila(now()));
    if (!validation.ok) {
      return jsonResponse({ error: "bad_request", message: validation.error }, 400);
    }

    const registration = validation.value;
    const { data: patient, error: insertError } = await serviceClient
      .from("patients")
      .insert({
        profile_id: user.id,
        first_name: registration.firstName,
        last_name: registration.lastName,
        date_of_birth: registration.dateOfBirth,
        gender: registration.gender,
        contact_number: registration.contactNumber,
        // Always the account email: the body may not change it.
        email: user.email ?? null,
        address: registration.address,
      })
      .select()
      .single();

    if (insertError) {
      console.error(`Patient insert failed for ${user.id}: ${insertError.message}`);

      // An overlapping call can insert the row between the lookup above and
      // this insert; with the unique index on patients.profile_id the second
      // insert then fails. The patient has a record, so that is a success.
      const racedResult = await findPatientByProfileId(serviceClient, user.id);
      const raced = racedResult.error ? null : racedResult.data?.[0] ?? null;
      if (raced) {
        return jsonResponse({ success: true, patient: raced, created: false }, 200);
      }

      return await handleInsertFailure(deps, user, now());
    }

    return jsonResponse({ success: true, patient, created: true }, 200);
  };
}

/**
 * Reports a failed insert. The account is only deleted when it is the brand
 * new signup this call belongs to and it still has no patient row; every other
 * account keeps its account and only gets the failure reported.
 */
async function handleInsertFailure(
  deps: HandlerDeps,
  user: AuthUser,
  now: Date,
): Promise<Response> {
  const serviceClient = deps.serviceClient;

  if (!isBrandNewAccount(user, now)) {
    return jsonResponse(
      { error: "patient_insert_failed", message: "Patient provisioning failed." },
      500,
    );
  }

  const stillMissing = await findPatientByProfileId(serviceClient, user.id);
  if (stillMissing.error || (stillMissing.data?.length ?? 0) > 0) {
    return jsonResponse(
      { error: "patient_insert_failed", message: "Patient provisioning failed." },
      500,
    );
  }

  const { error: deleteError } = await serviceClient.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error(`Failed to delete auth user ${user.id}: ${deleteError.message}`);
    return jsonResponse(
      {
        error: "cleanup_failed",
        message: "Patient provisioning failed and cleanup failed.",
      },
      500,
    );
  }

  return jsonResponse(
    { error: "patient_insert_failed", message: "Patient provisioning failed." },
    500,
  );
}
