import assert from "node:assert/strict";
import test from "node:test";

import {
  getSessionContext,
  type SessionContextHttpDependencies,
} from "../src/http-app.js";
import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";
import type { SessionContext } from "../src/session-context.js";

const verifiedIdentity: VerifiedIdentity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "synthetic-subject",
};

const context: SessionContext = {
  appUserId: "11111111-1111-4111-8111-111111111111",
  current: {
    workspace: {
      id: "22222222-2222-4222-8222-222222222222",
      kind: "personal",
      name: "个人空间",
    },
    project: {
      id: "33333333-3333-4333-8333-333333333333",
      name: "我的推广项目",
    },
    questionnaireVersion: {
      id: "44444444-4444-4444-8444-444444444444",
      versionNumber: 1,
    },
  },
  capabilities: ["record_contact"],
};

test("missing bearer token returns 401 without a context lookup", async () => {
  var contextLookups = 0;
  const dependencies = fakeDependencies({
    loadContext: async () => {
      contextLookups += 1;
      return context;
    },
  });

  const result = await getSessionContext(undefined, dependencies);

  assert.equal(result.status, 401);
  assert.deepEqual(result.body, { error: { code: "unauthenticated" } });
  assert.equal(contextLookups, 0);
});

test("verified identity returns internal context without external claims", async () => {
  var verifiedToken: string | undefined;
  var mappedIdentity: VerifiedIdentity | undefined;
  const dependencies = fakeDependencies({
    verify: async (token) => {
      verifiedToken = token;
      return verifiedIdentity;
    },
    loadContext: async (identity) => {
      mappedIdentity = identity;
      return context;
    },
  });

  const result = await getSessionContext(
    "Bearer synthetic-access-token",
    dependencies,
  );

  assert.equal(result.status, 200);
  assert.equal(verifiedToken, "synthetic-access-token");
  assert.deepEqual(mappedIdentity, verifiedIdentity);
  assert.deepEqual(result.body, {
    app_user_id: context.appUserId,
    current_context: {
      workspace: {
        workspace_id: context.current.workspace.id,
        kind: "personal",
        name: "个人空间",
      },
      project: {
        project_id: context.current.project.id,
        name: "我的推广项目",
      },
      questionnaire_version: {
        questionnaire_version_id: context.current.questionnaireVersion.id,
        version_number: 1,
      },
    },
    capabilities: ["record_contact"],
  });
  assert.equal(JSON.stringify(result.body).includes("synthetic-subject"), false);
});

test("invalid access token returns stable unauthenticated result", async () => {
  const dependencies = fakeDependencies({
    verify: async () => {
      throw new IdentityVerificationError();
    },
  });

  const result = await getSessionContext(
    "Bearer invalid-access-token",
    dependencies,
  );

  assert.equal(result.status, 401);
  assert.deepEqual(result.body, { error: { code: "unauthenticated" } });
});

test("database failure returns no partial context", async () => {
  const dependencies = fakeDependencies({
    loadContext: async () => {
      throw new Error("synthetic database failure");
    },
  });

  const result = await getSessionContext(
    "Bearer synthetic-access-token",
    dependencies,
  );

  assert.equal(result.status, 503);
  assert.deepEqual(result.body, { error: { code: "context_unavailable" } });
});

function fakeDependencies(overrides?: {
  readonly verify?: (token: string) => Promise<VerifiedIdentity>;
  readonly loadContext?: (
    identity: VerifiedIdentity,
  ) => Promise<SessionContext>;
}): SessionContextHttpDependencies {
  return {
    identityVerifier: {
      verify: overrides?.verify ?? (async () => verifiedIdentity),
    },
    contextStore: {
      loadOrCreate: overrides?.loadContext ?? (async () => context),
    },
  };
}
