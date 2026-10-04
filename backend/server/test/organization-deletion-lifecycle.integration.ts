import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
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

test("Backend lifecycle routes preserve 0104 bridge receipts and six timestamp digits", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
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
      identityVerifier: {verify: async () => identity},
      organizationDeletionLifecycleStore: store,
      contextStore: {
        loadOrCreate: async () => {
          throw new Error("context must not run for lifecycle routes");
        },
      },
    });
    const address = await listen(server);

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

    process.stdout.write("Backend organization deletion lifecycle HTTP integration: passed\n");
  } finally {
    if (server !== undefined) await close(server);
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      await pool.end();
    }
  }
});

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
