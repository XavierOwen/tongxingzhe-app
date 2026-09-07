import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import test from "node:test";

import {
  OrganizationDirectoryStoreError,
  PostgresOrganizationDirectoryStore,
} from "../src/organization-directory.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for organization directory integration");
}

const fixturePath = process.env.ORGANIZATION_DIRECTORY_FIXTURE ?? resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../database/fixtures/0089_organization_directory.sql",
);
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const issuer = "https://synthetic-0089.example/auth/v1";
const directoryIdentity = { issuer, subject: "directory-member" };
const emptyDirectoryIdentity = { issuer, subject: "empty-directory-member" };

test("organization directory adapter reads the runtime bridge", async () => {
  const pool = new Pool({ connectionString: databaseUrl });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const store = new PostgresOrganizationDirectoryStore(
      async (text, values) => client.query(text, [...values]),
    );

    assert.deepEqual(await store.list(directoryIdentity), [
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000001",
        organizationName: " 0089 Original 名称  ",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000002",
        organizationName: "0089 Alpha projectless",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000005",
        organizationName: "0089 Boundary start",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000003",
        organizationName: "0089 Same",
      },
      {
        organizationWorkspaceId: "00000000-0089-2000-0000-000000000004",
        organizationName: "0089 Same",
      },
    ]);
    assert.deepEqual(await store.list(emptyDirectoryIdentity), []);

    await client.query("SAVEPOINT forbidden_identity");
    await assertStoreError(
      () => store.list({ issuer, subject: "unknown-member" }),
      "organization_directory_forbidden",
    );
    await client.query("ROLLBACK TO SAVEPOINT forbidden_identity");
    await client.query("RELEASE SAVEPOINT forbidden_identity");

    await client.query("SAVEPOINT invalid_identity");
    await assertStoreError(
      () => store.list({ issuer, subject: " " }),
      "organization_directory_unavailable",
    );
    await client.query("ROLLBACK TO SAVEPOINT invalid_identity");
    await client.query("RELEASE SAVEPOINT invalid_identity");

    process.stdout.write("Backend organization directory runtime integration: passed\n");
  } finally {
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      await pool.end();
    }
  }
});

async function assertStoreError(
  operation: () => Promise<unknown>,
  code:
    | "organization_directory_forbidden"
    | "organization_directory_unavailable",
): Promise<void> {
  await assert.rejects(operation, (error: unknown) => {
    assert.ok(error instanceof OrganizationDirectoryStoreError);
    assert.equal(error.code, code);
    assert.equal(error.message, code);
    return true;
  });
}
