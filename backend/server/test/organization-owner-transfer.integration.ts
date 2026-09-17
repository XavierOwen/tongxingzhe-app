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

const ownerTransferFactsQuery = `SELECT jsonb_build_object(
  'owners', (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.organization_owner_assignment_id), '[]')
    FROM app_data.organization_owner_assignments a
    JOIN app_data.organization_memberships m USING (organization_membership_id)
    WHERE m.organization_workspace_id = $1::uuid),
  'claims', (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.request_id), '[]')
    FROM app_private.organization_owner_transfer_request_claims c WHERE c.organization_workspace_id = $1::uuid),
  'audits', (SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.organization_owner_transfer_audit_event_id), '[]')
    FROM app_private.organization_owner_transfer_audit_events e WHERE e.organization_workspace_id = $1::uuid)
) AS facts`;

for (const scenario of ["target parent starts", "actor becomes owner"] as const) {
  test(`owner transfer effective-time qualification: ${scenario} during implicit bridge lock wait`, async () => {
    const pool = new Pool({connectionString: databaseUrl, max: 4});
    const [holder, writer, observer, later] = await Promise.all([
      pool.connect(), pool.connect(), pool.connect(), pool.connect(),
    ]);
    let pending: ReturnType<typeof handleOrganizationOwnerTransfer> | undefined;
    try {
      const pids = await Promise.all([holder, writer, observer, later].map(async (client) =>
        (await client.query("SELECT pg_backend_pid() AS pid")).rows[0].pid as number));
      assert.equal(new Set(pids).size, 4, "four distinct physical connections");
      const [holderPid, writerPid] = pids;
      const oldOwnerId = randomUUID();
      const actorId = scenario === "target parent starts" ? oldOwnerId : randomUUID();
      const targetId = randomUUID();
      const actorMembershipId = randomUUID();
      const targetMembershipId = randomUUID();
      const blockedRequestId = randomUUID();
      const issuer = "https://synthetic-0098.example";
      await observer.query("BEGIN");
      for (const userId of new Set([oldOwnerId, actorId, targetId])) {
        await observer.query("INSERT INTO app_data.app_users(app_user_id, status) VALUES ($1::uuid, 'active')", [userId]);
        await observer.query(
          `INSERT INTO app_data.external_identities(external_identity_id, issuer, subject, app_user_id)
           VALUES ($1::uuid, $2::text, $3::text, $3::text::uuid)`, [randomUUID(), issuer, userId],
        );
      }
      const organization = (await observer.query(
        "SELECT * FROM app_private.create_organization_v1($1::uuid, $2::uuid, $3::text)",
        [oldOwnerId, randomUUID(), "0098 synthetic temporal qualification"],
      )).rows[0];
      const workspaceId = organization.organization_workspace_id as string;
      if (scenario === "actor becomes owner") {
        await observer.query(
          "INSERT INTO app_data.organization_memberships VALUES ($1::uuid, $2::uuid, $3::uuid, transaction_timestamp(), NULL)",
          [actorMembershipId, workspaceId, actorId],
        );
        await observer.query(
          "INSERT INTO app_data.organization_memberships VALUES ($1::uuid, $2::uuid, $3::uuid, transaction_timestamp(), NULL)",
          [targetMembershipId, workspaceId, targetId],
        );
      }
      await observer.query("COMMIT");
      await writer.query("SET ROLE tongxingzhe_runtime");
      await later.query("SET ROLE tongxingzhe_runtime");
      const lockName = `organization-owner-transfer-request:${blockedRequestId}`;
      const key = (await holder.query("SELECT hashtextextended($1::text, 0)::text AS key", [lockName])).rows[0].key as string;
      await holder.query("BEGIN");
      await holder.query("SELECT pg_advisory_xact_lock($1::bigint)", [key]);
      let databaseFailure: unknown;
      const store = new PostgresOrganizationOwnerTransferStore(async (text, values) => {
        try { return await writer.query(text, [...values]); }
        catch (error) { databaseFailure = error; throw error; }
      });
      // Synthetic verifier seam; the runtime bridge still resolves exact seeded identity.
      const invoke = (id: string) => handleOrganizationOwnerTransfer({
        authorization: "Bearer synthetic-owner-transfer", workspaceId, hasQuery: false,
        readBody: async () => ({request_id: id, target_organization_membership_id: targetMembershipId}),
      }, {identityVerifier: {verify: async () => ({issuer, subject: actorId})}, transferStore: store});
      pending = invoke(blockedRequestId); // No BEGIN: the real bridge SELECT owns its implicit transaction.
      const waitForExactLock = async () => {
        for (let attempt = 0; attempt < 1000; attempt += 1) {
          const wait = (await observer.query(
            `SELECT a.xact_start::text, a.wait_event_type, a.wait_event, pg_blocking_pids(a.pid) AS blockers
             FROM pg_stat_activity a JOIN pg_locks l ON l.pid = a.pid
             WHERE a.pid = $1 AND a.wait_event_type = 'Lock' AND a.wait_event = 'advisory'
               AND l.locktype = 'advisory' AND NOT l.granted AND l.objsubid = 1
               AND l.classid::bigint = (($2::bigint >> 32) & 4294967295::bigint)
               AND l.objid::bigint = ($2::bigint & 4294967295::bigint)
               AND EXISTS (SELECT 1 FROM pg_locks held WHERE held.pid = $3
                 AND held.locktype = 'advisory' AND held.granted
                 AND held.classid = l.classid AND held.objid = l.objid AND held.objsubid = l.objsubid)`,
            [writerPid, key, holderPid],
          )).rows[0];
          if (wait?.blockers.includes(holderPid)) {
            assert.equal(wait.wait_event_type, "Lock");
            assert.equal(wait.wait_event, "advisory");
            return;
          }
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
        assert.fail("writer physical PID did not wait on the exact holder advisory key");
      };
      await waitForExactLock();
      if (scenario === "target parent starts") {
        // Establish the parent only after the bridge's implicit transaction is blocked.
        await observer.query("BEGIN");
        await observer.query(
          "INSERT INTO app_data.organization_memberships VALUES ($1::uuid, $2::uuid, $3::uuid, transaction_timestamp(), NULL)",
          [targetMembershipId, workspaceId, targetId],
        );
        await observer.query("COMMIT");
        const times = (await observer.query(
          `SELECT a.xact_start < m.active_from_utc AS transaction_precedes_parent,
                  clock_timestamp() >= m.active_from_utc AS parent_now_active
           FROM pg_stat_activity a CROSS JOIN app_data.organization_memberships m
           WHERE a.pid = $1 AND m.organization_membership_id = $2::uuid`, [writerPid, targetMembershipId],
        )).rows[0];
        assert.equal(times.transaction_precedes_parent, true);
        assert.equal(times.parent_now_active, true);
      } else {
        const handoff = (await later.query(
          "SELECT * FROM app_data.transfer_organization_owner_for_identity_v1($1::text, $2::text, $3::uuid, $4::uuid, $5::uuid)",
          [issuer, oldOwnerId, randomUUID(), workspaceId, actorMembershipId],
        )).rows[0]; // This later implicit transaction has committed before the original writer unlocks.
        const times = (await observer.query(
          `SELECT a.xact_start < o.active_from_utc AS transaction_precedes_owner, o.inactive_from_utc IS NULL AS owner_unended
           FROM pg_stat_activity a CROSS JOIN app_data.organization_owner_assignments o
           WHERE a.pid = $1 AND o.organization_owner_assignment_id = $2::uuid`,
          [writerPid, handoff.organization_owner_assignment_id],
        )).rows[0];
        assert.equal(times.transaction_precedes_owner, true);
        assert.equal(times.owner_unended, true);
      }
      await waitForExactLock();
      const before = (await observer.query(ownerTransferFactsQuery, [workspaceId])).rows[0].facts;
      await holder.query("COMMIT");
      const rejected = await pending;
      pending = undefined;
      assert.ok(databaseFailure instanceof Error);
      assert.equal((databaseFailure as Error & {code?: string}).code, "42501");
      assert.equal(databaseFailure.message, "organization owner transfer forbidden");
      assert.equal(rejected.status, 403);
      assert.deepEqual(rejected.body, {error: {code: "organization_owner_transfer_forbidden"}});
      assert.deepEqual((await observer.query(ownerTransferFactsQuery, [workspaceId])).rows[0].facts, before);
      const control = await invoke(blockedRequestId); // Same request and intent, but a new implicit transaction.
      assert.equal(control.status, 200);
    } finally {
      await holder.query("ROLLBACK");
      await observer.query("ROLLBACK");
      if (pending !== undefined) await pending;
      for (const client of [holder, writer, observer, later]) client.release();
      await pool.end();
    }
  });
}
