import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";

import {
  ManagementFollowUpConsentRatioSnapshotDirectoryStoreError,
  PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore,
} from "../src/management-follow-up-consent-ratio-snapshot-directory.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error(
    "DATABASE_URL is required for follow-up consent-ratio directory runtime integration",
  );
}

const fixturePath = process.env.FOLLOW_UP_CONSENT_RATIO_DIRECTORY_FIXTURE ??
  resolve(
    dirname(fileURLToPath(import.meta.url)),
    "../../../database/fixtures/0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql",
  );
const fixture = readFileSync(fixturePath, "utf8")
  // The fixture is also consumed by psql. The integration owns the
  // transaction, so remove psql's meta-command and transaction wrapper.
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://runtime-follow-up-consent-directory.synthetic/auth/v1",
  subject: "active-reader",
};
const projectId = "6b930000-0000-4000-8000-000000000001";
const otherProjectId = "6b930000-0000-4000-8000-000000000002";

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query(fixture);
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");

  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const store =
    new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore(query);

  const result = await store.list(identity, projectId);
  assert.equal(
    result.accessContractId,
    "authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1",
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
      "contact_target_follow_up_consent_ratio_two_periods",
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
  assert.doesNotMatch(
    JSON.stringify(result),
    /protected_report|period_results|cells|coverage|yes_count|no_count|numerator|denominator|contributor|target_id|contact_id|external_subject|phone|email|pii/i,
  );

  const repeated = await store.list(identity, projectId);
  assert.notEqual(repeated.accessEventId, result.accessEventId);
  assert.deepEqual(repeated.snapshots, result.snapshots);

  const assertForbidden = async (
    subject: string,
    requestedProjectId = projectId,
    requestedIssuer = identity.issuer,
  ): Promise<void> => {
    await client.query("SAVEPOINT follow_up_consent_directory_forbidden");
    try {
      await assert.rejects(
        store.list(
          {issuer: requestedIssuer, subject},
          requestedProjectId,
        ),
        (error: unknown) =>
          error instanceof
            ManagementFollowUpConsentRatioSnapshotDirectoryStoreError &&
          error.code === "forbidden",
      );
    } finally {
      await client.query(
        "ROLLBACK TO SAVEPOINT follow_up_consent_directory_forbidden",
      );
      await client.query(
        "RELEASE SAVEPOINT follow_up_consent_directory_forbidden",
      );
    }
  };

  await assertForbidden("unknown-reader");
  await assertForbidden("inactive-reader");
  await assertForbidden(" active-reader ");
  await assertForbidden("release-only-reader");
  await assertForbidden("no-capability-reader");
  await assertForbidden("active-reader", otherProjectId);
  await assertForbidden("active-reader", projectId, ` ${identity.issuer} `);

  process.stdout.write(
    "Backend follow-up consent-ratio snapshot directory runtime integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
