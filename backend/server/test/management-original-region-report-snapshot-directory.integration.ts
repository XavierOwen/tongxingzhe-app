import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";

import {
  ManagementOriginalRegionReportSnapshotDirectoryStoreError,
  PostgresManagementOriginalRegionReportSnapshotDirectoryStore,
} from "../src/management-original-region-report-snapshot-directory.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error(
    "DATABASE_URL is required for original-region directory runtime integration",
  );
}

const fixturePath = process.env.ORIGINAL_REGION_DIRECTORY_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0071_authorized_management_original_region_report_snapshot_directory.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://directory-original.synthetic/auth/v1",
  subject: "active-reader",
};
const projectId = "6b730000-0000-4000-8000-000000000001";
const emptyProjectId = "6b730000-0000-4000-8000-000000000002";

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query(fixture);
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");

  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const store = new PostgresManagementOriginalRegionReportSnapshotDirectoryStore(
    query,
  );
  const assertForbidden = async (subject: string): Promise<void> => {
    await client.query("SAVEPOINT original_region_directory_forbidden");
    try {
      await assert.rejects(
        store.list({...identity, subject}, projectId),
        (error: unknown) =>
          error instanceof ManagementOriginalRegionReportSnapshotDirectoryStoreError &&
          error.code === "forbidden",
      );
    } finally {
      await client.query(
        "ROLLBACK TO SAVEPOINT original_region_directory_forbidden",
      );
      await client.query(
        "RELEASE SAVEPOINT original_region_directory_forbidden",
      );
    }
  };

  const result = await store.list(identity, projectId);
  assert.equal(
    result.accessContractId,
    "authorized_original_region_management_report_snapshot_directory_v1",
  );
  assert.equal(result.projectId, projectId);
  assert.ok(result.accessEventId.length > 0);
  assert.equal(result.snapshots.length, 20);

  for (let index = 0; index < result.snapshots.length; index += 1) {
    const snapshot = result.snapshots[index]!;
    assert.deepEqual(Object.keys(snapshot).sort(), [
      "dataCutoffUtc",
      "releasedAtUtc",
      "reportId",
      "reportVersion",
      "reportingTimeZone",
      "snapshotId",
    ]);
    assert.equal(
      snapshot.reportId,
      "contact_sessions_by_original_region_two_periods",
    );
    assert.equal(snapshot.reportVersion, 1);
    assert.equal(snapshot.reportingTimeZone, "UTC");
    assert.ok(snapshot.releasedAtUtc >= snapshot.dataCutoffUtc);
    if (index > 0) {
      const previous = result.snapshots[index - 1]!;
      assert.ok(
        previous.dataCutoffUtc > snapshot.dataCutoffUtc ||
          (previous.dataCutoffUtc === snapshot.dataCutoffUtc &&
            previous.releasedAtUtc > snapshot.releasedAtUtc) ||
          (previous.dataCutoffUtc === snapshot.dataCutoffUtc &&
            previous.releasedAtUtc === snapshot.releasedAtUtc &&
            previous.snapshotId > snapshot.snapshotId),
      );
    }
  }

  const empty = await store.list(identity, emptyProjectId);
  assert.equal(empty.projectId, emptyProjectId);
  assert.deepEqual(empty.snapshots, []);

  await assertForbidden("unknown-reader");
  await assertForbidden("no-capability-reader");

  process.stdout.write(
    "Backend original-region snapshot directory runtime integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
