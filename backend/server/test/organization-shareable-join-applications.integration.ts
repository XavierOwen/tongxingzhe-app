import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {Pool, type PoolClient} from "pg";
import test from "node:test";

import {
  OrganizationShareableJoinApplicationStoreError,
  PostgresOrganizationShareableJoinApplicationStore,
} from "../src/organization-shareable-join-applications.js";

const databaseUrl = required("DATABASE_URL");
const submitFixture = fixture(required(
  "ORGANIZATION_SHAREABLE_JOIN_APPLICATION_SUBMIT_FIXTURE",
));
const approvalFixture = fixture(required(
  "ORGANIZATION_SHAREABLE_JOIN_APPLICATION_APPROVAL_FIXTURE",
));

test("0093 and 0094 runtime bridges submit, approve, replay, forbid, and protect private facts", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(submitFixture);
    await client.query(approvalFixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const store = new PostgresOrganizationShareableJoinApplicationStore(
      async (text, values) => client.query(text, [...values]),
    );

    const submitted = await store.submit(
      {issuer: "https://synthetic-0093.example/auth/v1", subject: "wrong-applicant"},
      "00000000-0093-5000-0000-000000000090",
      "00000000-0093-6000-0000-000000000005",
    );
    assert.deepEqual(await store.submit(
      {issuer: "https://synthetic-0093.example/auth/v1", subject: "wrong-applicant"},
      "00000000-0093-5000-0000-000000000090",
      "00000000-0093-6000-0000-000000000005",
    ), submitted);
    assert.deepEqual(Object.keys(submitted).sort(), [
      "applicationId", "expiresAtUtc", "linkId",
      "organizationShareableJoinApplicationContractId",
      "organizationWorkspaceId", "submittedAtUtc",
    ]);
    assert.equal(Date.parse(submitted.expiresAtUtc) - Date.parse(submitted.submittedAtUtc),
      168 * 60 * 60 * 1000);

    await expectStoreError(client, () => store.submit(
      {issuer: "https://synthetic-0093.example/auth/v1", subject: "wrong-applicant"},
      "00000000-0093-5000-0000-000000000090",
      "00000000-0093-6000-0000-000000000001",
    ), "organization_shareable_join_conflict");

    const approved = await store.approve(
      {issuer: "https://synthetic-0094.example/auth/v1", subject: "owner-one"},
      "00000000-0094-5000-0000-000000000008",
      "00000000-0094-2000-0000-000000000002",
    );
    assert.deepEqual(await store.approve(
      {issuer: "https://synthetic-0094.example/auth/v1", subject: "owner-one"},
      "00000000-0094-5000-0000-000000000008",
      "00000000-0094-2000-0000-000000000002",
    ), approved);
    assert.deepEqual(Object.keys(approved).sort(), [
      "applicationId", "approvedAtUtc", "organizationMembershipId",
      "organizationShareableJoinApplicationContractId", "organizationWorkspaceId",
    ]);

    for (const [applicationId, workspaceId] of [
      ["00000000-0094-5000-0000-000000000003", "00000000-0094-2000-0000-000000000002"],
      ["00000000-0094-5000-0000-000000000099", "00000000-0094-2000-0000-000000000002"],
      ["00000000-0094-5000-0000-000000000008", "00000000-0094-2000-0000-000000000001"],
    ] as const) {
      await expectStoreError(client, () => store.approve(
        {issuer: "https://synthetic-0094.example/auth/v1", subject: "ordinary-member"},
        applicationId, workspaceId,
      ), "organization_shareable_join_forbidden");
    }

    await client.query("SAVEPOINT private_acl");
    await assert.rejects(client.query(
      "SELECT count(*) FROM app_private.organization_shareable_join_application_request_claims",
    ), (error: unknown) => property(error, "code") === "42501");
    await client.query("ROLLBACK TO SAVEPOINT private_acl");
    await client.query("RELEASE SAVEPOINT private_acl");
  } finally {
    try { await client.query("ROLLBACK"); } finally { client.release(); await pool.end(); }
  }
});

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required for application integration`);
  return value;
}
function fixture(path: string): string {
  return readFileSync(path, "utf8")
    .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
    .replace(/^BEGIN;\s*/mu, "")
    .replace(/^ROLLBACK;\s*$/mu, "");
}
async function expectStoreError(client: PoolClient, operation: () => Promise<unknown>,
  code: "organization_shareable_join_forbidden" | "organization_shareable_join_conflict") {
  await client.query("SAVEPOINT expected_error");
  await assert.rejects(operation, (error: unknown) =>
    error instanceof OrganizationShareableJoinApplicationStoreError && error.code === code);
  await client.query("ROLLBACK TO SAVEPOINT expected_error");
  await client.query("RELEASE SAVEPOINT expected_error");
}
function property(value: unknown, key: string): unknown {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)[key] : undefined;
}
