import assert from "node:assert/strict";
import test from "node:test";

import {
  listOrganizationDeletionRecoveryDirectory,
  OrganizationDeletionRecoveryDirectoryStoreError,
  PostgresOrganizationDeletionRecoveryDirectoryStore,
  type OrganizationDeletionRecoveryDirectoryItem,
} from "../src/organization-deletion-recovery-directory.js";
import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";

const identity: VerifiedIdentity = {
  issuer: "https://recovery-directory.synthetic/auth/v1",
  subject: "current-owner",
};
const item: OrganizationDeletionRecoveryDirectoryItem = {
  organizationWorkspaceId: "123e4567-e89b-12d3-a456-426614174001",
  deletionRequestId: "123e4567-e89b-12d3-a456-426614174002",
  displayName: "  Organization name  ",
  observedAtUtc: "2030-01-02T03:04:05.123456Z",
  effectiveAtUtc: "2030-01-01T03:04:05.123456Z",
  purgeAfterUtc: "2030-01-31T03:04:05.123456Z",
  status: "deletion_pending",
};
const wireRow = {
  organization_deletion_recovery_directory_contract_id:
    "organization-deletion-recovery-directory:v1",
  observed_at_utc: item.observedAtUtc,
  organization_workspace_id: item.organizationWorkspaceId,
  deletion_request_id: item.deletionRequestId,
  display_name: item.displayName,
  effective_at_utc: item.effectiveAtUtc,
  purge_after_utc: item.purgeAfterUtc,
  status: item.status,
};

test("module authenticates first, rejects query/body, and returns typed items", async () => {
  let verifyCalls = 0;
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {
      async verify(token: string) {
        verifyCalls += 1;
        if (token === "invalid") throw new IdentityVerificationError("unauthenticated");
        return identity;
      },
    },
    organizationDeletionRecoveryDirectoryStore: {
      async list(receivedIdentity: VerifiedIdentity) {
        storeCalls += 1;
        assert.deepEqual(receivedIdentity, identity);
        return [item];
      },
    },
  };

  assert.deepEqual(
    await listOrganizationDeletionRecoveryDirectory(
      { authorization: undefined, hasQuery: true, hasBody: true },
      dependencies,
    ),
    { status: 401, body: { error: { code: "unauthenticated" } } },
  );
  assert.equal(verifyCalls, 0);
  assert.deepEqual(
    await listOrganizationDeletionRecoveryDirectory(
      { authorization: "Bearer invalid", hasQuery: true, hasBody: true },
      dependencies,
    ),
    { status: 401, body: { error: { code: "unauthenticated" } } },
  );
  assert.equal(storeCalls, 0);
  assert.deepEqual(
    await listOrganizationDeletionRecoveryDirectory(
      { authorization: "Bearer token", hasQuery: true, hasBody: false },
      dependencies,
    ),
    {
      status: 400,
      body: { error: { code: "invalid_organization_deletion_recovery_directory_request" } },
    },
  );
  assert.equal(storeCalls, 0);

  const result = await listOrganizationDeletionRecoveryDirectory(
    { authorization: "Bearer token", hasQuery: false, hasBody: false },
    dependencies,
  );
  assert.deepEqual(result, {
    status: 200,
    body: {
      organization_deletion_recovery_directory_contract_id:
        "organization-deletion-recovery-directory:v1",
      items: [{
        organization_workspace_id: item.organizationWorkspaceId,
        deletion_request_id: item.deletionRequestId,
        display_name: item.displayName,
        observed_at_utc: item.observedAtUtc,
        effective_at_utc: item.effectiveAtUtc,
        purge_after_utc: item.purgeAfterUtc,
        status: "deletion_pending",
      }],
    },
  });
  assert.equal(storeCalls, 1);
});

test("PostgreSQL store uses the trusted external identity and preserves SQL order", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const rows = [
    wireRow,
    {
      ...wireRow,
      organization_workspace_id: "123e4567-e89b-12d3-a456-426614174003",
      deletion_request_id: "123e4567-e89b-12d3-a456-426614174004",
      display_name: "Earlier SQL row",
    },
  ];
  const store = new PostgresOrganizationDeletionRecoveryDirectoryStore(
    async (text, values) => {
      calls.push({ text, values });
      return { rows };
    },
  );

  assert.deepEqual(await store.list(identity), [
    item,
    {
      ...item,
      organizationWorkspaceId: "123e4567-e89b-12d3-a456-426614174003",
      deletionRequestId: "123e4567-e89b-12d3-a456-426614174004",
      displayName: "Earlier SQL row",
    },
  ]);
  assert.equal(calls.length, 1);
  assert.match(
    calls[0]!.text,
    /FROM app_data\.list_organization_deletion_recovery_for_identity_v1\(\$1::text, \$2::text\)/,
  );
  assert.deepEqual(calls[0]!.values, [identity.issuer, identity.subject]);
  assert.match(calls[0]!.text, /to_char\(observed_at_utc AT TIME ZONE 'UTC'/);
  assert.match(calls[0]!.text, /SS\.US"Z"/);

  const emptyStore = new PostgresOrganizationDeletionRecoveryDirectoryStore(
    async () => ({ rows: [] }),
  );
  assert.deepEqual(await emptyStore.list(identity), []);
});

test("PostgreSQL store preserves microseconds when timestamps share a millisecond", async () => {
  const exactWindow = {
    ...wireRow,
    observed_at_utc: "2030-01-31T03:04:05.123000Z",
    effective_at_utc: "2030-01-01T03:04:05.123000Z",
    purge_after_utc: "2030-01-31T03:04:05.123456Z",
  };
  const store = new PostgresOrganizationDeletionRecoveryDirectoryStore(
    async () => ({ rows: [exactWindow] }),
  );

  assert.equal((await store.list(identity))[0]?.purgeAfterUtc,
    "2030-01-31T03:04:05.123456Z");
});

test("PostgreSQL store rejects malformed, inconsistent, or partial rows", async () => {
  const badRows = [
    { ...wireRow, extra: "unexpected" },
    { ...wireRow, organization_deletion_recovery_directory_contract_id: "other" },
    { ...wireRow, organization_workspace_id: "not-a-uuid" },
    { ...wireRow, deletion_request_id: "not-a-uuid" },
    { ...wireRow, observed_at_utc: "2030-02-30T03:04:05Z" },
    { ...wireRow, effective_at_utc: "2030-01-01T03:04:05+00:00" },
    { ...wireRow, purge_after_utc: "2030-01-01T03:04:05.123456Z" },
    { ...wireRow, status: "restored" },
    { ...wireRow, display_name: "  " },
  ];
  for (const row of badRows) {
    const store = new PostgresOrganizationDeletionRecoveryDirectoryStore(
      async () => ({ rows: [wireRow, row] }),
    );
    await assert.rejects(
      store.list(identity),
      (error: unknown) => {
        assert.ok(error instanceof OrganizationDeletionRecoveryDirectoryStoreError);
        assert.equal(error.code, "organization_deletion_recovery_directory_unavailable");
        return true;
      },
    );
  }

  const inconsistentObservation = new PostgresOrganizationDeletionRecoveryDirectoryStore(
    async () => ({
      rows: [
        wireRow,
        { ...wireRow, observed_at_utc: "2030-01-02T03:04:05.123457Z" },
      ],
    }),
  );
  await assert.rejects(
    inconsistentObservation.list(identity),
    (error: unknown) => error instanceof OrganizationDeletionRecoveryDirectoryStoreError &&
      error.code === "organization_deletion_recovery_directory_unavailable",
  );
});

test("PostgreSQL store maps the runtime's unknown or inactive identity denial", async () => {
  const store = new PostgresOrganizationDeletionRecoveryDirectoryStore(
    async () => {
      throw { code: "42501", message: "organization deletion recovery directory forbidden" };
    },
  );
  await assert.rejects(
    store.list(identity),
    (error: unknown) => error instanceof OrganizationDeletionRecoveryDirectoryStoreError &&
      error.code === "organization_deletion_recovery_directory_forbidden",
  );
});
