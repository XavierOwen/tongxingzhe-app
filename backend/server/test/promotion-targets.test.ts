import assert from "node:assert/strict";
import test from "node:test";

import {
  createPromotionTarget,
  listAssignedPromotionTargets,
  PostgresPromotionTargetStore,
  type CreatePromotionTargetInput,
  type PromotionTargetProfile,
  type PromotionTargetStore,
} from "../src/promotion-targets.js";
import type {SessionContext} from "../src/session-context.js";

const profile: PromotionTargetProfile = {
  id: "44444444-4444-4444-8444-444444444444",
  type: "person",
  displayName: "王小明",
  phone: "+1 312 555 0100",
  email: null,
  createdAt: "2026-08-06T12:00:00.000Z",
};

test("target operations recheck capabilities before reading PII", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, ["record_contact"]);

  const [listed, created] = await Promise.all([
    listAssignedPromotionTargets("Bearer token", deps),
    createPromotionTarget("Bearer token", validBody(), deps),
  ]);

  for (const result of [listed, created]) {
    assert.deepEqual(result, {
      status: 403,
      body: {error: {code: "capability_forbidden"}},
    });
  }
  assert.equal(store.calls, 0);
});

test("create accepts explicit profile fields and never trusts workspace input", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, [
    "create_target",
    "view_assigned_target_pii",
  ]);

  const created = await createPromotionTarget(
    "Bearer token",
    validBody(),
    deps,
  );
  assert.equal(created.status, 201);
  assert.deepEqual(store.created, {
    type: "person",
    displayName: "王小明",
    phone: "+1 312 555 0100",
    email: null,
    requestId: "create-target-1",
  });

  const forged = await createPromotionTarget(
    "Bearer token",
    {...validBody(), workspace_id: "forged-workspace"},
    deps,
  );
  assert.deepEqual(forged, {
    status: 400,
    body: {error: {code: "invalid_promotion_target"}},
  });
  assert.equal(store.calls, 1);
});

test("create rejects missing, blank, or unexpected profile fields", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, [
    "create_target",
    "view_assigned_target_pii",
  ]);
  const invalidBodies = [
    {},
    {...validBody(), display_name: "   "},
    {...validBody(), phone: ""},
    {...validBody(), target_type: "group"},
  ];

  for (const body of invalidBodies) {
    const result = await createPromotionTarget("Bearer token", body, deps);
    assert.equal(result.status, 400);
  }
  assert.equal(store.calls, 0);
});

test("Postgres adapter passes only the trusted context and request document", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresPromotionTargetStore(async (text, values) => {
    calls.push({text, values});
    return {rows: [{target: {
      target_id: profile.id,
      target_type: profile.type,
      display_name: profile.displayName,
      phone: profile.phone,
      email: profile.email,
      created_at: profile.createdAt,
    }}]};
  });

  const created = await store.create(context([]), {
    type: "person",
    displayName: "王小明",
    phone: profile.phone,
    email: null,
    requestId: "create-target-1",
  });

  assert.deepEqual(created, profile);
  const call = calls.at(0);
  assert.ok(call);
  assert.match(call.text, /create_promotion_target/);
  assert.deepEqual(call.values, [
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    "22222222-2222-4222-8222-222222222222",
    "person",
    "王小明",
    "+1 312 555 0100",
    null,
    "create-target-1",
  ]);
});

function validBody() {
  return {
    target_type: "person",
    display_name: "  王小明  ",
    phone: "  +1 312 555 0100  ",
    email: null,
    request_id: "create-target-1",
  };
}

function dependencies(
  targetStore: PromotionTargetStore,
  capabilities: readonly string[],
) {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => context(capabilities),
    },
    targetStore,
  };
}

function context(capabilities: readonly string[]): SessionContext {
  return {
    appUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    current: {
      workspace: {
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        kind: "personal",
        name: "个人空间",
      },
      project: {
        id: "22222222-2222-4222-8222-222222222222",
        name: "校园推广",
      },
      questionnaireVersion: {
        id: "11111111-1111-4111-8111-111111111111",
        versionNumber: 1,
      },
    },
    capabilities,
  };
}

class MemoryStore implements PromotionTargetStore {
  calls = 0;
  created: CreatePromotionTargetInput | null = null;

  async listAssigned(): Promise<readonly PromotionTargetProfile[]> {
    this.calls += 1;
    return [profile];
  }

  async create(
    _context: SessionContext,
    input: CreatePromotionTargetInput,
  ): Promise<PromotionTargetProfile> {
    this.calls += 1;
    this.created = input;
    return profile;
  }
}
