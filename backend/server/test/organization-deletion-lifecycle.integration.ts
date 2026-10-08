import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {randomUUID} from "node:crypto";
import {type Server} from "node:http";
import {Pool} from "pg";
import test from "node:test";
import type {AddressInfo} from "node:net";

import {
  PostgresOrganizationDeletionLifecycleStore,
} from "../src/organization-deletion-lifecycle.js";
import {createBackendServer} from "../src/server.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for organization deletion lifecycle integration");
}
const fixturePath = process.env.ORGANIZATION_DELETION_IDENTITY_BRIDGES_FIXTURE;
if (fixturePath === undefined || fixturePath.trim().length === 0) {
  throw new Error("ORGANIZATION_DELETION_IDENTITY_BRIDGES_FIXTURE is required for organization deletion lifecycle integration");
}
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");
const firstRuntimeCall = fixture.indexOf("\nSET LOCAL ROLE tongxingzhe_runtime;");
assert.notEqual(firstRuntimeCall, -1);
const fixtureSetup = fixture.slice(0, firstRuntimeCall);

const issuer = " https://synthetic-0104.example/issuer ";
const identity = {issuer, subject: "owner two"};
const workspaceRequestId = "00000000-0104-4000-8000-000000000002";
const restoreRequestId = "00000000-0104-5000-8000-000000000002";
const deletionRequestId = "00000000-0104-4000-8000-000000000002";

test("Backend lifecycle routes preserve receipts, owner eligibility, and read-only observations", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  const unrelatedUserId = randomUUID();
  let server: Server | undefined;
  try {
    await client.query("BEGIN");
    await client.query(fixtureSetup);
    const workspaceId = (await client.query<{organization_workspace_id: string}>(
      "SELECT organization_workspace_id FROM fixture_0104_org",
    )).rows[0]?.organization_workspace_id;
    assert.ok(workspaceId);

    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const store = new PostgresOrganizationDeletionLifecycleStore(
      (text, values) => client.query(text, [...values]),
    );
    server = createBackendServer({
      identityVerifier: {verify: async (token) => token === "fixture-token"
        ? identity : {issuer, subject: decodeURIComponent(token)}},
      organizationDeletionLifecycleStore: store,
      contextStore: {
        loadOrCreate: async () => {
          throw new Error("context must not run for lifecycle routes");
        },
      },
    });
    const address = await listen(server);

    // Lifecycle writers require READ COMMITTED. Freeze the fixture's actors so
    // parallel committed fixtures cannot change these read-only observations.
    await client.query("RESET ROLE");
    const actorIds = (await client.query<{app_user_id: string}>(
      "SELECT app_user_id FROM app_data.external_identities WHERE issuer=$1", [issuer],
    )).rows.map((row) => row.app_user_id);
    assert.equal(actorIds.length, 4);
    const snapshotTables = [
      ["app_data.workspaces", "workspace_id=$1::uuid OR personal_owner_app_user_id=ANY($2::uuid[])"],
      ["app_data.app_users", "app_user_id=ANY($2::uuid[])"],
      ["app_data.external_identities", "issuer=$3::text OR app_user_id=ANY($2::uuid[])"],
      ["app_data.organization_memberships", "organization_workspace_id=$1::uuid OR app_user_id=ANY($2::uuid[])"],
      ["app_data.organization_owner_assignments", "organization_membership_id IN (SELECT organization_membership_id FROM app_data.organization_memberships WHERE organization_workspace_id=$1::uuid OR app_user_id=ANY($2::uuid[]))"],
      ["app_private.organization_deletion_current", "organization_workspace_id=$1::uuid"],
      ["app_private.organization_deletion_request_claims", "organization_workspace_id=$1::uuid"],
      ["app_private.organization_deletion_restore_claims", "organization_workspace_id=$1::uuid"],
      ["app_private.organization_deletion_audit_events", "organization_workspace_id=$1::uuid"],
    ] as const;
    const snapshotSql = snapshotTables.map(([table, predicate]) => `SELECT '${table}' AS name,
      COALESCE(jsonb_agg(to_jsonb(record) ORDER BY to_jsonb(record)::text), '[]') AS rows
      FROM ${table} AS record WHERE ${predicate}`).join(" UNION ALL ") + " ORDER BY name";
    const snapshotValues = [workspaceId, actorIds, issuer];
    const beforeReads = (await client.query(snapshotSql, snapshotValues)).rows;

    // A separate connection commits between observations: the old full-table
    // snapshot changes, while this fixture's rows remain unchanged.
    const unboundedSnapshotSql = snapshotTables.map(([table]) => `SELECT '${table}' AS name,
      COALESCE(jsonb_agg(to_jsonb(record) ORDER BY to_jsonb(record)::text), '[]') AS rows
      FROM ${table} AS record`).join(" UNION ALL ") + " ORDER BY name";
    const beforeUnrelatedCommit = (await client.query(unboundedSnapshotSql)).rows;
    await pool.query("INSERT INTO app_data.app_users(app_user_id,status) VALUES ($1::uuid,'active')", [unrelatedUserId]);
    assert.notDeepEqual((await client.query(unboundedSnapshotSql)).rows, beforeUnrelatedCommit);
    assert.deepEqual((await client.query(snapshotSql, snapshotValues)).rows, beforeReads);

    // Scope must still expose our own real writes, not merely stabilize output.
    await client.query("SAVEPOINT snapshot_write_probe");
    await client.query("UPDATE app_data.workspaces SET display_name='0104 snapshot write probe' WHERE workspace_id=$1::uuid", [workspaceId]);
    assert.notDeepEqual((await client.query(snapshotSql, snapshotValues)).rows, beforeReads);
    await client.query("ROLLBACK TO SAVEPOINT snapshot_write_probe");
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    for (const subject of ["owner one", "owner two", "member"]) {
      const eligibility = await getEligibility(address.port, subject);
      assert.equal(eligibility.status, 200);
      assert.deepEqual(eligibility.body, {
        organization_deletion_eligibility_contract_id: "organization-deletion-eligibility:v1",
        organization_workspace_ids: subject === "member" ? [] : [workspaceId],
      });
    }
    await client.query("SAVEPOINT unavailable_identity");
    const forbidden = await getEligibility(address.port, "unknown");
    assert.equal(forbidden.status, 403);
    assert.deepEqual(forbidden.body, {
      error: {code: "organization_deletion_eligibility_forbidden"},
    });
    await client.query("ROLLBACK TO SAVEPOINT unavailable_identity");
    await client.query("RESET ROLE");
    assert.deepEqual((await client.query(snapshotSql, snapshotValues)).rows, beforeReads);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");

    const deletion = await postJson(address.port,
      `/v1/organizations/${workspaceId}/deletion-requests`,
      {request_id: workspaceRequestId});
    assert.equal(deletion.status, 200);
    assert.equal(deletion.response.headers.get("cache-control"), "no-store");
    assert.deepEqual(deletion.body, {
      organization_deletion_contract_id: "organization-deletion-request:v1",
      organization_workspace_id: workspaceId,
      deletion_request_id: deletionRequestId,
      effective_at_utc: deletion.body.effective_at_utc,
      purge_after_utc: deletion.body.purge_after_utc,
    });
    assert.match(String(deletion.body.effective_at_utc),
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/);
    assert.match(String(deletion.body.purge_after_utc),
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/);

    const pendingEligibility = await getEligibility(address.port, "owner two");
    assert.equal(pendingEligibility.status, 200);
    assert.deepEqual(pendingEligibility.body, {
      organization_deletion_eligibility_contract_id: "organization-deletion-eligibility:v1",
      organization_workspace_ids: [],
    });

    const replay = await postJson(address.port,
      `/v1/organizations/${workspaceId}/deletion-requests`,
      {request_id: workspaceRequestId});
    assert.deepEqual(replay.body, deletion.body);

    const restoration = await postJson(address.port,
      `/v1/organizations/${workspaceId}/restorations`,
      {request_id: restoreRequestId, deletion_request_id: deletionRequestId});
    assert.equal(restoration.status, 200);
    assert.equal(restoration.response.headers.get("cache-control"), "no-store");
    assert.deepEqual(restoration.body, {
      organization_deletion_restore_contract_id: "organization-deletion-restore:v1",
      organization_workspace_id: workspaceId,
      deletion_request_id: deletionRequestId,
      restored_at_utc: restoration.body.restored_at_utc,
    });
    assert.match(String(restoration.body.restored_at_utc),
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/);

    await client.query("RESET ROLE");
    const beforeRestoredRead = (await client.query(snapshotSql, snapshotValues)).rows;
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const restoredEligibility = await getEligibility(address.port, "owner two");
    assert.equal(restoredEligibility.status, 200);
    assert.deepEqual(restoredEligibility.body, {
      organization_deletion_eligibility_contract_id: "organization-deletion-eligibility:v1",
      organization_workspace_ids: [workspaceId],
    });
    await client.query("RESET ROLE");
    assert.deepEqual((await client.query(snapshotSql, snapshotValues)).rows, beforeRestoredRead);

    process.stdout.write("Backend organization deletion lifecycle and eligibility HTTP integration: passed\n");
  } finally {
    if (server !== undefined) await close(server);
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      try {
        await pool.query("DELETE FROM app_data.app_users WHERE app_user_id=$1::uuid", [unrelatedUserId]);
      } finally {
        await pool.end();
      }
    }
  }
});

async function getEligibility(port: number, subject: string): Promise<{
  readonly status: number;
  readonly body: unknown;
}> {
  const response = await fetch(`http://127.0.0.1:${port}/v1/organizations/deletion-eligibility`, {
    headers: {authorization: `Bearer ${encodeURIComponent(subject)}`},
  });
  assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(response.headers.get("cache-control"), "no-store");
  return {status: response.status, body: await response.json() as unknown};
}

async function postJson(
  port: number,
  path: string,
  body: Readonly<Record<string, string>>,
): Promise<{
  readonly status: number;
  readonly response: Response;
  readonly body: Record<string, unknown>;
}> {
  const response = await fetch(`http://127.0.0.1:${port}${path}`, {
    method: "POST",
    headers: {authorization: "Bearer fixture-token", "content-type": "application/json"},
    body: JSON.stringify(body),
  });
  return {
    status: response.status,
    response,
    body: await response.json() as Record<string, unknown>,
  };
}

async function listen(server: Server): Promise<AddressInfo> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
  return server.address() as AddressInfo;
}

function close(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => error === undefined ? resolve() : reject(error));
  });
}
