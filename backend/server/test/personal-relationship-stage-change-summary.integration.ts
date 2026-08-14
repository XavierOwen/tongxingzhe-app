import assert from "node:assert/strict";

import {Pool} from "pg";

import {
  PostgresPersonalRelationshipStageChangeSummaryStore,
} from "../src/personal-relationship-stage-change-summary.js";
import {PostgresSessionContextStore} from "../src/session-context.js";

const identity = {
  issuer:
    "https://synthetic-stage-change-summary-integration.example.test/auth/v1",
  subject: "stage-change-summary-integration-owner",
};
const period = {
  fromUtc: "2020-01-01T00:00:00.000Z",
  untilUtc: "2020-02-01T00:00:00.000Z",
};

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for stage-change summary integration");
}

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");
  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const context = await new PostgresSessionContextStore(query).loadOrCreate(
    identity,
  );

  const targetIds: string[] = [];
  for (const suffix of ["first", "second", "third", "fourth"]) {
    const created = await query(
      `SELECT target
         FROM app_data.create_promotion_target(
           $1::uuid, $2::uuid, $3::uuid,
           'person', $4, NULL, NULL, $5
         )`,
      [
        context.appUserId,
        context.current.workspace.id,
        context.current.project.id,
        `integration-only ${suffix} target`,
        `stage-change-summary-integration-${suffix}`,
      ],
    );
    const document = requireRecord(
      requireRecord(created.rows[0], "created target row").target,
      "created target document",
    );
    targetIds.push(requireString(document.target_id, "target_id"));
  }
  const firstTargetId = requireString(targetIds[0], "first target id");
  const secondTargetId = requireString(targetIds[1], "second target id");
  const thirdTargetId = requireString(targetIds[2], "third target id");
  const fourthTargetId = requireString(targetIds[3], "fourth target id");

  // Install deterministic history as the deployment owner. Runtime still
  // performs the only read through the narrow SECURITY DEFINER bridge.
  await client.query("RESET ROLE");
  for (const targetId of targetIds) {
    await client.query(
      `INSERT INTO app_data.promotion_target_project_relationships (
         promotion_target_id,
         project_id,
         current_stage,
         established_by_app_user_id,
         established_at
       ) VALUES ($1::uuid, $2::uuid, 1, $3::uuid, $4::timestamptz)`,
      [
        targetId,
        context.current.project.id,
        context.appUserId,
        "2020-01-02T00:00:00Z",
      ],
    );
  }
  await insertRevision(firstTargetId, 2, 1, 3, ["stage"], "2020-01-03T00:00:00Z");
  await insertRevision(firstTargetId, 3, 3, 2, ["stage"], "2020-01-04T00:00:00Z");
  await insertRevision(firstTargetId, 4, 2, 2, ["stage"], "2020-01-05T00:00:00Z");
  await insertRevision(
    secondTargetId,
    2,
    1,
    2,
    ["stage", "follow_up_note"],
    "2020-01-06T00:00:00Z",
  );
  await insertRevision(
    secondTargetId,
    3,
    2,
    2,
    ["lifecycle_status"],
    "2020-01-07T00:00:00Z",
  );
  await insertRevision(thirdTargetId, 2, 1, 0, ["stage"], "2020-01-08T00:00:00Z");
  await insertRevision(fourthTargetId, 2, 1, 4, ["stage"], "2020-01-09T00:00:00Z");

  await client.query("SET LOCAL ROLE tongxingzhe_runtime");
  const summary = await new PostgresPersonalRelationshipStageChangeSummaryStore(
    query,
  ).read(identity, period);

  assert.equal(
    summary.contractId,
    "personal_relationship_stage_change_summary_result_v1",
  );
  assert.equal(summary.projectId, context.current.project.id.toLowerCase());
  assert.equal(summary.timeBasis, "relationshipChangedAtUtc");
  assert.deepEqual(summary.period, period);
  assert.equal(summary.dataCutoffUtc, summary.authorizedAtUtc);
  assert.deepEqual(summary.value, {
    eventCount: 5,
    distinctRelationshipCount: 4,
    upwardCount: 3,
    downwardCount: 2,
  });
  assert.doesNotMatch(
    JSON.stringify(summary),
    /integration-only|subject|workspace|display_name|phone|email|note/i,
  );
  const empty = await new PostgresPersonalRelationshipStageChangeSummaryStore(
    query,
  ).read(identity, {
    fromUtc: "2020-02-01T00:00:00.000Z",
    untilUtc: "2020-03-01T00:00:00.000Z",
  });
  assert.deepEqual(empty.value, {
    eventCount: 0,
    distinctRelationshipCount: 0,
    upwardCount: 0,
    downwardCount: 0,
  });
  process.stdout.write(
    "Backend personal relationship stage-change summary integration: passed\n",
  );

  async function insertRevision(
    targetId: string,
    revision: number,
    oldStage: number,
    newStage: number,
    changedFields: readonly string[],
    changedAt: string,
  ): Promise<void> {
    await client.query(
      `INSERT INTO app_data.promotion_target_relationship_revisions (
         promotion_target_id,
         project_id,
         revision_number,
         old_stage,
         new_stage,
         old_lifecycle_status,
         new_lifecycle_status,
         changed_fields,
         reason_code,
         changed_by_app_user_id,
         changed_at
       ) VALUES (
         $1::uuid, $2::uuid, $3::integer, $4::integer, $5::integer,
         'active', 'active', $6::text[], 'progress_update', $7::uuid,
         $8::timestamptz
       )`,
      [
        targetId,
        context.current.project.id,
        revision,
        oldStage,
        newStage,
        [...changedFields],
        context.appUserId,
        changedAt,
      ],
    );
  }
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
