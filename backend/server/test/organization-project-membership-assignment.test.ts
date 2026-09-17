import assert from "node:assert/strict";
import test from "node:test";

import {
  OrganizationProjectMembershipAssignmentStoreError,
  PostgresOrganizationProjectMembershipAssignmentStore,
  parseOrganizationProjectMembershipAssignmentResult,
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
