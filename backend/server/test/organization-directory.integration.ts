import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { Pool } from "pg";
import test from "node:test";

import {
  OrganizationDirectoryStoreError,
  PostgresOrganizationDirectoryStore,
} from "../src/organization-directory.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for organization directory integration");
}

const fixturePath = process.env.ORGANIZATION_DIRECTORY_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0089_organization_directory.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const issuer = "https://synthetic-0089.example/auth/v1";
const directoryIdentity = { issuer, subject: "directory-member" };
const emptyDirectoryIdentity = { issuer, subject: "empty-directory-member" };

test("organization directory adapter reads the runtime bridge", async () => {
  const pool = new Pool({ connectionString: databaseUrl });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const store = new PostgresOrganizationDirectoryStore(
      async (text, values) => client.query(text, [...values]),
    );

    assert.deepEqual(await store.list(directoryIdentity), [
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000001",
        organizationName: " 0089 Original 名称  ",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000002",
        organizationName: "0089 Alpha projectless",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000005",
        organizationName: "0089 Boundary start",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000003",
        organizationName: "0089 Same",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000004",
        organizationName: "0089 Same",
      },
    ]);
    assert.deepEqual(await store.list(emptyDirectoryIdentity), []);

    await client.query("SAVEPOINT forbidden_identity");
    await assertStoreError(
      () => store.list({ issuer, subject: "unknown-member" }),
      "organization_directory_forbidden",
    );
    await client.query("ROLLBACK TO SAVEPOINT forbidden_identity");
    await client.query("RELEASE SAVEPOINT forbidden_identity");

    await client.query("SAVEPOINT invalid_identity");
    await assertStoreError(
      () => store.list({ issuer, subject: " " }),
      "organization_directory_unavailable",
    );
    await client.query("ROLLBACK TO SAVEPOINT invalid_identity");
    await client.query("RELEASE SAVEPOINT invalid_identity");

    process.stdout.write("Backend organization directory runtime integration: passed\n");
  } finally {
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      await pool.end();
    }
  }
});

test("0089 side-effect counts ignore an unrelated commit after their baseline", {timeout: 20_000}, async () => {
  const pool = new Pool({connectionString: databaseUrl, max: 2, connectionTimeoutMillis: 5_000});
  const client = await pool.connect();
  const holder = await pool.connect();
  const barrierKey = randomInt(1, 2_147_483_647);
  const marker = "CREATE TEMP TABLE fixture_0089_main_directory";
  assert.equal(fixture.split(marker).length, 2, "after_baseline marker must be unique");
  let pending: Promise<unknown> | undefined;
  let settled = false;
  try {
    const fixturePid = (await client.query<{pid: number}>("SELECT pg_backend_pid() AS pid")).rows[0]?.pid;
    const holderPid = (await holder.query<{pid: number}>("SELECT pg_backend_pid() AS pid")).rows[0]?.pid;
    assert.ok(fixturePid && holderPid && fixturePid !== holderPid);
    await holder.query("BEGIN");
    await holder.query("SET LOCAL statement_timeout = '10s'");
    await holder.query("SELECT pg_advisory_xact_lock($1::integer, 89)", [barrierKey]);
    await client.query("BEGIN");
    await client.query("SET LOCAL statement_timeout = '10s'");
    assert.equal((await client.query("SHOW transaction_isolation")).rows[0].transaction_isolation, "read committed");
    pending = client.query(fixture.replace(marker,
      `SELECT pg_advisory_xact_lock(${barrierKey}, 89);\n${marker}`)).then(
      () => {settled = true; return undefined;},
      (error: unknown) => {settled = true; return error;},
    );
    const deadline = performance.now() + 5_000;
    let exactWait = false;
    do {
      exactWait = (await holder.query<{waiting: boolean}>(`SELECT EXISTS (
        SELECT 1 FROM pg_locks AS waiting JOIN pg_locks AS held
          USING(locktype, database, classid, objid, objsubid)
        WHERE waiting.locktype = 'advisory' AND waiting.pid = $1::integer AND NOT waiting.granted
          AND held.pid = $2::integer AND held.granted
          AND waiting.classid = $3::oid AND waiting.objid = 89 AND waiting.objsubid = 2
          AND $2::integer = ANY(pg_blocking_pids($1::integer))
      ) AS waiting`, [fixturePid, holderPid, barrierKey])).rows[0]?.waiting === true;
      if (exactWait) break;
      if (settled) {
        assert.ifError(await pending);
        assert.fail("0089 fixture finished before its exact after_baseline barrier");
      }
      await delay(10);
    } while (performance.now() < deadline);
    assert.equal(exactWait, true, "fixture PID must wait on the exact holder PID and advisory key");

    const context = (await holder.query<{app_user_id: string}>(
      "SELECT * FROM app_data.bootstrap_personal_context($1::text, $2::text)",
      ["https://0089-unrelated-bootstrap.example.test/auth/v1", randomUUID()],
    )).rows[0];
    assert.ok(context);
    const organization = (await holder.query<{organization_workspace_id: string; organization_membership_id: string}>(
      "SELECT * FROM app_private.create_organization_v1($1::uuid, $2::uuid, '0089 unrelated generated organization')",
      [context.app_user_id, randomUUID()],
    )).rows[0];
    assert.ok(organization);
    const projectId = randomUUID();
    const projectMembershipId = randomUUID();
    await holder.query("INSERT INTO app_data.projects(project_id, workspace_id, display_name) VALUES ($1::uuid, $2::uuid, '0089 unrelated project')",
      [projectId, organization.organization_workspace_id]);
    await holder.query(`INSERT INTO app_data.project_memberships(project_membership_id,
      organization_membership_id, project_id, active_from_utc) VALUES ($1::uuid, $2::uuid, $3::uuid, clock_timestamp())`,
    [projectMembershipId, organization.organization_membership_id, projectId]);
    await holder.query(`INSERT INTO app_data.management_report_capability_grants(capability_grant_id,
      project_membership_id, capability_id, active_from_utc) VALUES ($1::uuid, $2::uuid, 'view_anonymous_analytics', clock_timestamp())`,
    [randomUUID(), projectMembershipId]);
    // COMMIT both publishes the unrelated lineage under RC and releases this exact barrier.
    await holder.query("COMMIT");
    process.stdout.write(`0089 after_baseline: fixture PID ${fixturePid} waited on holder PID ${holderPid}, advisory ${barrierKey}/89, before unrelated bootstrap commit\n`);
    assert.ifError(await pending);
  } finally {
    await holder.query("ROLLBACK");
    if (pending !== undefined) await pending;
    await client.query("ROLLBACK");
    holder.release(true);
    client.release(true);
    await pool.end();
  }
});

test("0089 side-effect counts still reject generated facts in every fixture lineage", async (t) => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  const marker = "DO $read_only$";
  assert.equal(fixture.split(marker).length, 2, "final side-effect assertion marker must be unique");
  const scenarios: readonly (readonly [string, string, readonly number[]])[] = [
    ["same-issuer generated bootstrap", `SELECT * FROM app_data.bootstrap_personal_context(
      '${issuer}', '0089-generated-' || gen_random_uuid()::text);`, [1, 1, 1, 1, 0, 0, 0, 0]],
    ["generated alias identity on a fixture user", `INSERT INTO app_data.external_identities(issuer, subject, app_user_id)
      VALUES ('https://0089-related-alias.example.test/auth/v1', gen_random_uuid()::text,
        '00000000-0089-0000-0000-000000000001');`, [0, 1, 0, 0, 0, 0, 0, 0]],
    ["generated project in a fixture workspace", `INSERT INTO app_data.projects(project_id, workspace_id, display_name)
      VALUES (gen_random_uuid(), '00000000-0089-2000-0000-000000000003', '0089 generated project');`, [0, 0, 0, 1, 0, 0, 0, 0]],
    ["generated organization, membership and owner for a fixture user", `SELECT * FROM app_private.create_organization_v1(
      '00000000-0089-0000-0000-000000000001', gen_random_uuid(), '0089 related generated organization');`, [0, 0, 1, 0, 1, 1, 0, 0]],
    ["generated member and its personal, project and capability descendants", `DO $after_baseline$
      DECLARE context record; membership_id uuid := gen_random_uuid(); project_member_id uuid := gen_random_uuid();
      BEGIN
        SELECT * INTO STRICT context FROM app_data.bootstrap_personal_context(
          'https://0089-related-generated-member.example.test/auth/v1', gen_random_uuid()::text);
        INSERT INTO app_data.organization_memberships(organization_membership_id, organization_workspace_id,
          app_user_id, active_from_utc) VALUES (membership_id, '00000000-0089-2000-0000-000000000003',
          context.app_user_id, clock_timestamp());
        INSERT INTO app_data.project_memberships(project_membership_id, organization_membership_id,
          project_id, active_from_utc) VALUES (project_member_id, membership_id,
          '00000000-0089-2500-0000-000000000001', clock_timestamp());
        INSERT INTO app_data.management_report_capability_grants(capability_grant_id, project_membership_id,
          capability_id, active_from_utc) VALUES (gen_random_uuid(), project_member_id, 'view_anonymous_analytics', clock_timestamp());
      END $after_baseline$;`, [1, 1, 1, 1, 1, 0, 1, 1]],
  ];
  try {
    for (const [name, statement, expectedDelta] of scenarios) {
      await t.test(name, async () => {
        await client.query("BEGIN");
        try {
          await assert.rejects(client.query(fixture.replace(marker, `${statement}\n${marker}`)), (error: unknown) => {
            assert.ok(error instanceof Error);
            assert.equal((error as Error & {code?: string}).code, "P0001");
            const counts = /^0089 organization directory wrote business facts: before \(([^)]+)\), after \(([^)]+)\)$/.exec(error.message);
            assert.ok(counts, "the original eight-counter assertion must detect the related write");
            const before = counts[1]!.split(",").map(Number);
            const after = counts[2]!.split(",").map(Number);
            assert.deepEqual(after.map((count, index) => count - before[index]!), expectedDelta);
            process.stdout.write(`0089 after_baseline related ${name}: counter delta (${expectedDelta.join(",")}) rejected\n`);
            return true;
          });
        } finally {
          await client.query("ROLLBACK");
        }
      });
    }
  } finally {
    client.release();
    await pool.end();
  }
});

async function assertStoreError(
  operation: () => Promise<unknown>,
  code:
    | "organization_directory_forbidden"
    | "organization_directory_unavailable",
): Promise<void> {
  await assert.rejects(operation, (error: unknown) => {
    assert.ok(error instanceof OrganizationDirectoryStoreError);
    assert.equal(error.code, code);
    assert.equal(error.message, code);
    return true;
  });
}
