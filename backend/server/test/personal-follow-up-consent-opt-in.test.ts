import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  handlePersonalFollowUpConsentOptIn,
  personalFollowUpConsentOptInMetric,
  PersonalFollowUpConsentOptInStoreError,
  PostgresPersonalFollowUpConsentOptInStore,
  type PersonalFollowUpConsentOptInConfiguration,
  type PersonalFollowUpConsentOptInInput,
  type PersonalFollowUpConsentOptInState,
} from "../src/personal-follow-up-consent-opt-in.js";
import type {SessionContext} from "../src/session-context.js";

const identity = {
  issuer: "https://synthetic-consent-opt-in.example.test/auth/v1",
  subject: "consent-opt-in-owner",
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
      name: "校园推广",
    },
    questionnaireVersion: {
      id: "44444444-4444-4444-8444-444444444444",
      versionNumber: 1,
    },
  },
  capabilities: [],
};
const requestId = "55555555-5555-4555-8555-555555555555";
const configuration: PersonalFollowUpConsentOptInConfiguration = {
  configurationContractId:
    "project_follow_up_consent_opt_in_configuration_v1",
  metricId: personalFollowUpConsentOptInMetric,
  projectId: context.current.project.id,
  versionNumber: 1,
  expectedVersion: 0,
  enabled: true,
  actorAppUserId: context.appUserId,
  requestId,
  recordedAtUtc: "2030-01-01T00:00:00.000000Z",
};
const disabledConfiguration: PersonalFollowUpConsentOptInConfiguration = {
  ...configuration,
  versionNumber: 2,
  expectedVersion: 1,
  enabled: false,
  requestId: "66666666-6666-4666-8666-666666666666",
};
const enabledState: PersonalFollowUpConsentOptInState = {
  stateContractId: "project_follow_up_consent_opt_in_state_v1",
  metricId: personalFollowUpConsentOptInMetric,
  projectId: context.current.project.id,
  status: "enabled",
  configuration,
};
const notEnabledState: PersonalFollowUpConsentOptInState = {
  stateContractId: "project_follow_up_consent_opt_in_state_v1",
  metricId: personalFollowUpConsentOptInMetric,
  projectId: context.current.project.id,
  status: "not_enabled",
  configuration: null,
};

test("GET and PUT serialize exact contracts without leaking the actor", async () => {
  const events: string[] = [];
  const result = await handlePersonalFollowUpConsentOptIn(
    request("GET"),
    dependencies({
      verify: async () => {
        events.push("identity");
        return identity;
      },
      loadContext: async () => {
        events.push("context");
        return context;
      },
      read: async (...values) => {
        events.push("read");
        assert.deepEqual(values, [identity, context.current.project.id]);
        return enabledState;
      },
    }),
  );

  assert.deepEqual(events, ["identity", "context", "read"]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      state: {
        state_contract_id: "project_follow_up_consent_opt_in_state_v1",
        metric_id: personalFollowUpConsentOptInMetric,
        project_id: context.current.project.id,
        status: "enabled",
        configuration: {
          configuration_contract_id:
            "project_follow_up_consent_opt_in_configuration_v1",
          metric_id: personalFollowUpConsentOptInMetric,
          project_id: context.current.project.id,
          version_number: 1,
          expected_version: 0,
          enabled: true,
          request_id: requestId,
          recorded_at_utc: configuration.recordedAtUtc,
        },
      },
    },
  });
  assert.doesNotMatch(JSON.stringify(result), /actor|app_user|subject|sql/i);

  events.length = 0;
  let receivedInput: PersonalFollowUpConsentOptInInput | undefined;
  const putResult = await handlePersonalFollowUpConsentOptIn(
    request("PUT", {
      readBody: async () => {
        events.push("body");
        return {
          expected_version: 0,
          enabled: true,
          request_id: requestId,
        };
      },
    }),
    dependencies({
      verify: async () => {
        events.push("identity");
        return identity;
      },
      loadContext: async () => {
        events.push("context");
        return context;
      },
      configure: async (...values) => {
        events.push("configure");
        assert.equal(values[0], identity);
        assert.equal(values[1], context.current.project.id);
        receivedInput = values[2];
        return configuration;
      },
    }),
  );

  assert.deepEqual(events, ["identity", "body", "context", "configure"]);
  assert.deepEqual(receivedInput, {
    expectedVersion: 0,
    enabled: true,
    requestId,
  });
  assert.deepEqual(putResult, {
    status: 200,
    body: {
      configuration: {
        configuration_contract_id:
          "project_follow_up_consent_opt_in_configuration_v1",
        metric_id: personalFollowUpConsentOptInMetric,
        project_id: context.current.project.id,
        version_number: 1,
        expected_version: 0,
        enabled: true,
        request_id: requestId,
        recorded_at_utc: configuration.recordedAtUtc,
      },
    },
  });
  assert.doesNotMatch(JSON.stringify(putResult), /actor|app_user|subject|sql/i);
});

test("authentication precedes route, body, context, and store access", async () => {
  let verifyCalls = 0;
  let bodyCalls = 0;
  let contextCalls = 0;
  let storeCalls = 0;
  const deps = dependencies({
    verify: async () => {
      verifyCalls++;
      throw new IdentityVerificationError();
    },
    loadContext: async () => {
      contextCalls++;
      return context;
    },
    read: async () => {
      storeCalls++;
      return enabledState;
    },
    configure: async () => {
      storeCalls++;
      return configuration;
    },
  });

  const invalidToken = await handlePersonalFollowUpConsentOptIn(
    request("PUT", {
      hasQuery: true,
      readBody: async () => {
        bodyCalls++;
        return "not-json";
      },
    }),
    deps,
  );
  assert.deepEqual(invalidToken, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(verifyCalls, 1);
  assert.equal(bodyCalls, 0);
  assert.equal(contextCalls, 0);
  assert.equal(storeCalls, 0);

  const missingToken = await handlePersonalFollowUpConsentOptIn(
    request("GET", {authorization: undefined}),
    deps,
  );
  assert.deepEqual(missingToken, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(verifyCalls, 1);
  assert.equal(bodyCalls, 0);
  assert.equal(contextCalls, 0);
  assert.equal(storeCalls, 0);
});

test("GET and PUT reject route shape before context or store access", async () => {
  let contextCalls = 0;
  let storeCalls = 0;
  let bodyCalls = 0;
  const deps = dependencies({
    loadContext: async () => {
      contextCalls++;
      return context;
    },
    read: async () => {
      storeCalls++;
      return enabledState;
    },
    configure: async () => {
      storeCalls++;
      return configuration;
    },
  });

  for (const malformed of [
    request("GET", {hasQuery: true}),
    request("GET", {hasBody: true}),
    request("PUT", {hasQuery: true}),
    request("PUT", {hasBody: false}),
  ]) {
    const result = await handlePersonalFollowUpConsentOptIn(malformed, deps);
    assert.deepEqual(result, {
      status: 400,
      body: {error: {code: "invalid_personal_follow_up_consent_opt_in_request"}},
    });
  }
  assert.equal(bodyCalls, 0);
  assert.equal(contextCalls, 0);
  assert.equal(storeCalls, 0);
});

test("PUT accepts only the exact bounded payload and never client scope", async () => {
  let contextCalls = 0;
  let storeCalls = 0;
  let bodyCalls = 0;
  const deps = dependencies({
    loadContext: async () => {
      contextCalls++;
      return context;
    },
    configure: async () => {
      storeCalls++;
      return configuration;
    },
  });
  const invalidBodies: readonly unknown[] = [
    null,
    [],
    {},
    {expected_version: 0, enabled: true},
    {expected_version: 0, enabled: true, request_id: requestId, extra: true},
    {expected_version: -1, enabled: true, request_id: requestId},
    {expected_version: 2147483648, enabled: true, request_id: requestId},
    {expected_version: Number.MAX_SAFE_INTEGER, enabled: true, request_id: requestId},
    {expected_version: 0.5, enabled: true, request_id: requestId},
    {expected_version: 0, enabled: "true", request_id: requestId},
    {expected_version: 0, enabled: true, request_id: "not-a-uuid"},
    {
      expected_version: 0,
      enabled: true,
      request_id: requestId,
      app_user_id: context.appUserId,
    },
    {
      expected_version: 0,
      enabled: true,
      request_id: requestId,
      project_id: context.current.project.id,
    },
    {
      expected_version: 0,
      enabled: true,
      request_id: requestId,
      metric_id: personalFollowUpConsentOptInMetric,
    },
    {
      expected_version: 0,
      enabled: true,
      request_id: requestId,
      actor_app_user_id: context.appUserId,
    },
    {
      expected_version: 0,
      enabled: true,
      request_id: requestId,
      capability: "manage_analysis_definitions",
    },
    {
      expected_version: 0,
      enabled: true,
      request_id: requestId,
      sql: "select 1",
    },
  ];

  for (const body of invalidBodies) {
    const result = await handlePersonalFollowUpConsentOptIn(
      request("PUT", {
        readBody: async () => {
          bodyCalls++;
          return body;
        },
      }),
      deps,
    );
    assert.deepEqual(result, {
      status: 400,
      body: {error: {code: "invalid_personal_follow_up_consent_opt_in_request"}},
    });
  }
  assert.equal(bodyCalls, invalidBodies.length);
  assert.equal(contextCalls, 0);
  assert.equal(storeCalls, 0);
});

test("missing store and typed failures stay value-free and stable", async () => {
  let contextCalls = 0;
  const missing = await handlePersonalFollowUpConsentOptIn(
    request("GET"),
    dependencies({
      store: undefined,
      loadContext: async () => {
        contextCalls++;
        return context;
      },
    }),
  );
  assert.deepEqual(missing, {
    status: 503,
    body: {error: {code: "personal_follow_up_consent_opt_in_unavailable"}},
  });
  assert.equal(contextCalls, 0);

  for (const value of [
    {
      error: new PersonalFollowUpConsentOptInStoreError("forbidden"),
      status: 403,
      code: "personal_follow_up_consent_opt_in_forbidden",
    },
    {
      error: new PersonalFollowUpConsentOptInStoreError("conflict"),
      status: 409,
      code: "personal_follow_up_consent_opt_in_conflict",
    },
    {
      error: new PersonalFollowUpConsentOptInStoreError("invalid"),
      status: 503,
      code: "personal_follow_up_consent_opt_in_unavailable",
    },
    {
      error: new Error("secret PostgreSQL actor_app_user_id detail"),
      status: 503,
      code: "personal_follow_up_consent_opt_in_unavailable",
    },
  ] as const) {
    const result = await handlePersonalFollowUpConsentOptIn(
      request("GET"),
      dependencies({
        read: async () => {throw value.error;},
      }),
    );
    assert.deepEqual(result, {
      status: value.status,
      body: {error: {code: value.code}},
    });
    assert.doesNotMatch(JSON.stringify(result), /secret|PostgreSQL|actor_app_user_id/);
  }
});

test("known inactive context is forbidden without exposing database detail", async () => {
  for (const message of [
    "mapped app user is not active",
    "trusted identity is not mapped to an active app user",
  ]) {
    const contextError = Object.assign(new Error(message), {code: "42501"});
    const result = await handlePersonalFollowUpConsentOptIn(
      request("GET"),
      dependencies({
        loadContext: async () => {throw contextError;},
      }),
    );

    assert.deepEqual(result, {
      status: 403,
      body: {error: {code: "personal_follow_up_consent_opt_in_forbidden"}},
    });
    assert.doesNotMatch(JSON.stringify(result), /active app user|42501/);
  }
});

test("handler rejects a store actor outside the trusted context", async () => {
  const result = await handlePersonalFollowUpConsentOptIn(
    request("GET"),
    dependencies({
      read: async () => ({
        ...enabledState,
        configuration: {
          ...configuration,
          actorAppUserId: "77777777-7777-4777-8777-777777777777",
        },
      }),
    }),
  );

  assert.deepEqual(result, {
    status: 503,
    body: {error: {code: "personal_follow_up_consent_opt_in_unavailable"}},
  });
});

test("GET preserves unconfigured and disabled not_enabled states", async () => {
  const unconfigured = await handlePersonalFollowUpConsentOptIn(
    request("GET"),
    dependencies({read: async () => notEnabledState}),
  );
  assert.deepEqual(unconfigured, {
    status: 200,
    body: {
      state: {
        state_contract_id: "project_follow_up_consent_opt_in_state_v1",
        metric_id: personalFollowUpConsentOptInMetric,
        project_id: context.current.project.id,
        status: "not_enabled",
        configuration: null,
      },
    },
  });

  const disabled = await handlePersonalFollowUpConsentOptIn(
    request("GET"),
    dependencies({
      read: async () => ({
        ...notEnabledState,
        configuration: disabledConfiguration,
      }),
    }),
  );
  assert.deepEqual(disabled, {
    status: 200,
    body: {
      state: {
        state_contract_id: "project_follow_up_consent_opt_in_state_v1",
        metric_id: personalFollowUpConsentOptInMetric,
        project_id: context.current.project.id,
        status: "not_enabled",
        configuration: {
          configuration_contract_id:
            "project_follow_up_consent_opt_in_configuration_v1",
          metric_id: personalFollowUpConsentOptInMetric,
          project_id: context.current.project.id,
          version_number: 2,
          expected_version: 1,
          enabled: false,
          request_id: disabledConfiguration.requestId,
          recorded_at_utc: disabledConfiguration.recordedAtUtc,
        },
      },
    },
  });
});

test("Postgres store binds verified identity, current project, and fixed metric", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresPersonalFollowUpConsentOptInStore(
    async (text, values) => {
      calls.push({text, values});
      return {
        rows: [{opt_in_state: databaseState("enabled", databaseConfiguration)}],
      };
    },
  );

  const state = await store.read(identity, context.current.project.id);
  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.read_project_follow_up_consent_opt_in_v1/,
  );
  assert.match(
    calls[0]?.text ?? "",
    /\$1::text,\s*\$2::text,\s*\$3::uuid,\s*\$4::text/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    context.current.project.id,
    personalFollowUpConsentOptInMetric,
  ]);
  assert.deepEqual(state, enabledState);
});

test("Postgres configure binds exact input and fixed metric", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresPersonalFollowUpConsentOptInStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{opt_in_configuration: databaseConfiguration}]};
    },
  );
  const input: PersonalFollowUpConsentOptInInput = {
    expectedVersion: 0,
    enabled: true,
    requestId,
  };

  const result = await store.configure(
    identity,
    context.current.project.id,
    input,
  );
  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.configure_project_follow_up_consent_opt_in_v1/,
  );
  assert.match(
    calls[0]?.text ?? "",
    /\$1::text,\s*\$2::text,\s*\$3::uuid,\s*\$4::text,\s*\$5::uuid,\s*\$6::integer,\s*\$7::boolean/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    context.current.project.id,
    personalFollowUpConsentOptInMetric,
    requestId,
    0,
    true,
  ]);
  assert.deepEqual(result, configuration);
});

test("Postgres parsers require exact state and configuration contracts", async () => {
  const validState = databaseState("enabled", databaseConfiguration);
  const invalidStates: readonly unknown[] = [
    {...validState, extra: true},
    {...validState, state_contract_id: "other_v1"},
    {...validState, metric_id: "caller_metric@1"},
    {...validState, project_id: "44444444-4444-4444-8444-444444444444"},
    {...validState, status: "unknown"},
    {...validState, status: "enabled", configuration: null},
    {...validState, status: "not_enabled", configuration: databaseConfiguration},
    {...validState, configuration: {...databaseConfiguration, extra: true}},
    {...validState, configuration: {...databaseConfiguration, configuration_contract_id: "other_v1"}},
    {...validState, configuration: {...databaseConfiguration, metric_id: "caller_metric@1"}},
    {...validState, configuration: {...databaseConfiguration, project_id: "44444444-4444-4444-8444-444444444444"}},
    {...validState, configuration: {...databaseConfiguration, version_number: 0}},
    {...validState, configuration: {...databaseConfiguration, version_number: 1.5}},
    {...validState, configuration: {...databaseConfiguration, expected_version: -1}},
    {...validState, configuration: {...databaseConfiguration, expected_version: 1}},
    {...validState, configuration: {...databaseConfiguration, enabled: "true"}},
    {...validState, configuration: {...databaseConfiguration, actor_app_user_id: "not-a-uuid"}},
    {...validState, configuration: {...databaseConfiguration, request_id: "not-a-uuid"}},
    {...validState, configuration: {...databaseConfiguration, recorded_at_utc: "not-a-time"}},
    {...validState, configuration: {...databaseConfiguration, recorded_at_utc: "2030-01-01T00:00:00+00:00"}},
    {...validState, configuration: {...databaseConfiguration, recorded_at_utc: "2030-02-30T00:00:00.000000Z"}},
  ];

  for (const [index, value] of invalidStates.entries()) {
    await assert.rejects(
      () => readStoreFor(value).read(identity, context.current.project.id),
      (error: unknown) =>
        error instanceof PersonalFollowUpConsentOptInStoreError &&
        error.code === "invalid",
      `invalid state fixture ${index}`,
    );
  }

  const invalidConfigurations: readonly unknown[] = [
    {...databaseConfiguration, extra: true},
    {...databaseConfiguration, configuration_contract_id: "other_v1"},
    {...databaseConfiguration, project_id: "44444444-4444-4444-8444-444444444444"},
    {...databaseConfiguration, version_number: 0},
    {...databaseConfiguration, expected_version: -1},
    {...databaseConfiguration, enabled: "true"},
    {...databaseConfiguration, actor_app_user_id: "not-a-uuid"},
    {...databaseConfiguration, request_id: "not-a-uuid"},
    {...databaseConfiguration, recorded_at_utc: "not-a-time"},
  ];
  for (const [index, value] of invalidConfigurations.entries()) {
    await assert.rejects(
      () => configureStoreFor(value).configure(
        identity,
        context.current.project.id,
        {
          expectedVersion: 0,
          enabled: true,
          requestId,
        },
      ),
      (error: unknown) =>
        error instanceof PersonalFollowUpConsentOptInStoreError &&
        error.code === "invalid",
      `invalid configuration fixture ${index}`,
    );
  }
});

test("Postgres store rejects missing or duplicate bridge rows", async () => {
  for (const rows of [
    [],
    [{state: databaseState("enabled", databaseConfiguration)}, {state: databaseState("enabled", databaseConfiguration)}],
  ] as const) {
    await assert.rejects(
      () => new PostgresPersonalFollowUpConsentOptInStore(
        async () => ({rows}),
      ).read(identity, context.current.project.id),
      (error: unknown) =>
        error instanceof PersonalFollowUpConsentOptInStoreError &&
        error.code === "invalid",
    );
  }
});

test("Postgres SQLSTATE mapping is stable and does not expose messages", async () => {
  for (const [sqlState, message, expected] of [
    [
      "42501",
      "project follow-up consent opt-in scope is forbidden",
      "forbidden",
    ],
    [
      "22023",
      "project follow-up consent opt-in idempotency conflict",
      "conflict",
    ],
    [
      "40001",
      "project follow-up consent opt-in version conflict",
      "conflict",
    ],
  ] as const) {
    const databaseError = Object.assign(
      new Error(message),
      {code: sqlState},
    );
    const store = new PostgresPersonalFollowUpConsentOptInStore(
      async () => {throw databaseError;},
    );
    await assert.rejects(
      () => store.configure(identity, context.current.project.id, {
        expectedVersion: 0,
        enabled: true,
        requestId,
      }),
      (error: unknown) =>
        error instanceof PersonalFollowUpConsentOptInStoreError &&
        error.code === expected &&
        !error.message.includes(message),
    );
  }

  for (const sqlState of ["42501", "22023", "40001"] as const) {
    const databaseError = Object.assign(
      new Error("unexpected database failure"),
      {code: sqlState},
    );
    const store = new PostgresPersonalFollowUpConsentOptInStore(
      async () => {throw databaseError;},
    );
    await assert.rejects(
      () => store.configure(identity, context.current.project.id, {
        expectedVersion: 0,
        enabled: true,
        requestId,
      }),
      (error: unknown) => error === databaseError,
    );
  }
});

function request(
  method: "GET" | "PUT",
  overrides: Partial<Parameters<typeof handlePersonalFollowUpConsentOptIn>[0]> = {},
): Parameters<typeof handlePersonalFollowUpConsentOptIn>[0] {
  return {
    method,
    authorization: "Bearer token",
    hasQuery: false,
    hasBody: method === "PUT",
    readBody: async () => undefined,
    ...overrides,
  };
}

type OptInDependencies = Parameters<
  typeof handlePersonalFollowUpConsentOptIn
>[1];
type OptInStore = NonNullable<
  OptInDependencies["optInStore"]
>;

function dependencies(overrides: {
  readonly verify?: OptInDependencies["identityVerifier"]["verify"];
  readonly loadContext?: OptInDependencies["contextStore"]["loadOrCreate"];
  readonly read?: OptInStore["read"];
  readonly configure?: OptInStore["configure"];
  readonly store?: OptInStore | undefined;
} = {}): OptInDependencies {
  const defaultStore: OptInStore = {
    read: overrides.read ?? (async () => enabledState),
    configure: overrides.configure ?? (async () => configuration),
  };
  const baseDependencies: Omit<OptInDependencies, "optInStore"> = {
    identityVerifier: {
      verify: overrides.verify ?? (async () => identity),
    },
    contextStore: {
      loadOrCreate: overrides.loadContext ?? (async () => context),
    },
  };
  const store = Object.prototype.hasOwnProperty.call(overrides, "store")
    ? overrides.store
    : defaultStore;
  if (store === undefined) return baseDependencies;
  return {...baseDependencies, optInStore: store};
}

function readStoreFor(value: unknown): PostgresPersonalFollowUpConsentOptInStore {
  return new PostgresPersonalFollowUpConsentOptInStore(
    async () => ({rows: [{opt_in_state: value}]}),
  );
}

function configureStoreFor(
  value: unknown,
): PostgresPersonalFollowUpConsentOptInStore {
  return new PostgresPersonalFollowUpConsentOptInStore(
    async () => ({rows: [{opt_in_configuration: value}]}),
  );
}

const databaseConfiguration = {
  configuration_contract_id:
    "project_follow_up_consent_opt_in_configuration_v1",
  metric_id: personalFollowUpConsentOptInMetric,
  project_id: context.current.project.id,
  version_number: 1,
  expected_version: 0,
  enabled: true,
  actor_app_user_id: context.appUserId,
  request_id: configuration.requestId,
  recorded_at_utc: "2030-01-01T00:00:00.000000Z",
};

function databaseState(
  status: "enabled" | "not_enabled",
  value: typeof databaseConfiguration | null,
): Readonly<Record<string, unknown>> {
  return {
    state_contract_id: "project_follow_up_consent_opt_in_state_v1",
    metric_id: personalFollowUpConsentOptInMetric,
    project_id: context.current.project.id,
    status,
    configuration: value,
  };
}
