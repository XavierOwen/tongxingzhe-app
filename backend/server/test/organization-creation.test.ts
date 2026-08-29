import assert from "node:assert/strict";
import test from "node:test";
import {
  handleOrganizationCreation,
  OrganizationCreationStoreError,
  parseOrganizationCreationBody,
  PostgresOrganizationCreationStore,
  type OrganizationCreationDependencies,
  type OrganizationCreationRequest,
  type OrganizationCreationResult,
  type OrganizationCreationStore,
} from "../src/organization-creation.js";
import {
  OrganizationCreationIdentityError,
  type OrganizationCreationEligibility,
} from "../src/organization-creation-identity.js";

const requestId = "123e4567-e89b-12d3-a456-426614174000";
const identity: OrganizationCreationEligibility = {
  issuer: "https://issuer.example",
  subject: "subject-123",
  purpose: "organization_creation",
};
const creationResult: OrganizationCreationResult = {
  creationContractId: "organization-creation:v1",
  organizationWorkspaceId: "123e4567-e89b-12d3-a456-426614174001",
  organizationMembershipId: "123e4567-e89b-12d3-a456-426614174002",
  organizationOwnerAssignmentId: "123e4567-e89b-12d3-a456-426614174003",
  createdAtUtc: "2030-01-01T00:00:00.000Z",
};

function validRequest(
  body: unknown,
  overrides: Partial<OrganizationCreationRequest> = {},
): OrganizationCreationRequest {
  return {
    authorization: "Bearer access-token",
    hasQuery: false,
    readBody: async () => body,
    ...overrides,
  };
}

function verifier(
  value: OrganizationCreationEligibility = identity,
): NonNullable<OrganizationCreationDependencies["identityVerifier"]> {
  return {
    verify: async () => value,
  };
}

function store(
  create: OrganizationCreationStore["create"],
): OrganizationCreationStore {
  return { create };
}

test("handler runs verifier, query, body parser, then one store call", async () => {
  const events: string[] = [];
  const displayName = "  原样 Name  ";
  let received: [OrganizationCreationEligibility, string, string] | undefined;

  const result = await handleOrganizationCreation(
    validRequest({ request_id: requestId, display_name: displayName }, {
      readBody: async () => {
        events.push("body");
        return { request_id: requestId, display_name: displayName };
      },
    }),
    {
      identityVerifier: {
        verify: async (token) => {
          assert.equal(token, "access-token");
          events.push("identity");
          return identity;
        },
      },
      creationStore: store(async (...args) => {
        events.push("store");
        received = args;
        return creationResult;
      }),
    },
  );

  assert.deepEqual(events, ["identity", "body", "store"]);
  assert.deepEqual(received, [identity, requestId, displayName]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      creation_contract_id: "organization-creation:v1",
      organization_workspace_id: creationResult.organizationWorkspaceId,
      organization_membership_id: creationResult.organizationMembershipId,
      organization_owner_assignment_id:
        creationResult.organizationOwnerAssignmentId,
      created_at_utc: creationResult.createdAtUtc,
    },
  });
});

test("missing bearer token stops before verifier, body, and store", async () => {
  let verifierCalls = 0;
  let bodyCalls = 0;
  let storeCalls = 0;

  const result = await handleOrganizationCreation(
    validRequest({}, {
      authorization: undefined,
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    }),
    {
      identityVerifier: {
        verify: async () => {
          verifierCalls += 1;
          return identity;
        },
      },
      creationStore: store(async () => {
        storeCalls += 1;
        return creationResult;
      }),
    },
  );

  assert.deepEqual(result, {
    status: 401,
    body: { error: { code: "unauthenticated" } },
  });
  assert.equal(verifierCalls, 0);
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);
});

test("missing verifier is unavailable after bearer parsing and before body", async () => {
  let bodyCalls = 0;
  const result = await handleOrganizationCreation(
    validRequest({}, {
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    }),
    { identityVerifier: undefined, creationStore: undefined },
  );

  assert.deepEqual(result, {
    status: 503,
    body: { error: { code: "organization_creation_unavailable" } },
  });
  assert.equal(bodyCalls, 0);
});

test("dedicated verifier categories stop before query, body, and store", async () => {
  const cases = [
    ["unauthenticated", 401, "unauthenticated"],
    ["forbidden", 403, "organization_creation_forbidden"],
    ["unavailable", 503, "organization_creation_unavailable"],
  ] as const;

  for (const [category, status, code] of cases) {
    let bodyCalls = 0;
    let storeCalls = 0;
    const result = await handleOrganizationCreation(
      validRequest({}, {
        readBody: async () => {
          bodyCalls += 1;
          return {};
        },
      }),
      {
        identityVerifier: {
          verify: async () => {
            throw new OrganizationCreationIdentityError(category);
          },
        },
        creationStore: store(async () => {
          storeCalls += 1;
          return creationResult;
        }),
      },
    );

    assert.deepEqual(result, { status, body: { error: { code } } });
    assert.equal(bodyCalls, 0);
    assert.equal(storeCalls, 0);
  }
});

test("query presence is checked after verifier and before body or store", async () => {
  let bodyCalls = 0;
  let storeCalls = 0;
  const result = await handleOrganizationCreation(
    validRequest({}, {
      hasQuery: true,
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    }),
    {
      identityVerifier: verifier(),
      creationStore: store(async () => {
        storeCalls += 1;
        return creationResult;
      }),
    },
  );

  assert.deepEqual(result, {
    status: 400,
    body: { error: { code: "invalid_organization_creation_request" } },
  });
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);
});

test("missing store is checked after verifier and query but before body", async () => {
  let bodyCalls = 0;
  const result = await handleOrganizationCreation(
    validRequest({}, {
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    }),
    { identityVerifier: verifier(), creationStore: undefined },
  );

  assert.deepEqual(result, {
    status: 503,
    body: { error: { code: "organization_creation_unavailable" } },
  });
  assert.equal(bodyCalls, 0);
});

test("body parser requires exactly request_id and display_name and preserves values", async () => {
  const displayName = "  原样 Name  ";
  assert.deepEqual(
    parseOrganizationCreationBody({ request_id: requestId, display_name: displayName }),
    { requestId, displayName },
  );

  const invalidBodies: unknown[] = [
    null,
    [],
    {},
    { request_id: requestId },
    { display_name: displayName },
    { request_id: requestId, display_name: displayName, extra: true },
    { request_id: "not-a-uuid", display_name: displayName },
    { request_id: 123, display_name: displayName },
    { request_id: requestId, display_name: 123 },
  ];

  for (const body of invalidBodies) {
    let storeCalls = 0;
    const result = await handleOrganizationCreation(validRequest(body), {
      identityVerifier: verifier(),
      creationStore: store(async () => {
        storeCalls += 1;
        return creationResult;
      }),
    });
    assert.deepEqual(result, {
      status: 400,
      body: { error: { code: "invalid_organization_creation_request" } },
    });
    assert.equal(storeCalls, 0);
  }
});

test("postgres store makes one parameterized bridge call and parses five fields", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const storeAdapter = new PostgresOrganizationCreationStore(async (text, values) => {
    calls.push({ text, values });
    return {
      rows: [
        {
          creation_contract_id: "organization-creation:v1",
          organization_workspace_id: creationResult.organizationWorkspaceId,
          organization_membership_id: creationResult.organizationMembershipId,
          organization_owner_assignment_id:
            creationResult.organizationOwnerAssignmentId,
          created_at_utc: "2030-01-01T01:00:00.000000+01:00",
        },
      ],
    };
  });

  const result = await storeAdapter.create(identity, requestId, "  原样 Name  ");

  assert.equal(calls.length, 1);
  assert.match(calls[0]?.text ?? "", /app_data\.create_organization_for_identity_v1/);
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private/);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject, requestId, "  原样 Name  "]);
  assert.deepEqual(result, {
    ...creationResult,
    createdAtUtc: "2030-01-01T00:00:00.000Z",
  });
});

test("postgres store rejects non-exact result rows without exposing details", async () => {
  const validRow = {
    creation_contract_id: "organization-creation:v1",
    organization_workspace_id: creationResult.organizationWorkspaceId,
    organization_membership_id: creationResult.organizationMembershipId,
    organization_owner_assignment_id: creationResult.organizationOwnerAssignmentId,
    created_at_utc: creationResult.createdAtUtc,
  };
  const rows: readonly unknown[][] = [
    [],
    [validRow, validRow],
    [{ ...validRow, extra: true }],
    [{ ...validRow, creation_contract_id: "wrong" }],
    [{ ...validRow, organization_workspace_id: "wrong" }],
    [{ ...validRow, created_at_utc: "wrong" }],
  ];

  for (const resultRows of rows) {
    const storeAdapter = new PostgresOrganizationCreationStore(async () => ({
      rows: resultRows,
    }));
    await assert.rejects(
      storeAdapter.create(identity, requestId, "Name"),
      (error: unknown) =>
        error instanceof Error &&
        error.message === "organization creation store unavailable",
    );
  }
});

test("postgres store maps only exact SQLSTATE and message pairs", async () => {
  const cases = [
    ["22023", "invalid organization creation identity", "organization_creation_unavailable"],
    ["22023", "invalid organization creation request", "invalid_organization_creation_request"],
    ["42501", "organization creation forbidden", "organization_creation_forbidden"],
    ["22023", "organization creation idempotency conflict", "organization_creation_conflict"],
  ] as const;

  for (const [sqlState, message, expectedCode] of cases) {
    const storeAdapter = new PostgresOrganizationCreationStore(async () => {
      throw Object.assign(new Error(message), { code: sqlState });
    });
    await assert.rejects(
      storeAdapter.create(identity, requestId, "Name"),
      (error: unknown) =>
        error instanceof OrganizationCreationStoreError &&
        error.code === expectedCode,
    );
  }

  const unknownStoreError = new PostgresOrganizationCreationStore(async () => {
    throw Object.assign(new Error("secret database detail"), {
      code: "22023",
    });
  });
  await assert.rejects(
    unknownStoreError.create(identity, requestId, "Name"),
    (error: unknown) =>
      error instanceof Error &&
      error.message === "organization creation store unavailable" &&
      !error.message.includes("secret database detail"),
  );
});

test("handler maps store failures to the four stable HTTP outcomes", async () => {
  const cases = [
    ["organization_creation_unavailable", 503],
    ["invalid_organization_creation_request", 400],
    ["organization_creation_forbidden", 403],
    ["organization_creation_conflict", 409],
  ] as const;

  for (const [code, status] of cases) {
    const result = await handleOrganizationCreation(
      validRequest({ request_id: requestId, display_name: "Name" }),
      {
        identityVerifier: verifier(),
        creationStore: store(async () => {
          throw new OrganizationCreationStoreError(code);
        }),
      },
    );
    assert.deepEqual(result, { status, body: { error: { code } } });
  }
});

test("first creation and same-request replay both return the exact 200 contract", async () => {
  let storeCalls = 0;
  const dependencies: OrganizationCreationDependencies = {
    identityVerifier: verifier(),
    creationStore: store(async () => {
      storeCalls += 1;
      return creationResult;
    }),
  };
  const request = validRequest({ request_id: requestId, display_name: "Name" });

  const first = await handleOrganizationCreation(request, dependencies);
  const replay = await handleOrganizationCreation(request, dependencies);

  assert.deepEqual(first, replay);
  assert.equal(first.status, 200);
  assert.deepEqual(Object.keys(first.body).sort(), [
    "created_at_utc",
    "creation_contract_id",
    "organization_membership_id",
    "organization_owner_assignment_id",
    "organization_workspace_id",
  ]);
  assert.equal("replayed" in first.body, false);
  assert.equal(storeCalls, 2);
});
