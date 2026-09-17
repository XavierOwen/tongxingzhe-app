import assert from "node:assert/strict";
import test from "node:test";
import { IdentityVerificationError } from "../src/identity.js";

import {
  OrganizationProjectMembershipAssignmentStoreError,
  PostgresOrganizationProjectMembershipAssignmentStore,
  parseOrganizationProjectMembershipAssignmentResult,
  handleOrganizationProjectMembershipAssignment,
  matchOrganizationProjectMembershipAssignmentRequestTarget,
  parseOrganizationProjectMembershipAssignmentBody,
  type OrganizationProjectMembershipAssignmentRequest,
} from "../src/organization-project-membership-assignment.js";

const requestId = "123e4567-e89b-12d3-a456-426614174000";
const workspaceId = "123e4567-e89b-12d3-a456-426614174001";
const projectId = "123e4567-e89b-12d3-a456-426614174002";
const targetMembershipId = "123e4567-e89b-12d3-a456-426614174003";
const projectMembershipId = "123e4567-e89b-12d3-a456-426614174004";
const identity = {
  issuer: " https://issuer.example/auth/v1 ",
  subject: " subject-123 ",
};

const validRow = {
  project_membership_assignment_contract_id:
    "organization-project-membership-assignment:v1",
  organization_workspace_id: workspaceId,
  project_id: projectId,
  organization_membership_id: targetMembershipId,
  project_membership_id: projectMembershipId,
  active_from_utc: "2030-01-01T00:00:00.123456Z",
  inactive_from_utc: null,
};

test("store makes one parameterized bridge call with exact identity and six values", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresOrganizationProjectMembershipAssignmentStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [validRow]};
    },
  );

  const result = await store.assign(
    identity,
    requestId,
    workspaceId,
    projectId,
    targetMembershipId,
  );

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.assign_organization_project_member_for_identity_v1/,
  );
  assert.match(calls[0]?.text ?? "", /\$1[\s\S]*\$2[\s\S]*\$3[\s\S]*\$4[\s\S]*\$5[\s\S]*\$6/);
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private/);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    requestId,
    workspaceId,
    projectId,
    targetMembershipId,
  ]);
  assert.deepEqual(result, {
    projectMembershipAssignmentContractId:
      "organization-project-membership-assignment:v1",
    organizationWorkspaceId: workspaceId,
    projectId,
    organizationMembershipId: targetMembershipId,
    projectMembershipId,
    activeFromUtc: "2030-01-01T00:00:00.123Z",
    inactiveFromUtc: null,
  });
});

test("result parser canonicalizes UUIDs and finite timestamps", () => {
  assert.deepEqual(
    parseOrganizationProjectMembershipAssignmentResult(
      {
        ...validRow,
        organization_workspace_id: workspaceId.toUpperCase(),
        project_id: projectId.toUpperCase(),
        organization_membership_id: targetMembershipId.toUpperCase(),
        project_membership_id: projectMembershipId.toUpperCase(),
        active_from_utc: new Date("2030-01-01T00:00:00.123Z"),
        inactive_from_utc: "2030-01-02T01:02:03.004000+01:00",
      },
      workspaceId,
      projectId,
      targetMembershipId,
    ),
    {
      projectMembershipAssignmentContractId:
        "organization-project-membership-assignment:v1",
      organizationWorkspaceId: workspaceId,
      projectId,
      organizationMembershipId: targetMembershipId,
      projectMembershipId,
      activeFromUtc: "2030-01-01T00:00:00.123Z",
      inactiveFromUtc: "2030-01-02T00:02:03.004Z",
    },
  );

  assert.deepEqual(
    parseOrganizationProjectMembershipAssignmentResult(
      {
        ...validRow,
        active_from_utc: "2030-02-28T23:59:59.999999-05:00",
        inactive_from_utc: "2030-03-01T00:00:00.000001-05:00",
      },
      workspaceId,
      projectId,
      targetMembershipId,
    ).inactiveFromUtc,
    "2030-03-01T05:00:00.000Z",
  );
});

test("result parser accepts a sub-millisecond interval whose projected dates are equal", () => {
  const result = parseOrganizationProjectMembershipAssignmentResult(
    {
      ...validRow,
      active_from_utc: "2030-01-01T00:00:00.123456Z",
      inactive_from_utc: "2030-01-01T00:00:00.123789Z",
    },
    workspaceId,
    projectId,
    targetMembershipId,
  );

  assert.equal(result.activeFromUtc, "2030-01-01T00:00:00.123Z");
  assert.equal(result.inactiveFromUtc, "2030-01-01T00:00:00.123Z");
});

test("result parser rejects mismatched selectors, contract drift, and every non-exact row shape", () => {
  const invalidRows: unknown[] = [
    {...validRow, extra: true},
    Object.fromEntries(Object.entries(validRow).filter(([key]) => key !== "project_id")),
    {...validRow, project_id: undefined},
    {...validRow, inactive_from_utc: undefined},
    {...validRow, project_membership_id: null},
    {...validRow, actor_app_user_id: "not-allowed"},
    {...validRow, owner_assignment_id: "not-allowed"},
    {...validRow, project_membership_assignment_contract_id: "wrong:v1"},
    {...validRow, organization_workspace_id: targetMembershipId},
    {...validRow, project_id: targetMembershipId},
    {...validRow, organization_membership_id: projectId},
    {...validRow, active_from_utc: ""},
    {...validRow, active_from_utc: "-Infinity"},
    {...validRow, active_from_utc: new Date(Number.NaN)},
    {...validRow, active_from_utc: new Date(Number.POSITIVE_INFINITY)},
    {...validRow, active_from_utc: "2030-02-30T00:00:00Z"},
    {...validRow, active_from_utc: "2030-04-31T00:00:00Z"},
    {...validRow, inactive_from_utc: "2029-12-31T23:59:59.999Z"},
    null,
    undefined,
  ];

  for (const row of invalidRows) {
    assert.throws(() =>
      parseOrganizationProjectMembershipAssignmentResult(
        row,
        workspaceId,
        projectId,
        targetMembershipId,
      ),
    );
  }

  for (const [expectedWorkspaceId, expectedProjectId, expectedTargetId] of [
    [targetMembershipId, projectId, targetMembershipId],
    [workspaceId, targetMembershipId, targetMembershipId],
    [workspaceId, projectId, projectId],
  ] as const) {
    assert.throws(() =>
      parseOrganizationProjectMembershipAssignmentResult(
        validRow,
        expectedWorkspaceId,
        expectedProjectId,
        expectedTargetId,
      ),
    );
  }
});

test("store maps only the five exact SQLSTATE/message pairs", async () => {
  const cases = [
    [
      "22023",
      "invalid organization project membership assignment identity",
      "organization_project_membership_assignment_unavailable",
    ],
    [
      "22023",
      "invalid organization project membership assignment request",
      "invalid_organization_project_membership_assignment_request",
    ],
    [
      "42501",
      "organization project membership assignment forbidden",
      "organization_project_membership_assignment_forbidden",
    ],
    [
      "22023",
      "organization project membership assignment idempotency conflict",
      "organization_project_membership_assignment_conflict",
    ],
    [
      "0A000",
      "organization project membership assignment requires read committed",
      "organization_project_membership_assignment_unavailable",
    ],
  ] as const;

  for (const [sqlState, message, expectedCode] of cases) {
    const store = new PostgresOrganizationProjectMembershipAssignmentStore(
      async () => {
        throw Object.assign(new Error(message), {code: sqlState});
      },
    );
    await assert.rejects(
      store.assign(
        identity,
        requestId,
        workspaceId,
        projectId,
        targetMembershipId,
      ),
      (error: unknown) =>
        error instanceof OrganizationProjectMembershipAssignmentStoreError &&
        error.code === expectedCode,
    );
  }
});

test("unknown SQLSTATE, message, constraint, parser, and row-count errors are typed unavailable without leakage", async () => {
  const failures: unknown[] = [
    Object.assign(new Error("secret database detail"), {code: "22023"}),
    Object.assign(new Error("constraint detail"), {code: "23505", constraint: "secret_constraint"}),
    new Error("provider parser secret"),
  ];

  for (const failure of failures) {
    const store = new PostgresOrganizationProjectMembershipAssignmentStore(
      async () => {
        throw failure;
      },
    );
    await assert.rejects(
      store.assign(
        identity,
        requestId,
        workspaceId,
        projectId,
        targetMembershipId,
      ),
      (error: unknown) =>
        error instanceof OrganizationProjectMembershipAssignmentStoreError &&
        error.code === "organization_project_membership_assignment_unavailable" &&
        !error.message.includes("secret") &&
        !error.message.includes("constraint") &&
        !error.message.includes("provider"),
    );
  }

  for (const rows of [[], [validRow, validRow]]) {
    const store = new PostgresOrganizationProjectMembershipAssignmentStore(
      async () => ({rows}),
    );
    await assert.rejects(
      store.assign(
        identity,
        requestId,
        workspaceId,
        projectId,
        targetMembershipId,
      ),
      (error: unknown) =>
        error instanceof OrganizationProjectMembershipAssignmentStoreError &&
        error.code === "organization_project_membership_assignment_unavailable",
    );
  }
});

const validBody = { request_id: requestId, target_organization_membership_id: targetMembershipId };
const storeResult = parseOrganizationProjectMembershipAssignmentResult(
  validRow, workspaceId, projectId, targetMembershipId,
);
const handlerRequest: OrganizationProjectMembershipAssignmentRequest = {
  authorization: "Bearer access-token",
  workspaceId,
  projectId,
  hasQuery: false,
  readBody: async () => validBody,
};

test("handler verifies then reads then assigns canonical selectors and serializes exactly seven fields", async () => {
  const events: string[] = [];
  const result = await handleOrganizationProjectMembershipAssignment({
    ...handlerRequest,
    workspaceId: workspaceId.toUpperCase(),
    projectId: projectId.toUpperCase(),
    readBody: async () => {
      events.push("body");
      return { request_id: requestId.toUpperCase(), target_organization_membership_id: targetMembershipId.toUpperCase() };
    },
  }, {
    identityVerifier: { verify: async (token) => {
      events.push("verify"); assert.equal(token, "access-token"); return identity;
    } },
    assignmentStore: { assign: async (...args) => {
      events.push("assign");
      assert.deepEqual(args, [identity, requestId, workspaceId, projectId, targetMembershipId]);
      return { ...storeResult, actor: "not serialized", capability: "not serialized", replay: true };
    } },
  });
  assert.deepEqual(events, ["verify", "body", "assign"]);
  assert.deepEqual(result, { status: 200, body: { ...validRow, active_from_utc: "2030-01-01T00:00:00.123Z" } });
});

test("body parser allows only the two UUID fields and no actor, role, capability, time or foreign scope", () => {
  assert.deepEqual(parseOrganizationProjectMembershipAssignmentBody({
    request_id: requestId.toUpperCase(), target_organization_membership_id: targetMembershipId.toUpperCase(),
  }), { requestId, targetOrganizationMembershipId: targetMembershipId });
  for (const value of [null, [], "body", {}, { request_id: requestId },
    { target_organization_membership_id: targetMembershipId },
    ...["actor", "app_user_id", "issuer", "subject", "role", "capability", "active_from_utc", "inactive_from_utc",
      "workspace_id", "organization_workspace_id", "project_id", "extra"].map((key) => ({ ...validBody, [key]: "untrusted" })),
    ...[null, undefined, 1, "", "not-a-uuid", ` ${requestId}`].map((value) => ({ ...validBody, request_id: value })),
    ...[null, undefined, 1, "", "not-a-uuid", `${targetMembershipId} `].map((value) => ({ ...validBody, target_organization_membership_id: value })),
  ]) assert.equal(parseOrganizationProjectMembershipAssignmentBody(value), null);
});

test("raw matcher preserves bare query and rejects aliases on both opaque selectors", () => {
  const path = `/v1/organizations/${workspaceId}/projects/${projectId}/memberships`;
  assert.deepEqual(matchOrganizationProjectMembershipAssignmentRequestTarget(`${path}?`), { workspaceId, projectId, hasQuery: true });
  assert.deepEqual(matchOrganizationProjectMembershipAssignmentRequestTarget(path), { workspaceId, projectId, hasQuery: false });
  for (const target of [undefined, `${path}/`, `${path}/extra`, path.replace("/projects/", "//projects/"),
    path.replace(workspaceId, "."), path.replace(workspaceId, ".."), path.replace(projectId, "."), path.replace(projectId, ".."),
    ...["%2e", "%2E%2E", "%41", "%2F"].flatMap((alias) => [path.replace(workspaceId, alias), path.replace(projectId, alias)]),
  ]) assert.equal(matchOrganizationProjectMembershipAssignmentRequestTarget(target), null);
});

test("authentication, query, both path UUIDs and missing store stop before body", async () => {
  let verifierCalls = 0;
  const verifier = { verify: async () => { verifierCalls += 1; return identity; } };
  const unread = async () => { throw new Error("body must not be read"); };
  const unusedStore = { assign: async () => { throw new Error("store must not be called"); } };
  for (const authorization of [undefined, "", "Bearer", "Basic token"]) {
    assert.deepEqual(await handleOrganizationProjectMembershipAssignment({
      ...handlerRequest, authorization, hasQuery: true, workspaceId: "invalid", projectId: "invalid", readBody: unread,
    }, { identityVerifier: verifier, assignmentStore: unusedStore }), { status: 401, body: { error: { code: "unauthenticated" } } });
  }
  assert.equal(verifierCalls, 0);
  assert.deepEqual(await handleOrganizationProjectMembershipAssignment({
    ...handlerRequest, hasQuery: true, readBody: unread,
  }, { identityVerifier: undefined, assignmentStore: undefined }), {
    status: 503, body: { error: { code: "organization_project_membership_assignment_unavailable" } },
  });
  for (const invalid of [{ hasQuery: true }, { workspaceId: "bad" }, { projectId: "bad" }]) {
    assert.deepEqual(await handleOrganizationProjectMembershipAssignment({
      ...handlerRequest, ...invalid, readBody: unread,
    }, { identityVerifier: verifier, assignmentStore: undefined }), {
      status: 400, body: { error: { code: "invalid_organization_project_membership_assignment_request" } },
    });
  }
  assert.equal(verifierCalls, 3);
  assert.deepEqual(await handleOrganizationProjectMembershipAssignment({
    ...handlerRequest, readBody: unread,
  }, { identityVerifier: verifier, assignmentStore: undefined }), {
    status: 503, body: { error: { code: "organization_project_membership_assignment_unavailable" } },
  });
});

test("verifier and typed store errors map only to stable public codes", async () => {
  for (const [error, status, code] of [
    [new IdentityVerificationError("unauthenticated"), 401, "unauthenticated"],
    [new IdentityVerificationError("unavailable"), 503, "organization_project_membership_assignment_unavailable"],
    [new Error("provider secret"), 503, "organization_project_membership_assignment_unavailable"],
  ] as const) {
    assert.deepEqual(await handleOrganizationProjectMembershipAssignment({
      ...handlerRequest, hasQuery: true, readBody: async () => { throw new Error("body must not run"); },
    }, { identityVerifier: { verify: async () => { throw error; } }, assignmentStore: undefined }), {
      status, body: { error: { code } },
    });
  }
  for (const [code, status] of [
    ["invalid_organization_project_membership_assignment_request", 400],
    ["organization_project_membership_assignment_forbidden", 403],
    ["organization_project_membership_assignment_conflict", 409],
    ["organization_project_membership_assignment_unavailable", 503],
  ] as const) {
    assert.deepEqual(await handleOrganizationProjectMembershipAssignment(handlerRequest, {
      identityVerifier: { verify: async () => identity },
      assignmentStore: { assign: async () => { throw new OrganizationProjectMembershipAssignmentStoreError(code); } },
    }), { status, body: { error: { code } } });
  }
  assert.deepEqual(await handleOrganizationProjectMembershipAssignment(handlerRequest, {
    identityVerifier: { verify: async () => identity },
    assignmentStore: { assign: async () => { throw new Error("database secret"); } },
  }), { status: 503, body: { error: { code: "organization_project_membership_assignment_unavailable" } } });
});

test("handler leaves body reader errors to shared HTTP handling, outside store catch", async () => {
  const readerError = new SyntaxError("invalid JSON");
  await assert.rejects(handleOrganizationProjectMembershipAssignment({
    ...handlerRequest, readBody: async () => { throw readerError; },
  }, {
    identityVerifier: { verify: async () => identity }, assignmentStore: { assign: async () => storeResult },
  }), (error: unknown) => error === readerError);
});
