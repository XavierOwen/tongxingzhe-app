import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";
import {Pool} from "pg";

import {
  ManagementCurrentCityReportSnapshotStoreError,
  PostgresManagementCurrentCityReportSnapshotStore,
} from "../src/management-current-city-report-snapshots.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for current-city runtime integration");
}

const fixturePath = process.env.CURRENT_CITY_RUNTIME_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0059_runtime_authorized_management_current_city_report_snapshot_read.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  // The fixture is also consumed by psql, so strip its meta-command and
  // transaction wrapper wherever the SQL comments place those lines.
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://runtime-current-city.synthetic/auth/v1",
  subject: "active-reader",
};
const projectId = "af130000-0000-4000-8000-000000000001";
const snapshotId = "af1a0000-0000-4000-8000-000000000001";

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query(fixture);
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");

  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const store = new PostgresManagementCurrentCityReportSnapshotStore(query);

  const result = await store.read(identity, projectId, snapshotId);
  assert.equal(result.status, "completed");
  if (result.status === "completed") {
    assert.equal(result.requestedSnapshotId, snapshotId);
    assert.equal(result.resolvedSnapshotId, snapshotId);
    assert.equal(
      result.protectedReport.report_id,
      "contact_sessions_by_current_city_two_periods",
    );
    assert.equal(result.protectedReport.project_id, projectId);
  }

  await assert.rejects(
    store.read(
      {...identity, subject: "unknown-reader"},
      projectId,
      snapshotId,
    ),
    (error: unknown) =>
      error instanceof ManagementCurrentCityReportSnapshotStoreError &&
      error.code === "forbidden",
  );

  process.stdout.write(
    "Backend current-city runtime bridge integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
