import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";

import {
  ManagementFollowUpConsentRatioReportSnapshotStoreError,
  PostgresManagementFollowUpConsentRatioReportSnapshotStore,
} from "../src/management-follow-up-consent-ratio-report-snapshots.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error(
    "DATABASE_URL is required for follow-up consent-ratio runtime integration",
  );
}

const fixturePath =
  process.env.FOLLOW_UP_CONSENT_RATIO_RUNTIME_FIXTURE ??
  resolve(
    dirname(fileURLToPath(import.meta.url)),
    "../../../database/fixtures/0077_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql",
  );
const fixture = readFileSync(fixturePath, "utf8")
  // The same fixture is consumed by psql. The integration owns the
  // transaction, so remove psql's meta-command and transaction wrapper.
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://runtime-follow-up-consent.synthetic/auth/v1",
  subject: "active-reader",
};
const projectId = "6b530000-0000-4000-8000-000000000001";
const otherProjectId = "6b530000-0000-4000-8000-000000000002";
const untrustedSnapshotId = "6b5a0000-0000-4000-8000-000000000002";
const unknownSnapshotId = "6b5a0000-0000-4000-8000-000000000099";

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await client.query(fixture);

  const settings = await client.query<{readonly snapshot_id: string | null}>(
    `SELECT current_setting(
       'app.fixture_6bs_baseline_snapshot_id', true
     ) AS snapshot_id`,
  );
  const snapshotId = settings.rows[0]?.snapshot_id;
  assert.ok(snapshotId);

  await client.query("SET LOCAL ROLE tongxingzhe_runtime");
  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const store =
    new PostgresManagementFollowUpConsentRatioReportSnapshotStore(query);

  const completed = await store.read(identity, projectId, snapshotId);
  assert.equal(completed.status, "completed");
  if (completed.status === "completed") {
    assert.equal(completed.requestedSnapshotId, snapshotId);
    assert.equal(completed.resolvedSnapshotId, snapshotId);
    assert.equal(
      completed.protectedReport.report_id,
      "contact_target_follow_up_consent_ratio_two_periods",
    );
    assert.equal(completed.protectedReport.project_id, projectId);
    assert.equal(completed.protectedReport.dimension, "consent_state");
    assert.equal(completed.protectedReport.statistical_unit, "contact_target_link");
    const periodResults = completed.protectedReport.period_results;
    assert.ok(Array.isArray(periodResults));
    assert.equal(periodResults.length, 2);
    assert.doesNotMatch(
      JSON.stringify(completed.protectedReport),
      /contact_id|promotion_target_id|contributor|raw_answer|email|phone/i,
    );
  }

  const notFound = await store.read(identity, projectId, unknownSnapshotId);
  assert.equal(notFound.status, "not_found");
  if (notFound.status === "not_found") {
    assert.equal(notFound.requestedSnapshotId, unknownSnapshotId);
    assert.equal(notFound.resolvedSnapshotId, null);
  }

  const crossProject = await store.read(
    identity,
    otherProjectId,
    snapshotId,
  );
  assert.equal(crossProject.status, "not_found");
  if (crossProject.status === "not_found") {
    assert.equal(crossProject.requestedSnapshotId, snapshotId);
    assert.equal(crossProject.resolvedSnapshotId, null);
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

  await client.query("SAVEPOINT follow_up_consent_ratio_runtime_forbidden");
  try {
    await assert.rejects(
      store.read(
        {...identity, subject: "unknown-reader"},
        projectId,
        snapshotId,
      ),
      (error: unknown) => {
        if (
          !(error instanceof
            ManagementFollowUpConsentRatioReportSnapshotStoreError)
        ) {
          return false;
        }
        return error.code === "forbidden" && !error.message.includes("identity");
      },
    );
  } finally {
    await client.query(
      "ROLLBACK TO SAVEPOINT follow_up_consent_ratio_runtime_forbidden",
    );
    await client.query(
      "RELEASE SAVEPOINT follow_up_consent_ratio_runtime_forbidden",
    );
  }

  process.stdout.write(
    "Backend follow-up consent-ratio runtime bridge integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
