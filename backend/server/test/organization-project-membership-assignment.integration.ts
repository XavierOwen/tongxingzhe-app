import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { Pool } from "pg";

import {
  PostgresOrganizationProjectMembershipAssignmentStore,
  OrganizationProjectMembershipAssignmentStoreError,
  type OrganizationProjectMembershipAssignmentResult,
} from "../src/organization-project-membership-assignment.js";

const databaseUrl = process.env.DATABASE_URL;
const fixturePath = process.env.ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for project membership assignment integration");
}
if (fixturePath === undefined || fixturePath.trim().length === 0) {
  throw new Error("ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE is required");
}
const fixtureSource = readFileSync(fixturePath, "utf8");
// Reuse only the seed; the fixture later owns separate isolation transactions.
const bootstrapEnd = fixtureSource.indexOf("CREATE TEMP TABLE fixture_0096_first AS");
assert.ok(bootstrapEnd > 0, "0096 fixture seed boundary is required");
const fixture = fixtureSource.slice(0, bootstrapEnd)
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "");
const identity = { issuer: "https://synthetic-0096.example", subject: " owner exact " };
const targetParent = "00000000-0096-4200-8000-000000000002";
const finiteProject = "00000000-0096-4300-8000-000000000001";
const nullableProject = "00000000-0096-4300-8000-000000000002";
const finiteRequest = "00000000-0096-5000-8000-000000000002";
const nullableRequest = "00000000-0096-5000-8000-000000000004";

test("runtime assignments preserve finite and null bounds with exact history replay", async () => {
  const pool = new Pool({ connectionString: databaseUrl });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    const org = (await client.query("SELECT * FROM fixture_0096_org")).rows[0];
    const parentEnd = (await client.query(
      "SELECT inactive_from_utc FROM app_data.organization_memberships WHERE organization_membership_id = $1::uuid",
      [targetParent],
    )).rows[0].inactive_from_utc as Date;
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const store = new PostgresOrganizationProjectMembershipAssignmentStore(
      async (text, values) => client.query(text, [...values]),
    );

    const finite = await store.assign(identity, finiteRequest,
      org.organization_workspace_id, finiteProject, targetParent);
    assert.deepEqual(await store.assign(identity, finiteRequest,
      org.organization_workspace_id, finiteProject, targetParent), finite);
    assertReceipt(finite);
    assert.equal(finite.organizationWorkspaceId, org.organization_workspace_id);
    assert.equal(finite.projectId, finiteProject);
    assert.equal(finite.organizationMembershipId, targetParent);
    assert.equal(finite.inactiveFromUtc, parentEnd.toISOString());

    const nullable = await store.assign(identity, nullableRequest,
      org.organization_workspace_id, nullableProject, org.organization_membership_id);
    assert.deepEqual(await store.assign(identity, nullableRequest,
      org.organization_workspace_id, nullableProject, org.organization_membership_id), nullable);
    assertReceipt(nullable);
    assert.equal(nullable.projectId, nullableProject);
    assert.equal(nullable.organizationMembershipId, org.organization_membership_id);
    assert.equal(nullable.inactiveFromUtc, null);

    await client.query("SAVEPOINT assignment_drift");
    await assert.rejects(store.assign(identity, finiteRequest,
      org.organization_workspace_id, nullableProject, targetParent),
    (error: unknown) => error instanceof OrganizationProjectMembershipAssignmentStoreError &&
      error.code === "organization_project_membership_assignment_conflict");
    await client.query("ROLLBACK TO SAVEPOINT assignment_drift");
    await client.query("RESET ROLE");
    const facts = (await client.query(`SELECT
      (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_request_claims
       WHERE request_id IN ($1::uuid, $2::uuid)) AS claims,
      (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_audit_events
       WHERE request_id IN ($1::uuid, $2::uuid)) AS audits`,
    [finiteRequest, nullableRequest])).rows[0];
    assert.deepEqual(facts, { claims: 2, audits: 2 });
    process.stdout.write("Backend project membership assignment runtime integration: passed\n");
  } finally {
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      await pool.end();
    }
  }
});

function assertReceipt(result: OrganizationProjectMembershipAssignmentResult): void {
  assert.deepEqual(Object.keys(result).sort(), [
    "activeFromUtc", "inactiveFromUtc", "organizationMembershipId",
    "organizationWorkspaceId", "projectId", "projectMembershipAssignmentContractId",
    "projectMembershipId",
  ]);
  assert.equal(result.projectMembershipAssignmentContractId,
    "organization-project-membership-assignment:v1");
  assert.match(result.projectMembershipId,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  assert.match(result.activeFromUtc, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
}
