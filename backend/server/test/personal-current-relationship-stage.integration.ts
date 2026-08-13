import assert from "node:assert/strict";

import {Pool} from "pg";

import {
  PostgresPersonalCurrentRelationshipStageStore,
} from "../src/personal-current-relationship-stage.js";
import {PostgresSessionContextStore} from "../src/session-context.js";

const identity = {
  issuer:
    "https://synthetic-current-relationship-stage-integration.example.test/auth/v1",
  subject: "current-relationship-stage-integration-owner",
};

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error(
    "DATABASE_URL is required for current relationship stage integration",
  );
}

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");
  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const contextStore = new PostgresSessionContextStore(query);
  const context = await contextStore.loadOrCreate(identity);

  const createdTarget = await query(
    `SELECT target
       FROM app_data.create_promotion_target(
         $1::uuid, $2::uuid, $3::uuid,
         'person', $4, NULL, NULL, $5
       )`,
    [
      context.appUserId,
      context.current.workspace.id,
      context.current.project.id,
      "integration-only target name",
      "current-relationship-stage-integration-target",
    ],
  );
  assert.equal(createdTarget.rows.length, 1);
  const targetDocument = requireRecord(
    (createdTarget.rows[0] as Record<string, unknown>).target,
    "created target document",
  );
  const targetId = requireString(targetDocument.target_id, "target_id");

  // The fixture installs rows through the deployment owner. This integration
  // does the same inside its rollback-only transaction, then reads only via
  // the runtime bridge.
  await client.query("RESET ROLE");
  await client.query(
    `INSERT INTO app_data.promotion_target_project_relationships (
       promotion_target_id,
       project_id,
       current_stage,
       established_by_app_user_id
     ) VALUES ($1::uuid, $2::uuid, 2, $3::uuid)`,
    [targetId, context.current.project.id, context.appUserId],
  );
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");

  const snapshotStore = new PostgresPersonalCurrentRelationshipStageStore(
    query,
  );
  const snapshot = await snapshotStore.read(context);
  assert.equal(snapshot.contractId, "current_relationship_stage_distribution@1");
  assert.equal(snapshot.statisticalUnit, "targetProjectRelationship");
  assert.equal(snapshot.projectKey, context.current.project.id.toLowerCase());
  assert.deepEqual(snapshot.coverage, {total: 1, pending: 0});
  assert.equal(snapshot.relationships.length, 1);
  const relationship = snapshot.relationships[0];
  assert.ok(relationship);
  assert.deepEqual(relationship, {
    targetKey: targetId,
    stage: 2,
    revision: 1,
    updatedAtUtc: relationship.updatedAtUtc,
  });
  assert.equal(snapshot.sourceCutoffUtc <= snapshot.snapshotAsOfUtc, true);
  assert.equal(snapshot.authorizedAtUtc <= snapshot.snapshotAsOfUtc, true);
  assert.equal(
    JSON.stringify(snapshot).includes("integration-only target name"),
    false,
  );
  process.stdout.write(
    "Backend current relationship stage bridge integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}

function requireRecord(value: unknown, name: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${name} must be an object`);
  }
  return value as Record<string, unknown>;
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${name} must be a non-empty string`);
  }
  return value;
}
