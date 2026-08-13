import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  personalFollowUpConsentRatioContract,
  personalFollowUpConsentRatioMetric,
  PersonalFollowUpConsentRatioStoreError,
  PostgresPersonalFollowUpConsentRatioStore,
  readPersonalFollowUpConsentRatio,
  type PersonalFollowUpConsentRatioDependencies,
  type PersonalFollowUpConsentRatioPeriod,
  type PersonalFollowUpConsentRatioResult,
  type PersonalFollowUpConsentRatioStore,
} from "../src/personal-follow-up-consent-ratio.js";
import type {SessionContext} from "../src/session-context.js";

const identity = {
  issuer: "https://synthetic-consent-ratio.example.test/auth/v1",
  subject: "consent-ratio-owner",
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

const period = {
  fromUtc: "2030-01-01T00:00:00.000Z",
  untilUtc: "2030-02-01T00:00:00.000Z",
};

const notEnabled: PersonalFollowUpConsentRatioResult = {
  contractId: personalFollowUpConsentRatioContract,
  metricId: personalFollowUpConsentRatioMetric,
  projectId: context.current.project.id,
  status: "not_enabled",
};

const ready: PersonalFollowUpConsentRatioResult = {
  contractId: personalFollowUpConsentRatioContract,
  metricId: personalFollowUpConsentRatioMetric,
  projectId: context.current.project.id,
  status: "ready",
  period,
  value: {
    yesCount: 2,
    noCount: 1,
    numerator: 2,
    unknownCount: 0,
    refusedCount: 1,
    notApplicableCount: 1,
    unansweredCount: 2,
    excludedCount: 0,
    denominator: 3,
    percentageBasisPoints: 6667,
  },
};

test("personal consent ratio uses verified identity and current project", async () => {
  let received:
    | Parameters<PersonalFollowUpConsentRatioStore["read"]>
    | undefined;
  const result = await readPersonalFollowUpConsentRatio(
    request(period.fromUtc, period.untilUtc),
    dependencies({
      read: async (...values) => {
        received = values;
        return ready;
      },
    }),
  );

  assert.deepEqual(received, [identity, context.current.project.id, period]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      result: {
        contract_id: personalFollowUpConsentRatioContract,
        metric_id: personalFollowUpConsentRatioMetric,
        project_id: context.current.project.id,
        status: "ready",
        period: {
          from_utc: period.fromUtc,
          until_utc: period.untilUtc,
        },
        value: {
          yes_count: 2,
          no_count: 1,
          numerator: 2,
          unknown_count: 0,
          refused_count: 1,
          not_applicable_count: 1,
          unanswered_count: 2,
          excluded_count: 0,
          denominator: 3,
          percentage_basis_points: 6667,
        },
      },
    },
  });
});

test("not enabled remains distinct and value-free", async () => {
  const result = await readPersonalFollowUpConsentRatio(
    request(period.fromUtc, period.untilUtc),
    dependencies({read: async () => notEnabled}),
  );

  assert.deepEqual(result, {
    status: 200,
    body: {
      result: {
        contract_id: personalFollowUpConsentRatioContract,
        metric_id: personalFollowUpConsentRatioMetric,
        project_id: context.current.project.id,
        status: "not_enabled",
      },
    },
  });
});

test("authentication precedes request, context, and store access", async () => {
  let verifies = 0;
  let contextLoads = 0;
  let storeReads = 0;
  const base = dependencies({
    loadContext: async () => {
      contextLoads++;
      return context;
    },
    read: async () => {
      storeReads++;
      return ready;
    },
  });

  const missing = await readPersonalFollowUpConsentRatio(
    {authorization: undefined, query: new URLSearchParams(), hasBody: true},
    {
      ...base,
      identityVerifier: {
        verify: async () => {
          verifies++;
          return identity;
        },
      },
    },
  );
  const invalid = await readPersonalFollowUpConsentRatio(
    {authorization: "Bearer bad", query: new URLSearchParams(), hasBody: true},
    {
      ...base,
      identityVerifier: {
        verify: async () => {
          verifies++;
          throw new IdentityVerificationError();
        },
      },
    },
  );

  assert.deepEqual(missing, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.deepEqual(invalid, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(verifies, 1);
  assert.equal(contextLoads, 0);
  assert.equal(storeReads, 0);
});

test("period query is exact, UTC-only, and half-open", async () => {
  let contextLoads = 0;
  let storeReads = 0;
  const deps = dependencies({
    loadContext: async () => {
      contextLoads++;
      return context;
    },
    read: async () => {
      storeReads++;
      return ready;
    },
  });
  const invalidQueries = [
    new URLSearchParams(),
    new URLSearchParams({from_utc: period.fromUtc}),
    new URLSearchParams({
      from_utc: period.fromUtc,
      until_utc: period.untilUtc,
      project_id: context.current.project.id,
    }),
    new URLSearchParams([
      ["from_utc", period.fromUtc],
      ["from_utc", period.fromUtc],
      ["until_utc", period.untilUtc],
    ]),
    new URLSearchParams({
      from_utc: "2030-01-01T00:00:00-06:00",
      until_utc: period.untilUtc,
    }),
    new URLSearchParams({
      from_utc: "2030-02-30T00:00:00Z",
      until_utc: period.untilUtc,
    }),
    new URLSearchParams({
      from_utc: period.untilUtc,
      until_utc: period.fromUtc,
    }),
  ];

  for (const query of invalidQueries) {
    const result = await readPersonalFollowUpConsentRatio(
      {authorization: "Bearer token", query, hasBody: false},
      deps,
    );
    assert.deepEqual(result, {
      status: 400,
      body: {error: {code: "invalid_personal_follow_up_consent_ratio_request"}},
    });
  }
  const body = await readPersonalFollowUpConsentRatio(
    {...request(period.fromUtc, period.untilUtc), hasBody: true},
    deps,
  );
  assert.equal(body.status, 400);
  assert.equal(contextLoads, 0);
  assert.equal(storeReads, 0);
});

test("UTC query accepts fractional seconds and normalizes to milliseconds", async () => {
  let receivedPeriod: PersonalFollowUpConsentRatioPeriod | undefined;
  const result = await readPersonalFollowUpConsentRatio(
    request("2030-01-01T00:00:00.1Z", "2030-02-01T00:00:00.123456Z"),
    dependencies({
      read: async (_identity, _projectId, requestedPeriod) => {
        receivedPeriod = requestedPeriod;
        return {
          ...notEnabled,
        };
      },
    }),
  );

  assert.equal(result.status, 200);
  assert.deepEqual(receivedPeriod, {
    fromUtc: "2030-01-01T00:00:00.100Z",
    untilUtc: "2030-02-01T00:00:00.123Z",
  });
});

test("missing store and stable store failures remain distinct", async () => {
  const missing = await readPersonalFollowUpConsentRatio(
    request(period.fromUtc, period.untilUtc),
    dependencies({missingStore: true}),
  );
  const forbidden = await readPersonalFollowUpConsentRatio(
    request(period.fromUtc, period.untilUtc),
    dependencies({
      read: async () => {
        throw new PersonalFollowUpConsentRatioStoreError("forbidden");
      },
    }),
  );
  const invalid = await readPersonalFollowUpConsentRatio(
    request(period.fromUtc, period.untilUtc),
    dependencies({
      read: async () => {
        throw new PersonalFollowUpConsentRatioStoreError("invalid");
      },
    }),
  );

  assert.deepEqual(missing, {
    status: 503,
    body: {error: {code: "personal_follow_up_consent_ratio_unavailable"}},
  });
  assert.deepEqual(forbidden, {
    status: 403,
    body: {error: {code: "personal_follow_up_consent_ratio_forbidden"}},
  });
  assert.deepEqual(invalid, {
    status: 503,
    body: {error: {code: "personal_follow_up_consent_ratio_unavailable"}},
  });
});

test("Postgres store binds only trusted identity, project, metric, and period", async () => {
  let sql = "";
  let values: readonly unknown[] = [];
  const store = new PostgresPersonalFollowUpConsentRatioStore(
    async (text, parameters) => {
      sql = text;
      values = parameters;
      return {rows: [{ratio_result: databaseReady}]};
    },
  );

  const result = await store.read(identity, context.current.project.id, period);

  assert.match(sql, /read_personal_follow_up_consent_ratio_v1/);
  assert.match(
    sql,
    /\$1::text, \$2::text, \$3::uuid, \$4::text, \$5::timestamptz, \$6::timestamptz/,
  );
  assert.deepEqual(values, [
    identity.issuer,
    identity.subject,
    context.current.project.id,
    personalFollowUpConsentRatioMetric,
    period.fromUtc,
    period.untilUtc,
  ]);
  assert.deepEqual(result, ready);
});

test("Postgres store accepts zero denominator and strict not-enabled result", async () => {
  const store = new PostgresPersonalFollowUpConsentRatioStore(
    async () => ({rows: [{ratio_result: databaseNotEnabled}]}),
  );
  assert.deepEqual(
    await store.read(identity, context.current.project.id, period),
    notEnabled,
  );

  const zeroStore = new PostgresPersonalFollowUpConsentRatioStore(
    async () => ({rows: [{ratio_result: {
      ...databaseReady,
      value: {
        ...databaseReady.value,
        yes_count: 0,
        no_count: 0,
        numerator: 0,
        denominator: 0,
        percentage_basis_points: null,
      },
    }}]}),
  );
  const zero = await zeroStore.read(identity, context.current.project.id, period);
  assert.equal(zero.status, "ready");
  if (zero.status === "ready") {
    assert.equal(zero.value.denominator, 0);
    assert.equal(zero.value.percentageBasisPoints, null);
  }
});

test("Postgres store rejects contract drift and inconsistent values", async () => {
  const invalidResults: unknown[] = [
    {...databaseNotEnabled, value: {}},
    {...databaseReady, project_id: "55555555-5555-4555-8555-555555555555"},
    {...databaseReady, metric_id: "caller_metric@1"},
    {...databaseReady, status: "suppressed"},
    {...databaseReady, period: {...databaseReady.period, until_utc: "2030-03-01T00:00:00Z"}},
    {...databaseReady, value: {...databaseReady.value, numerator: 1}},
    {...databaseReady, value: {...databaseReady.value, denominator: 4}},
    {...databaseReady, value: {...databaseReady.value, percentage_basis_points: 6666}},
    {...databaseReady, value: {...databaseReady.value, unknown_count: 1}},
    {...databaseReady, value: {...databaseReady.value, excluded_count: 1}},
    {...databaseReady, value: {...databaseReady.value, yes_count: Number.MAX_SAFE_INTEGER + 1}},
  ];

  for (const databaseResult of invalidResults) {
    const store = new PostgresPersonalFollowUpConsentRatioStore(
      async () => ({rows: [{ratio_result: databaseResult}]}),
    );
    await assert.rejects(
      () => store.read(identity, context.current.project.id, period),
      (error: unknown) =>
        error instanceof PersonalFollowUpConsentRatioStoreError &&
        error.code === "invalid",
    );
  }
});

test("Postgres authorization errors are mapped without their messages", async () => {
  const forbidden = new PostgresPersonalFollowUpConsentRatioStore(
    async () => {
      throw {code: "42501", message: "private details"};
    },
  );
  const invalid = new PostgresPersonalFollowUpConsentRatioStore(
    async () => {
      throw {code: "22023", message: "private details"};
    },
  );

  await assert.rejects(
    () => forbidden.read(identity, context.current.project.id, period),
    (error: unknown) =>
      error instanceof PersonalFollowUpConsentRatioStoreError &&
      error.code === "forbidden" &&
      !error.message.includes("private"),
  );
  await assert.rejects(
    () => invalid.read(identity, context.current.project.id, period),
    (error: unknown) =>
      error instanceof PersonalFollowUpConsentRatioStoreError &&
      error.code === "invalid" &&
      !error.message.includes("private"),
  );
});

function request(fromUtc: string, untilUtc: string) {
  return {
    authorization: "Bearer token",
    query: new URLSearchParams({from_utc: fromUtc, until_utc: untilUtc}),
    hasBody: false,
  };
}

function dependencies(overrides: {
  readonly read?: PersonalFollowUpConsentRatioStore["read"];
  readonly loadContext?: PersonalFollowUpConsentRatioDependencies["contextStore"]["loadOrCreate"];
  readonly missingStore?: boolean;
} = {}): PersonalFollowUpConsentRatioDependencies {
  return {
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: overrides.loadContext ?? (async () => context),
    },
    ...(overrides.missingStore
      ? {}
      : {ratioStore: {read: overrides.read ?? (async () => ready)}}),
  };
}

const databaseNotEnabled = {
  contract_id: personalFollowUpConsentRatioContract,
  metric_id: personalFollowUpConsentRatioMetric,
  project_id: context.current.project.id,
  status: "not_enabled",
};

const databaseReady = {
  ...databaseNotEnabled,
  status: "ready",
  period: {
    from_utc: "2030-01-01T00:00:00.000000Z",
    until_utc: "2030-02-01T00:00:00.000000Z",
  },
  value: {
    yes_count: 2,
    no_count: 1,
    numerator: 2,
    unknown_count: 0,
    refused_count: 1,
    not_applicable_count: 1,
    unanswered_count: 2,
    excluded_count: 0,
    denominator: 3,
    percentage_basis_points: 6667,
  },
};
