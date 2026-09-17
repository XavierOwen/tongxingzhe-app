import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {readFileSync} from "node:fs";
import {Pool} from "pg";
import test from "node:test";

import {
  handleOrganizationOwnerTransfer,
  PostgresOrganizationOwnerTransferStore,
  type OrganizationOwnerTransferResult,
} from "../src/organization-owner-transfer.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for owner transfer integration");
}

const fixturePath = process.env.OWNER_TRANSFER_FIXTURE;
if (fixturePath === undefined || fixturePath.trim().length === 0) {
  throw new Error("OWNER_TRANSFER_FIXTURE is required for owner transfer integration");
}
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://synthetic-0086.example/auth/v1",
  subject: "multi-other-owner",
};
const requestId = "00000000-0086-3900-0000-000000000001";
const organizationWorkspaceId = "00000000-0086-2000-0000-000000000002";
const targetOrganizationMembershipId =
  "00000000-0086-2100-0000-000000000006";

test("organization owner transfer bridge returns and replays one exact receipt", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");

    const query = async (text: string, values: readonly unknown[]) =>
      client.query(text, [...values]);
    const store = new PostgresOrganizationOwnerTransferStore(query);

    const finiteUserId = randomUUID();
    const finiteMembershipId = randomUUID();
    const finiteRequestId = randomUUID();
    await client.query("RESET ROLE");
    await client.query(
      "INSERT INTO app_data.app_users(app_user_id, status) VALUES ($1::uuid, 'active')",
      [finiteUserId],
    );
    await client.query(
      `INSERT INTO app_data.organization_memberships(
         organization_membership_id, organization_workspace_id, app_user_id,
         active_from_utc, inactive_from_utc
       ) VALUES ($1::uuid, $2::uuid, $3::uuid,
         transaction_timestamp() - interval '1 hour',
         transaction_timestamp() + interval '1 day')`,
      [finiteMembershipId, organizationWorkspaceId, finiteUserId],
    );
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    await client.query("SAVEPOINT finite_target");
    const finiteResult = await handleOrganizationOwnerTransfer(
      {
        authorization: "Bearer synthetic-owner-transfer",
        workspaceId: organizationWorkspaceId,
        hasQuery: false,
        readBody: async () => ({
          request_id: finiteRequestId,
          target_organization_membership_id: finiteMembershipId,
        }),
      },
      {identityVerifier: {verify: async () => identity}, transferStore: store},
    );
    assert.equal(finiteResult.status, 403);
    assert.deepEqual(finiteResult.body, {
      error: {code: "organization_owner_transfer_forbidden"},
    });
    await client.query("ROLLBACK TO SAVEPOINT finite_target");

    const first = await store.transfer(
      identity,
      requestId,
      organizationWorkspaceId,
      targetOrganizationMembershipId,
    );
    const replay = await store.transfer(
      identity,
      requestId,
      organizationWorkspaceId,
      targetOrganizationMembershipId,
    );

    assert.deepEqual(replay, first);
    assertExactReceipt(first);
    assert.equal(first.organizationWorkspaceId, organizationWorkspaceId);
    assert.equal(first.ownerTransferContractId, "organization-owner-transfer:v1");

    process.stdout.write(
      "Backend organization owner transfer runtime integration: passed\n",
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

function assertExactReceipt(
  result: OrganizationOwnerTransferResult,
): void {
  assert.deepEqual(Object.keys(result).sort(), [
    "effectiveAtUtc",
    "organizationOwnerAssignmentId",
    "organizationWorkspaceId",
    "ownerTransferContractId",
    "previousOwnerAssignmentId",
  ]);
  assert.match(
    result.previousOwnerAssignmentId,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  assert.match(
    result.organizationOwnerAssignmentId,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  assert.match(
    result.effectiveAtUtc,
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/,
  );
}
