import assert from "node:assert/strict";
import test from "node:test";
import {
  handleOrganizationOwnerTransfer,
  matchOrganizationOwnerTransferRequestTarget,
  OrganizationOwnerTransferStoreError,
  parseOrganizationOwnerTransferBody,
  parseOrganizationOwnerTransferResult,
  PostgresOrganizationOwnerTransferStore,
  type OrganizationOwnerTransferDependencies,
  type OrganizationOwnerTransferRequest,
  type OrganizationOwnerTransferResult,
  type OrganizationOwnerTransferStore,
} from "../src/organization-owner-transfer.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "../src/identity.js";

const requestId = "123e4567-e89b-12d3-a456-426614174000";
const workspaceId = "123e4567-e89b-12d3-a456-426614174001";
const targetMembershipId = "123e4567-e89b-12d3-a456-426614174002";
const previousAssignmentId = "123e4567-e89b-12d3-a456-426614174003";
const newAssignmentId = "123e4567-e89b-12d3-a456-426614174004";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const transferResult: OrganizationOwnerTransferResult = {
  ownerTransferContractId: "organization-owner-transfer:v1",
  organizationWorkspaceId: workspaceId,
  previousOwnerAssignmentId: previousAssignmentId,
  organizationOwnerAssignmentId: newAssignmentId,
  effectiveAtUtc: "2030-01-01T00:00:00.000Z",
};

function validRequest(
  body: unknown,
  overrides: Partial<OrganizationOwnerTransferRequest> = {},
): OrganizationOwnerTransferRequest {
  return {
    authorization: "Bearer access-token",
    workspaceId,
    hasQuery: false,
    readBody: async () => body,
    ...overrides,
  };
}

function verifier(
  value: VerifiedIdentity = identity,
): IdentityVerifier {
  return { verify: async () => value };
}

function store(
  transfer: OrganizationOwnerTransferStore["transfer"],
): OrganizationOwnerTransferStore {
  return { transfer };
}

test("handler verifies, validates, reads, and transfers in the fixed order", async () => {
  const events: string[] = [];
  let received:
    | [VerifiedIdentity, string, string, string]
    | undefined;

  const result = await handleOrganizationOwnerTransfer(
    validRequest(
      {
        request_id: requestId.toUpperCase(),
        target_organization_membership_id: targetMembershipId.toUpperCase(),
      },
      {
        workspaceId: workspaceId.toUpperCase(),
        readBody: async () => {
          events.push("body");
          return {
            request_id: requestId.toUpperCase(),
            target_organization_membership_id: targetMembershipId.toUpperCase(),
          };
        },
      },
    ),
    {
      identityVerifier: {
        verify: async (token) => {
          assert.equal(token, "access-token");
          events.push("verifier");
          return identity;
        },
      },
      transferStore: store(async (...args) => {
        events.push("store");
        received = args;
        return transferResult;
      }),
    },
  );

  assert.deepEqual(events, ["verifier", "body", "store"]);
  assert.deepEqual(received, [identity, requestId, workspaceId, targetMembershipId]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      owner_transfer_contract_id: "organization-owner-transfer:v1",
      organization_workspace_id: workspaceId,
      previous_owner_assignment_id: previousAssignmentId,
      organization_owner_assignment_id: newAssignmentId,
      effective_at_utc: "2030-01-01T00:00:00.000Z",
    },
  });
});

test("missing bearer, verifier, and verifier failures stop before body or store", async () => {
  let verifierCalls = 0;
  let bodyCalls = 0;
  let storeCalls = 0;
  const bodyRequest = validRequest({}, {
    authorization: undefined,
    readBody: async () => {
      bodyCalls += 1;
      return {};
    },
  });

  const missingBearer = await handleOrganizationOwnerTransfer(bodyRequest, {
    identityVerifier: {
      verify: async () => {
        verifierCalls += 1;
        return identity;
      },
    },
    transferStore: store(async () => {
      storeCalls += 1;
      return transferResult;
    }),
  });
  assert.deepEqual(missingBearer, {
    status: 401,
    body: { error: { code: "unauthenticated" } },
  });
  assert.equal(verifierCalls, 0);
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);

  const missingVerifier = await handleOrganizationOwnerTransfer(
    validRequest({}, {
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    }),
    { identityVerifier: undefined, transferStore: undefined },
  );
  assert.deepEqual(missingVerifier, {
    status: 503,
    body: { error: { code: "organization_owner_transfer_unavailable" } },
  });
  assert.equal(bodyCalls, 0);

  for (const [category, expected] of [
    ["unauthenticated", { status: 401, code: "unauthenticated" }],
    [
      "unavailable",
      { status: 503, code: "organization_owner_transfer_unavailable" },
    ],
  ] as const) {
    bodyCalls = 0;
    storeCalls = 0;
    const result = await handleOrganizationOwnerTransfer(
      validRequest({}, {
        readBody: async () => {
          bodyCalls += 1;
          return {};
        },
      }),
      {
        identityVerifier: {
          verify: async () => {
            throw new IdentityVerificationError(category);
          },
        },
        transferStore: store(async () => {
          storeCalls += 1;
          return transferResult;
        }),
      },
    );
    assert.deepEqual(result, {
      status: expected.status,
      body: { error: { code: expected.code } },
    });
    assert.equal(bodyCalls, 0);
    assert.equal(storeCalls, 0);
  }

  const unknownVerifierFailure = await handleOrganizationOwnerTransfer(
    validRequest({}, {
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    }),
    {
      identityVerifier: {
        verify: async () => {
          throw new Error("provider secret");
        },
      },
      transferStore: store(async () => {
        storeCalls += 1;
        return transferResult;
      }),
    },
  );
  assert.deepEqual(unknownVerifierFailure, {
    status: 503,
    body: { error: { code: "organization_owner_transfer_unavailable" } },
  });
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);
});

test("query, path, and missing store are checked after identity and before body", async () => {
  const events: string[] = [];
  const dependencies: OrganizationOwnerTransferDependencies = {
    identityVerifier: {
      verify: async () => {
        events.push("verifier");
        return identity;
      },
    },
    transferStore: store(async () => {
      events.push("store");
      return transferResult;
    }),
  };

  const queryResult = await handleOrganizationOwnerTransfer(
    validRequest({}, {
      hasQuery: true,
      readBody: async () => {
        events.push("body");
        return {};
      },
    }),
    dependencies,
  );
  assert.deepEqual(queryResult, {
    status: 400,
    body: { error: { code: "invalid_organization_owner_transfer_request" } },
  });
  assert.deepEqual(events, ["verifier"]);

  events.length = 0;
  const invalidPathResult = await handleOrganizationOwnerTransfer(
    validRequest({}, {
      workspaceId: "not-a-uuid",
      readBody: async () => {
        events.push("body");
        return {};
      },
    }),
    dependencies,
  );
  assert.deepEqual(invalidPathResult, {
    status: 400,
    body: { error: { code: "invalid_organization_owner_transfer_request" } },
  });
  assert.deepEqual(events, ["verifier"]);

  events.length = 0;
  const missingStoreResult = await handleOrganizationOwnerTransfer(
    validRequest(
      { request_id: requestId, target_organization_membership_id: targetMembershipId },
      {
        readBody: async () => {
          events.push("body");
          return {
            request_id: requestId,
            target_organization_membership_id: targetMembershipId,
          };
        },
      },
    ),
    { identityVerifier: verifier(), transferStore: undefined },
  );
  assert.deepEqual(missingStoreResult, {
    status: 503,
    body: { error: { code: "organization_owner_transfer_unavailable" } },
  });
  assert.deepEqual(events, []);
});

test("request parser accepts only the two UUID fields and canonicalizes them", () => {
  assert.deepEqual(
    parseOrganizationOwnerTransferBody({
      request_id: requestId.toUpperCase(),
      target_organization_membership_id: targetMembershipId.toUpperCase(),
    }),
    { requestId, targetOrganizationMembershipId: targetMembershipId },
  );

  const invalidBodies: unknown[] = [
    null,
    [],
    {},
    { request_id: requestId },
    { target_organization_membership_id: targetMembershipId },
    {
      request_id: requestId,
      target_organization_membership_id: targetMembershipId,
      extra: true,
    },
    { request_id: "not-a-uuid", target_organization_membership_id: targetMembershipId },
    { request_id: 123, target_organization_membership_id: targetMembershipId },
    { request_id: requestId, target_organization_membership_id: 123 },
  ];
  for (const body of invalidBodies) {
    assert.equal(parseOrganizationOwnerTransferBody(body), null);
  }
});

test("raw route matcher rejects normalized or encoded path variants", () => {
  assert.deepEqual(
    matchOrganizationOwnerTransferRequestTarget(
      `/v1/organizations/${workspaceId}/owner-transfer`,
    ),
    { workspaceId, hasQuery: false },
  );
  assert.deepEqual(
    matchOrganizationOwnerTransferRequestTarget(
      `/v1/organizations/${workspaceId}/owner-transfer?`,
    ),
    { workspaceId, hasQuery: true },
  );

  for (const target of [
    `/v1/organizations/${workspaceId}/owner-transfer/`,
    `/v1/organizations//owner-transfer`,
    `/v1/organizations/${workspaceId}/./owner-transfer`,
    `/v1/organizations/${workspaceId}/../owner-transfer`,
    `/v1/organizations/%31${workspaceId.slice(1)}/owner-transfer`,
    `/v1/organizations/${workspaceId}%2F/owner-transfer`,
    `/v1/organizations/${workspaceId}/owner%2dtransfer`,
    "/v1/organizations/not-the-transfer-route",
    undefined,
  ]) {
    assert.equal(matchOrganizationOwnerTransferRequestTarget(target), null);
  }
});

test("store makes one parameterized bridge call and returns the exact five fields", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const storeAdapter = new PostgresOrganizationOwnerTransferStore(
    async (text, values) => {
      calls.push({ text, values });
      return {
        rows: [
          {
            owner_transfer_contract_id: "organization-owner-transfer:v1",
            organization_workspace_id: workspaceId.toUpperCase(),
            previous_owner_assignment_id: previousAssignmentId.toUpperCase(),
            organization_owner_assignment_id: newAssignmentId.toUpperCase(),
            effective_at_utc: "2030-01-01T01:00:00.000000+01:00",
          },
        ],
      };
    },
  );

  const result = await storeAdapter.transfer(
    identity,
    requestId,
    workspaceId,
    targetMembershipId,
  );

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.transfer_organization_owner_for_identity_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|create_organization/);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    requestId,
    workspaceId,
    targetMembershipId,
  ]);
  assert.deepEqual(result, transferResult);
});

test("result parser accepts Date and RFC3339 offsets and rejects drift or extra fields", () => {
  assert.equal(
    parseOrganizationOwnerTransferResult(
      {
        owner_transfer_contract_id: "organization-owner-transfer:v1",
        organization_workspace_id: workspaceId.toUpperCase(),
        previous_owner_assignment_id: previousAssignmentId.toUpperCase(),
        organization_owner_assignment_id: newAssignmentId.toUpperCase(),
        effective_at_utc: new Date("2030-01-01T00:00:00.123Z"),
      },
      workspaceId,
    ).effectiveAtUtc,
    "2030-01-01T00:00:00.123Z",
  );

  const validRow = {
    owner_transfer_contract_id: "organization-owner-transfer:v1",
    organization_workspace_id: workspaceId,
    previous_owner_assignment_id: previousAssignmentId,
    organization_owner_assignment_id: newAssignmentId,
    effective_at_utc: "2030-01-01T01:00:00.000000+01:00",
  };
  assert.deepEqual(
    parseOrganizationOwnerTransferResult(validRow, workspaceId),
    transferResult,
  );

  for (const row of [
    { ...validRow, extra: true },
    { ...validRow, owner_transfer_contract_id: "wrong" },
    { ...validRow, organization_workspace_id: targetMembershipId },
    { ...validRow, effective_at_utc: "not-a-timestamp" },
    { ...validRow, effective_at_utc: "2030-02-30T00:00:00Z" },
    { ...validRow, effective_at_utc: "2030-04-31T00:00:00Z" },
    { ...validRow, effective_at_utc: "2029-02-29T00:00:00Z" },
    { ...validRow, effective_at_utc: "2030-01-01T24:00:00Z" },
    { ...validRow, effective_at_utc: "2030-01-01T23:60:00Z" },
    { ...validRow, effective_at_utc: 123 },
  ]) {
    assert.throws(
      () => parseOrganizationOwnerTransferResult(row, workspaceId),
      /invalid organization owner transfer result/,
    );
  }
});

test("store maps only exact SQLSTATE and message pairs and hides unknown errors", async () => {
  const cases = [
    ["22023", "invalid organization owner transfer identity", "organization_owner_transfer_unavailable"],
    ["22023", "invalid organization owner transfer request", "invalid_organization_owner_transfer_request"],
    ["42501", "organization owner transfer forbidden", "organization_owner_transfer_forbidden"],
    ["22023", "organization owner transfer idempotency conflict", "organization_owner_transfer_conflict"],
    ["22023", "organization owner transfer target already owner", "organization_owner_transfer_target_already_owner"],
  ] as const;

  for (const [sqlState, message, expectedCode] of cases) {
    const storeAdapter = new PostgresOrganizationOwnerTransferStore(async () => {
      throw Object.assign(new Error(message), { code: sqlState });
    });
    await assert.rejects(
      storeAdapter.transfer(identity, requestId, workspaceId, targetMembershipId),
      (error: unknown) =>
        error instanceof OrganizationOwnerTransferStoreError &&
        error.code === expectedCode,
    );
  }

  for (const error of [
    Object.assign(new Error("secret database detail"), { code: "22023" }),
    Object.assign(new Error("constraint detail"), { code: "23505" }),
  ]) {
    const storeAdapter = new PostgresOrganizationOwnerTransferStore(async () => {
      throw error;
    });
    await assert.rejects(
      storeAdapter.transfer(identity, requestId, workspaceId, targetMembershipId),
      (received: unknown) =>
        received instanceof Error &&
        received.message === "organization owner transfer store unavailable" &&
        !received.message.includes(error.message),
    );
  }
});

test("handler maps stable store outcomes and exact replay has no extra fields", async () => {
  const cases = [
    ["organization_owner_transfer_unavailable", 503],
    ["invalid_organization_owner_transfer_request", 400],
    ["organization_owner_transfer_forbidden", 403],
    ["organization_owner_transfer_conflict", 409],
    ["organization_owner_transfer_target_already_owner", 409],
  ] as const;

  for (const [code, status] of cases) {
    const result = await handleOrganizationOwnerTransfer(
      validRequest({
        request_id: requestId,
        target_organization_membership_id: targetMembershipId,
      }),
      {
        identityVerifier: verifier(),
        transferStore: store(async () => {
          throw new OrganizationOwnerTransferStoreError(code);
        }),
      },
    );
    assert.deepEqual(result, { status, body: { error: { code } } });
  }

  let storeCalls = 0;
  const dependencies: OrganizationOwnerTransferDependencies = {
    identityVerifier: verifier(),
    transferStore: store(async () => {
      storeCalls += 1;
      return transferResult;
    }),
  };
  const request = validRequest({
    request_id: requestId,
    target_organization_membership_id: targetMembershipId,
  });
  const first = await handleOrganizationOwnerTransfer(request, dependencies);
  const replay = await handleOrganizationOwnerTransfer(request, dependencies);
  assert.deepEqual(first, replay);
  assert.equal(first.status, 200);
  assert.deepEqual(Object.keys(first.body).sort(), [
    "effective_at_utc",
    "organization_owner_assignment_id",
    "organization_workspace_id",
    "owner_transfer_contract_id",
    "previous_owner_assignment_id",
  ]);
  assert.equal("replayed" in first.body, false);
  assert.equal(storeCalls, 2);
});
