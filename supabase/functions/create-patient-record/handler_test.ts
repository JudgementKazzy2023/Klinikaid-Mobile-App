/**
 * Tests for the `create-patient-record` edge function.
 *
 * The Supabase clients are mocked, so nothing here touches the live backend
 * and no network call is made.
 */

import {
  createCreatePatientRecordHandler,
  type AuthUser,
  type InsertBuilder,
  type QueryResult,
  type Row,
  type SelectBuilder,
  type ServiceClient,
  type TableBuilder,
  type UserClient,
} from "./handler.ts";

const NOW = new Date("2026-10-22T00:00:00.000Z");

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(`Assertion failed: ${message}`);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`Assertion failed: ${message} (expected ${expected}, got ${actual})`);
  }
}

interface FakeDatabase {
  profiles: Row[];
  patients: Row[];
  user: AuthUser | null;
  userError: { message: string } | null;
  selectError: { message: string } | null;
  insertError: string | null;
  deleteError: string | null;
  insertedRows: Row[];
  deletedUsers: string[];
  patientLookups: number;
  revealPatientsAfterFirstLookup: boolean;
}

function createDatabase(overrides: Partial<FakeDatabase> = {}): FakeDatabase {
  return {
    profiles: [],
    patients: [],
    user: null,
    userError: null,
    selectError: null,
    insertError: null,
    deleteError: null,
    insertedRows: [],
    deletedUsers: [],
    patientLookups: 0,
    revealPatientsAfterFirstLookup: false,
    ...overrides,
  };
}

class FakeQuery implements SelectBuilder {
  constructor(
    private readonly db: FakeDatabase,
    private readonly table: string,
    private readonly filters: Record<string, string>,
  ) {}

  eq(column: string, value: string): FakeQuery {
    return new FakeQuery(this.db, this.table, { ...this.filters, [column]: value });
  }

  limit(_count: number): FakeQuery {
    return this;
  }

  then<TResult1 = QueryResult<Row[]>, TResult2 = never>(
    onfulfilled?: ((value: QueryResult<Row[]>) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    return Promise.resolve(this.select()).then(onfulfilled, onrejected);
  }

  private select(): QueryResult<Row[]> {
    if (this.db.selectError) {
      return { data: null, error: this.db.selectError };
    }
    const source = this.table === "patients" ? this.db.patients : this.db.profiles;
    if (this.table === "patients") {
      this.db.patientLookups += 1;
      if (this.db.revealPatientsAfterFirstLookup && this.db.patientLookups === 1) {
        return { data: [], error: null };
      }
    }
    const filtered = source.filter((row) =>
      Object.entries(this.filters).every(([column, value]) => String(row[column]) === value)
    );
    return { data: filtered, error: null };
  }
}

class FakeTable implements TableBuilder {
  constructor(
    private readonly db: FakeDatabase,
    private readonly table: string,
  ) {}

  select(_columns?: string): SelectBuilder {
    return new FakeQuery(this.db, this.table, {});
  }

  insert(values: Row): InsertBuilder {
    return {
      select: () => ({
        single: (): Promise<QueryResult<Row>> => {
          this.db.insertedRows.push(values);
          if (this.db.insertError) {
            return Promise.resolve({ data: null, error: { message: this.db.insertError } });
          }
          const row: Row = {
            id: `patient-${this.db.patients.length + 1}`,
            created_at: NOW.toISOString(),
            updated_at: NOW.toISOString(),
            ...values,
          };
          this.db.patients.push(row);
          return Promise.resolve({ data: row, error: null });
        },
      }),
    };
  }
}

class FakeServiceClient implements ServiceClient {
  constructor(private readonly db: FakeDatabase) {}

  from(table: string): TableBuilder {
    return new FakeTable(this.db, table);
  }

  auth = {
    admin: {
      deleteUser: (id: string): Promise<{ error: { message: string } | null }> => {
        this.db.deletedUsers.push(id);
        if (this.db.deleteError) {
          return Promise.resolve({ error: { message: this.db.deleteError } });
        }
        return Promise.resolve({ error: null });
      },
    },
  };
}

class FakeUserClient implements UserClient {
  constructor(private readonly db: FakeDatabase) {}

  auth = {
    getUser: () => {
      if (this.db.userError) {
        return Promise.resolve({ data: { user: null }, error: this.db.userError });
      }
      return Promise.resolve({ data: { user: this.db.user }, error: null });
    },
  };
}

function buildHandler(db: FakeDatabase) {
  return createCreatePatientRecordHandler({
    createUserClient: () => new FakeUserClient(db),
    serviceClient: new FakeServiceClient(db),
    now: () => NOW,
  });
}

function buildRequest(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/create-patient-record", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-token",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

const validBody = {
  first_name: "Jane",
  last_name: "Patient",
  date_of_birth: "1990-01-15",
  gender: "female",
  contact_number: "09171234567",
  email: "spoofed@example.com",
  address: "123 Test St",
};

function patientUser(overrides: Partial<AuthUser> = {}): AuthUser {
  return {
    id: "user-1",
    email: "jane@example.com",
    created_at: NOW.toISOString(),
    ...overrides,
  };
}

Deno.test("refuses a non-patient caller with 403 and never deletes the account", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "receptionist" }],
    user: patientUser(),
  });
  const handler = buildHandler(db);

  const response = await handler(buildRequest(validBody));
  const body = await response.json();

  assertEquals(response.status, 403, "a staff account is refused");
  assertEquals(body.error, "forbidden", "the refusal is reported as forbidden");
  assertEquals(db.deletedUsers.length, 0, "the account is never deleted");
  assertEquals(db.insertedRows.length, 0, "no patient row is written");
});

Deno.test("refuses a caller without a profile with 403 and never deletes the account", async () => {
  const db = createDatabase({ profiles: [], user: patientUser() });
  const handler = buildHandler(db);

  const response = await handler(buildRequest(validBody));

  assertEquals(response.status, 403, "a caller without a profile is refused");
  assertEquals(db.deletedUsers.length, 0, "the account is never deleted");
});

Deno.test("returns 400 for an invalid field and never deletes the account", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    user: patientUser(),
  });
  const handler = buildHandler(db);

  const response = await handler(buildRequest({ ...validBody, contact_number: "12345" }));
  const body = await response.json();

  assertEquals(response.status, 400, "an invalid contact number is refused");
  assert(
    String(body.message).includes("valid Philippine mobile number"),
    "the refusal explains the contact number rule",
  );
  assertEquals(db.deletedUsers.length, 0, "a validation failure never deletes the account");
  assertEquals(db.insertedRows.length, 0, "a validation failure writes no row");
});

Deno.test("returns 400 for a date of birth below 18 years old", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    user: patientUser(),
  });
  const handler = buildHandler(db);

  const response = await handler(buildRequest({ ...validBody, date_of_birth: "2015-01-15" }));
  const body = await response.json();

  assertEquals(response.status, 400, "an under-18 date of birth is refused");
  assert(
    String(body.message).includes("18 years old and above"),
    "the refusal explains the age rule",
  );
  assertEquals(db.deletedUsers.length, 0, "the account is never deleted");
});

Deno.test("returns 400 for a date of birth more than 120 years in the past", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    user: patientUser(),
  });
  const handler = buildHandler(db);

  const response = await handler(buildRequest({ ...validBody, date_of_birth: "1900-01-15" }));

  assertEquals(response.status, 400, "a date of birth beyond 120 years is refused");
  assertEquals(db.deletedUsers.length, 0, "the account is never deleted");
});

Deno.test("returns the existing patient row on a repeated call and inserts no second row", async () => {
  const existing: Row = {
    id: "patient-1",
    profile_id: "user-1",
    first_name: "Jane",
    last_name: "Patient",
    date_of_birth: "1990-01-15",
    gender: "female",
    contact_number: "09171234567",
    email: "jane@example.com",
    address: "123 Test St",
  };
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    patients: [existing],
    user: patientUser(),
  });
  const handler = buildHandler(db);

  const first = await handler(buildRequest(validBody));
  const second = await handler(buildRequest(validBody));
  const firstBody = await first.json();
  const secondBody = await second.json();

  assertEquals(first.status, 200, "the repeated call succeeds");
  assertEquals(second.status, 200, "the repeated call succeeds");
  assertEquals(firstBody.patient.id, "patient-1", "the existing row is returned");
  assertEquals(secondBody.patient.id, "patient-1", "the same row is returned again");
  assertEquals(secondBody.created, false, "the repeated call creates nothing");
  assertEquals(db.insertedRows.length, 0, "no duplicate row is written");
  assertEquals(db.patients.length, 1, "the table still holds a single row");
  assertEquals(db.deletedUsers.length, 0, "the account is never deleted");
});

Deno.test("stores the account email and creates the row only once", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    user: patientUser(),
  });
  const handler = buildHandler(db);

  const first = await handler(buildRequest(validBody));
  const second = await handler(buildRequest(validBody));
  const secondBody = await second.json();

  assertEquals(first.status, 200, "the first call succeeds");
  assertEquals(second.status, 200, "the second call succeeds");
  assertEquals(db.insertedRows.length, 1, "the row is written once");
  assertEquals(db.patients.length, 1, "the table holds a single row");
  assertEquals(
    db.insertedRows[0].email,
    "jane@example.com",
    "the account email is stored, not the email from the body",
  );
  assertEquals(secondBody.created, false, "the second call creates nothing");
  assertEquals(db.deletedUsers.length, 0, "the account is never deleted");
});

Deno.test("deletes the account when the insert fails for a brand new signup", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    user: patientUser(),
    insertError: "duplicate key value violates unique constraint",
  });
  const handler = buildHandler(db);

  const response = await handler(buildRequest(validBody));
  const body = await response.json();

  assertEquals(response.status, 500, "the failed insert is reported");
  assertEquals(body.error, "patient_insert_failed", "the failure is reported");
  assertEquals(db.deletedUsers.length, 1, "the brand new account is deleted");
  assertEquals(db.deletedUsers[0], "user-1", "only the caller account is deleted");
});

Deno.test("keeps an account that is not a brand new signup when the insert fails", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    user: patientUser({ created_at: new Date(NOW.getTime() - 2 * 24 * 60 * 60 * 1000).toISOString() }),
    insertError: "insert failed",
  });
  const handler = buildHandler(db);

  const response = await handler(buildRequest(validBody));

  assertEquals(response.status, 500, "the failed insert is reported");
  assertEquals(db.deletedUsers.length, 0, "an existing account is never deleted");
});

Deno.test("returns the row an overlapping call inserted when this insert fails", async () => {
  const db = createDatabase({
    profiles: [{ id: "user-1", role: "patient" }],
    patients: [{
      id: "patient-1",
      profile_id: "user-1",
      first_name: "Jane",
      last_name: "Patient",
      date_of_birth: "1990-01-15",
      gender: "female",
      contact_number: "09171234567",
      email: "jane@example.com",
      address: "123 Test St",
    }],
    user: patientUser(),
    insertError: "insert failed",
    revealPatientsAfterFirstLookup: true,
  });
  const handler = buildHandler(db);

  const response = await handler(buildRequest(validBody));

  assertEquals(response.status, 200, "the patient has a record, so the call succeeds");
  const json = await response.json();
  assertEquals(json.created, false, "the existing row is returned, not a new one");
  assertEquals(json.patient.id, "patient-1", "the row the overlapping call wrote");
  assertEquals(db.deletedUsers.length, 0, "the account is kept when a row exists");
});

Deno.test("returns 401 without an Authorization header", async () => {
  const db = createDatabase({ user: patientUser() });
  const handler = buildHandler(db);

  const request = new Request("http://localhost/create-patient-record", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(validBody),
  });
  const response = await handler(request);

  assertEquals(response.status, 401, "a missing token is refused");
  assertEquals(db.deletedUsers.length, 0, "the account is never deleted");
});

Deno.test("returns 405 for a method other than POST", async () => {
  const db = createDatabase({ user: patientUser() });
  const handler = buildHandler(db);

  const response = await handler(
    new Request("http://localhost/create-patient-record", { method: "GET" }),
  );

  assertEquals(response.status, 405, "only POST is allowed");
});
