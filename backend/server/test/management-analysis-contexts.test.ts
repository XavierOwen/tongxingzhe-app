import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementAnalysisContextStoreError,
  PostgresManagementAnalysisContextStore,
  getManagementAnalysisContext,
  selectManagementAnalysisContext,
} from "../src/management-analysis-contexts.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-viewer",
};
const firstProjectId = "33333333-3333-4333-8333-333333333333";
const secondProjectId = "44444444-4444-4444-8444-444444444444";
const rows = [
  {
    organization_workspace_id: "22222222-2222-4222-8222-222222222222",
    organization_name: "Synthetic organization",
    project_id: firstProjectId,
    project_name: "First project",
    is_current: false,
  },
  {
    organization_workspace_id: "22222222-2222-4222-8222-222222222222",
    organization_name: "Synthetic organization",
    project_id: secondProjectId,
    project_name: "Second project",
    is_current: true,
  },
];

test("GET context passes only verified identity and returns navigation data", async () => {
  let receivedIdentity: unknown;
  const result = await getManagementAnalysisContext("Bearer token", {
    identityVerifier: {verify: async () => identity},
    contextStore: {
      load: async (value) => {
        receivedIdentity = value;
        return {
          current: contextFromRow(rows[1]!),
          available: rows.map(contextFromRow),
        };
      },
      select: async () => {throw new Error("select must not run");},
    },
  });

  assert.deepEqual(receivedIdentity, identity);
  assert.deepEqual(result, {
    status: 200,
    body: {
      current_context: serializedContext(rows[1]!),
      available_contexts: rows.map(serializedContext),
      authorization: "must_reauthorize",
    },
  });
  assert.doesNotMatch(
    JSON.stringify(result),
    /app_user|subject|membership|grant|snapshot|report/,
  );
});

test("GET context returns an explicit empty state", async () => {
  const result = await getManagementAnalysisContext("Bearer token", {
    identityVerifier: {verify: async () => identity},
    contextStore: {
      load: async () => ({current: null, available: []}),
      select: async () => {throw new Error("select must not run");},
    },
  });

  assert.deepEqual(result, {
    status: 200,
    body: {
      current_context: null,
      available_contexts: [],
      authorization: "must_reauthorize",
    },
  });
});

test("authentication precedes exact selection body validation", async () => {
  let identityCalls = 0;
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {
      verify: async () => {
        identityCalls += 1;
        return identity;
      },
    },
    contextStore: {
      load: async () => {
        storeCalls += 1;
        return {current: null, available: []};
      },
      select: async () => {
        storeCalls += 1;
        throw new Error("store must not run");
      },
    },
  };

  assert.deepEqual(await getManagementAnalysisContext(undefined, dependencies), {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  for (const body of [
    null,
    {},
    {project_id: "not-a-uuid"},
    {project_id: firstProjectId, app_user_id: "forged"},
    {project_id: firstProjectId, capability: "release_management_reports"},
  ]) {
    assert.deepEqual(
      await selectManagementAnalysisContext("Bearer token", body, dependencies),
      {
        status: 400,
        body: {error: {code: "invalid_management_analysis_context"}},
      },
    );
  }
  assert.equal(identityCalls, 5);
  assert.equal(storeCalls, 0);
});

test("invalid identity hides selection body errors from the store", async () => {
  let storeCalls = 0;
  const result = await selectManagementAnalysisContext(
    "Bearer invalid",
    {project_id: firstProjectId, app_user_id: "forged"},
    {
      identityVerifier: {
        verify: async () => {throw new IdentityVerificationError();},
      },
      contextStore: {
        load: async () => {
          storeCalls += 1;
          return {current: null, available: []};
        },
        select: async () => {
          storeCalls += 1;
          return {current: null, available: []};
        },
      },
    },
  );

  assert.deepEqual(result, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(storeCalls, 0);
});

test("invalid token, forbidden selection, and store failures are stable", async () => {
  const invalidToken = await getManagementAnalysisContext("Bearer invalid", {
    identityVerifier: {
      verify: async () => {throw new IdentityVerificationError();},
    },
    contextStore: {
      load: async () => {throw new Error("store must not run");},
      select: async () => {throw new Error("store must not run");},
    },
  });
  assert.deepEqual(invalidToken, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });

  for (const value of [
    {
      error: new ManagementAnalysisContextStoreError("forbidden"),
      status: 403,
      code: "management_analysis_context_forbidden",
    },
    {
      error: new Error("secret database message"),
      status: 503,
      code: "management_analysis_context_unavailable",
    },
  ]) {
    const result = await selectManagementAnalysisContext(
      "Bearer token",
      {project_id: firstProjectId},
      {
        identityVerifier: {verify: async () => identity},
        contextStore: {
          load: async () => {throw new Error("load must not run");},
          select: async () => {throw value.error;},
        },
      },
    );
    assert.deepEqual(result, {
      status: value.status,
      body: {error: {code: value.code}},
    });
    assert.doesNotMatch(JSON.stringify(result), /secret|database/);
  }
});

test("Postgres store uses one narrow list query and parses one current row", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementAnalysisContextStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows};
    },
  );

  const result = await store.load(identity);

  assert.equal(calls.length, 1);
  assert.match(calls[0]?.text ?? "", /list_management_analysis_contexts_v1/);
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject]);
  assert.deepEqual(result, {
    current: contextFromRow(rows[1]!),
    available: rows.map(contextFromRow),
  });
});

test("Postgres selection uses one narrow query with the requested project", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementAnalysisContextStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{...rows[0]!, is_current: true}]};
    },
  );

  const result = await store.select(identity, firstProjectId);

  assert.equal(calls.length, 1);
  assert.match(calls[0]?.text ?? "", /select_management_analysis_context_v1/);
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    firstProjectId,
  ]);
  assert.deepEqual(result, {
    current: contextFromRow(rows[0]!),
    available: [contextFromRow(rows[0]!)],
  });
});

test("Postgres context parser fails closed and hides 42501 messages", async () => {
  for (const badRows of [
    [{...rows[0]!, unexpected: "field"}],
    [{...rows[0]!, project_id: "not-a-uuid"}],
    [{...rows[0]!, is_current: true}, {...rows[1]!, is_current: true}],
    [rows[0]!, {...rows[0]!}],
  ]) {
    const store = new PostgresManagementAnalysisContextStore(
      async () => ({rows: badRows}),
    );
    await assert.rejects(store.load(identity), /invalid management analysis context/);
  }

  const databaseError = Object.assign(new Error("authorization detail"), {
    code: "42501",
  });
  const forbiddenStore = new PostgresManagementAnalysisContextStore(
    async () => {throw databaseError;},
  );
  await assert.rejects(
    forbiddenStore.load(identity),
    (error: unknown) =>
      error instanceof ManagementAnalysisContextStoreError &&
      error.code === "forbidden" &&
      !error.message.includes("authorization detail"),
  );
});

function contextFromRow(row: typeof rows[number]) {
  return {
    organization: {
      id: row.organization_workspace_id,
      name: row.organization_name,
    },
    project: {id: row.project_id, name: row.project_name},
  };
}

function serializedContext(row: typeof rows[number]) {
  return {
    organization: {
      workspace_id: row.organization_workspace_id,
      name: row.organization_name,
    },
    project: {project_id: row.project_id, name: row.project_name},
  };
}
