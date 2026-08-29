import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";
import test from "node:test";

import {PostgresOrganizationCreationStore} from "../src/organization-creation.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for organization creation integration");
}

const fixturePath = process.env.ORGANIZATION_CREATION_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0084_organization_creation.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const identity = {
  issuer: "https://synthetic-0084.example/auth/v1",
  subject: "owner-exact",
  purpose: "organization_creation" as const,
};
const requestId = "00000000-0084-2100-0000-000000000001";

test("organization creation adapter returns one exact row and replays it", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");

    const query = async (text: string, values: readonly unknown[]) =>
      client.query(text, [...values]);
    const store = new PostgresOrganizationCreationStore(query);

    const first = await store.create(
      identity,
      requestId,
      "Adapter integration organization",
    );
    const replay = await store.create(
      identity,
      requestId,
      "Adapter integration organization",
    );

    assert.deepEqual(replay, first);
    assert.deepEqual(Object.keys(first).sort(), [
      "createdAtUtc",
      "creationContractId",
      "organizationMembershipId",
      "organizationOwnerAssignmentId",
      "organizationWorkspaceId",
    ]);
    assert.equal(first.creationContractId, "organization-creation:v1");
    assert.match(first.createdAtUtc, /^\d{4}-\d{2}-\d{2}T.*Z$/);
  } finally {
    await client.query("ROLLBACK");
    client.release();
    await pool.end();
  }
});
