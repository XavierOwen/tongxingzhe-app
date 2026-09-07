import assert from "node:assert/strict";
import test from "node:test";
import {
  handleOrganizationDirectedAccountInvitation,
  matchOrganizationDirectedAccountInvitationRequestTarget,
  OrganizationDirectedAccountInvitationStoreError,
  parseOrganizationDirectedAccountInvitationAcceptBody,
  parseOrganizationDirectedAccountInvitationAcceptResult,
  parseOrganizationDirectedAccountInvitationCreateBody,
  parseOrganizationDirectedAccountInvitationCreateResult,
  parseOrganizationDirectedAccountInvitationPreviewResult,
  PostgresOrganizationDirectedAccountInvitationStore,
  type OrganizationDirectedAccountInvitationAcceptResult,
  type OrganizationDirectedAccountInvitationCreateResult,
  type OrganizationDirectedAccountInvitationPreviewResult,
  type OrganizationDirectedAccountInvitationRequest,
  type OrganizationDirectedAccountInvitationStore,
} from "../src/organization-directed-account-invitations.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "../src/identity.js";

const invitationId = "123e4567-e89b-12d3-a456-426614174000";
const workspaceId = "123e4567-e89b-12d3-a456-426614174001";
const targetAppUserId = "123e4567-e89b-12d3-a456-426614174002";
const membershipId = "123e4567-e89b-12d3-a456-426614174003";
const otherId = "123e4567-e89b-12d3-a456-426614174004";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const createResult: OrganizationDirectedAccountInvitationCreateResult = {
  organizationInvitationContractId:
    "organization-directed-account-invitation:v1",
  invitationId,
  organizationWorkspaceId: workspaceId,
  issuedAtUtc: "2030-01-01T00:00:00.000Z",
  expiresAtUtc: "2030-01-08T00:00:00.000Z",
};
const acceptResult: OrganizationDirectedAccountInvitationAcceptResult = {
  organizationInvitationContractId:
    "organization-directed-account-invitation:v1",
  invitationId,
  organizationWorkspaceId: workspaceId,
  organizationMembershipId: membershipId,
  acceptedAtUtc: "2030-01-02T00:00:00.000Z",
};
const previewResult: OrganizationDirectedAccountInvitationPreviewResult = {
  organizationInvitationPreviewContractId:
    "organization-directed-account-invitation-preview:v1",
  invitationId,
  organizationName: " 同行组织 ",
  expiresAtUtc: createResult.expiresAtUtc,
};

type CreateRequest = OrganizationDirectedAccountInvitationRequest & {
  readonly operation: "create";
};
type AcceptRequest = OrganizationDirectedAccountInvitationRequest & {
  readonly operation: "accept";
};
type PreviewRequest = OrganizationDirectedAccountInvitationRequest & {
  readonly operation: "preview";
};

function previewRequest(overrides: Partial<PreviewRequest> = {}): PreviewRequest {
  return {
    operation: "preview",
    authorization: "Bearer access-token",
    invitationId,
    hasQuery: false,
    hasBody: false,
    readBody: async () => assert.fail("preview must not read a body"),
    ...overrides,
  };
}

function createRequest(
  body: unknown,
  overrides: Partial<CreateRequest> = {},
): CreateRequest {
  return {
    operation: "create",
    authorization: "Bearer access-token",
    workspaceId,
    hasQuery: false,
    hasBody: true,
    readBody: async () => body,
    ...overrides,
  };
}

function acceptRequest(
  body: unknown,
  overrides: Partial<AcceptRequest> = {},
): AcceptRequest {
  return {
    operation: "accept",
    authorization: "Bearer access-token",
    invitationId,
    hasQuery: false,
    hasBody: true,
    readBody: async () => body,
    ...overrides,
  };
}

function verifier(value: VerifiedIdentity = identity): IdentityVerifier {
  return { verify: async () => value };
}

function invitationStore(
  overrides: Partial<OrganizationDirectedAccountInvitationStore> = {},
): OrganizationDirectedAccountInvitationStore {
  return {
    create: async () => createResult,
    accept: async () => acceptResult,
    preview: async () => previewResult,
    ...overrides,
  };
}

test("preview authenticates then reads only its bound selector without a body", async () => {
  const events: string[] = [];
  const result = await handleOrganizationDirectedAccountInvitation(
    previewRequest({invitationId: invitationId.toUpperCase()}),
    {
      identityVerifier: {
        verify: async () => {
          events.push("verify");
          return identity;
        },
      },
      invitationStore: invitationStore({
        create: async () => assert.fail("preview must not create"),
        accept: async () => assert.fail("preview must not accept"),
        preview: async (actor, selectedId) => {
          events.push("preview");
          assert.deepEqual(actor, identity);
          assert.equal(selectedId, invitationId);
          return previewResult;
        },
      }),
    },
  );
  assert.deepEqual(events, ["verify", "preview"]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      organization_invitation_preview_contract_id:
        "organization-directed-account-invitation-preview:v1",
      invitation_id: invitationId,
      organization_name: " 同行组织 ",
      expires_at_utc: createResult.expiresAtUtc,
    },
  });
});

test("preview rejects query, body, and selector only after authentication", async () => {
  let reads = 0;
  const dependencies = {
    identityVerifier: verifier(),
    invitationStore: invitationStore({
      preview: async () => {
        reads += 1;
        return previewResult;
      },
    }),
  };
  for (const override of [
    {hasQuery: true},
    {hasBody: true},
    {invitationId: "not-a-uuid"},
  ]) {
    assert.deepEqual(
      await handleOrganizationDirectedAccountInvitation(
        previewRequest({...override, authorization: undefined}),
        dependencies,
      ),
      {status: 401, body: {error: {code: "unauthenticated"}}},
    );
    assert.deepEqual(
      await handleOrganizationDirectedAccountInvitation(
        previewRequest(override),
        dependencies,
      ),
      {
        status: 400,
        body: {error: {code: "invalid_organization_invitation_request"}},
      },
    );
  }
  assert.equal(reads, 0);
});

test("create verifies, validates, reads, and calls only create in order", async () => {
  const events: string[] = [];
  let received:
    | [VerifiedIdentity, string, string, string]
    | undefined;
  const result = await handleOrganizationDirectedAccountInvitation(
    createRequest(
      {
        invitation_id: invitationId.toUpperCase(),
        target_app_user_id: targetAppUserId.toUpperCase(),
      },
      {
        workspaceId: workspaceId.toUpperCase(),
        readBody: async () => {
          events.push("body");
          return {
            invitation_id: invitationId.toUpperCase(),
            target_app_user_id: targetAppUserId.toUpperCase(),
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
      invitationStore: invitationStore({
        create: async (...args) => {
          events.push("create");
          received = args;
          return createResult;
        },
        accept: async () => {
          assert.fail("accept must not run for create");
        },
      }),
    },
  );

  assert.deepEqual(events, ["verifier", "body", "create"]);
  assert.deepEqual(received, [
    identity,
    invitationId,
    workspaceId,
    targetAppUserId,
  ]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      organization_invitation_contract_id:
        "organization-directed-account-invitation:v1",
      invitation_id: invitationId,
      organization_workspace_id: workspaceId,
      issued_at_utc: "2030-01-01T00:00:00.000Z",
      expires_at_utc: "2030-01-08T00:00:00.000Z",
    },
  });
});

test("accept verifies, validates, reads, and calls only accept in order", async () => {
  const events: string[] = [];
  let received: [VerifiedIdentity, string] | undefined;
  const result = await handleOrganizationDirectedAccountInvitation(
    acceptRequest({}, {
      invitationId: invitationId.toUpperCase(),
      readBody: async () => {
        events.push("body");
        return {};
      },
    }),
    {
      identityVerifier: {
        verify: async () => {
          events.push("verifier");
          return identity;
        },
      },
      invitationStore: invitationStore({
        create: async () => {
          assert.fail("create must not run for accept");
        },
        accept: async (...args) => {
          events.push("accept");
          received = args;
          return acceptResult;
        },
      }),
    },
  );

  assert.deepEqual(events, ["verifier", "body", "accept"]);
  assert.deepEqual(received, [identity, invitationId]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      organization_invitation_contract_id:
        "organization-directed-account-invitation:v1",
      invitation_id: invitationId,
      organization_workspace_id: workspaceId,
      organization_membership_id: membershipId,
      accepted_at_utc: "2030-01-02T00:00:00.000Z",
    },
  });
});

test("authentication failures stop before body and store", async () => {
  let verifierCalls = 0;
  let bodyCalls = 0;
  let storeCalls = 0;
  const countedStore = invitationStore({
    create: async () => {
      storeCalls += 1;
      return createResult;
    },
  });
  const missingBearer = await handleOrganizationDirectedAccountInvitation(
    createRequest({}, {
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
      invitationStore: countedStore,
    },
  );
  assert.deepEqual(missingBearer, {
    status: 401,
    body: { error: { code: "unauthenticated" } },
  });

  const missingVerifier = await handleOrganizationDirectedAccountInvitation(
    acceptRequest({}, {
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    }),
    { identityVerifier: undefined, invitationStore: countedStore },
  );
  assert.deepEqual(missingVerifier, {
    status: 503,
    body: { error: { code: "organization_invitation_unavailable" } },
  });

  for (const [failure, expected] of [
    [
      new IdentityVerificationError("unauthenticated"),
      { status: 401, code: "unauthenticated" },
    ],
    [
      new IdentityVerificationError("unavailable"),
      { status: 503, code: "organization_invitation_unavailable" },
    ],
    [
      new Error("provider secret"),
      { status: 503, code: "organization_invitation_unavailable" },
    ],
  ] as const) {
    const result = await handleOrganizationDirectedAccountInvitation(
      acceptRequest({}, {
        readBody: async () => {
          bodyCalls += 1;
          return {};
        },
      }),
      {
        identityVerifier: {
          verify: async () => {
            verifierCalls += 1;
            throw failure;
          },
        },
        invitationStore: countedStore,
      },
    );
    assert.deepEqual(result, {
      status: expected.status,
      body: { error: { code: expected.code } },
    });
  }

  assert.equal(verifierCalls, 3);
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);
});

test("query, path, store, and body checks short-circuit in order", async () => {
  const events: string[] = [];
  const dependencies = {
    identityVerifier: {
      verify: async () => {
        events.push("verifier");
        return identity;
      },
    },
    invitationStore: invitationStore({
      create: async () => {
        events.push("store");
        return createResult;
      },
      accept: async () => {
        events.push("store");
        return acceptResult;
      },
    }),
  };

  for (const request of [
    createRequest({}, { hasQuery: true }),
    acceptRequest({}, { hasQuery: true }),
    createRequest({}, { workspaceId: "not-a-uuid" }),
    acceptRequest({}, { invitationId: "not-a-uuid" }),
  ]) {
    events.length = 0;
    const result = await handleOrganizationDirectedAccountInvitation(
      request,
      dependencies,
    );
    assert.deepEqual(result, {
      status: 400,
      body: { error: { code: "invalid_organization_invitation_request" } },
    });
    assert.deepEqual(events, ["verifier"]);
  }

  events.length = 0;
  const missingStore = await handleOrganizationDirectedAccountInvitation(
    acceptRequest({}, {
      readBody: async () => {
        events.push("body");
        return {};
      },
    }),
    { identityVerifier: verifier(), invitationStore: undefined },
  );
  assert.deepEqual(missingStore, {
    status: 503,
    body: { error: { code: "organization_invitation_unavailable" } },
  });
  assert.equal(events.length, 0);

  for (const request of [
    createRequest({ invitation_id: invitationId }),
    acceptRequest({ invitation_id: invitationId }),
  ]) {
    const result = await handleOrganizationDirectedAccountInvitation(
      request,
      dependencies,
    );
    assert.deepEqual(result, {
      status: 400,
      body: { error: { code: "invalid_organization_invitation_request" } },
    });
  }
  assert.equal(events.join(",").includes("store"), false);
});

test("body parsers accept only canonicalizable operation fields", () => {
  assert.deepEqual(
    parseOrganizationDirectedAccountInvitationCreateBody({
      invitation_id: invitationId.toUpperCase(),
      target_app_user_id: targetAppUserId.toUpperCase(),
    }),
    { invitationId, targetAppUserId },
  );
  assert.deepEqual(parseOrganizationDirectedAccountInvitationAcceptBody({}), {});

  for (const value of [
    null,
    [],
    {},
    { invitation_id: invitationId },
    { target_app_user_id: targetAppUserId },
    {
      invitation_id: invitationId,
      target_app_user_id: targetAppUserId,
      actor_app_user_id: otherId,
    },
    { invitation_id: "not-a-uuid", target_app_user_id: targetAppUserId },
    { invitation_id: invitationId, target_app_user_id: 1 },
  ]) {
    assert.equal(
      parseOrganizationDirectedAccountInvitationCreateBody(value),
      null,
    );
  }
  for (const value of [null, [], "", { invitation_id: invitationId }]) {
    assert.equal(
      parseOrganizationDirectedAccountInvitationAcceptBody(value),
      null,
    );
  }
});

test("raw matcher recognizes only the three unnormalized paths", () => {
  assert.deepEqual(
    matchOrganizationDirectedAccountInvitationRequestTarget(
      `/v1/organization-directed-account-invitations/${invitationId}`,
    ),
    {operation: "preview", invitationId, hasQuery: false},
  );
  assert.deepEqual(
    matchOrganizationDirectedAccountInvitationRequestTarget(
      `/v1/organizations/${workspaceId}/directed-account-invitations`,
    ),
    { operation: "create", workspaceId, hasQuery: false },
  );
  assert.deepEqual(
    matchOrganizationDirectedAccountInvitationRequestTarget(
      `/v1/organization-directed-account-invitations/${invitationId}/accept?`,
    ),
    { operation: "accept", invitationId, hasQuery: true },
  );

  for (const target of [
    `/v1/organizations/${workspaceId}/directed-account-invitations/`,
    `/v1/organizations//directed-account-invitations`,
    `/v1/organizations/./directed-account-invitations`,
    `/v1/organizations/../directed-account-invitations`,
    `/v1/organizations/%31${workspaceId.slice(1)}/directed-account-invitations`,
    `/v1/organizations/${workspaceId}/directed-account%2dinvitations`,
    `/v1/organizations/${workspaceId}//directed-account-invitations`,
    `/v1/organization-directed-account-invitations/${invitationId}/accept/`,
    `/v1/organization-directed-account-invitations/${invitationId}/`,
    `/v1/organization-directed-account-invitations/${invitationId}/extra`,
    "/v1/organization-directed-account-invitations/.",
    "/v1/organization-directed-account-invitations/..",
    `/v1/organization-directed-account-invitations/%31${invitationId.slice(1)}`,
    "/v1/organization-directed-account-invitations//accept",
    "/v1/organization-directed-account-invitations/./accept",
    "/v1/organization-directed-account-invitations/../accept",
    `/v1/organization-directed-account-invitations/%31${invitationId.slice(1)}/accept`,
    `/v1/organization-directed-account-invitations/${invitationId}/%61ccept`,
    `/v1/organization-directed-account-invitations/${invitationId}//accept`,
    `/v1/organization-directed-account-invitations/${invitationId}/accept/extra`,
    "/v1/not-an-invitation-route",
    undefined,
  ]) {
    assert.equal(
      matchOrganizationDirectedAccountInvitationRequestTarget(target),
      null,
    );
  }
});

test("Postgres preview uses one exact identity bridge and retains the name", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresOrganizationDirectedAccountInvitationStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{
        organization_invitation_preview_contract_id:
          "organization-directed-account-invitation-preview:v1",
        invitation_id: invitationId.toUpperCase(),
        organization_name: " 同行组织 ",
        expires_at_utc: "2030-01-08T01:00:00.000001+01:00",
      }]};
    },
  );
  const exactIdentity = {issuer: "  https://issuer.example  ", subject: " target "};
  assert.deepEqual(await store.preview(exactIdentity, invitationId), previewResult);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0]?.values, [
    exactIdentity.issuer, exactIdentity.subject, invitationId,
  ]);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.preview_organization_directed_invitation_for_identity_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|create_|accept_|bootstrap/);
});

test("preview result rejects field, selector, name, and timestamp drift", () => {
  const row = {
    organization_invitation_preview_contract_id:
      "organization-directed-account-invitation-preview:v1",
    invitation_id: invitationId,
    organization_name: " 同行组织 ",
    expires_at_utc: new Date(createResult.expiresAtUtc),
  };
  assert.deepEqual(
    parseOrganizationDirectedAccountInvitationPreviewResult(row, invitationId),
    previewResult,
  );
  for (const bad of [
    null, [], {},
    {...row, organization_invitation_preview_contract_id: "wrong:v1"},
    {...row, organization_workspace_id: workspaceId},
    {...row, target_app_user_id: targetAppUserId},
    {...row, invitation_id: otherId},
    {...row, organization_name: ""},
    {...row, organization_name: "   "},
    {...row, organization_name: null},
    {...row, expires_at_utc: "2030-02-30T00:00:00.000Z"},
    {...row, expires_at_utc: "2030-01-08"},
    {...row, expires_at_utc: "infinity"},
    {...row, expires_at_utc: new Date(Number.NaN)},
  ]) {
    assert.throws(
      () => parseOrganizationDirectedAccountInvitationPreviewResult(bad, invitationId),
      /invalid organization invitation preview result/,
    );
  }
});

test("preview store rejects row counts and maps only the existing SQL errors", async () => {
  for (const rows of [[], [{}, {}], [{}]]) {
    const store = new PostgresOrganizationDirectedAccountInvitationStore(
      async () => ({rows}),
    );
    await assert.rejects(
      () => store.preview(identity, invitationId),
      /organization invitation store unavailable/,
    );
  }
  for (const [error, status, code] of [
    [{code: "42501", message: "organization invitation forbidden"}, 403,
      "organization_invitation_forbidden"],
    [{code: "22023", message: "invalid organization invitation request"}, 400,
      "invalid_organization_invitation_request"],
    [{code: "22023", message: "invalid organization invitation identity"}, 503,
      "organization_invitation_unavailable"],
    [{code: "42501", message: "secret SQL"}, 503,
      "organization_invitation_unavailable"],
    [new Error("secret token"), 503, "organization_invitation_unavailable"],
  ] as const) {
    const store = new PostgresOrganizationDirectedAccountInvitationStore(
      async () => { throw error; },
    );
    assert.deepEqual(
      await handleOrganizationDirectedAccountInvitation(previewRequest(), {
        identityVerifier: verifier(), invitationStore: store,
      }),
      {status, body: {error: {code}}},
    );
  }
});

test("Postgres create uses one bridge query and returns the bound receipt", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const store = new PostgresOrganizationDirectedAccountInvitationStore(
    async (text, values) => {
      calls.push({ text, values });
      return {
        rows: [
          {
            organization_invitation_contract_id:
              "organization-directed-account-invitation:v1",
            invitation_id: invitationId.toUpperCase(),
            organization_workspace_id: workspaceId.toUpperCase(),
            issued_at_utc: "2030-01-01T01:00:00.000001+01:00",
            expires_at_utc: "2030-01-08T01:00:00.000001+01:00",
          },
        ],
      };
    },
  );

  assert.deepEqual(
    await store.create(identity, invitationId, workspaceId, targetAppUserId),
    createResult,
  );
  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.create_organization_directed_account_invitation_for_identity_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|accept_/);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    invitationId,
    workspaceId,
    targetAppUserId,
  ]);
});

test("Postgres accept uses one bridge query and returns the bound receipt", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const store = new PostgresOrganizationDirectedAccountInvitationStore(
    async (text, values) => {
      calls.push({ text, values });
      return {
        rows: [
          {
            organization_invitation_contract_id:
              "organization-directed-account-invitation:v1",
            invitation_id: invitationId.toUpperCase(),
            organization_workspace_id: workspaceId.toUpperCase(),
            organization_membership_id: membershipId.toUpperCase(),
            accepted_at_utc: new Date("2030-01-02T00:00:00.000Z"),
          },
        ],
      };
    },
  );

  assert.deepEqual(await store.accept(identity, invitationId), acceptResult);
  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.accept_organization_directed_account_invitation_for_identity_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|create_/);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    invitationId,
  ]);
});

test("create result requires exact fields, bindings, timestamps, and lifetime", () => {
  const validRow = {
    organization_invitation_contract_id:
      "organization-directed-account-invitation:v1",
    invitation_id: invitationId,
    organization_workspace_id: workspaceId,
    issued_at_utc: "2028-02-29t01:02:03.123456+01:00",
    expires_at_utc: "2028-03-07T00:02:03.123456z",
  };
  assert.deepEqual(
    parseOrganizationDirectedAccountInvitationCreateResult(
      validRow,
      invitationId.toUpperCase(),
      workspaceId.toUpperCase(),
    ),
    {
      ...createResult,
      issuedAtUtc: "2028-02-29T00:02:03.123Z",
      expiresAtUtc: "2028-03-07T00:02:03.123Z",
    },
  );

  for (const row of [
    { ...validRow, target_app_user_id: targetAppUserId },
    {
      ...validRow,
      organization_invitation_contract_id: "wrong-contract",
    },
    { ...validRow, invitation_id: otherId },
    { ...validRow, organization_workspace_id: otherId },
    { ...validRow, issued_at_utc: "2030-02-30T00:00:00Z" },
    { ...validRow, issued_at_utc: "2029-02-29T00:00:00Z" },
    { ...validRow, issued_at_utc: "2030-04-31T00:00:00Z" },
    { ...validRow, issued_at_utc: "2030-01-01T24:00:00Z" },
    { ...validRow, issued_at_utc: "2030-01-01T23:60:00Z" },
    { ...validRow, issued_at_utc: "2030-01-01T23:59:60Z" },
    { ...validRow, issued_at_utc: "2030-01-01T00:00:00+24:00" },
    { ...validRow, issued_at_utc: "2030-01-01T00:00:00" },
    { ...validRow, issued_at_utc: new Date(Number.NaN) },
    { ...validRow, expires_at_utc: "2028-03-06T23:02:03.123456Z" },
    { ...validRow, expires_at_utc: "2028-03-07T00:02:03.124456Z" },
    {
      ...validRow,
      issued_at_utc: "2028-02-29T00:02:03.123400Z",
      expires_at_utc: "2028-03-07T00:02:03.123499Z",
    },
  ]) {
    assert.throws(
      () =>
        parseOrganizationDirectedAccountInvitationCreateResult(
          row,
          invitationId,
          workspaceId,
        ),
      /invalid organization invitation create result/,
    );
  }
});

test("accept result requires exact fields and the invitation binding", () => {
  const validRow = {
    organization_invitation_contract_id:
      "organization-directed-account-invitation:v1",
    invitation_id: invitationId.toUpperCase(),
    organization_workspace_id: workspaceId.toUpperCase(),
    organization_membership_id: membershipId.toUpperCase(),
    accepted_at_utc: "2030-01-02T01:00:00.999999+01:00",
  };
  assert.deepEqual(
    parseOrganizationDirectedAccountInvitationAcceptResult(
      validRow,
      invitationId,
    ),
    { ...acceptResult, acceptedAtUtc: "2030-01-02T00:00:00.999Z" },
  );

  for (const row of [
    { ...validRow, actor_app_user_id: targetAppUserId },
    {
      ...validRow,
      organization_invitation_contract_id: "wrong-contract",
    },
    { ...validRow, invitation_id: otherId },
    { ...validRow, organization_workspace_id: "not-a-uuid" },
    { ...validRow, organization_membership_id: "not-a-uuid" },
    { ...validRow, accepted_at_utc: "not-a-timestamp" },
    { ...validRow, accepted_at_utc: "2030-02-30T00:00:00Z" },
    { ...validRow, accepted_at_utc: new Date(Number.NaN) },
  ]) {
    assert.throws(
      () =>
        parseOrganizationDirectedAccountInvitationAcceptResult(
          row,
          invitationId,
        ),
      /invalid organization invitation accept result/,
    );
  }
});

test("store maps only exact SQLSTATE and message pairs", async () => {
  const cases = [
    [
      "22023",
      "invalid organization invitation identity",
      "organization_invitation_unavailable",
    ],
    [
      "22023",
      "invalid organization invitation request",
      "invalid_organization_invitation_request",
    ],
    [
      "42501",
      "organization invitation forbidden",
      "organization_invitation_forbidden",
    ],
    [
      "22023",
      "organization invitation idempotency conflict",
      "organization_invitation_conflict",
    ],
  ] as const;

  for (const operation of ["create", "accept"] as const) {
    for (const [sqlState, message, expectedCode] of cases) {
      const store = new PostgresOrganizationDirectedAccountInvitationStore(
        async () => {
          throw Object.assign(new Error(message), { code: sqlState });
        },
      );
      await assert.rejects(
        operation === "create"
          ? store.create(identity, invitationId, workspaceId, targetAppUserId)
          : store.accept(identity, invitationId),
        (error: unknown) =>
          error instanceof OrganizationDirectedAccountInvitationStoreError &&
          error.code === expectedCode,
      );
    }
  }

  for (const error of [
    Object.assign(new Error("organization invitation forbidden"), {
      code: "22023",
    }),
    Object.assign(new Error("database secret"), { code: "42501" }),
    Object.assign(new Error("constraint secret"), { code: "23505" }),
  ]) {
    const store = new PostgresOrganizationDirectedAccountInvitationStore(
      async () => {
        throw error;
      },
    );
    await assert.rejects(
      store.accept(identity, invitationId),
      (received: unknown) =>
        received instanceof Error &&
        received.message === "organization invitation store unavailable" &&
        !received.message.includes(error.message),
    );
  }
});

test("handler maps store errors to the fixed status and error root", async () => {
  const cases = [
    ["organization_invitation_unavailable", 503],
    ["invalid_organization_invitation_request", 400],
    ["organization_invitation_forbidden", 403],
    ["organization_invitation_conflict", 409],
  ] as const;

  for (const [code, status] of cases) {
    const result = await handleOrganizationDirectedAccountInvitation(
      createRequest({
        invitation_id: invitationId,
        target_app_user_id: targetAppUserId,
      }),
      {
        identityVerifier: verifier(),
        invitationStore: invitationStore({
          create: async () => {
            throw new OrganizationDirectedAccountInvitationStoreError(code);
          },
        }),
      },
    );
    assert.deepEqual(result, { status, body: { error: { code } } });
  }

  const unknown = await handleOrganizationDirectedAccountInvitation(
    acceptRequest({}),
    {
      identityVerifier: verifier(),
      invitationStore: invitationStore({
        accept: async () => {
          throw new Error("database secret");
        },
      }),
    },
  );
  assert.deepEqual(unknown, {
    status: 503,
    body: { error: { code: "organization_invitation_unavailable" } },
  });
});

test("first success and exact replay use the same five-field receipts", async () => {
  let createCalls = 0;
  let acceptCalls = 0;
  const store = invitationStore({
    create: async () => {
      createCalls += 1;
      return createResult;
    },
    accept: async () => {
      acceptCalls += 1;
      return acceptResult;
    },
  });
  const dependencies = { identityVerifier: verifier(), invitationStore: store };
  const create = createRequest({
    invitation_id: invitationId,
    target_app_user_id: targetAppUserId,
  });
  const accept = acceptRequest({});

  for (const request of [create, accept]) {
    const first = await handleOrganizationDirectedAccountInvitation(
      request,
      dependencies,
    );
    const replay = await handleOrganizationDirectedAccountInvitation(
      request,
      dependencies,
    );
    assert.deepEqual(replay, first);
    assert.equal(first.status, 200);
    assert.equal(Object.keys(first.body).length, 5);
    assert.equal("replayed" in first.body, false);
    assert.equal("target_app_user_id" in first.body, false);
  }
  assert.equal(createCalls, 2);
  assert.equal(acceptCalls, 2);
});

test("handler waits for each store promise before returning", async () => {
  for (const operation of ["create", "accept"] as const) {
    let resolve:
      | ((
        value:
          | OrganizationDirectedAccountInvitationCreateResult
          | OrganizationDirectedAccountInvitationAcceptResult,
      ) => void)
      | undefined;
    let storeCalled = false;
    let settled = false;
    const gate = new Promise<
      | OrganizationDirectedAccountInvitationCreateResult
      | OrganizationDirectedAccountInvitationAcceptResult
    >((gateResolve) => {
      resolve = gateResolve;
    });
    const promise = handleOrganizationDirectedAccountInvitation(
      operation === "create"
        ? createRequest({
          invitation_id: invitationId,
          target_app_user_id: targetAppUserId,
        })
        : acceptRequest({}),
      {
        identityVerifier: verifier(),
        invitationStore: invitationStore({
          create: async () => {
            storeCalled = true;
            return gate as Promise<OrganizationDirectedAccountInvitationCreateResult>;
          },
          accept: async () => {
            storeCalled = true;
            return gate as Promise<OrganizationDirectedAccountInvitationAcceptResult>;
          },
        }),
      },
    ).then((value) => {
      settled = true;
      return value;
    });

    await new Promise((gateResolve) => setImmediate(gateResolve));
    assert.equal(storeCalled, true);
    assert.equal(settled, false);
    assert.ok(resolve);
    resolve(operation === "create" ? createResult : acceptResult);
    assert.equal((await promise).status, 200);
    assert.equal(settled, true);
  }
});
