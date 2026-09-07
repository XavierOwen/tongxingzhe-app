import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {Pool} from "pg";
import test from "node:test";

import {PostgresOrganizationDirectoryStore} from "../src/organization-directory.js";
import {
  PostgresOrganizationMembershipSelfLeaveStore,
  type OrganizationMembershipSelfLeaveResult,
} from "../src/organization-membership-self-leave.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for membership self-leave integration");
}

const fixturePath = process.env.ORGANIZATION_MEMBERSHIP_SELF_LEAVE_FIXTURE;
if (fixturePath === undefined || fixturePath.trim().length === 0) {
  throw new Error(
    "ORGANIZATION_MEMBERSHIP_SELF_LEAVE_FIXTURE is required for membership self-leave integration",
  );
}
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://synthetic-0090.example/auth/v1",
  subject: "integration-member",
};
const requestId = "00000000-0090-3000-0000-000000000001";
const organizationWorkspaceId = "00000000-0090-2000-0000-000000000001";
const organizationMembershipId = "00000000-0090-2100-0000-000000000002";
const rejoinedMembershipId = "00000000-0090-2100-0000-000000000003";
const actorAppUserId = "00000000-0090-0000-0000-000000000002";

test("runtime self-leave excludes the organization and stale replay cannot leave a rejoin", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const query = async (text: string, values: readonly unknown[]) =>
      client.query(text, [...values]);
    const leaveStore = new PostgresOrganizationMembershipSelfLeaveStore(query);
    const directoryStore = new PostgresOrganizationDirectoryStore(query);

    assert.equal(
      (await directoryStore.list(identity)).some(
        (entry) => entry.organizationWorkspaceId === organizationWorkspaceId,
      ),
      true,
    );

    const first = await leaveStore.leave(identity, requestId, organizationWorkspaceId);
    const replay = await leaveStore.leave(identity, requestId, organizationWorkspaceId);
    assert.deepEqual(replay, first);
    assertExactReceipt(first);
    assert.equal(first.organizationMembershipId, organizationMembershipId);
    assert.equal(
      (await directoryStore.list(identity)).some(
        (entry) => entry.organizationWorkspaceId === organizationWorkspaceId,
      ),
      false,
    );

    await client.query("RESET ROLE");
    await client.query(
      `INSERT INTO app_data.organization_memberships (
         organization_membership_id,
         organization_workspace_id,
         app_user_id,
         active_from_utc,
         inactive_from_utc
       ) VALUES ($1::uuid, $2::uuid, $3::uuid, clock_timestamp(), NULL)`,
      [rejoinedMembershipId, organizationWorkspaceId, actorAppUserId],
    );
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");

    assert.equal(
      (await directoryStore.list(identity)).some(
        (entry) => entry.organizationWorkspaceId === organizationWorkspaceId,
      ),
      true,
    );
    assert.deepEqual(
      await leaveStore.leave(identity, requestId, organizationWorkspaceId),
      first,
    );

    await client.query("RESET ROLE");
    const currentRejoin = await client.query(
      `SELECT inactive_from_utc
       FROM app_data.organization_memberships
       WHERE organization_membership_id = $1::uuid`,
      [rejoinedMembershipId],
    );
    assert.equal(currentRejoin.rows.length, 1);
    assert.equal(currentRejoin.rows[0]?.inactive_from_utc, null);

    process.stdout.write(
      "Backend organization membership self-leave runtime integration: passed\n",
    );
  } finally {
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      await pool.end();
    }
  }
});

function assertExactReceipt(result: OrganizationMembershipSelfLeaveResult): void {
  assert.deepEqual(Object.keys(result).sort(), [
    "effectiveAtUtc",
    "membershipSelfLeaveContractId",
    "organizationMembershipId",
    "organizationWorkspaceId",
  ]);
  assert.equal(
    result.membershipSelfLeaveContractId,
    "organization-membership-self-leave:v1",
  );
  assert.equal(result.organizationWorkspaceId, organizationWorkspaceId);
  assert.match(
    result.effectiveAtUtc,
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/,
  );
}
