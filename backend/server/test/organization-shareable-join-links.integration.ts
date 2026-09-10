import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {Pool, type PoolClient} from "pg";
import test from "node:test";

import {
  OrganizationShareableJoinLinkStoreError,
  PostgresOrganizationShareableJoinLinkStore,
  type OrganizationShareableJoinLinkCreateResult,
  type OrganizationShareableJoinLinkPreviewResult,
} from "../src/organization-shareable-join-links.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for shareable join-link integration");
}
const fixturePath = process.env.ORGANIZATION_SHAREABLE_JOIN_LINK_FIXTURE;
if (fixturePath === undefined || fixturePath.trim().length === 0) {
  throw new Error(
    "ORGANIZATION_SHAREABLE_JOIN_LINK_FIXTURE is required for shareable join-link integration",
  );
}
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const issuer = "https://synthetic-0092.example/auth/v1";
const ownerIdentity = {issuer, subject: "main-owner"};
const viewerIdentity = {issuer, subject: "viewer"};
const nonOwnerIdentity = {issuer, subject: "non-owner"};
const workspaceId = "00000000-0092-2000-0000-000000000001";
const otherWorkspaceId = "00000000-0092-2000-0000-000000000002";
const linkId = "00000000-0092-5000-0000-000000000090";
const forbiddenLinkId = "00000000-0092-5000-0000-000000000091";

test("0092 runtime bridges create, replay, preview, errors, and private ACL", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const store = new PostgresOrganizationShareableJoinLinkStore(
      async (text, values) => client.query(text, [...values]),
    );

    const created = await store.create(
      ownerIdentity,
      linkId,
      workspaceId,
    );
    assert.deepEqual(
      await store.create(ownerIdentity, linkId, workspaceId),
      created,
    );
    assertCreateReceipt(created);

    const preview = await store.preview(viewerIdentity, linkId);
    assertPreviewReceipt(preview, created);

    await expectStoreError(client, () => store.create(
      ownerIdentity,
      linkId,
      otherWorkspaceId,
    ), "organization_shareable_join_conflict");
    await expectStoreError(client, () => store.create(
      nonOwnerIdentity,
      forbiddenLinkId,
      workspaceId,
    ), "organization_shareable_join_forbidden");
    await expectStoreError(client, () => store.preview(
      {issuer, subject: "unknown"},
      linkId,
    ), "organization_shareable_join_forbidden");
    await expectStoreError(client, () => store.preview(
      {issuer, subject: " "},
      linkId,
    ), "organization_shareable_join_unavailable");

    await client.query("SAVEPOINT private_acl");
    await assert.rejects(
      client.query(
        "SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims",
      ),
      (error: unknown) => property(error, "code") === "42501",
    );
    await client.query("ROLLBACK TO SAVEPOINT private_acl");
    await client.query("RELEASE SAVEPOINT private_acl");

    process.stdout.write(
      "Backend organization shareable join-link runtime integration: passed\n",
    );
  } finally {
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      await pool.end();
    }
  }
});

function assertCreateReceipt(
  result: OrganizationShareableJoinLinkCreateResult,
): void {
  assert.deepEqual(Object.keys(result).sort(), [
    "expiresAtUtc",
    "issuedAtUtc",
    "linkId",
    "organizationShareableJoinLinkContractId",
    "organizationWorkspaceId",
  ]);
  assert.equal(
    result.organizationShareableJoinLinkContractId,
    "organization-shareable-join-link:v1",
  );
  assert.equal(result.linkId, linkId);
  assert.equal(result.organizationWorkspaceId, workspaceId);
  assertUtc(result.issuedAtUtc);
  assertUtc(result.expiresAtUtc);
  assert.equal(
    Date.parse(result.expiresAtUtc) - Date.parse(result.issuedAtUtc),
    168 * 60 * 60 * 1000,
  );
}

function assertPreviewReceipt(
  result: OrganizationShareableJoinLinkPreviewResult,
  created: OrganizationShareableJoinLinkCreateResult,
): void {
  assert.deepEqual(Object.keys(result).sort(), [
    "expiresAtUtc",
    "linkId",
    "organizationName",
    "organizationShareableJoinLinkPreviewContractId",
  ]);
  assert.deepEqual(result, {
    organizationShareableJoinLinkPreviewContractId:
      "organization-shareable-join-link-preview:v1",
    linkId,
    organizationName: " 0092 Original 组织名称 ",
    expiresAtUtc: created.expiresAtUtc,
  });
  assertUtc(result.expiresAtUtc);
}

function assertUtc(value: string): void {
  assert.match(value, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
}

async function expectStoreError(
  client: PoolClient,
  operation: () => Promise<unknown>,
  code:
    | "organization_shareable_join_unavailable"
    | "organization_shareable_join_forbidden"
    | "organization_shareable_join_conflict",
): Promise<void> {
  const savepoint = `case_${code}`;
  await client.query(`SAVEPOINT ${savepoint}`);
  await assert.rejects(operation, (error: unknown) => {
    assert.ok(error instanceof OrganizationShareableJoinLinkStoreError);
    assert.equal(error.code, code);
    assert.equal(error.message, code);
    return true;
  });
  await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
  await client.query(`RELEASE SAVEPOINT ${savepoint}`);
}

function property(value: unknown, key: string): unknown {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)[key]
    : undefined;
}
