import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { request as httpRequest, type IncomingHttpHeaders, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";
import { Pool, type PoolClient } from "pg";

import { IdentityVerificationError } from "../src/identity.js";
import { PostgresOrganizationProjectMembershipAssignmentStore } from "../src/organization-project-membership-assignment.js";
import { createBackendServer } from "../src/server.js";

const databaseUrl = process.env.DATABASE_URL;
const fixturePath = process.env.ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for assignment HTTP integration");
}
if (fixturePath === undefined || fixturePath.trim().length === 0) {
  throw new Error("ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE is required");
}

const fixtureSource = readFileSync(fixturePath, "utf8");
const bootstrapEnd = fixtureSource.indexOf("CREATE TEMP TABLE fixture_0096_first AS");
assert.ok(bootstrapEnd > 0, "0096 fixture seed boundary is required");
const fixedUuidPattern = /00000000-0096-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gu;
const uuidMap = new Map<string, string>(
  [...new Set(fixtureSource.match(fixedUuidPattern))].map((id) => [id, randomUUID()]),
);
const issuer = `https://synthetic-0096-http-${randomUUID()}.example`;
// Only committed synthetic seed is reused. No fixture assertions, role changes,
// isolation transactions, or immutable-guard exceptions are copied into HTTP.
const seed = fixtureSource.slice(0, bootstrapEnd)
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(fixedUuidPattern, (id) => mappedUuid(id))
  .replaceAll("https://synthetic-0096.example", issuer);
assert.doesNotMatch(seed, fixedUuidPattern);
const finiteProject = mappedUuid("00000000-0096-4300-8000-000000000001");
const nullProject = mappedUuid("00000000-0096-4300-8000-000000000002");
const unassignedProject = mappedUuid("00000000-0096-4300-8000-000000000004");
const targetParent = mappedUuid("00000000-0096-4200-8000-000000000002");
const finiteRequest = mappedUuid("00000000-0096-5000-8000-000000000002");
const nullRequest = mappedUuid("00000000-0096-5000-8000-000000000004");
const bridgeQuery = `SELECT project_membership_assignment_contract_id,
  organization_workspace_id, project_id, organization_membership_id,
  project_membership_id, active_from_utc, inactive_from_utc
  FROM app_data.assign_organization_project_member_for_identity_v1(
    $1::text, $2::text, $3::uuid, $4::uuid, $5::uuid, $6::uuid
  )`.replace(/\s+/gu, " ").trim();

test("actual HTTP 200 acknowledges runtime-role committed finite/null assignments and exact replay", { timeout: 30_000 }, async () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 2, connectionTimeoutMillis: 5_000 });
  let owner: PoolClient | undefined;
  let runtime: PoolClient | undefined;
  let server: Server | undefined;
  try {
    owner = await pool.connect();
    runtime = await pool.connect();
    await owner.query("BEGIN");
    await owner.query(seed);
    const organization = (await owner.query<{
      organization_workspace_id: string;
      organization_membership_id: string;
    }>("SELECT organization_workspace_id, organization_membership_id FROM fixture_0096_org")).rows[0];
    assert.ok(organization);
    const workspaceId = organization.organization_workspace_id;
    const selfParent = organization.organization_membership_id;
    await owner.query("COMMIT");
    await runtime.query("SET ROLE tongxingzhe_runtime");
    const runtimeSession = (await runtime.query<{ role: string; pid: number }>(
      "SELECT current_user AS role, pg_backend_pid() AS pid",
    )).rows[0];
    const observerSession = (await owner.query<{ role: string; pid: number }>(
      "SELECT current_user AS role, pg_backend_pid() AS pid",
    )).rows[0];
    assert.equal(runtimeSession?.role, "tongxingzhe_runtime");
    assert.notEqual(observerSession?.role, "tongxingzhe_runtime");
    assert.notEqual(runtimeSession?.pid, observerSession?.pid);

    const businessCalls: (readonly unknown[])[] = [];
    const runtimeClient = runtime;
    const store = new PostgresOrganizationProjectMembershipAssignmentStore(async (text, values) => {
      assert.equal(text.replace(/\s+/gu, " ").trim(), bridgeQuery);
      assert.equal(values.length, 6);
      assert.equal(values[0], issuer);
      assert.ok(values[1] === " owner exact " || values[1] === "target");
      businessCalls.push([...values]);
      // No explicit transaction: each real six-parameter bridge call commits
      // before its query promise and thus the actual HTTP response complete.
      return runtimeClient.query(text, [...values]);
    });
    let verificationCalls = 0;
    server = createBackendServer({
      identityVerifier: { verify: async (token) => {
        verificationCalls += 1;
        if (token === "unavailable") throw new Error("synthetic provider detail must not escape");
        if (token !== "owner" && token !== "target") {
          throw new IdentityVerificationError("unauthenticated");
        }
        return { issuer, subject: token === "owner" ? " owner exact " : "target" };
      } },
      contextStore: { loadOrCreate: async () => { throw new Error("session context must not run"); } },
      organizationProjectMembershipAssignmentStore: store,
    });
    const port = (await listen(server)).port;
    const path = (projectId: string) => `/v1/organizations/${workspaceId}/projects/${projectId}/memberships`;
    const body = (requestId: string, parentId: string) => JSON.stringify({
      request_id: requestId,
      target_organization_membership_id: parentId,
    });

    for (const assignment of [
      { requestId: finiteRequest, projectId: finiteProject, parentId: targetParent, nullable: false },
      { requestId: nullRequest, projectId: nullProject, parentId: selfParent, nullable: true },
    ]) {
      const response = await rawRequest(port, path(assignment.projectId), "owner", body(assignment.requestId, assignment.parentId));
      const receipt = assertReceipt(response, workspaceId, assignment.projectId, assignment.parentId, assignment.nullable);
      // This owner observer is another physical connection. These reads occur
      // only after HTTP 200; it cannot see uncommitted runtime-session facts.
      await assertCommitted(owner, assignment.requestId, receipt);
      const replay = await rawRequest(port, path(assignment.projectId), "owner", body(assignment.requestId, assignment.parentId));
      assertHeaders(replay, 200);
      assert.equal(replay.rawBody, response.rawBody);
      assert.deepEqual(replay.body, receipt);
      await assertCommitted(owner, assignment.requestId, receipt);
    }

    assertError(await rawRequest(port, path(nullProject), "owner", body(finiteRequest, targetParent)),
      409, "organization_project_membership_assignment_conflict");
    const overlapRequest = randomUUID();
    assertError(await rawRequest(port, path(finiteProject), "owner", body(overlapRequest, targetParent)),
      403, "organization_project_membership_assignment_forbidden");
    const nonownerRequest = randomUUID();
    assertError(await rawRequest(port, path(unassignedProject), "target", body(nonownerRequest, targetParent)),
      403, "organization_project_membership_assignment_forbidden");
    assert.equal(businessCalls.length, 7);
    assert.deepEqual(businessCalls, [
      [issuer, " owner exact ", finiteRequest, workspaceId, finiteProject, targetParent],
      [issuer, " owner exact ", finiteRequest, workspaceId, finiteProject, targetParent],
      [issuer, " owner exact ", nullRequest, workspaceId, nullProject, selfParent],
      [issuer, " owner exact ", nullRequest, workspaceId, nullProject, selfParent],
      [issuer, " owner exact ", finiteRequest, workspaceId, nullProject, targetParent],
      [issuer, " owner exact ", overlapRequest, workspaceId, finiteProject, targetParent],
      [issuer, "target", nonownerRequest, workspaceId, unassignedProject, targetParent],
    ]);

    for (const token of [undefined, "invalid"]) {
      assertError(await rawRequest(port, `${path(finiteProject)}?`, token, "not-json"), 401, "unauthenticated");
    }
    const beforeAliases = verificationCalls;
    for (const alias of [path(finiteProject).replace(workspaceId, `%${workspaceId.charCodeAt(0).toString(16)}${workspaceId.slice(1)}`),
      path(finiteProject).replace(finiteProject, "%2e%2e")]) {
      assertError(await rawRequest(port, alias, "owner", "not-json"), 404, "not_found");
    }
    assert.equal(verificationCalls, beforeAliases);
    assertError(await rawRequest(port, path(finiteProject), "owner", "not-json"), 400, "invalid_json");
    assertError(await rawRequest(port, path(finiteProject), "owner", JSON.stringify({
      request_id: randomUUID(), target_organization_membership_id: targetParent, actor: "untrusted",
    })), 400, "invalid_organization_project_membership_assignment_request");
    assertError(await rawRequest(port, path(finiteProject), "owner", " ".repeat(1024 * 1024 + 1)), 413, "payload_too_large");
    assertError(await rawRequest(port, path(finiteProject), "unavailable", "not-json"),
      503, "organization_project_membership_assignment_unavailable");
    assert.equal(businessCalls.length, 7, "all transport rejections precede the business query");

    const facts = (await owner.query(`SELECT
      (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_request_claims
       WHERE organization_workspace_id = $1::uuid) AS claims,
      (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_audit_events
       WHERE organization_workspace_id = $1::uuid) AS audits,
      (SELECT count(*)::integer FROM app_data.project_memberships AS member
       JOIN app_data.projects AS project USING(project_id)
       WHERE project.workspace_id = $1::uuid) AS memberships,
      (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_request_claims
       WHERE request_id IN ($2::uuid, $3::uuid)) AS rejected_claims,
      (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_audit_events
       WHERE request_id IN ($2::uuid, $3::uuid)) AS rejected_audits`,
    [workspaceId, overlapRequest, nonownerRequest])).rows[0];
    // The fixture seeds two historical/future memberships; HTTP adds only two.
    assert.deepEqual(facts, { claims: 2, audits: 2, memberships: 4, rejected_claims: 0, rejected_audits: 0 });
    process.stdout.write("Assignment HTTP runtime integration: committed members=2 claims=2 audits=2; business callbacks=7; replay and stable rejections passed\n");
  } finally {
    try {
      if (server?.listening) await close(server);
    } finally {
      // Destroy role-bearing clients; never delete committed synthetic facts or
      // bypass immutable guards. The runner owns this disposable database.
      runtime?.release(true);
      owner?.release(true);
      await pool.end();
    }
  }
});

interface Receipt {
  readonly project_membership_assignment_contract_id: string;
  readonly organization_workspace_id: string;
  readonly project_id: string;
  readonly organization_membership_id: string;
  readonly project_membership_id: string;
  readonly active_from_utc: string;
  readonly inactive_from_utc: string | null;
}

async function assertCommitted(observer: PoolClient, requestId: string, receipt: Receipt): Promise<void> {
  const counts = (await observer.query(`SELECT
    (SELECT count(*)::integer FROM app_data.project_memberships WHERE project_membership_id = $2::uuid) AS members,
    (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_request_claims WHERE request_id = $1::uuid) AS claims,
    (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_audit_events WHERE request_id = $1::uuid) AS audits`,
  [requestId, receipt.project_membership_id])).rows[0];
  assert.deepEqual(counts, { members: 1, claims: 1, audits: 1 });
  const row = (await observer.query<{ active: Date; inactive: Date | null; parent_end: Date | null; atomic: boolean }>(`SELECT
    member.active_from_utc AS active, member.inactive_from_utc AS inactive,
    parent.inactive_from_utc AS parent_end,
    (member.project_id = $3::uuid AND parent.organization_workspace_id = $4::uuid
      AND member.organization_membership_id = $5::uuid
      AND claim.organization_workspace_id = $4::uuid AND claim.project_id = $3::uuid
      AND claim.organization_membership_id = $5::uuid
      AND claim.project_membership_id = member.project_membership_id
      AND audit.project_membership_id = member.project_membership_id
      AND audit.organization_workspace_id = $4::uuid AND audit.project_id = $3::uuid
      AND claim.active_from_utc = member.active_from_utc AND audit.active_from_utc = member.active_from_utc
      AND claim.inactive_from_utc IS NOT DISTINCT FROM member.inactive_from_utc
      AND audit.inactive_from_utc IS NOT DISTINCT FROM member.inactive_from_utc
      AND parent.inactive_from_utc IS NOT DISTINCT FROM member.inactive_from_utc) AS atomic
    FROM app_data.project_memberships AS member
    JOIN app_data.organization_memberships AS parent USING(organization_membership_id)
    JOIN app_private.organization_project_membership_assignment_request_claims AS claim ON claim.request_id = $1::uuid
    JOIN app_private.organization_project_membership_assignment_audit_events AS audit ON audit.request_id = $1::uuid
    WHERE member.project_membership_id = $2::uuid`,
  [requestId, receipt.project_membership_id, receipt.project_id, receipt.organization_workspace_id, receipt.organization_membership_id])).rows[0];
  assert.ok(row);
  assert.equal(row.atomic, true, "member, claim, audit and parent preserve exact SQL timestamps and selectors");
  assert.equal(receipt.active_from_utc, row.active.toISOString());
  assert.equal(receipt.inactive_from_utc, row.inactive?.toISOString() ?? null);
  assert.equal(receipt.inactive_from_utc, row.parent_end?.toISOString() ?? null);
}

function assertReceipt(response: RawResponse, workspaceId: string, projectId: string, parentId: string, nullable: boolean): Receipt {
  assertHeaders(response, 200);
  assert.ok(typeof response.body === "object" && response.body !== null && !Array.isArray(response.body));
  const receipt = response.body as Receipt;
  assert.deepEqual(Object.keys(receipt).sort(), [
    "active_from_utc", "inactive_from_utc", "organization_membership_id", "organization_workspace_id",
    "project_id", "project_membership_assignment_contract_id", "project_membership_id",
  ]);
  assert.equal(receipt.project_membership_assignment_contract_id, "organization-project-membership-assignment:v1");
  for (const id of [receipt.organization_workspace_id, receipt.project_id, receipt.organization_membership_id, receipt.project_membership_id]) {
    assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u);
  }
  assert.equal(receipt.organization_workspace_id, workspaceId);
  assert.equal(receipt.project_id, projectId);
  assert.equal(receipt.organization_membership_id, parentId);
  assert.match(receipt.active_from_utc, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u);
  assert.equal(new Date(receipt.active_from_utc).toISOString(), receipt.active_from_utc);
  if (nullable) assert.equal(receipt.inactive_from_utc, null);
  else {
    assert.equal(typeof receipt.inactive_from_utc, "string");
    assert.equal(new Date(receipt.inactive_from_utc!).toISOString(), receipt.inactive_from_utc);
  }
  return receipt;
}

function mappedUuid(id: string): string {
  const mapped = uuidMap.get(id);
  assert.ok(mapped, "fixed 0096 UUID must be regenerated consistently");
  return mapped;
}

interface RawResponse {
  readonly status: number;
  readonly headers: IncomingHttpHeaders;
  readonly body: unknown;
  readonly rawBody: string;
}

function assertHeaders(response: RawResponse, status: number): void {
  assert.equal(response.status, status);
  assert.equal(response.headers["content-type"], "application/json; charset=utf-8");
  assert.equal(response.headers["cache-control"], "no-store");
}

function assertError(response: RawResponse, status: number, code: string): void {
  assertHeaders(response, status);
  assert.deepEqual(response.body, { error: { code } });
}

function rawRequest(port: number, path: string, token: string | undefined, body: string): Promise<RawResponse> {
  return new Promise((resolve, reject) => {
    const request = httpRequest({ host: "127.0.0.1", port, method: "POST", path, headers: {
      ...(token === undefined ? {} : { authorization: `Bearer ${token}` }),
      "content-type": "application/json; charset=utf-8", "content-length": String(Buffer.byteLength(body)),
    } }, (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk: Buffer) => chunks.push(chunk));
      response.on("error", reject);
      response.on("end", () => {
        try {
          const rawBody = Buffer.concat(chunks).toString("utf8");
          resolve({ status: response.statusCode ?? 0, headers: response.headers, rawBody, body: JSON.parse(rawBody) as unknown });
        } catch (error) { reject(error); }
      });
    });
    request.setTimeout(5_000, () => request.destroy(new Error("assignment HTTP test request timed out")));
    request.on("error", reject);
    request.end(body);
  });
}

async function listen(server: Server): Promise<AddressInfo> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => { server.off("error", reject); resolve(); });
  });
  return server.address() as AddressInfo;
}

function close(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => { if (error === undefined) resolve(); else reject(error); });
  });
}
