import assert from "node:assert/strict";
import test from "node:test";
import {IdentityVerificationError} from "../src/identity.js";

import {
  handleOrganizationShareableJoinApplication,
  matchOrganizationShareableJoinApplicationRequestTarget,
  OrganizationShareableJoinApplicationStoreError,
  parseOrganizationShareableJoinApplicationApproveBody,
  parseOrganizationShareableJoinApplicationApproveResult,
  parseOrganizationShareableJoinApplicationDirectoryResult,
  parseOrganizationShareableJoinApplicationSubmitBody,
  parseOrganizationShareableJoinApplicationSubmitResult,
  PostgresOrganizationShareableJoinApplicationStore,
  type OrganizationShareableJoinApplicationRequest,
  type OrganizationShareableJoinApplicationStore,
} from "../src/organization-shareable-join-applications.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const linkId = "123e4567-e89b-12d3-a456-426614174001";
const applicationId = "123e4567-e89b-12d3-a456-426614174002";
const membershipId = "123e4567-e89b-12d3-a456-426614174003";
const identity = {issuer: "https://issuer.example", subject: "subject"};
const submitResult = {
  organizationShareableJoinApplicationContractId:
    "organization-shareable-join-application:v1" as const,
  applicationId,
  linkId,
  organizationWorkspaceId: workspaceId,
  submittedAtUtc: "2030-01-01T00:00:00.000Z",
  expiresAtUtc: "2030-01-08T00:00:00.000Z",
};
const approveResult = {
  organizationShareableJoinApplicationContractId:
    "organization-shareable-join-application:v1" as const,
  applicationId,
  organizationWorkspaceId: workspaceId,
  organizationMembershipId: membershipId,
  approvedAtUtc: "2030-01-02T00:00:00.000Z",
};

test("matches only exact raw submit and approve targets", () => {
  assert.deepEqual(
    matchOrganizationShareableJoinApplicationRequestTarget(
      `/v1/organization-shareable-join-links/${linkId}/applications`,
    ),
    {operation: "submit", linkId, hasQuery: false},
  );
  assert.deepEqual(
    matchOrganizationShareableJoinApplicationRequestTarget(
      `/v1/organizations/${workspaceId}/shareable-join-applications/${applicationId}/approve?x=1`,
    ),
    {operation: "approve", workspaceId, applicationId, hasQuery: true},
  );
  for (const target of [
    `/v1/organization-shareable-join-links/${linkId}/applications/`,
    `/v1/organization-shareable-join-links/%31${linkId.slice(1)}/applications`,
    `/v1/organization-shareable-join-links/./applications`,
    `/v1/organizations/${workspaceId}/shareable-join-applications/${applicationId}/approve/`,
    `/v1/organizations/${workspaceId}/shareable-join-applications/%2e/approve`,
  ]) {
    assert.equal(matchOrganizationShareableJoinApplicationRequestTarget(target), null);
  }
});

test("body parsers require exact fields and lowercase UUID output", () => {
  assert.deepEqual(
    parseOrganizationShareableJoinApplicationSubmitBody({
      application_id: applicationId.toUpperCase(),
    }),
    {applicationId},
  );
  for (const value of [{}, {application_id: applicationId, extra: true}, []]) {
    assert.equal(parseOrganizationShareableJoinApplicationSubmitBody(value), null);
  }
  assert.deepEqual(parseOrganizationShareableJoinApplicationApproveBody({}), {});
  assert.equal(parseOrganizationShareableJoinApplicationApproveBody({x: 1}), null);
});

test("handlers authenticate before validation and dependencies", async () => {
  let readCalls = 0;
  const request: OrganizationShareableJoinApplicationRequest = {
    operation: "submit" as const,
    linkId: "bad",
    hasQuery: true,
    authorization: undefined,
    readBody: async () => { readCalls += 1; return {}; },
  };
  assert.deepEqual(await handleOrganizationShareableJoinApplication(request, {
    identityVerifier: undefined,
    applicationStore: undefined,
  }), {status: 401, body: {error: {code: "unauthenticated"}}});
  const authorizedRequest = {...request, authorization: "Bearer token"};
  assert.deepEqual(await handleOrganizationShareableJoinApplication(authorizedRequest, {
    identityVerifier: {verify: async () => identity},
    applicationStore: undefined,
  }), {status: 400, body: {error: {code: "invalid_organization_shareable_join_request"}}});
  const validTargetRequest = {...authorizedRequest, hasQuery: false, linkId};
  assert.deepEqual(await handleOrganizationShareableJoinApplication(validTargetRequest, {
    identityVerifier: {verify: async () => identity},
    applicationStore: undefined,
  }), {status: 503, body: {error: {code: "organization_shareable_join_unavailable"}}});
  assert.equal(readCalls, 0);
});

test("handlers bind verified identity and exact receipts", async () => {
  let submitArgs: unknown;
  let approveArgs: unknown;
  const store: OrganizationShareableJoinApplicationStore = {
    listPending: async () => directoryResult(),
    submit: async (...args) => { submitArgs = args; return submitResult; },
    approve: async (...args) => { approveArgs = args; return approveResult; },
  };
  const dependencies = {
    identityVerifier: {verify: async () => identity}, applicationStore: store,
  };
  assert.deepEqual(await handleOrganizationShareableJoinApplication({
    operation: "submit", linkId: linkId.toUpperCase(), hasQuery: false,
    authorization: "Bearer token",
    readBody: async () => ({application_id: applicationId.toUpperCase()}),
  }, dependencies), {status: 200, body: {
    organization_shareable_join_application_contract_id:
      "organization-shareable-join-application:v1",
    application_id: applicationId, link_id: linkId,
    organization_workspace_id: workspaceId,
    submitted_at_utc: submitResult.submittedAtUtc,
    expires_at_utc: submitResult.expiresAtUtc,
  }});
  assert.deepEqual(submitArgs, [identity, applicationId, linkId]);
  assert.deepEqual(await handleOrganizationShareableJoinApplication({
    operation: "approve", workspaceId: workspaceId.toUpperCase(),
    applicationId: applicationId.toUpperCase(), hasQuery: false,
    authorization: "Bearer token", readBody: async () => ({}),
  }, dependencies), {status: 200, body: {
    organization_shareable_join_application_contract_id:
      "organization-shareable-join-application:v1",
    application_id: applicationId, organization_workspace_id: workspaceId,
    organization_membership_id: membershipId,
    approved_at_utc: approveResult.approvedAtUtc,
  }});
  assert.deepEqual(approveArgs, [identity, applicationId, workspaceId]);
});

test("store uses only exact 0093 and 0094 bridges and validates rows", async () => {
  const calls: Array<[string, readonly unknown[]]> = [];
  const rows = [
    {
      organization_shareable_join_application_contract_id:
        "organization-shareable-join-application:v1",
      application_id: applicationId.toUpperCase(), link_id: linkId.toUpperCase(),
      organization_workspace_id: workspaceId.toUpperCase(),
      submitted_at_utc: "2030-01-01T00:00:00Z",
      expires_at_utc: "2030-01-08T00:00:00Z",
    },
    {
      organization_shareable_join_application_contract_id:
        "organization-shareable-join-application:v1",
      application_id: applicationId, organization_workspace_id: workspaceId,
      organization_membership_id: membershipId,
      approved_at_utc: new Date("2030-01-02T00:00:00Z"),
    },
  ];
  const store = new PostgresOrganizationShareableJoinApplicationStore(
    async (text, values) => {
      calls.push([text, values]);
      return {rows: [rows[calls.length - 1]]};
    },
  );
  assert.deepEqual(await store.submit(identity, applicationId, linkId), submitResult);
  assert.deepEqual(await store.approve(identity, applicationId, workspaceId), approveResult);
  assert.match(calls[0]![0], /app_data\.submit_organization_shareable_join_application_for_identity_v1/);
  assert.match(calls[1]![0], /app_data\.approve_organization_shareable_join_application_for_identity_v1/);
  assert.deepEqual(calls[0]![1], [identity.issuer, identity.subject, applicationId, linkId]);
  assert.deepEqual(calls[1]![1], [identity.issuer, identity.subject, applicationId, workspaceId]);
});

test("result parsers reject drift and store errors stay stable", async () => {
  for (const parse of [
    () => parseOrganizationShareableJoinApplicationSubmitResult(
      {...wireSubmit(), extra: true}, applicationId, linkId),
    () => parseOrganizationShareableJoinApplicationSubmitResult(
      {...wireSubmit(), organization_shareable_join_application_contract_id: "wrong"},
      applicationId, linkId),
    () => parseOrganizationShareableJoinApplicationSubmitResult(
      {...wireSubmit(), application_id: membershipId}, applicationId, linkId),
    () => parseOrganizationShareableJoinApplicationSubmitResult(
      {...wireSubmit(), link_id: membershipId}, applicationId, linkId),
    () => parseOrganizationShareableJoinApplicationSubmitResult(
      {...wireSubmit(), organization_workspace_id: "not-a-uuid"}, applicationId, linkId),
    () => parseOrganizationShareableJoinApplicationSubmitResult(
      {...wireSubmit(), submitted_at_utc: "2030-01-01T00:00:00"}, applicationId, linkId),
    () => parseOrganizationShareableJoinApplicationSubmitResult(
      {...wireSubmit(), expires_at_utc: "2030-01-07T00:00:00Z"}, applicationId, linkId),
    () => parseOrganizationShareableJoinApplicationApproveResult(
      {...wireApprove(), extra: true}, applicationId, workspaceId),
    () => parseOrganizationShareableJoinApplicationApproveResult(
      {...wireApprove(), organization_shareable_join_application_contract_id: "wrong"},
      applicationId, workspaceId),
    () => parseOrganizationShareableJoinApplicationApproveResult(
      {...wireApprove(), application_id: membershipId}, applicationId, workspaceId),
    () => parseOrganizationShareableJoinApplicationApproveResult(
      {...wireApprove(), organization_workspace_id: linkId}, applicationId, workspaceId),
    () => parseOrganizationShareableJoinApplicationApproveResult(
      {...wireApprove(), organization_membership_id: "not-a-uuid"}, applicationId, workspaceId),
    () => parseOrganizationShareableJoinApplicationApproveResult(
      {...wireApprove(), approved_at_utc: "2030-02-30T00:00:00Z"}, applicationId, workspaceId),
  ]) {
    assert.throws(parse);
  }
  for (const [databaseCode, message, expected] of [
    ["22023", "invalid organization shareable join request", "invalid_organization_shareable_join_request"],
    ["42501", "organization shareable join forbidden", "organization_shareable_join_forbidden"],
    ["22023", "organization shareable join idempotency conflict", "organization_shareable_join_conflict"],
  ] as const) {
    const store = new PostgresOrganizationShareableJoinApplicationStore(async () => {
      throw {code: databaseCode, message};
    });
    await assert.rejects(store.submit(identity, applicationId, linkId), (error: unknown) =>
      error instanceof OrganizationShareableJoinApplicationStoreError &&
      error.code === expected);
  }
});

test("store rejects zero or duplicate rows for both bridge shapes", async () => {
  for (const operation of ["submit", "approve"] as const) {
    for (const rows of [[], [wireSubmit(), wireSubmit()]]) {
      const store = new PostgresOrganizationShareableJoinApplicationStore(
        async () => ({rows: operation === "submit"
          ? rows
          : rows.map(() => wireApprove())}),
      );
      await assert.rejects(operation === "submit"
        ? store.submit(identity, applicationId, linkId)
        : store.approve(identity, applicationId, workspaceId));
    }
  }
});

test("identity and unknown database failures map only to unavailable", async () => {
  const cases = [
    [{code: "22023", message: "invalid organization shareable join identity"}, true],
    [{code: "XX000", message: "sensitive database detail"}, false],
  ] as const;
  for (const [databaseError, typed] of cases) {
    const store = new PostgresOrganizationShareableJoinApplicationStore(
      async () => { throw databaseError; },
    );
    await assert.rejects(store.submit(identity, applicationId, linkId), (error: unknown) => {
      if (typed) {
        return error instanceof OrganizationShareableJoinApplicationStoreError &&
          error.code === "organization_shareable_join_unavailable";
      }
      return error instanceof Error &&
        !(error instanceof OrganizationShareableJoinApplicationStoreError) &&
        error.message === "organization shareable join application store unavailable" &&
        !error.message.includes(databaseError.message);
    });
  }
});

test("handler maps each typed store outcome to its stable status", async () => {
  for (const [code, status] of [
    ["invalid_organization_shareable_join_request", 400],
    ["organization_shareable_join_forbidden", 403],
    ["organization_shareable_join_conflict", 409],
    ["organization_shareable_join_unavailable", 503],
  ] as const) {
    const result = await handleOrganizationShareableJoinApplication({
      operation: "submit", linkId, hasQuery: false,
      authorization: "Bearer token",
      readBody: async () => ({application_id: applicationId}),
    }, {
      identityVerifier: {verify: async () => identity},
      applicationStore: {
        listPending: async () => directoryResult(),
        submit: async () => { throw new OrganizationShareableJoinApplicationStoreError(code); },
        approve: async () => approveResult,
      },
    });
    assert.deepEqual(result, {status, body: {error: {code}}});
  }
});

function wireSubmit() {
  return {
    organization_shareable_join_application_contract_id:
      "organization-shareable-join-application:v1",
    application_id: applicationId, link_id: linkId,
    organization_workspace_id: workspaceId,
    submitted_at_utc: "2030-01-01T00:00:00Z",
    expires_at_utc: "2030-01-08T00:00:00Z",
  };
}

function wireApprove() {
  return {
    organization_shareable_join_application_contract_id:
      "organization-shareable-join-application:v1",
    application_id: applicationId, organization_workspace_id: workspaceId,
    organization_membership_id: membershipId,
    approved_at_utc: "2030-01-02T00:00:00Z",
  };
}

function wireDirectory() {
  return {
    organization_shareable_join_application_directory_contract_id:
      "organization-shareable-join-application-directory:v1",
    organization_workspace_id: workspaceId,
    observed_at_utc: "2030-01-02T00:00:00.000001Z",
    applications: [{application_id: applicationId, link_id: linkId,
      submitted_at_utc: "2030-01-01T00:00:00.123456Z",
      expires_at_utc: "2030-01-08T00:00:00.123456Z"}],
  };
}

function directoryResult() {
  return parseOrganizationShareableJoinApplicationDirectoryResult(wireDirectory(), workspaceId);
}

test("pending directory matches raw target and authenticates before GET shape or store", async () => {
  const path = `/v1/organizations/${workspaceId}/shareable-join-applications`;
  assert.deepEqual(matchOrganizationShareableJoinApplicationRequestTarget(path),
    {operation: "listPending", workspaceId, hasQuery: false});
  for (const target of [path + "/", path.replace(workspaceId, "%31" + workspaceId.slice(1)),
    path.replace(workspaceId, "."), path.replace(workspaceId, ".."),
    path.replace("/organizations/", "/organizations//")]) {
    assert.equal(matchOrganizationShareableJoinApplicationRequestTarget(target), null);
  }
  let reads = 0;
  let calls = 0;
  const request: OrganizationShareableJoinApplicationRequest = {
    operation: "listPending", workspaceId: "bad", hasQuery: true, hasBody: true,
    authorization: undefined, readBody: async () => { reads++; throw new Error("must not read"); },
  };
  assert.equal((await handleOrganizationShareableJoinApplication(request,
    {identityVerifier: undefined, applicationStore: undefined})).status, 401);
  for (const shape of [{hasQuery: true, hasBody: false}, {hasQuery: false, hasBody: true},
    {hasQuery: false, hasBody: false, workspaceId: "bad"}]) {
    const response = await handleOrganizationShareableJoinApplication(
      {...request, workspaceId, authorization: "Bearer token", ...shape},
      {identityVerifier: {verify: async () => {calls++; return identity;}}, applicationStore: undefined});
    assert.deepEqual(response, {status: 400, body: {error: {code: "invalid_organization_shareable_join_request"}}});
  }
  assert.equal(calls, 3);
  assert.equal(reads, 0);
  const args: unknown[][] = [];
  const result = await handleOrganizationShareableJoinApplication(
    {...request, workspaceId: workspaceId.toUpperCase(), hasQuery: false, hasBody: false,
      authorization: "Bearer token"},
    {identityVerifier: {verify: async () => identity}, applicationStore: {
      listPending: async (...values) => {args.push(values); return directoryResult();},
      submit: async () => submitResult, approve: async () => approveResult,
    }});
  assert.equal(result.status, 200);
  assert.deepEqual(args, [[identity, workspaceId]]);
  assert.equal(reads, 0);
  assert.deepEqual(result.body, {...wireDirectory(), observed_at_utc: "2030-01-02T00:00:00.000Z",
    applications: [{application_id: applicationId, link_id: linkId,
      submitted_at_utc: "2030-01-01T00:00:00.123Z", expires_at_utc: "2030-01-08T00:00:00.123Z"}]});
});

test("pending directory strict parser bounds shapes, duplicate IDs, order, selector and instants", () => {
  const valid = wireDirectory();
  const item = valid.applications[0]!;
  const another = {...item, application_id: membershipId};
  const malformed = [null, [], {...valid, extra: true},
    {...valid, organization_shareable_join_application_directory_contract_id: "wrong"},
    {...valid, organization_workspace_id: linkId}, {...valid, organization_workspace_id: "bad"},
    {...valid, organization_workspace_id: workspaceId.toUpperCase()},
    {...valid, observed_at_utc: "2030-02-30T00:00:00Z"},
    {...valid, observed_at_utc: "2030-01-02T00:00:00"}, {...valid, applications: {}},
    {...valid, applications: Array.from({length: 21}, () => item)},
    {...valid, applications: [item, item]}, {...valid, applications: [another, item]},
    ...[null, [], {...item, extra: true}, {...item, applicant_app_user_id: membershipId},
      {...item, application_id: "bad"}, {...item, link_id: "bad"},
      {...item, application_id: applicationId.toUpperCase()}, {...item, link_id: linkId.toUpperCase()},
      {...item, submitted_at_utc: "2030-01-01T00:00:00"},
      {...item, submitted_at_utc: "2030-01-01T00:00:00.123Z"},
      {...item, submitted_at_utc: new Date("2030-01-01T00:00:00.123Z")},
      {...item, submitted_at_utc: "2030-01-01T01:00:00.123456+01:00"},
      {...item, expires_at_utc: "2030-01-08T00:00:00.123Z"},
      {...item, expires_at_utc: "2030-01-08T00:00:00.123457Z"},
      {...item, expires_at_utc: "2030-01-07T00:00:00.123456Z"}]
      .map((bad) => ({...valid, applications: [bad]})),
    {...valid, applications: [item, {...another,
      submitted_at_utc: "2030-01-01T00:00:00.123455Z",
      expires_at_utc: "2030-01-08T00:00:00.123455Z"}]},
    {...valid, observed_at_utc: "2030-01-08T00:00:00.124Z"},
  ];
  for (const value of malformed) {
    assert.throws(() => parseOrganizationShareableJoinApplicationDirectoryResult(value, workspaceId));
  }
  assert.deepEqual(parseOrganizationShareableJoinApplicationDirectoryResult(
    {...valid, applications: []}, workspaceId).applications, []);
  const twenty = Array.from({length: 20}, (_, index) => ({...item,
    application_id: `123e4567-e89b-12d3-a456-${String(index).padStart(12, "0")}`}));
  assert.equal(parseOrganizationShareableJoinApplicationDirectoryResult(
    {...valid, applications: twenty}, workspaceId).applications.length, 20);
  assert.equal(parseOrganizationShareableJoinApplicationDirectoryResult(
    {...valid, observed_at_utc: "2030-01-08T00:00:00.123455Z"}, workspaceId).observedAtUtc,
    "2030-01-08T00:00:00.123Z");
  assert.equal(parseOrganizationShareableJoinApplicationDirectoryResult(
    {...valid, observed_at_utc: new Date("2030-01-08T00:00:00.123Z")}, workspaceId).applications.length, 1);
  assert.equal(parseOrganizationShareableJoinApplicationDirectoryResult(
    {...valid, observed_at_utc: "2030-01-02T01:00:00.000001+01:00"}, workspaceId)
    .observedAtUtc, "2030-01-02T00:00:00.000Z");
});

test("pending directory uses a single fixed runtime SELECT and family stable mappings", async () => {
  let calls = 0;
  const store = new PostgresOrganizationShareableJoinApplicationStore(async (text, values) => {
    calls++;
    assert.match(text, /FROM app_data\.list_org_join_applications_for_identity_v1\(/);
    assert.doesNotMatch(text, /app_private|SessionContext/);
    assert.deepEqual(values, [identity.issuer, identity.subject, workspaceId]);
    return {rows: [wireDirectory()]};
  });
  assert.deepEqual(await store.listPending(identity, workspaceId), directoryResult());
  assert.equal(calls, 1);
  for (const rows of [[], [wireDirectory(), wireDirectory()], [{...wireDirectory(), extra: true}]]) {
    await assert.rejects(new PostgresOrganizationShareableJoinApplicationStore(async () => ({rows}))
      .listPending(identity, workspaceId));
  }
  for (const [code, message, expected] of [
    ["22023", "invalid organization shareable join application directory identity", "organization_shareable_join_unavailable"],
    ["22023", "invalid organization shareable join application directory request", "invalid_organization_shareable_join_request"],
    ["42501", "organization shareable join application directory forbidden", "organization_shareable_join_forbidden"],
  ] as const) {
    await assert.rejects(new PostgresOrganizationShareableJoinApplicationStore(async () => {throw {code, message};})
      .listPending(identity, workspaceId), (error: unknown) => error instanceof OrganizationShareableJoinApplicationStoreError && error.code === expected);
  }
  for (const error of [{code: "XX000", message: "sensitive"},
    {code: "22023", message: "organization shareable join application directory forbidden"}]) {
    await assert.rejects(new PostgresOrganizationShareableJoinApplicationStore(async () => {throw error;})
      .listPending(identity, workspaceId), (value: unknown) => value instanceof Error && !value.message.includes("sensitive"));
  }
});

test("pending directory verifier failures win over invalid GET shape", async () => {
  const request: OrganizationShareableJoinApplicationRequest = {
    operation: "listPending", workspaceId: "bad", hasQuery: true, hasBody: true,
    authorization: "Bearer token", readBody: async () => {throw new Error("must not read");},
  };
  assert.deepEqual(await handleOrganizationShareableJoinApplication(request,
    {identityVerifier: undefined, applicationStore: undefined}),
    {status: 503, body: {error: {code: "organization_shareable_join_unavailable"}}});
  for (const [error, status, code] of [
    [new IdentityVerificationError("unauthenticated"), 401, "unauthenticated"],
    [new IdentityVerificationError("unavailable"), 503, "organization_shareable_join_unavailable"],
    [new Error("sensitive verifier"), 503, "organization_shareable_join_unavailable"],
  ] as const) {
    assert.deepEqual(await handleOrganizationShareableJoinApplication(request,
      {identityVerifier: {verify: async () => {throw error;}}, applicationStore: undefined}),
      {status, body: {error: {code}}});
  }
});

test("pending SQL microsecond order survives HTTP millisecond projection without a false UUID tie", () => {
  const valid = wireDirectory();
  const item = valid.applications[0]!;
  const projected = parseOrganizationShareableJoinApplicationDirectoryResult({...valid,
    applications: [
      {...item, application_id: membershipId, submitted_at_utc: "2030-01-01T00:00:00.000001Z",
        expires_at_utc: "2030-01-08T00:00:00.000001Z"},
      {...item, application_id: applicationId, submitted_at_utc: "2030-01-01T00:00:00.000002Z",
        expires_at_utc: "2030-01-08T00:00:00.000002Z"},
    ]}, workspaceId);
  assert.deepEqual(projected.applications.map((entry) => entry.applicationId), [membershipId, applicationId]);
  assert.deepEqual(projected.applications.map((entry) => entry.submittedAtUtc),
    ["2030-01-01T00:00:00.000Z", "2030-01-01T00:00:00.000Z"]);
  assert.throws(() => parseOrganizationShareableJoinApplicationDirectoryResult({...valid,
    applications: [{...item, application_id: membershipId}, item]}, workspaceId));
});
