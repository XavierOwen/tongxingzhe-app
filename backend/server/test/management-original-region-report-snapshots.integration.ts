import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";

import {
  ManagementOriginalRegionReportSnapshotStoreError,
  PostgresManagementOriginalRegionReportSnapshotStore,
} from "../src/management-original-region-report-snapshots.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error(
    "DATABASE_URL is required for original-region runtime integration",
  );
}

const fixturePath = process.env.ORIGINAL_REGION_RUNTIME_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0070_runtime_authorized_management_original_region_report_snapshot_read.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  // The same fixture is also consumed by psql.  The integration owns the
  // transaction so strip psql's meta-command and transaction wrapper.
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");
const unknownSnapshotId = "6bb00000-0000-4000-8000-000000000001";
const untrustedSnapshotId = "6ba00000-0000-4000-8000-000000000001";

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query(fixture);

  const settings = await client.query<{
    readonly issuer: string | null;
    readonly subject: string | null;
    readonly project_id: string | null;
    readonly snapshot_id: string | null;
  }>(
    `SELECT
       current_setting('app.fixture_6bi_identity_issuer', true) AS issuer,
       current_setting('app.fixture_6bi_identity_subject', true) AS subject,
       current_setting('app.fixture_6bi_project_id', true) AS project_id,
       current_setting('app.fixture_6bi_baseline_snapshot_id', true)
         AS snapshot_id`,
  );
  const setting = settings.rows[0];
  assert.ok(setting);
  assert.ok(setting.issuer);
  assert.ok(setting.subject);
  assert.ok(setting.project_id);
  assert.ok(setting.snapshot_id);
  const identity = {
    issuer: setting.issuer,
    subject: setting.subject,
  };
  const projectId = setting.project_id;
  const snapshotId = setting.snapshot_id;

  await client.query("SET LOCAL ROLE tongxingzhe_runtime");
  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const store = new PostgresManagementOriginalRegionReportSnapshotStore(query);

  const result = await store.read(identity, projectId, snapshotId);
  assert.equal(result.status, "completed");
  if (result.status === "completed") {
    assert.equal(result.requestedSnapshotId, snapshotId);
    assert.equal(result.resolvedSnapshotId, snapshotId);
    assert.equal(
      result.protectedReport.report_id,
      "contact_sessions_by_original_region_two_periods",
    );
    assert.equal(result.protectedReport.project_id, projectId);
    assert.equal(result.protectedReport.dimension, "original_region");
    assert.equal(result.protectedReport.view_mode, "original");
    const sourceTreeContext = result.protectedReport.source_tree_context;
    assert.ok(sourceTreeContext);
    assert.equal(
      (sourceTreeContext as Record<string, unknown>).result_status,
      "selected",
    );
    const cells = result.protectedReport.cells;
    assert.ok(Array.isArray(cells));
    assert.ok(cells.length > 0);
    assert.equal(cells.length % 2, 0);
  }

  const notFound = await store.read(identity, projectId, unknownSnapshotId);
  assert.equal(notFound.status, "not_found");
  if (notFound.status === "not_found") {
    assert.equal(notFound.requestedSnapshotId, unknownSnapshotId);
    assert.equal(notFound.resolvedSnapshotId, null);
  }

  const untrusted = await store.read(
    identity,
    projectId,
    untrustedSnapshotId,
  );
  assert.equal(untrusted.status, "untrusted_provenance");
  if (untrusted.status === "untrusted_provenance") {
    assert.equal(untrusted.requestedSnapshotId, untrustedSnapshotId);
    assert.equal(untrusted.resolvedSnapshotId, untrustedSnapshotId);
  }

  await client.query("SAVEPOINT original_region_runtime_forbidden");
  try {
    await assert.rejects(
      store.read({...identity, subject: "unknown-reader"}, projectId, snapshotId),
      (error: unknown) =>
        error instanceof ManagementOriginalRegionReportSnapshotStoreError &&
        error.code === "forbidden",
    );
  } finally {
    await client.query("ROLLBACK TO SAVEPOINT original_region_runtime_forbidden");
    await client.query("RELEASE SAVEPOINT original_region_runtime_forbidden");
  }

  process.stdout.write(
    "Backend original-region runtime bridge integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
