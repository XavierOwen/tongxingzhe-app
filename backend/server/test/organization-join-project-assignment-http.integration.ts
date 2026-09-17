import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { request as httpRequest, type IncomingHttpHeaders, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";
import { Pool, type PoolClient } from "pg";

import { IdentityVerificationError } from "../src/identity.js";
import { PostgresOrganizationProjectMembershipAssignmentStore } from "../src/organization-project-membership-assignment.js";
import { PostgresOrganizationShareableJoinApplicationStore } from "../src/organization-shareable-join-applications.js";
import { PostgresOrganizationShareableJoinLinkStore } from "../src/organization-shareable-join-links.js";
import { createBackendServer } from "../src/server.js";

const databaseUrl = process.env.DATABASE_URL;
const fixturePath = process.env.ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) throw new Error("DATABASE_URL is required");
if (fixturePath === undefined || fixturePath.trim().length === 0) {
  throw new Error("ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE is required");
}
const fixtureSource = readFileSync(fixturePath, "utf8");
const bootstrapEnd = fixtureSource.indexOf("CREATE TEMP TABLE fixture_0096_first AS");
assert.ok(bootstrapEnd > 0, "0096 fixture seed boundary is required");
const fixedUuidPattern = /00000000-0096-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gu;
const uuidMap = new Map([...new Set(fixtureSource.match(fixedUuidPattern))].map((id) => [id, randomUUID()]));
const issuer = `https://synthetic-join-project-http-${randomUUID()}.example`;
const applicantUserId = randomUUID();
const linkId = randomUUID();
const applicationId = randomUUID();
const assignmentRequestId = randomUUID();
const projectId = mappedUuid("00000000-0096-4300-8000-000000000004");
const otherProjectId = mappedUuid("00000000-0096-4300-8000-000000000002");
// Keep all original seed memberships and guards. The new applicant has never
// had an organization/project membership; no fixture approval is pre-seeded.
const seed = fixtureSource.slice(0, bootstrapEnd)
  .replace(/^BEGIN;\s*/mu, "")
  .replace(fixedUuidPattern, mappedUuid)
  .replaceAll("https://synthetic-0096.example", issuer);
assert.doesNotMatch(seed, fixedUuidPattern);
const createSql = `SELECT organization_shareable_join_link_contract_id, link_id,
  organization_workspace_id, issued_at_utc, expires_at_utc
  FROM app_data.create_organization_shareable_join_link_for_identity_v1( $1::text, $2::text, $3::uuid, $4::uuid )`;
const previewSql = `SELECT organization_shareable_join_link_preview_contract_id, link_id,
  organization_name, expires_at_utc
  FROM app_data.preview_organization_shareable_join_link_for_identity_v1( $1::text, $2::text, $3::uuid )`;
const submitSql = `SELECT organization_shareable_join_application_contract_id, application_id,
  link_id, organization_workspace_id, submitted_at_utc, expires_at_utc
  FROM app_data.submit_organization_shareable_join_application_for_identity_v1( $1::text, $2::text, $3::uuid, $4::uuid )`;
const approveSql = `SELECT organization_shareable_join_application_contract_id, application_id,
  organization_workspace_id, organization_membership_id, approved_at_utc
  FROM app_data.approve_organization_shareable_join_application_for_identity_v1( $1::text, $2::text, $3::uuid, $4::uuid )`;
const assignSql = `SELECT project_membership_assignment_contract_id, organization_workspace_id,
  project_id, organization_membership_id, project_membership_id, active_from_utc, inactive_from_utc
  FROM app_data.assign_organization_project_member_for_identity_v1(
    $1::text, $2::text, $3::uuid, $4::uuid, $5::uuid, $6::uuid
  )`;

test("actual HTTP join approval creates only an organization member until explicit project assignment", { timeout: 30_000 }, async () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 2, connectionTimeoutMillis: 5_000 });
  let owner: PoolClient | undefined;
  let runtime: PoolClient | undefined;
  let server: Server | undefined;
  try {
    owner = await pool.connect();
    runtime = await pool.connect();
    await owner.query("BEGIN");
    await owner.query(seed);
    await owner.query("INSERT INTO app_data.app_users(app_user_id, status) VALUES ($1::uuid, 'active')", [applicantUserId]);
    await owner.query(`INSERT INTO app_data.external_identities(external_identity_id, issuer, subject, app_user_id)
      VALUES ($1::uuid, $2::text, $3::text, $4::uuid)`, [randomUUID(), issuer, " applicant exact ", applicantUserId]);
    const organization = (await owner.query<{ organization_workspace_id: string }>(
      "SELECT organization_workspace_id FROM fixture_0096_org",
    )).rows[0];
    assert.ok(organization);
    const workspaceId = organization.organization_workspace_id;
    await assertFacts(owner, workspaceId, 0, 0, 0, 0, 0);
    await owner.query("COMMIT");
    await runtime.query("SET ROLE tongxingzhe_runtime");
    const runtimeSession = (await runtime.query("SELECT current_user AS role, pg_backend_pid() AS pid")).rows[0];
    const observerSession = (await owner.query("SELECT current_user AS role, pg_backend_pid() AS pid")).rows[0];
    assert.equal(runtimeSession.role, "tongxingzhe_runtime");
    assert.notEqual(observerSession.role, "tongxingzhe_runtime");
    assert.notEqual(runtimeSession.pid, observerSession.pid);

    let expectedCall: { sql: string; values: readonly unknown[] } | undefined;
    let businessCalls = 0;
    const runtimeClient = runtime;
    const query = async (text: string, values: readonly unknown[]) => {
      assert.ok(expectedCall, "a transport rejection must not execute a business query");
      assert.equal(normalizeSql(text), normalizeSql(expectedCall.sql));
      assert.deepEqual(values, expectedCall.values);
      expectedCall = undefined;
      businessCalls += 1;
      // The sole callback statement is the route's existing identity bridge.
      // Its implicit commit settles before the handler can send HTTP 200.
      return runtimeClient.query(text, [...values]);
    };
    let verificationCalls = 0;
    let contextCalls = 0;
    server = createBackendServer({
      identityVerifier: { verify: async (token) => {
        verificationCalls += 1;
        if (token === "unavailable") throw new Error("synthetic provider detail must not escape");
        if (token !== "owner" && token !== "applicant") throw new IdentityVerificationError("unauthenticated");
        return { issuer, subject: token === "owner" ? " owner exact " : " applicant exact " };
      } },
      contextStore: { loadOrCreate: async () => { contextCalls += 1; throw new Error("context lookup must not run"); } },
      organizationShareableJoinLinkStore: new PostgresOrganizationShareableJoinLinkStore(query),
      organizationShareableJoinApplicationStore: new PostgresOrganizationShareableJoinApplicationStore(query),
      organizationProjectMembershipAssignmentStore: new PostgresOrganizationProjectMembershipAssignmentStore(query),
    });
    const port = (await listen(server)).port;
    const createPath = `/v1/organizations/${workspaceId}/shareable-join-links`;
    const previewPath = `/v1/organization-shareable-join-links/${linkId}`;
    const submitPath = `${previewPath}/applications`;
    const approvePath = `/v1/organizations/${workspaceId}/shareable-join-applications/${applicationId}/approve`;
    const assignPath = `/v1/organizations/${workspaceId}/projects/${projectId}/memberships`;
    const call = async (sql: string, values: readonly unknown[], method: "GET" | "POST", path: string, token: string, body?: unknown) => {
      assert.equal(expectedCall, undefined);
      expectedCall = { sql, values };
      const response = await rawRequest(port, method, path, token, body === undefined ? undefined : JSON.stringify(body));
      assert.equal(expectedCall, undefined, "each business HTTP request executes exactly one bridge");
      return response;
    };

    const createdResponse = await call(createSql, [issuer, " owner exact ", linkId, workspaceId], "POST", createPath, "owner", { link_id: linkId });
    const created = receipt(createdResponse, {
      organization_shareable_join_link_contract_id: "organization-shareable-join-link:v1", link_id: linkId, organization_workspace_id: workspaceId,
    }, ["issued_at_utc", "expires_at_utc"]);
    assert.equal(Date.parse(created.expires_at_utc as string) - Date.parse(created.issued_at_utc as string), 168 * 60 * 60 * 1_000);
    const link = (await owner.query(`SELECT claim.issued_at_utc, claim.expires_at_utc,
      (claim.creator_app_user_id = $2::uuid AND audit.organization_workspace_id = claim.organization_workspace_id
        AND audit.event_kind = 'link_created' AND audit.issued_at_utc = claim.issued_at_utc
        AND audit.expires_at_utc = claim.expires_at_utc) AS atomic
      FROM app_private.organization_shareable_join_link_request_claims AS claim
      JOIN app_private.organization_shareable_join_link_audit_events AS audit USING(link_id)
      WHERE claim.link_id = $1::uuid`, [linkId, mappedUuid("00000000-0096-4000-8000-000000000001")])).rows[0];
    assert.equal(link.atomic, true);
    assert.equal(created.issued_at_utc, link.issued_at_utc.toISOString());
    assert.equal(created.expires_at_utc, link.expires_at_utc.toISOString());
    await assertFacts(owner, workspaceId, 1, 0, 0, 0, 0);

    const preview = receipt(await call(previewSql, [issuer, " applicant exact ", linkId], "GET", previewPath, "applicant"), {
      organization_shareable_join_link_preview_contract_id: "organization-shareable-join-link-preview:v1", link_id: linkId, organization_name: "0096 organization",
    }, ["expires_at_utc"]);
    assert.equal(preview.expires_at_utc, created.expires_at_utc);
    await assertFacts(owner, workspaceId, 1, 0, 0, 0, 0);

    const submittedResponse = await call(submitSql, [issuer, " applicant exact ", applicationId, linkId], "POST", submitPath, "applicant", { application_id: applicationId });
    const submitted = receipt(submittedResponse, {
      organization_shareable_join_application_contract_id: "organization-shareable-join-application:v1", application_id: applicationId, link_id: linkId, organization_workspace_id: workspaceId,
    }, ["submitted_at_utc", "expires_at_utc"]);
    assert.equal(Date.parse(submitted.expires_at_utc as string) - Date.parse(submitted.submitted_at_utc as string), 168 * 60 * 60 * 1_000);
    const pending = (await owner.query(`SELECT claim.submitted_at_utc, claim.expires_at_utc,
      claim.submitted_at_utc::text AS submitted_sql_time, claim.expires_at_utc::text AS expires_sql_time,
      (claim.applicant_app_user_id = $2::uuid AND claim.approved_at_utc IS NULL
        AND claim.approved_organization_membership_id IS NULL AND audit.organization_membership_id IS NULL
        AND audit.occurred_at_utc = claim.submitted_at_utc AND audit.link_id = claim.link_id
        AND audit.organization_workspace_id = claim.organization_workspace_id) AS atomic
      FROM app_private.organization_shareable_join_application_request_claims AS claim
      JOIN app_private.organization_shareable_join_application_audit_events AS audit USING(application_id)
      WHERE claim.application_id = $1::uuid AND audit.event_kind = 'application_submitted'`, [applicationId, applicantUserId])).rows[0];
    assert.equal(pending.atomic, true);
    assert.equal(submitted.submitted_at_utc, pending.submitted_at_utc.toISOString());
    assert.equal(submitted.expires_at_utc, pending.expires_at_utc.toISOString());
    await assertFacts(owner, workspaceId, 1, 1, 0, 0, 0);

    const approvedResponse = await call(approveSql, [issuer, " owner exact ", applicationId, workspaceId], "POST", approvePath, "owner", {});
    const approved = receipt(approvedResponse, {
      organization_shareable_join_application_contract_id: "organization-shareable-join-application:v1", application_id: applicationId, organization_workspace_id: workspaceId,
    }, ["approved_at_utc"], ["organization_membership_id"]);
    const parentId = approved.organization_membership_id as string;
    const parent = (await owner.query(`SELECT member.active_from_utc, member.inactive_from_utc,
      (member.app_user_id = $2::uuid AND member.organization_workspace_id = $3::uuid
        AND member.organization_membership_id = $6::uuid
        AND claim.approved_at_utc = member.active_from_utc AND audit.occurred_at_utc = member.active_from_utc
        AND audit.organization_membership_id = member.organization_membership_id
        AND claim.submitted_at_utc = $4::timestamptz AND claim.expires_at_utc = $5::timestamptz) AS atomic
      FROM app_data.organization_memberships AS member
      JOIN app_private.organization_shareable_join_application_request_claims AS claim
        ON claim.approved_organization_membership_id = member.organization_membership_id
      JOIN app_private.organization_shareable_join_application_audit_events AS audit USING(application_id)
      WHERE claim.application_id = $1::uuid AND audit.event_kind = 'application_approved'`,
    [applicationId, applicantUserId, workspaceId, pending.submitted_sql_time, pending.expires_sql_time, parentId])).rows[0];
    assert.equal(parent.atomic, true);
    assert.equal(parent.inactive_from_utc, null);
    assert.equal(approved.approved_at_utc, parent.active_from_utc.toISOString());
    await assertFacts(owner, workspaceId, 1, 1, 1, 1, 0);

    const assignmentBody = { request_id: assignmentRequestId, target_organization_membership_id: parentId };
    const assignedResponse = await call(assignSql, [issuer, " owner exact ", assignmentRequestId, workspaceId, projectId, parentId], "POST", assignPath, "owner", assignmentBody);
    const assigned = receipt(assignedResponse, {
      project_membership_assignment_contract_id: "organization-project-membership-assignment:v1", organization_workspace_id: workspaceId, project_id: projectId,
      organization_membership_id: parentId, inactive_from_utc: null,
    }, ["active_from_utc"], ["project_membership_id"]);
    const child = (await owner.query(`SELECT member.active_from_utc, member.inactive_from_utc,
      (member.project_id = $3::uuid AND member.organization_membership_id = $4::uuid
        AND claim.organization_workspace_id = $5::uuid AND claim.project_id = member.project_id
        AND claim.organization_membership_id = member.organization_membership_id
        AND claim.project_membership_id = member.project_membership_id AND audit.project_membership_id = member.project_membership_id
        AND audit.organization_workspace_id = claim.organization_workspace_id AND audit.project_id = member.project_id
        AND claim.active_from_utc = member.active_from_utc AND audit.active_from_utc = member.active_from_utc
        AND claim.inactive_from_utc IS NOT DISTINCT FROM member.inactive_from_utc
        AND audit.inactive_from_utc IS NOT DISTINCT FROM member.inactive_from_utc
        AND parent.inactive_from_utc IS NOT DISTINCT FROM member.inactive_from_utc
        AND member.active_from_utc >= parent.active_from_utc) AS atomic
      FROM app_data.project_memberships AS member
      JOIN app_data.organization_memberships AS parent USING(organization_membership_id)
      JOIN app_private.organization_project_membership_assignment_request_claims AS claim ON claim.request_id = $1::uuid
      JOIN app_private.organization_project_membership_assignment_audit_events AS audit ON audit.request_id = $1::uuid
      WHERE member.project_membership_id = $2::uuid`,
    [assignmentRequestId, assigned.project_membership_id, projectId, parentId, workspaceId])).rows[0];
    assert.equal(child.atomic, true);
    assert.equal(assigned.active_from_utc, child.active_from_utc.toISOString());
    assert.equal(child.inactive_from_utc, null);
    assert.ok(child.active_from_utc.getTime() >= parent.active_from_utc.getTime());
    await assertFacts(owner, workspaceId, 1, 1, 1, 1, 1);

    // After joining and explicit assignment, submit still returns its original
    // pending-time receipt. These historical rows are not current-access proof.
    for (const replay of [
      { sql: submitSql, values: [issuer, " applicant exact ", applicationId, linkId], path: submitPath, token: "applicant", body: { application_id: applicationId }, original: submittedResponse },
      { sql: approveSql, values: [issuer, " owner exact ", applicationId, workspaceId], path: approvePath, token: "owner", body: {}, original: approvedResponse },
      { sql: assignSql, values: [issuer, " owner exact ", assignmentRequestId, workspaceId, projectId, parentId], path: assignPath, token: "owner", body: assignmentBody, original: assignedResponse },
    ]) {
      const response = await call(replay.sql, replay.values, "POST", replay.path, replay.token, replay.body);
      assertHeaders(response, 200);
      assert.equal(response.rawBody, replay.original.rawBody);
      assert.deepEqual(response.body, replay.original.body);
      await assertFacts(owner, workspaceId, 1, 1, 1, 1, 1);
    }
    const otherAssignPath = assignPath.replace(projectId, otherProjectId);
    const nonownerRequestId = randomUUID();
    // Active applicant, valid parent, same organization, empty active project:
    // no target/overlap/recovery guard can mask lack of current ownership.
    assertError(await call(assignSql, [issuer, " applicant exact ", nonownerRequestId, workspaceId, otherProjectId, parentId], "POST", otherAssignPath, "applicant", {
      request_id: nonownerRequestId, target_organization_membership_id: parentId,
    }), 403, "organization_project_membership_assignment_forbidden");
    assertError(await call(assignSql, [issuer, " owner exact ", assignmentRequestId, workspaceId, otherProjectId, parentId], "POST", otherAssignPath, "owner", assignmentBody),
      409, "organization_project_membership_assignment_conflict");
    assert.equal(businessCalls, 10);

    for (const route of [
      { method: "POST" as const, path: createPath }, { method: "GET" as const, path: previewPath },
      { method: "POST" as const, path: submitPath }, { method: "POST" as const, path: approvePath }, { method: "POST" as const, path: assignPath },
    ]) {
      assertError(await rawRequest(port, route.method, `${route.path}?`, undefined, "not-json"), 401, "unauthenticated");
      const beforeAlias = verificationCalls;
      assertError(await rawRequest(port, route.method, route.path.replace("/v1/", "/v1/%2e/"), "owner", "not-json"), 404, "not_found");
      assert.equal(verificationCalls, beforeAlias);
    }
    assertError(await rawRequest(port, "POST", approvePath, "owner", JSON.stringify({ project_id: projectId })), 400, "invalid_organization_shareable_join_request");
    assertError(await rawRequest(port, "POST", assignPath, "unavailable", "not-json"), 503, "organization_project_membership_assignment_unavailable");
    assert.equal(businessCalls, 10);
    assert.equal(contextCalls, 0);
    // Observe after a final exact HTTP replay rather than treating a rejection
    // as a successful commit acknowledgement. It also proves failures added no facts.
    const finalReplay = await call(assignSql, [issuer, " owner exact ", assignmentRequestId, workspaceId, projectId, parentId], "POST", assignPath, "owner", assignmentBody);
    assertHeaders(finalReplay, 200);
    assert.equal(finalReplay.rawBody, assignedResponse.rawBody);
    await assertFacts(owner, workspaceId, 1, 1, 1, 1, 1);
    assert.equal(businessCalls, 11);
    process.stdout.write("Join/project HTTP runtime integration: applicant org 0->0->1->1; project 0->0->0->1; capabilities=0; link claim/audit=1/1; application claim/submitted/approved=1/1/1; assignment claim/audit=1/1; callbacks=11; exact replay and stable rejections passed\n");
  } finally {
    try { if (server?.listening) await close(server); }
    finally {
      // Leave unique committed synthetic facts in the disposable database.
      // Destroy role-bearing connections; no physical delete or guard bypass.
      runtime?.release(true);
      owner?.release(true);
      await pool.end();
    }
  }
});

async function assertFacts(observer: PoolClient, workspaceId: string, links: number, applications: number, approvals: number, parents: number, children: number): Promise<void> {
  const facts = (await observer.query(`SELECT
    (SELECT count(*)::integer FROM app_data.organization_memberships WHERE app_user_id = $2::uuid) AS applicant_parents,
    (SELECT count(*)::integer FROM app_data.project_memberships JOIN app_data.organization_memberships USING(organization_membership_id) WHERE app_user_id = $2::uuid) AS applicant_children,
    (SELECT count(*)::integer FROM app_data.organization_memberships WHERE organization_workspace_id = $1::uuid) AS parents,
    (SELECT count(*)::integer FROM app_data.project_memberships JOIN app_data.projects USING(project_id) WHERE workspace_id = $1::uuid) AS children,
    (SELECT count(*)::integer FROM app_data.organization_owner_assignments JOIN app_data.organization_memberships USING(organization_membership_id) WHERE organization_workspace_id = $1::uuid) AS owners,
    (SELECT count(*)::integer FROM app_data.management_report_capability_grants JOIN app_data.project_memberships USING(project_membership_id) JOIN app_data.projects USING(project_id) WHERE workspace_id = $1::uuid) AS capabilities,
    (SELECT count(*)::integer FROM app_private.organization_shareable_join_link_request_claims WHERE organization_workspace_id = $1::uuid) AS link_claims,
    (SELECT count(*)::integer FROM app_private.organization_shareable_join_link_audit_events WHERE organization_workspace_id = $1::uuid) AS link_audits,
    (SELECT count(*)::integer FROM app_private.organization_shareable_join_application_request_claims WHERE organization_workspace_id = $1::uuid) AS application_claims,
    (SELECT count(*)::integer FROM app_private.organization_shareable_join_application_audit_events WHERE organization_workspace_id = $1::uuid AND event_kind = 'application_submitted') AS submitted_audits,
    (SELECT count(*)::integer FROM app_private.organization_shareable_join_application_audit_events WHERE organization_workspace_id = $1::uuid AND event_kind = 'application_approved') AS approved_audits,
    (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_request_claims WHERE organization_workspace_id = $1::uuid) AS assignment_claims,
    (SELECT count(*)::integer FROM app_private.organization_project_membership_assignment_audit_events WHERE organization_workspace_id = $1::uuid) AS assignment_audits`,
  [workspaceId, applicantUserId])).rows[0];
  assert.deepEqual(facts, {
    applicant_parents: parents, applicant_children: children, parents: 3 + parents, children: 2 + children, owners: 1, capabilities: 0,
    link_claims: links, link_audits: links, application_claims: applications, submitted_audits: applications, approved_audits: approvals,
    assignment_claims: children, assignment_audits: children,
  });
}

function receipt(response: RawResponse, fields: Readonly<Record<string, unknown>>, times: readonly string[], ids: readonly string[] = []): Record<string, unknown> {
  assertHeaders(response, 200);
  assert.ok(typeof response.body === "object" && response.body !== null && !Array.isArray(response.body));
  const row = response.body as Record<string, unknown>;
  assert.deepEqual(Object.keys(row).sort(), [...Object.keys(fields), ...times, ...ids].sort());
  for (const [key, value] of Object.entries(fields)) {
    assert.equal(row[key], value);
    if (key.endsWith("_id") && !key.endsWith("_contract_id")) assertUuid(row[key]);
  }
  for (const key of ids) assertUuid(row[key]);
  for (const key of times) {
    assert.equal(typeof row[key], "string");
    assert.match(row[key] as string, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u);
    assert.equal(new Date(row[key] as string).toISOString(), row[key]);
  }
  return row;
}

function assertUuid(value: unknown): void {
  assert.equal(typeof value, "string");
  assert.match(value as string, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u);
}

function mappedUuid(id: string): string {
  const mapped = uuidMap.get(id);
  assert.ok(mapped, "fixed 0096 UUID must be regenerated consistently");
  return mapped;
}

function normalizeSql(text: string): string { return text.replace(/\s+/gu, " ").trim(); }

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

function rawRequest(port: number, method: "GET" | "POST", path: string, token: string | undefined, body?: string): Promise<RawResponse> {
  return new Promise((resolve, reject) => {
    const request = httpRequest({ host: "127.0.0.1", port, method, path, headers: {
      ...(token === undefined ? {} : { authorization: `Bearer ${token}` }),
      ...(body === undefined ? {} : { "content-type": "application/json; charset=utf-8", "content-length": String(Buffer.byteLength(body)) }),
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
    request.setTimeout(5_000, () => request.destroy(new Error("join/project HTTP test request timed out")));
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
  return new Promise((resolve, reject) => server.close((error) => error === undefined ? resolve() : reject(error)));
}
