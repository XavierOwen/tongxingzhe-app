import assert from "node:assert/strict";
import test from "node:test";

import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";
import {
  OrganizationDirectoryStoreError,
  PostgresOrganizationDirectoryStore,
  listOrganizationDirectory,
} from "../src/organization-directory.js";

const identity: VerifiedIdentity = {
  issuer: "https://directory.synthetic/auth/v1",
  subject: "active-member",
};
const firstWorkspaceId = "123e4567-e89b-12d3-a456-426614174001";
const secondWorkspaceId = "123e4567-e89b-12d3-a456-426614174002";

test("directory authenticates before request and dependency validation", async () => {
  let verifyCalls = 0;
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {
      verify: async () => {
        verifyCalls += 1;
        return identity;
      },
    },
    organizationDirectoryStore: {
      list: async () => {
        storeCalls += 1;
        return [];
      },
    },
  };

  assert.deepEqual(
    await listOrganizationDirectory(
      {
        authorization: undefined,
        hasQuery: true,
        hasBody: true,
      },
      dependencies,
    ),
    { status: 401, body: { error: { code: "unauthenticated" } } },
  );
  assert.equal(verifyCalls, 0);

  for (const request of [
    { hasQuery: true, hasBody: false },
    { hasQuery: false, hasBody: true },
    { hasQuery: true, hasBody: true },
  ]) {
    assert.deepEqual(
      await listOrganizationDirectory(
        { authorization: "Bearer token", ...request },
        dependencies,
      ),
      {
        status: 400,
        body: { error: { code: "invalid_organization_directory_request" } },
      },
    );
  }
  assert.equal(verifyCalls, 3);
  assert.equal(storeCalls, 0);

  assert.deepEqual(
    await listOrganizationDirectory(
      {
        authorization: "Bearer token",
        hasQuery: false,
        hasBody: false,
      },
      { identityVerifier: dependencies.identityVerifier },
    ),
    {
      status: 503,
      body: { error: { code: "organization_directory_unavailable" } },
    },
  );
  assert.equal(verifyCalls, 4);
});

test("directory maps generic identity failures without exposing details", async () => {
  for (const [error, status, code] of [
    [new IdentityVerificationError("unauthenticated"), 401, "unauthenticated"],
    [
      new IdentityVerificationError("unavailable"),
      503,
      "organization_directory_unavailable",
    ],
    [new Error("secret provider detail"), 503, "organization_directory_unavailable"],
  ] as const) {
    let storeCalls = 0;
    const result = await listOrganizationDirectory(
      {
        authorization: "Bearer token",
        hasQuery: true,
        hasBody: true,
      },
      {
        identityVerifier: { verify: async () => { throw error; } },
        organizationDirectoryStore: {
          list: async () => {
            storeCalls += 1;
            return [];
          },
        },
      },
    );
    assert.deepEqual(result, { status, body: { error: { code } } });
    assert.doesNotMatch(JSON.stringify(result), /secret|provider/);
    assert.equal(storeCalls, 0);
  }
});

test("directory awaits one store call and returns the exact wire", async () => {
  let releaseList: (() => void) | undefined;
  let markListStarted: (() => void) | undefined;
  const listStarted = new Promise<void>((resolve) => {
    markListStarted = resolve;
  });
  const listGate = new Promise<void>((resolve) => {
    releaseList = resolve;
  });
  let storeCalls = 0;
  const resultPromise = listOrganizationDirectory(
    {
      authorization: "Bearer token",
      hasQuery: false,
      hasBody: false,
    },
    {
      identityVerifier: { verify: async () => identity },
      organizationDirectoryStore: {
        async list(receivedIdentity) {
          storeCalls += 1;
          assert.deepEqual(receivedIdentity, identity);
          markListStarted?.();
          await listGate;
          return [
            {
              organizationWorkspaceId: firstWorkspaceId,
              organizationName: "  同行者  ",
            },
          ];
        },
      },
    },
  );
  let settled = false;
  void resultPromise.then(() => { settled = true; });
  await listStarted;
  assert.equal(settled, false);
  assert.equal(storeCalls, 1);
  releaseList?.();

  assert.deepEqual(await resultPromise, {
    status: 200,
    body: {
      organization_directory_contract_id: "organization-directory:v1",
      organizations: [{
        organization_workspace_id: firstWorkspaceId,
        organization_name: "  同行者  ",
      }],
    },
  });

  assert.deepEqual(
    await listOrganizationDirectory(
      {
        authorization: "Bearer token",
        hasQuery: false,
        hasBody: false,
      },
      {
        identityVerifier: { verify: async () => identity },
        organizationDirectoryStore: { list: async () => [] },
      },
    ),
    {
      status: 200,
      body: {
        organization_directory_contract_id: "organization-directory:v1",
        organizations: [],
      },
    },
  );
});

test("directory maps only the dedicated forbidden store failure to 403", async () => {
  const request = {
    authorization: "Bearer token",
    hasQuery: false,
    hasBody: false,
  };
  const identityVerifier = { verify: async () => identity };

  for (const [error, status, code] of [
    [
      new OrganizationDirectoryStoreError("organization_directory_forbidden"),
      403,
      "organization_directory_forbidden",
    ],
    [
      new OrganizationDirectoryStoreError("organization_directory_unavailable"),
      503,
      "organization_directory_unavailable",
    ],
    [
      new Error("secret SQL identity and parser detail"),
      503,
      "organization_directory_unavailable",
    ],
  ] as const) {
    const result = await listOrganizationDirectory(request, {
      identityVerifier,
      organizationDirectoryStore: { list: async () => { throw error; } },
    });
    assert.deepEqual(result, { status, body: { error: { code } } });
    assert.doesNotMatch(JSON.stringify(result), /secret|SQL|identity|parser/);
  }
});

test("PostgreSQL store calls one fixed reader and preserves database order and names", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const store = new PostgresOrganizationDirectoryStore(async (text, values) => {
    calls.push({ text, values });
    return {
      rows: [
        {
          organization_workspace_id: firstWorkspaceId,
          organization_name: "Zeta",
        },
        {
          organization_workspace_id: secondWorkspaceId,
          organization_name: "   同行者   ",
        },
      ],
    };
  });

  assert.deepEqual(await store.list(identity), [
    {
      organizationWorkspaceId: firstWorkspaceId,
      organizationName: "Zeta",
    },
    {
      organizationWorkspaceId: secondWorkspaceId,
      organizationName: "   同行者   ",
    },
  ]);
  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /SELECT\s+organization_workspace_id,\s+organization_name\s+FROM app_data\.list_organizations_for_identity_v1\(\$1::text, \$2::text\)/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT|LIMIT/i);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject]);
});

test("PostgreSQL store accepts empty and unpaged results", async () => {
  const empty = new PostgresOrganizationDirectoryStore(
    async () => ({ rows: [] }),
  );
  assert.deepEqual(await empty.list(identity), []);

  const rows = Array.from({ length: 25 }, (_, index) => ({
    organization_workspace_id:
      `123e4567-e89b-12d3-a456-${String(index).padStart(12, "0")}`,
    organization_name: `Organization ${index}`,
  }));
  const unpaged = new PostgresOrganizationDirectoryStore(
    async () => ({ rows }),
  );
  assert.equal((await unpaged.list(identity)).length, rows.length);
});

test("PostgreSQL store rejects uppercase UUIDs, malformed rows, and duplicates", async () => {
  const validRow = {
    organization_workspace_id: firstWorkspaceId,
    organization_name: "Organization",
  };
  const invalidRows: readonly (readonly unknown[])[] = [
    [null],
    [[]],
    [{}],
    [{ ...validRow, private_member_count: 1 }],
    [{ organization_name: "Organization" }],
    [{ ...validRow, organization_workspace_id: "not-a-uuid" }],
    [{
      ...validRow,
      organization_workspace_id: firstWorkspaceId.toUpperCase(),
    }],
    [{ ...validRow, organization_name: null }],
    [{ ...validRow, organization_name: "" }],
    [{ ...validRow, organization_name: "   " }],
    [validRow, validRow],
  ];

  for (const rows of invalidRows) {
    const store = new PostgresOrganizationDirectoryStore(
      async () => ({ rows }),
    );
    await assert.rejects(
      store.list(identity),
      (error: unknown) =>
        error instanceof OrganizationDirectoryStoreError &&
        error.code === "organization_directory_unavailable" &&
        error.message === "organization_directory_unavailable",
    );
  }
});

test("PostgreSQL store maps only exact database errors", async () => {
  for (const [databaseError, expectedCode] of [
    [
      Object.assign(new Error("organization directory forbidden"), {
        code: "42501",
      }),
      "organization_directory_forbidden",
    ],
    [
      Object.assign(new Error("invalid organization directory identity"), {
        code: "22023",
      }),
      "organization_directory_unavailable",
    ],
    [
      Object.assign(new Error("different forbidden detail"), { code: "42501" }),
      "organization_directory_unavailable",
    ],
    [new Error("database secret"), "organization_directory_unavailable"],
  ] as const) {
    const store = new PostgresOrganizationDirectoryStore(async () => {
      throw databaseError;
    });
    await assert.rejects(store.list(identity), (error: unknown) => {
      assert.ok(error instanceof OrganizationDirectoryStoreError);
      assert.equal(error.code, expectedCode);
      assert.equal(error.message, expectedCode);
      assert.doesNotMatch(error.message, /forbidden detail|database secret/);
      return true;
    });
  }
});
