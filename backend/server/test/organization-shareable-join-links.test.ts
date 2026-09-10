import assert from "node:assert/strict";
import test from "node:test";

import {
  handleOrganizationShareableJoinLink,
  matchOrganizationShareableJoinLinkRequestTarget,
  OrganizationShareableJoinLinkStoreError,
  parseOrganizationShareableJoinLinkCreateBody,
  parseOrganizationShareableJoinLinkCreateResult,
  parseOrganizationShareableJoinLinkPreviewResult,
  PostgresOrganizationShareableJoinLinkStore,
  type OrganizationShareableJoinLinkCreateResult,
  type OrganizationShareableJoinLinkPreviewResult,
  type OrganizationShareableJoinLinkRequest,
  type OrganizationShareableJoinLinkStore,
} from "../src/organization-shareable-join-links.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "../src/identity.js";

const linkId = "123e4567-e89b-12d3-a456-426614174000";
const workspaceId = "123e4567-e89b-12d3-a456-426614174001";
const otherId = "123e4567-e89b-12d3-a456-426614174002";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const createResult: OrganizationShareableJoinLinkCreateResult = {
  organizationShareableJoinLinkContractId:
    "organization-shareable-join-link:v1",
  linkId,
  organizationWorkspaceId: workspaceId,
  issuedAtUtc: "2030-01-01T00:00:00.000Z",
  expiresAtUtc: "2030-01-08T00:00:00.000Z",
};
const previewResult: OrganizationShareableJoinLinkPreviewResult = {
  organizationShareableJoinLinkPreviewContractId:
    "organization-shareable-join-link-preview:v1",
  linkId,
  organizationName: " 同行组织 ",
  expiresAtUtc: createResult.expiresAtUtc,
};

type CreateRequest = OrganizationShareableJoinLinkRequest & {
  readonly operation: "create";
};
type PreviewRequest = OrganizationShareableJoinLinkRequest & {
  readonly operation: "preview";
};

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

function previewRequest(
  overrides: Partial<PreviewRequest> = {},
): PreviewRequest {
  return {
    operation: "preview",
    authorization: "Bearer access-token",
    linkId,
    hasQuery: false,
    hasBody: false,
    readBody: async () => assert.fail("preview must not read a body"),
    ...overrides,
  };
}

function verifier(value: VerifiedIdentity = identity): IdentityVerifier {
  return {verify: async () => value};
}

function linkStore(
  overrides: Partial<OrganizationShareableJoinLinkStore> = {},
): OrganizationShareableJoinLinkStore {
  return {
    create: async () => createResult,
    preview: async () => previewResult,
    ...overrides,
  };
}

test("create authenticates, canonicalizes selectors, and returns the exact receipt", async () => {
  const events: string[] = [];
  let received:
    | Parameters<OrganizationShareableJoinLinkStore["create"]>
    | undefined;
  const result = await handleOrganizationShareableJoinLink(
    createRequest(
      {link_id: linkId.toUpperCase()},
      {
        workspaceId: workspaceId.toUpperCase(),
        readBody: async () => {
          events.push("body");
          return {link_id: linkId.toUpperCase()};
        },
      },
    ),
    {
      identityVerifier: {
        verify: async (token) => {
          assert.equal(token, "access-token");
          events.push("verify");
          return identity;
        },
      },
      linkStore: linkStore({
        create: async (...args) => {
          events.push("create");
          received = args;
          return createResult;
        },
        preview: async () => assert.fail("create must not preview"),
      }),
    },
  );

  assert.deepEqual(events, ["verify", "body", "create"]);
  assert.deepEqual(received, [identity, linkId, workspaceId]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      organization_shareable_join_link_contract_id:
        "organization-shareable-join-link:v1",
      link_id: linkId,
      organization_workspace_id: workspaceId,
      issued_at_utc: "2030-01-01T00:00:00.000Z",
      expires_at_utc: "2030-01-08T00:00:00.000Z",
    },
  });
});

test("preview authenticates and returns only the bound four-field receipt", async () => {
  const events: string[] = [];
  const result = await handleOrganizationShareableJoinLink(
    previewRequest({linkId: linkId.toUpperCase()}),
    {
      identityVerifier: {
        verify: async () => {
          events.push("verify");
          return identity;
        },
      },
      linkStore: linkStore({
        create: async () => assert.fail("preview must not create"),
        preview: async (actor, selectedLinkId) => {
          events.push("preview");
          assert.deepEqual(actor, identity);
          assert.equal(selectedLinkId, linkId);
          return previewResult;
        },
      }),
    },
  );
  assert.deepEqual(events, ["verify", "preview"]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      organization_shareable_join_link_preview_contract_id:
        "organization-shareable-join-link-preview:v1",
      link_id: linkId,
      organization_name: " 同行组织 ",
      expires_at_utc: "2030-01-08T00:00:00.000Z",
    },
  });
});

test("authentication precedes request shape, dependency, body, and store access", async () => {
  let bodyCalls = 0;
  let storeCalls = 0;
  const request = createRequest({}, {
    authorization: undefined,
    workspaceId: "not-a-uuid",
    hasQuery: true,
    readBody: async () => {
      bodyCalls += 1;
      return {};
    },
  });
  const store = linkStore({
    create: async () => {
      storeCalls += 1;
      return createResult;
    },
  });
  assert.deepEqual(
    await handleOrganizationShareableJoinLink(request, {
      identityVerifier: verifier(),
      linkStore: store,
    }),
    {status: 401, body: {error: {code: "unauthenticated"}}},
  );
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);

  for (const [error, status, code] of [
    [new IdentityVerificationError("unauthenticated"), 401, "unauthenticated"],
    [
      new IdentityVerificationError("unavailable"),
      503,
      "organization_shareable_join_unavailable",
    ],
    [new Error("provider secret"), 503, "organization_shareable_join_unavailable"],
  ] as const) {
    assert.deepEqual(
      await handleOrganizationShareableJoinLink(
        {...request, authorization: "Bearer token"},
        {
          identityVerifier: {verify: async () => { throw error; }},
          linkStore: store,
        },
      ),
      {status, body: {error: {code}}},
    );
  }
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);
});

test("authenticated request validation short-circuits before body or store", async () => {
  let bodyCalls = 0;
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: verifier(),
    linkStore: linkStore({
      create: async () => {
        storeCalls += 1;
        return createResult;
      },
      preview: async () => {
        storeCalls += 1;
        return previewResult;
      },
    }),
  };
  for (const request of [
    createRequest({}, {
      hasQuery: true,
      readBody: async () => { bodyCalls += 1; return {}; },
    }),
    createRequest({}, {
      workspaceId: "not-a-uuid",
      readBody: async () => { bodyCalls += 1; return {}; },
    }),
    previewRequest({hasQuery: true}),
    previewRequest({hasBody: true}),
    previewRequest({linkId: "not-a-uuid"}),
  ]) {
    assert.deepEqual(
      await handleOrganizationShareableJoinLink(request, dependencies),
      {
        status: 400,
        body: {error: {code: "invalid_organization_shareable_join_request"}},
      },
    );
  }
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);

  assert.deepEqual(
    await handleOrganizationShareableJoinLink(
      createRequest({}, {
        readBody: async () => { bodyCalls += 1; return {}; },
      }),
      {identityVerifier: verifier(), linkStore: undefined},
    ),
    {
      status: 503,
      body: {error: {code: "organization_shareable_join_unavailable"}},
    },
  );
  assert.equal(bodyCalls, 0);
});

test("create body accepts exactly one UUID link selector", () => {
  assert.deepEqual(
    parseOrganizationShareableJoinLinkCreateBody({
      link_id: linkId.toUpperCase(),
    }),
    {linkId},
  );
  for (const body of [
    null,
    [],
    {},
    {link_id: "not-a-uuid"},
    {link_id: 1},
    {link_id: linkId, actor_app_user_id: otherId},
  ]) {
    assert.equal(parseOrganizationShareableJoinLinkCreateBody(body), null);
  }
});

test("raw matcher recognizes only the two unnormalized route shapes", () => {
  assert.deepEqual(
    matchOrganizationShareableJoinLinkRequestTarget(
      `/v1/organizations/${workspaceId}/shareable-join-links`,
    ),
    {operation: "create", workspaceId, hasQuery: false},
  );
  assert.deepEqual(
    matchOrganizationShareableJoinLinkRequestTarget(
      `/v1/organization-shareable-join-links/${linkId}?`,
    ),
    {operation: "preview", linkId, hasQuery: true},
  );
  for (const target of [
    `/v1/organizations/${workspaceId}/shareable-join-links/`,
    "/v1/organizations/./shareable-join-links",
    "/v1/organizations/../shareable-join-links",
    `/v1/organizations/%31${workspaceId.slice(1)}/shareable-join-links`,
    `/v1/organizations/${workspaceId}/shareable%2djoin-links`,
    `/v1/organizations/${workspaceId}//shareable-join-links`,
    `/v1/organization-shareable-join-links/${linkId}/`,
    "/v1/organization-shareable-join-links/.",
    "/v1/organization-shareable-join-links/..",
    `/v1/organization-shareable-join-links/%31${linkId.slice(1)}`,
    "/v1/organization-shareable-join-links/",
    "/v1/not-a-shareable-link-route",
    undefined,
  ]) {
    assert.equal(matchOrganizationShareableJoinLinkRequestTarget(target), null);
  }
});

test("Postgres adapter uses only the two exact 0092 identity bridges", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresOrganizationShareableJoinLinkStore(
    async (text, values) => {
      calls.push({text, values});
      return calls.length === 1
        ? {rows: [{
          organization_shareable_join_link_contract_id:
            "organization-shareable-join-link:v1",
          link_id: linkId.toUpperCase(),
          organization_workspace_id: workspaceId.toUpperCase(),
          issued_at_utc: "2030-01-01T01:00:00.000001+01:00",
          expires_at_utc: "2030-01-08T01:00:00.000001+01:00",
        }]}
        : {rows: [{
          organization_shareable_join_link_preview_contract_id:
            "organization-shareable-join-link-preview:v1",
          link_id: linkId.toUpperCase(),
          organization_name: " 同行组织 ",
          expires_at_utc: new Date("2030-01-08T00:00:00.000Z"),
        }]};
    },
  );
  const exactIdentity = {issuer: "  https://issuer.example  ", subject: " actor "};
  assert.deepEqual(
    await store.create(exactIdentity, linkId, workspaceId),
    createResult,
  );
  assert.deepEqual(await store.preview(exactIdentity, linkId), previewResult);
  assert.deepEqual(calls[0]?.values, [
    exactIdentity.issuer,
    exactIdentity.subject,
    linkId,
    workspaceId,
  ]);
  assert.deepEqual(calls[1]?.values, [
    exactIdentity.issuer,
    exactIdentity.subject,
    linkId,
  ]);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.create_organization_shareable_join_link_for_identity_v1/,
  );
  assert.match(
    calls[1]?.text ?? "",
    /app_data\.preview_organization_shareable_join_link_for_identity_v1/,
  );
  assert.doesNotMatch(calls.map((call) => call.text).join("\n"), /app_private/);
});

test("create result requires exact fields, request bindings, UTC, and 168 hours", () => {
  const valid = {
    organization_shareable_join_link_contract_id:
      "organization-shareable-join-link:v1",
    link_id: linkId.toUpperCase(),
    organization_workspace_id: workspaceId.toUpperCase(),
    issued_at_utc: "2028-02-29t01:02:03.123456+01:00",
    expires_at_utc: "2028-03-07T00:02:03.123456z",
  };
  assert.deepEqual(
    parseOrganizationShareableJoinLinkCreateResult(
      valid,
      linkId,
      workspaceId,
    ),
    {
      ...createResult,
      issuedAtUtc: "2028-02-29T00:02:03.123Z",
      expiresAtUtc: "2028-03-07T00:02:03.123Z",
    },
  );
  for (const row of [
    {...valid, creator_app_user_id: otherId},
    {...valid, organization_shareable_join_link_contract_id: "wrong:v1"},
    {...valid, link_id: otherId},
    {...valid, organization_workspace_id: otherId},
    {...valid, issued_at_utc: "2030-02-30T00:00:00Z"},
    {...valid, issued_at_utc: "2030-01-01T24:00:00Z"},
    {...valid, issued_at_utc: "2030-01-01T00:00:00"},
    {...valid, expires_at_utc: "2028-03-06T23:02:03.123456Z"},
    {...valid, expires_at_utc: "2028-03-07T00:02:03.124456Z"},
  ]) {
    assert.throws(
      () => parseOrganizationShareableJoinLinkCreateResult(
        row,
        linkId,
        workspaceId,
      ),
      /invalid organization shareable join link create result/,
    );
  }
});

test("preview result requires exact fields, link binding, name, and UTC", () => {
  const valid = {
    organization_shareable_join_link_preview_contract_id:
      "organization-shareable-join-link-preview:v1",
    link_id: linkId.toUpperCase(),
    organization_name: " 同行组织 ",
    expires_at_utc: "2030-01-08T01:00:00.999999+01:00",
  };
  assert.deepEqual(
    parseOrganizationShareableJoinLinkPreviewResult(valid, linkId),
    {...previewResult, expiresAtUtc: "2030-01-08T00:00:00.999Z"},
  );
  for (const row of [
    {...valid, organization_workspace_id: workspaceId},
    {...valid, organization_shareable_join_link_preview_contract_id: "wrong:v1"},
    {...valid, link_id: otherId},
    {...valid, organization_name: "   "},
    {...valid, organization_name: null},
    {...valid, expires_at_utc: "2030-02-30T00:00:00Z"},
    {...valid, expires_at_utc: "infinity"},
  ]) {
    assert.throws(
      () => parseOrganizationShareableJoinLinkPreviewResult(row, linkId),
      /invalid organization shareable join link preview result/,
    );
  }
});

test("store maps only exact SQLSTATE and message pairs", async () => {
  const cases = [
    [
      "22023",
      "invalid organization shareable join identity",
      "organization_shareable_join_unavailable",
    ],
    [
      "22023",
      "invalid organization shareable join request",
      "invalid_organization_shareable_join_request",
    ],
    [
      "42501",
      "organization shareable join forbidden",
      "organization_shareable_join_forbidden",
    ],
    [
      "22023",
      "organization shareable join idempotency conflict",
      "organization_shareable_join_conflict",
    ],
  ] as const;
  for (const operation of ["create", "preview"] as const) {
    for (const [sqlState, message, expectedCode] of cases) {
      const store = new PostgresOrganizationShareableJoinLinkStore(
        async () => {
          throw Object.assign(new Error(message), {code: sqlState});
        },
      );
      await assert.rejects(
        operation === "create"
          ? store.create(identity, linkId, workspaceId)
          : store.preview(identity, linkId),
        (error: unknown) =>
          error instanceof OrganizationShareableJoinLinkStoreError &&
          error.code === expectedCode,
      );
    }
  }
  for (const error of [
    Object.assign(new Error("organization shareable join forbidden"), {
      code: "22023",
    }),
    Object.assign(new Error("database secret"), {code: "42501"}),
    Object.assign(new Error("constraint secret"), {code: "23505"}),
  ]) {
    const store = new PostgresOrganizationShareableJoinLinkStore(
      async () => { throw error; },
    );
    await assert.rejects(
      store.preview(identity, linkId),
      (received: unknown) =>
        received instanceof Error &&
        received.message === "organization shareable join store unavailable",
    );
  }
});

test("handler maps typed and unknown store failures to the stable surface", async () => {
  for (const [code, status] of [
    ["invalid_organization_shareable_join_request", 400],
    ["organization_shareable_join_forbidden", 403],
    ["organization_shareable_join_conflict", 409],
    ["organization_shareable_join_unavailable", 503],
  ] as const) {
    assert.deepEqual(
      await handleOrganizationShareableJoinLink(
        createRequest({link_id: linkId}),
        {
          identityVerifier: verifier(),
          linkStore: linkStore({
            create: async () => {
              throw new OrganizationShareableJoinLinkStoreError(code);
            },
          }),
        },
      ),
      {status, body: {error: {code}}},
    );
  }
  assert.deepEqual(
    await handleOrganizationShareableJoinLink(previewRequest(), {
      identityVerifier: verifier(),
      linkStore: linkStore({
        preview: async () => { throw new Error("database secret"); },
      }),
    }),
    {
      status: 503,
      body: {error: {code: "organization_shareable_join_unavailable"}},
    },
  );
});

test("first success and exact replay retain the same minimal receipts", async () => {
  const dependencies = {identityVerifier: verifier(), linkStore: linkStore()};
  for (const request of [
    createRequest({link_id: linkId}),
    previewRequest(),
  ]) {
    const first = await handleOrganizationShareableJoinLink(
      request,
      dependencies,
    );
    const replay = await handleOrganizationShareableJoinLink(
      request,
      dependencies,
    );
    assert.deepEqual(replay, first);
    assert.equal(first.status, 200);
    assert.equal(Object.keys(first.body).length, request.operation === "create" ? 5 : 4);
    assert.equal("replayed" in first.body, false);
    assert.equal("creator_app_user_id" in first.body, false);
  }
});
