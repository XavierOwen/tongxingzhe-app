import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {request as httpRequest, type Server} from "node:http";
import type {AddressInfo} from "node:net";
import {Pool, type PoolClient} from "pg";
import test from "node:test";

import {
  OrganizationShareableJoinApplicationStoreError,
  PostgresOrganizationShareableJoinApplicationStore,
} from "../src/organization-shareable-join-applications.js";
import {createBackendServer} from "../src/server.js";

const databaseUrl = required("DATABASE_URL");
const fixture = readFileSync(required("ORGANIZATION_SHAREABLE_JOIN_APPLICATION_DIRECTORY_FIXTURE"), "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "");

test("0099 runtime directory preserves exact identity, metadata-only bounds and authorization", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  let server: Server | undefined;
  try {
    // The fixture commits random governance setup, then seeds business facts in
    // a rollback transaction. Keep its own transaction boundaries intact.
    assert.equal(fixture.split("-- Live, fixture-scoped").length, 2);
    const setup = fixture.split("-- Live, fixture-scoped")[0]!.split("COMMIT;");
    assert.equal(setup.length, 2);
    // Separate protocol messages give the second transaction a later start
    // timestamp; one multi-statement message would reuse its arrival time.
    await client.query(`${setup[0]}COMMIT;`);
    await client.query(setup[1]!);
    const issuer = (await client.query<{issuer: string}>(
      "SELECT issuer FROM fixture_0099_identity",
    )).rows[0]?.issuer;
    assert.ok(issuer);
    assert.notEqual(issuer, issuer.trim());
    const owner = {issuer, subject: " owner exact "};
    const workspaces = new Map((await client.query<{n: number; workspace_id: string}>(
      "SELECT n, workspace_id FROM fixture_0099_orgs",
    )).rows.map((row) => [row.n, row.workspace_id]));
    const workspaceId = workspaces.get(1);
    assert.ok(workspaceId);
    const before = await scopedCounts(client, workspaceId);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    let queries = 0;
    const store = new PostgresOrganizationShareableJoinApplicationStore(async (text, values) => {
      queries++;
      return client.query(text, [...values]);
    });
    const result = await store.listPending(owner, workspaceId);
    assert.deepEqual(Object.keys(result).sort(), ["applications", "observedAtUtc",
      "organizationShareableJoinApplicationDirectoryContractId", "organizationWorkspaceId"]);
    assert.equal(result.organizationShareableJoinApplicationDirectoryContractId,
      "organization-shareable-join-application-directory:v1");
    assert.equal(result.organizationWorkspaceId, workspaceId);
    assert.equal(result.applications.length, 20);
    assert.equal(queries, 1);
    assert.match(result.observedAtUtc, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    for (const item of result.applications) {
      assert.deepEqual(Object.keys(item).sort(), ["applicationId", "expiresAtUtc", "linkId", "submittedAtUtc"]);
      assert.match(item.applicationId, /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/);
      assert.match(item.linkId, /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/);
      assert.match(item.submittedAtUtc, /\.\d{3}Z$/);
      assert.match(item.expiresAtUtc, /\.\d{3}Z$/);
      assert.equal(Date.parse(item.expiresAtUtc) - Date.parse(item.submittedAtUtc), 168 * 60 * 60 * 1_000);
      assert.ok(Date.parse(item.expiresAtUtc) >= Date.parse(result.observedAtUtc));
    }
    const coowner = await store.listPending({issuer, subject: "user-2"}, workspaceId);
    assert.deepEqual(coowner.applications, result.applications);
    const emptyWorkspace = workspaces.get(2);
    assert.ok(emptyWorkspace);
    assert.deepEqual((await store.listPending(owner, emptyWorkspace)).applications, []);

    for (const [identity, selectedWorkspace] of [
      [{issuer, subject: "user-4"}, workspaceId],
      [{issuer, subject: "user-11"}, workspaceId],
      [{issuer: issuer.trim(), subject: owner.subject}, workspaceId],
      [{issuer, subject: owner.subject.trim()}, workspaceId],
      [owner, workspaces.get(3)], [owner, workspaces.get(4)],
      [owner, workspaces.get(5)], [owner, workspaces.get(6)],
      [owner, "00000000-0099-2000-0000-999999999999"],
    ] as const) {
      assert.ok(selectedWorkspace);
      await expectStoreError(client, () => store.listPending(identity, selectedWorkspace),
        "organization_shareable_join_forbidden");
    }
    await expectStoreError(client, () => store.listPending({issuer: "", subject: owner.subject}, workspaceId),
      "organization_shareable_join_unavailable");
    await client.query("SAVEPOINT private_acl");
    await assert.rejects(client.query(
      "SELECT count(*) FROM app_private.organization_shareable_join_application_request_claims",
    ), (error: unknown) => property(error, "code") === "42501");
    await client.query("ROLLBACK TO SAVEPOINT private_acl");
    await client.query("RELEASE SAVEPOINT private_acl");

    server = createBackendServer({identityVerifier: {verify: async () => owner},
      contextStore: {loadOrCreate: async () => {throw new Error("session context must not run");}},
      organizationShareableJoinApplicationStore: store});
    const address = await listen(server);
    const http = await get(address.port, `/v1/organizations/${workspaceId}/shareable-join-applications`);
    assert.equal(http.status, 200);
    assert.equal(http.contentType, "application/json; charset=utf-8");
    assert.equal(http.cacheControl, "no-store");
    assert.deepEqual(Object.keys(http.body).sort(), ["applications", "observed_at_utc",
      "organization_shareable_join_application_directory_contract_id", "organization_workspace_id"]);
    assert.deepEqual(http.body.applications, result.applications.map((item) => ({
      application_id: item.applicationId, link_id: item.linkId,
      submitted_at_utc: item.submittedAtUtc, expires_at_utc: item.expiresAtUtc,
    })));
    await client.query("RESET ROLE");
    assert.deepEqual(await scopedCounts(client, workspaceId), before);
    process.stdout.write(`0099 Backend runtime: owner directory bounded at 20, coowner and empty allowed, exact identity/nonowner/inactive/recovery/private ACL denied; HTTP no-store; PostgreSQL business facts unchanged\n`);
  } finally {
    if (server !== undefined) await new Promise<void>((resolve, reject) =>
      server!.close((error) => error === undefined ? resolve() : reject(error)));
    try {await client.query("ROLLBACK");} finally {client.release(); await pool.end();}
  }
});

async function scopedCounts(client: PoolClient, workspaceId: string) {
  return (await client.query(`SELECT
    (SELECT count(*)::integer FROM app_private.organization_shareable_join_application_request_claims
      WHERE organization_workspace_id = $1::uuid) AS claims,
    (SELECT count(*)::integer FROM app_private.organization_shareable_join_application_audit_events
      WHERE organization_workspace_id = $1::uuid) AS audits,
    (SELECT count(*)::integer FROM app_data.organization_memberships
      WHERE organization_workspace_id = $1::uuid) AS memberships`, [workspaceId])).rows[0];
}
async function expectStoreError(client: PoolClient, operation: () => Promise<unknown>,
  code: "organization_shareable_join_forbidden" | "organization_shareable_join_unavailable") {
  await client.query("SAVEPOINT expected_error");
  await assert.rejects(operation, (error: unknown) =>
    error instanceof OrganizationShareableJoinApplicationStoreError && error.code === code);
  await client.query("ROLLBACK TO SAVEPOINT expected_error");
  await client.query("RELEASE SAVEPOINT expected_error");
}
function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required for application directory integration`);
  return value;
}
function property(value: unknown, key: string): unknown {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>)[key] : undefined;
}
async function listen(server: Server): Promise<AddressInfo> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {server.off("error", reject); resolve();});
  });
  return server.address() as AddressInfo;
}
function get(port: number, path: string): Promise<{
  status: number; contentType: string | undefined; cacheControl: string | undefined;
  body: Record<string, unknown>;
}> {
  return new Promise((resolve, reject) => {
    const request = httpRequest({host: "127.0.0.1", port, method: "GET", path,
      headers: {authorization: "Bearer synthetic-owner"}}, (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk: Buffer) => chunks.push(chunk));
      response.on("end", () => resolve({status: response.statusCode ?? 0,
        contentType: response.headers["content-type"], cacheControl: response.headers["cache-control"],
        body: JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>}));
    });
    request.on("error", reject);
    request.end();
  });
}
