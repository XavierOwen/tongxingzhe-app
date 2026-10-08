import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  PersonalTargetPiiExportStoreError,
  PostgresPersonalTargetPiiExportStore,
  exportPersonalTargetPii,
} from "../src/personal-target-pii-export.js";
import type {SessionContext} from "../src/session-context.js";

const now = new Date("2030-01-01T00:15:00.000Z");
const nowSeconds = now.getTime() / 1000;
const identity = {
  issuer: "https://synthetic-export.example.test/auth/v1",
  subject: "personal-export-owner",
  passwordAuthenticatedAtUnixSeconds: nowSeconds - 30,
};
const context: SessionContext = {
  appUserId: "11111111-1111-4111-8111-111111111111",
  current: {
    workspace: {
      id: "22222222-2222-4222-8222-222222222222",
      kind: "personal",
      name: "个人空间",
    },
    project: {
      id: "33333333-3333-4333-8333-333333333333",
      name: "校园推广",
    },
    questionnaireVersion: {
      id: "44444444-4444-4444-8444-444444444444",
      versionNumber: 1,
    },
  },
  capabilities: ["export_target_pii", "view_assigned_target_pii"],
};

test("recent password identity prepares exact bytes for the trusted project", async () => {
  const bytes = Buffer.from("{\"display_name\":\"张三\"}", "utf8");
  let received: readonly unknown[] | undefined;
  const result = await exportPersonalTargetPii(request(), {
    identityVerifier: {verify: async () => identity},
    contextStore: {loadOrCreate: async () => context},
    exportStore: {
      prepare: async (...values) => {
        received = values;
        return bytes;
      },
    },
    now: () => now,
  });

  assert.deepEqual(received, [
    identity,
    context.current.project.id,
    identity.passwordAuthenticatedAtUnixSeconds,
  ]);
  assert.equal(result.status, 200);
  assert.ok("bytes" in result);
  assert.equal(result.bytes, bytes);
});

test("identity and recent password checks precede request shape and context", async () => {
  let contextCalls = 0;
  const contextStore = {
    loadOrCreate: async () => {
      contextCalls += 1;
      return context;
    },
  };
  const cases = [
    {
      authorization: undefined,
      verifier: {verify: async () => assert.fail("missing bearer must not verify")},
      expectedStatus: 401,
      expectedCode: "unauthenticated",
    },
    {
      authorization: "Bearer invalid",
      verifier: {
        verify: async () => {throw new IdentityVerificationError();},
      },
      expectedStatus: 401,
      expectedCode: "unauthenticated",
    },
    {
      authorization: "Bearer unavailable",
      verifier: {
        verify: async () => {
          throw new IdentityVerificationError("unavailable");
        },
      },
      expectedStatus: 503,
      expectedCode: "personal_target_pii_export_unavailable",
    },
    {
      authorization: "Bearer no-password",
      verifier: {verify: async () => ({issuer: "issuer", subject: "subject"})},
      expectedStatus: 403,
      expectedCode: "reauthentication_required",
    },
  ] as const;

  for (const item of cases) {
    const result = await exportPersonalTargetPii(
      {
        authorization: item.authorization,
        hasQuery: true,
        hasBody: true,
      },
      {
        identityVerifier: item.verifier,
        contextStore,
        now: () => now,
      },
    );
    assert.deepEqual(result, {
      status: item.expectedStatus,
      body: {error: {code: item.expectedCode}},
    });
  }
  assert.equal(contextCalls, 0);

  for (const shape of [
    {hasQuery: true, hasBody: false},
    {hasQuery: false, hasBody: true},
  ]) {
    const result = await exportPersonalTargetPii(
      {...request(), ...shape},
      {
        identityVerifier: {verify: async () => identity},
        contextStore,
        now: () => now,
      },
    );
    assert.deepEqual(result, {
      status: 400,
      body: {
        error: {code: "invalid_personal_target_pii_export_request"},
      },
    });
  }
  assert.equal(contextCalls, 0);
});

test("recent password uses the exact half-open clock-skew window", async () => {
  const cases = [
    {timestamp: nowSeconds + 60, status: 503},
    {timestamp: nowSeconds + 61, status: 403},
    {timestamp: nowSeconds - 899, status: 503},
    {timestamp: nowSeconds - 900, status: 403},
  ] as const;
  for (const item of cases) {
    const result = await exportPersonalTargetPii(request(), {
      identityVerifier: {
        verify: async () => ({
          issuer: identity.issuer,
          subject: identity.subject,
          passwordAuthenticatedAtUnixSeconds: item.timestamp,
        }),
      },
      contextStore: {loadOrCreate: async () => context},
      now: () => now,
    });
    assert.equal(result.status, item.status, String(item.timestamp));
  }
});

test("only a personal context with both capabilities may reach the store", async () => {
  let storeCalls = 0;
  for (const deniedContext of [
    {...context, capabilities: ["export_target_pii"]},
    {...context, capabilities: ["view_assigned_target_pii"]},
    {
      ...context,
      current: {
        ...context.current,
        workspace: {...context.current.workspace, kind: "organization" as const},
      },
    },
  ]) {
    const result = await exportPersonalTargetPii(request(), {
      identityVerifier: {verify: async () => identity},
      contextStore: {loadOrCreate: async () => deniedContext},
      exportStore: {
        prepare: async () => {
          storeCalls += 1;
          throw new Error("must not prepare");
        },
      },
      now: () => now,
    });
    assert.deepEqual(result, {
      status: 403,
      body: {error: {code: "personal_target_pii_export_forbidden"}},
    });
  }
  assert.equal(storeCalls, 0);

  const unavailable = await exportPersonalTargetPii(request(), {
    identityVerifier: {verify: async () => identity},
    contextStore: {loadOrCreate: async () => {throw new Error("secret");}},
    now: () => now,
  });
  assert.deepEqual(unavailable, {
    status: 503,
    body: {error: {code: "personal_target_pii_export_unavailable"}},
  });
  assert.doesNotMatch(JSON.stringify(unavailable), /secret/);
});

test("stable store failures become value-free HTTP errors", async () => {
  for (const item of [
    {
      error: new PersonalTargetPiiExportStoreError("reauthentication_required"),
      status: 403,
      code: "reauthentication_required",
    },
    {
      error: new PersonalTargetPiiExportStoreError("forbidden"),
      status: 403,
      code: "personal_target_pii_export_forbidden",
    },
    {
      error: new Error("secret database detail"),
      status: 503,
      code: "personal_target_pii_export_unavailable",
    },
  ]) {
    const result = await exportPersonalTargetPii(request(), {
      identityVerifier: {verify: async () => identity},
      contextStore: {loadOrCreate: async () => context},
      exportStore: {prepare: async () => {throw item.error;}},
      now: () => now,
    });
    assert.deepEqual(result, {
      status: item.status,
      body: {error: {code: item.code}},
    });
    assert.doesNotMatch(JSON.stringify(result), /secret|database/);
  }
});

test("Postgres store calls one bridge and returns its Buffer unchanged", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const bytes = Buffer.from([0, 1, 2, 255]);
  const store = new PostgresPersonalTargetPiiExportStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{export_bytes: bytes}]};
    },
  );

  const result = await store.prepare(
    identity,
    context.current.project.id,
    identity.passwordAuthenticatedAtUnixSeconds,
  );

  assert.equal(result, bytes);
  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.prepare_personal_target_pii_export_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    context.current.project.id,
    identity.passwordAuthenticatedAtUnixSeconds,
  ]);
});

test("Postgres store rejects non-Buffer results and maps only exact errors", async () => {
  for (const rows of [[], [{export_bytes: "not-bytes"}], [{other: Buffer.alloc(0)}]]) {
    const store = new PostgresPersonalTargetPiiExportStore(async () => ({rows}));
    await assert.rejects(
      store.prepare(identity, context.current.project.id, nowSeconds),
      /invalid personal target PII export result/,
    );
  }

  for (const item of [
    {
      database: Object.assign(new Error(
        "invalid personal target PII export authentication evidence",
      ), {code: "22023"}),
      expected: "reauthentication_required",
    },
    {
      database: Object.assign(new Error(
        "personal target PII export scope is forbidden",
      ), {code: "42501"}),
      expected: "forbidden",
    },
  ]) {
    const store = new PostgresPersonalTargetPiiExportStore(async () => {
      throw item.database;
    });
    await assert.rejects(
      store.prepare(identity, context.current.project.id, nowSeconds),
      (error: unknown) =>
        error instanceof PersonalTargetPiiExportStoreError &&
        error.code === item.expected &&
        !error.message.includes("personal target"),
    );
  }
});

function request() {
  return {
    authorization: "Bearer token",
    hasQuery: false,
    hasBody: false,
  };
}
