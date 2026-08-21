import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";

import {
  ManagementInterestReportSnapshotDirectoryStoreError,
  PostgresManagementInterestReportSnapshotDirectoryStore,
} from "../src/management-interest-report-snapshot-directory.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error(
    "DATABASE_URL is required for interest directory runtime integration",
  );
}

const fixturePath = process.env.INTEREST_DIRECTORY_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0065_authorized_management_interest_report_snapshot_directory.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://directory-interest.synthetic/auth/v1",
  subject: "active-reader",
};
const projectId = "6b130000-0000-4000-8000-000000000001";

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query(fixture);
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");

  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const store = new PostgresManagementInterestReportSnapshotDirectoryStore(
    query,
  );

  const result = await store.list(identity, projectId);
  assert.equal(
    result.accessContractId,
    "authorized_interest_management_report_snapshot_directory_v1",
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
      "contact_sessions_by_interest_level_two_periods",
    );
    assert.equal(snapshot.reportVersion, 1);
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

  await assert.rejects(
    store.list({...identity, subject: "unknown-reader"}, projectId),
    (error: unknown) =>
      error instanceof ManagementInterestReportSnapshotDirectoryStoreError &&
      error.code === "forbidden",
  );

  process.stdout.write(
    "Backend interest snapshot directory runtime integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
