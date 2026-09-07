import assert from "node:assert/strict";
import test from "node:test";

import {
  handleOrganizationMembershipSelfLeave,
  matchOrganizationMembershipSelfLeaveRequestTarget,
  OrganizationMembershipSelfLeaveStoreError,
  parseOrganizationMembershipSelfLeaveBody,
  parseOrganizationMembershipSelfLeaveResult,
  PostgresOrganizationMembershipSelfLeaveStore,
  type OrganizationMembershipSelfLeaveDependencies,
  type OrganizationMembershipSelfLeaveResult,
  type OrganizationMembershipSelfLeaveStore,
} from "../src/organization-membership-self-leave.js";
import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const requestId = "123e4567-e89b-12d3-a456-426614174001";
const membershipId = "123e4567-e89b-12d3-a456-426614174002";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example/auth/v1",
  subject: "subject-123",
};
const leaveResult: OrganizationMembershipSelfLeaveResult = {
  membershipSelfLeaveContractId: "organization-membership-self-leave:v1",
  organizationWorkspaceId: workspaceId,
  organizationMembershipId: membershipId,
  effectiveAtUtc: "2030-01-01T00:00:00.000Z",
};

test("raw matcher accepts only the literal self-leave path and preserves query presence", () => {
  assert.deepEqual(
    matchOrganizationMembershipSelfLeaveRequestTarget(
      `/v1/organizations/${workspaceId}/membership-self-leave`,
    ),
    {workspaceId, hasQuery: false},
  );
  assert.deepEqual(
    matchOrganizationMembershipSelfLeaveRequestTarget(
      `/v1/organizations/${workspaceId}/membership-self-leave?`,
    ),
    {workspaceId, hasQuery: true},
  );
  for (const path of [
    undefined,
    `/v1/organizations/${workspaceId}/membership-self-leave/`,
    "/v1/organizations/./membership-self-leave",
    "/v1/organizations/../membership-self-leave",
    "/v1/organizations/%41/membership-self-leave",
  ]) {
    assert.equal(matchOrganizationMembershipSelfLeaveRequestTarget(path), null);
  }
});

test("body is exact and canonicalizes its UUID", () => {
  assert.deepEqual(
    parseOrganizationMembershipSelfLeaveBody({request_id: requestId.toUpperCase()}),
    {requestId},
  );
  for (const body of [
    null,
    [],
    {},
    {request_id: "not-a-uuid"},
    {request_id: requestId, actor: "forbidden"},
  ]) {
    assert.equal(parseOrganizationMembershipSelfLeaveBody(body), null);
  }
});

test("handler authenticates before request validation and calls the store once", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  let received: Parameters<OrganizationMembershipSelfLeaveStore["leave"]> | undefined;
  const dependencies: OrganizationMembershipSelfLeaveDependencies = {
    identityVerifier: {
      verify: async (token) => {
        verifierCalls += 1;
        if (token === "bad") throw new IdentityVerificationError("unauthenticated");
        return identity;
      },
    },
    leaveStore: {
      leave: async (...args) => {
        storeCalls += 1;
        received = args;
        return leaveResult;
      },
    },
  };

  const unauthenticated = await handleOrganizationMembershipSelfLeave(
    request({authorization: "Bearer bad", hasQuery: true, body: "ignored"}),
    dependencies,
  );
  assert.deepEqual(unauthenticated, {status: 401, body: {error: {code: "unauthenticated"}}});
  const invalidQuery = await handleOrganizationMembershipSelfLeave(
    request({hasQuery: true, body: "ignored"}),
    dependencies,
  );
  assert.deepEqual(invalidQuery, {
    status: 400,
    body: {error: {code: "invalid_organization_membership_self_leave_request"}},
  });
  const success = await handleOrganizationMembershipSelfLeave(
    request({workspaceId: workspaceId.toUpperCase(), body: {request_id: requestId.toUpperCase()}}),
    dependencies,
  );
  assert.deepEqual(success, {
    status: 200,
    body: {
      membership_self_leave_contract_id: "organization-membership-self-leave:v1",
      organization_workspace_id: workspaceId,
      organization_membership_id: membershipId,
      effective_at_utc: leaveResult.effectiveAtUtc,
    },
  });
  assert.deepEqual(received, [identity, requestId, workspaceId]);
  assert.equal(verifierCalls, 3);
  assert.equal(storeCalls, 1);
});

test("handler fails closed for missing dependencies and verifier failures", async () => {
  const unavailable = {status: 503, body: {error: {code: "organization_membership_self_leave_unavailable"}}};
  assert.deepEqual(
    await handleOrganizationMembershipSelfLeave(request(), {
      identityVerifier: undefined,
      leaveStore: undefined,
    }),
    unavailable,
  );
  for (const error of [new IdentityVerificationError("unavailable"), new Error("secret")]) {
    assert.deepEqual(
      await handleOrganizationMembershipSelfLeave(request(), {
        identityVerifier: {verify: async () => { throw error; }},
        leaveStore: store(),
      }),
      unavailable,
    );
  }
  assert.deepEqual(
    await handleOrganizationMembershipSelfLeave(request(), {
      identityVerifier: {verify: async () => identity},
      leaveStore: undefined,
    }),
    unavailable,
  );
});

test("PostgreSQL adapter calls the exact bridge once and validates one exact row", async () => {
  let calls = 0;
  const adapter = new PostgresOrganizationMembershipSelfLeaveStore(
    async (sql, values) => {
      calls += 1;
      assert.match(sql, /FROM app_data\.leave_organization_membership_for_identity_v1\(\s*\$1::text,\s*\$2::text,\s*\$3::uuid,\s*\$4::uuid\s*\)/s);
      assert.deepEqual(values, [identity.issuer, identity.subject, requestId, workspaceId]);
      return {rows: [{
        membership_self_leave_contract_id: "organization-membership-self-leave:v1",
        organization_workspace_id: workspaceId,
        organization_membership_id: membershipId,
        effective_at_utc: new Date(leaveResult.effectiveAtUtc),
      }]};
    },
  );
  assert.deepEqual(await adapter.leave(identity, requestId, workspaceId), leaveResult);
  assert.equal(calls, 1);

  for (const rows of [[], [{...wireResult(), extra: true}], [wireResult(), wireResult()]]) {
    const invalid = new PostgresOrganizationMembershipSelfLeaveStore(async () => ({rows}));
    await assert.rejects(
      invalid.leave(identity, requestId, workspaceId),
      /organization membership self-leave store unavailable/,
    );
  }
});

test("strict result parser rejects key, contract, workspace, UUID, and time drift", () => {
  assert.deepEqual(parseOrganizationMembershipSelfLeaveResult(wireResult(), workspaceId), leaveResult);
  assert.equal(
    parseOrganizationMembershipSelfLeaveResult(
      {...wireResult(), effective_at_utc: "2030-01-01T08:00:00+08:00"},
      workspaceId,
    ).effectiveAtUtc,
    leaveResult.effectiveAtUtc,
  );
  for (const value of [
    {...wireResult(), extra: true},
    {...wireResult(), membership_self_leave_contract_id: "other:v1"},
    {...wireResult(), organization_workspace_id: requestId},
    {...wireResult(), organization_workspace_id: workspaceId.toUpperCase()},
    {...wireResult(), organization_membership_id: "not-a-uuid"},
    {...wireResult(), organization_membership_id: membershipId.toUpperCase()},
    {...wireResult(), effective_at_utc: "2030-02-30T00:00:00Z"},
    {...wireResult(), effective_at_utc: "infinity"},
  ]) {
    assert.throws(
      () => parseOrganizationMembershipSelfLeaveResult(value, workspaceId),
      /invalid organization membership self-leave result/,
    );
  }
});

test("stable SQL errors map exactly and unknown details stay private", async () => {
  const cases = [
    ["22023", "invalid organization membership self-leave identity", "organization_membership_self_leave_unavailable"],
    ["22023", "invalid organization membership self-leave request", "invalid_organization_membership_self_leave_request"],
    ["42501", "organization membership self-leave forbidden", "organization_membership_self_leave_forbidden"],
    ["22023", "organization membership self-leave idempotency conflict", "organization_membership_self_leave_conflict"],
  ] as const;
  for (const [sqlState, message, expectedCode] of cases) {
    const adapter = new PostgresOrganizationMembershipSelfLeaveStore(async () => {
      throw Object.assign(new Error(message), {code: sqlState});
    });
    await assert.rejects(
      adapter.leave(identity, requestId, workspaceId),
      (error: unknown) => error instanceof OrganizationMembershipSelfLeaveStoreError && error.code === expectedCode,
    );
  }
  const adapter = new PostgresOrganizationMembershipSelfLeaveStore(async () => {
    throw Object.assign(new Error("database secret"), {code: "23505"});
  });
  await assert.rejects(
    adapter.leave(identity, requestId, workspaceId),
    (error: unknown) => error instanceof Error &&
      error.message === "organization membership self-leave store unavailable" &&
      !error.message.includes("secret"),
  );
});

test("handler maps the four store outcomes", async () => {
  const cases = [
    ["organization_membership_self_leave_unavailable", 503],
    ["invalid_organization_membership_self_leave_request", 400],
    ["organization_membership_self_leave_forbidden", 403],
    ["organization_membership_self_leave_conflict", 409],
  ] as const;
  for (const [code, status] of cases) {
    const result = await handleOrganizationMembershipSelfLeave(request(), {
      identityVerifier: {verify: async () => identity},
      leaveStore: {leave: async () => { throw new OrganizationMembershipSelfLeaveStoreError(code); }},
    });
    assert.deepEqual(result, {status, body: {error: {code}}});
  }
});

function request(options: {
  authorization?: string;
  workspaceId?: string;
  hasQuery?: boolean;
  body?: unknown;
} = {}) {
  return {
    authorization: options.authorization ?? "Bearer token",
    workspaceId: options.workspaceId ?? workspaceId,
    hasQuery: options.hasQuery ?? false,
    readBody: async () => options.body ?? {request_id: requestId},
  };
}

function store(): OrganizationMembershipSelfLeaveStore {
  return {leave: async () => leaveResult};
}

function wireResult(): Record<string, unknown> {
  return {
    membership_self_leave_contract_id: "organization-membership-self-leave:v1",
    organization_workspace_id: workspaceId,
    organization_membership_id: membershipId,
    effective_at_utc: leaveResult.effectiveAtUtc,
  };
}
