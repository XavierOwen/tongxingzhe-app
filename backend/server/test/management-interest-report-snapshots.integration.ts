import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";

import {
  ManagementInterestReportSnapshotStoreError,
  PostgresManagementInterestReportSnapshotStore,
} from "../src/management-interest-report-snapshots.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for interest runtime integration");
}

const fixturePath = process.env.INTEREST_RUNTIME_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0064_runtime_authorized_management_interest_report_snapshot_read.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  // The fixture is also consumed by psql, so strip its meta-command and
  // transaction wrapper before running it in this integration transaction.
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://runtime-interest.synthetic/auth/v1",
  subject: "active-reader",
};
const projectId = "6f130000-0000-4000-8000-000000000001";

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query(fixture);
  const snapshotResult = await client.query<{value: string}>(
    "SELECT current_setting('app.fixture_6ay_baseline_snapshot_id') AS value",
  );
  assert.equal(snapshotResult.rows.length, 1);
  const snapshotId = snapshotResult.rows[0]?.value;
  assert.ok(snapshotId);

  await client.query("SET LOCAL ROLE tongxingzhe_runtime");
  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const store = new PostgresManagementInterestReportSnapshotStore(query);

  const assertForbidden = async (subject: string): Promise<void> => {
    await client.query("SAVEPOINT interest_runtime_forbidden");
    try {
      await assert.rejects(
        store.read({...identity, subject}, projectId, snapshotId),
        (error: unknown) =>
          error instanceof ManagementInterestReportSnapshotStoreError &&
          error.code === "forbidden",
      );
    } finally {
      await client.query("ROLLBACK TO SAVEPOINT interest_runtime_forbidden");
      await client.query("RELEASE SAVEPOINT interest_runtime_forbidden");
    }
  };

  const result = await store.read(identity, projectId, snapshotId);
  assert.equal(result.status, "completed");
  if (result.status === "completed") {
    assert.equal(result.requestedSnapshotId, snapshotId);
    assert.equal(result.resolvedSnapshotId, snapshotId);
    assert.equal(
      result.protectedReport.report_id,
      "contact_sessions_by_interest_level_two_periods",
    );
    assert.equal(result.protectedReport.project_id, projectId);
    const cells = result.protectedReport.cells;
    assert.ok(Array.isArray(cells));
    assert.equal(cells.length, 10);
  }

  await assertForbidden("unknown-reader");
  await assertForbidden("inactive-reader");

  process.stdout.write(
    "Backend interest runtime bridge integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
