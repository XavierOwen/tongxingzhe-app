import assert from "node:assert/strict";

import {Pool} from "pg";

import {
  personalFollowUpConsentRatioMetric,
  PostgresPersonalFollowUpConsentRatioStore,
} from "../src/personal-follow-up-consent-ratio.js";
import {PostgresSessionContextStore} from "../src/session-context.js";

const identity = {
  issuer: "https://synthetic-consent-ratio-integration.example.test/auth/v1",
  subject: "consent-ratio-integration-owner",
};
const period = {
  fromUtc: "2030-01-01T00:00:00.000Z",
  untilUtc: "2030-02-01T00:00:00.000Z",
};

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for consent ratio integration");
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
  const ratioStore = new PostgresPersonalFollowUpConsentRatioStore(query);

  const disabled = await ratioStore.read(
    identity,
    context.current.project.id,
    period,
  );
  assert.deepEqual(disabled, {
    contractId: "personal_follow_up_consent_ratio_result_v1",
    metricId: personalFollowUpConsentRatioMetric,
    projectId: context.current.project.id.toLowerCase(),
    status: "not_enabled",
  });

  const configured = await query(
    `SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
       $1::text, $2::text, $3::uuid, $4::text, $5::uuid, $6::integer, $7::boolean
     ) AS configuration`,
    [
      identity.issuer,
      identity.subject,
      context.current.project.id,
      personalFollowUpConsentRatioMetric,
      "e4a30000-0000-4000-8000-000000000001",
      0,
      true,
    ],
  );
  assert.equal(configured.rows.length, 1);

  const enabled = await ratioStore.read(
    identity,
    context.current.project.id,
    period,
  );
  assert.equal(enabled.status, "ready");
  if (enabled.status === "ready") {
    assert.deepEqual(enabled.period, period);
    assert.deepEqual(enabled.value, {
      yesCount: 0,
      noCount: 0,
      numerator: 0,
      unknownCount: 0,
      refusedCount: 0,
      notApplicableCount: 0,
      unansweredCount: 0,
      excludedCount: 0,
      denominator: 0,
      percentageBasisPoints: null,
    });
  }
  process.stdout.write("Backend personal consent ratio bridge integration: passed\n");
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}
