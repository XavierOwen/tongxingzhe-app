import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  personalRelationshipStageChangeSummaryContract,
  PersonalRelationshipStageChangeSummaryStoreError,
  PostgresPersonalRelationshipStageChangeSummaryStore,
  readPersonalRelationshipStageChangeSummary,
  relationshipStageChangeTimeBasis,
  type PersonalRelationshipStageChangeSummary,
  type PersonalRelationshipStageChangeSummaryDependencies,
  type PersonalRelationshipStageChangeSummaryStore,
} from "../src/personal-relationship-stage-change-summary.js";

const identity = {
  issuer: "https://synthetic-stage-change.example.test/auth/v1",
  subject: "stage-change-owner",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const period = {
  fromUtc: "2030-01-01T00:00:00.000Z",
  untilUtc: "2030-02-01T00:00:00.000Z",
};
const summary: PersonalRelationshipStageChangeSummary = {
  contractId: personalRelationshipStageChangeSummaryContract,
  projectId,
  timeBasis: relationshipStageChangeTimeBasis,
  period,
  dataCutoffUtc: "2020-02-02T00:00:00.000Z",
  authorizedAtUtc: "2020-02-02T00:00:00.000Z",
  value: {
    eventCount: 5,
    distinctRelationshipCount: 4,
    upwardCount: 3,
    downwardCount: 2,
  },
};

test("stage-change summary passes only verified identity and canonical period", async () => {
  let received:
    | Parameters<PersonalRelationshipStageChangeSummaryStore["read"]>
    | undefined;
  const result = await readPersonalRelationshipStageChangeSummary(
    request("2030-01-01T00:00:00.1Z", "2030-02-01T00:00:00.123456Z"),
    dependencies({
      read: async (...values) => {
        received = values;
        return {
          ...summary,
          period: {
            fromUtc: "2030-01-01T00:00:00.100Z",
            untilUtc: "2030-02-01T00:00:00.123Z",
          },
        };
      },
    }),
  );

  assert.deepEqual(received, [identity, {
    fromUtc: "2030-01-01T00:00:00.100Z",
    untilUtc: "2030-02-01T00:00:00.123Z",
  }]);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {
    result: {
      contract_id: personalRelationshipStageChangeSummaryContract,
      project_id: projectId,
      time_basis: relationshipStageChangeTimeBasis,
      period: {
        from_utc: "2030-01-01T00:00:00.100Z",
        until_utc: "2030-02-01T00:00:00.123Z",
      },
      data_cutoff_utc: summary.dataCutoffUtc,
      authorized_at_utc: summary.authorizedAtUtc,
      value: {
        event_count: 5,
        distinct_relationship_count: 4,
        upward_count: 3,
        downward_count: 2,
      },
    },
  });
});

test("authentication precedes query validation and store access", async () => {
  let verifies = 0;
  let reads = 0;
  const deps = dependencies({
    read: async () => {
      reads++;
      return summary;
    },
  });

  const missing = await readPersonalRelationshipStageChangeSummary(
    {authorization: undefined, query: new URLSearchParams(), hasBody: true},
    deps,
  );
  const rejected = await readPersonalRelationshipStageChangeSummary(
    {authorization: "Bearer bad", query: new URLSearchParams(), hasBody: true},
    {
      ...deps,
      identityVerifier: {
        verify: async () => {
          verifies++;
          throw new IdentityVerificationError();
        },
      },
    },
  );

  assert.deepEqual(missing, {status: 401, body: {error: {code: "unauthenticated"}}});
  assert.deepEqual(rejected, {status: 401, body: {error: {code: "unauthenticated"}}});
  assert.equal(verifies, 1);
  assert.equal(reads, 0);
});

test("request accepts exactly one ordered UTC half-open period and no body", async () => {
  let reads = 0;
  const deps = dependencies({
    read: async () => {
      reads++;
      return summary;
    },
  });
  const invalid = [
    new URLSearchParams(),
    new URLSearchParams({from_utc: period.fromUtc}),
    new URLSearchParams({...queryObject(), project_id: projectId}),
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

  for (const query of invalid) {
    const result = await readPersonalRelationshipStageChangeSummary(
      {authorization: "Bearer token", query, hasBody: false},
      deps,
    );
    assert.deepEqual(result, {
      status: 400,
      body: {error: {code: "invalid_personal_relationship_stage_change_summary_request"}},
    });
  }
  const body = await readPersonalRelationshipStageChangeSummary(
    {...request(period.fromUtc, period.untilUtc), hasBody: true},
    deps,
  );
  assert.equal(body.status, 400);
  assert.equal(reads, 0);
});

test("handler fails closed for missing, forbidden, and unavailable stores", async () => {
  const missing = await readPersonalRelationshipStageChangeSummary(
    request(period.fromUtc, period.untilUtc),
    dependencies({missingStore: true}),
  );
  const forbidden = await readPersonalRelationshipStageChangeSummary(
    request(period.fromUtc, period.untilUtc),
    dependencies({
      read: async () => {
        throw new PersonalRelationshipStageChangeSummaryStoreError("forbidden");
      },
    }),
  );
  const unavailable = await readPersonalRelationshipStageChangeSummary(
    request(period.fromUtc, period.untilUtc),
    dependencies({read: async () => { throw new Error("private detail"); }}),
  );

  assert.deepEqual(missing, {status: 503, body: {error: {
    code: "personal_relationship_stage_change_summary_unavailable",
  }}});
  assert.deepEqual(forbidden, {status: 403, body: {error: {
    code: "personal_relationship_stage_change_summary_forbidden",
  }}});
  assert.deepEqual(unavailable, {status: 503, body: {error: {
    code: "personal_relationship_stage_change_summary_unavailable",
  }}});
});

test("Postgres store binds issuer, subject, and period only", async () => {
  let sql = "";
  let values: readonly unknown[] = [];
  const store = new PostgresPersonalRelationshipStageChangeSummaryStore(
    async (receivedSql, receivedValues) => {
      sql = receivedSql;
      values = receivedValues;
      return {rows: [{summary: databaseSummary()}]};
    },
  );

  const result = await store.read(identity, period);

  assert.match(sql, /read_personal_relationship_stage_change_summary_v1/);
  assert.doesNotMatch(sql, /workspace_id|project_id|app_user_id/);
  assert.deepEqual(values, [identity.issuer, identity.subject, period.fromUtc, period.untilUtc]);
  assert.deepEqual(result, summary);
});

test("Postgres store rejects malformed or internally inconsistent documents", async (t) => {
  const cases: ReadonlyArray<[string, (value: Record<string, unknown>) => void]> = [
    ["extra root field", (value) => { value.private_detail = "leak"; }],
    ["wrong contract", (value) => { value.contract_id = "other"; }],
    ["wrong project shape", (value) => { value.project_id = "not-a-uuid"; }],
    ["period mismatch", (value) => {
      (value.period as Record<string, unknown>).from_utc = "2030-01-02T00:00:00Z";
    }],
    ["cutoff mismatch", (value) => {
      value.authorized_at_utc = "2030-02-02T00:00:01Z";
    }],
    ["invalid cutoff date", (value) => {
      value.data_cutoff_utc = "2030-02-30T00:00:00Z";
      value.authorized_at_utc = "2030-02-30T00:00:00Z";
    }],
    ["future cutoff", (value) => {
      value.data_cutoff_utc = "2999-01-01T00:00:00Z";
      value.authorized_at_utc = "2999-01-01T00:00:00Z";
    }],
    ["negative count", (value) => {
      (value.value as Record<string, unknown>).upward_count = -1;
    }],
    ["unsafe count", (value) => {
      (value.value as Record<string, unknown>).event_count =
        Number.MAX_SAFE_INTEGER + 1;
    }],
    ["direction total mismatch", (value) => {
      (value.value as Record<string, unknown>).event_count = 6;
    }],
    ["distinct exceeds events", (value) => {
      (value.value as Record<string, unknown>).distinct_relationship_count = 6;
    }],
  ];

  for (const [name, mutate] of cases) {
    await t.test(name, async () => {
      const value = databaseSummary();
      mutate(value);
      const store = new PostgresPersonalRelationshipStageChangeSummaryStore(
        async () => ({rows: [{summary: value}]}),
      );
      await assert.rejects(
        () => store.read(identity, period),
        (error: unknown) =>
          error instanceof PersonalRelationshipStageChangeSummaryStoreError &&
          error.code === "invalid",
      );
    });
  }
});

test("Postgres errors map to stable private-free categories", async () => {
  for (const [databaseCode, expected] of [
    ["42501", "forbidden"],
    ["22023", "invalid"],
    ["23514", "invalid"],
  ] as const) {
    const store = new PostgresPersonalRelationshipStageChangeSummaryStore(
      async () => { throw {code: databaseCode, message: "private detail"}; },
    );
    await assert.rejects(
      () => store.read(identity, period),
      (error: unknown) =>
        error instanceof PersonalRelationshipStageChangeSummaryStoreError &&
        error.code === expected &&
        !error.message.includes("private"),
    );
  }
});

function request(fromUtc: string, untilUtc: string) {
  return {
    authorization: "Bearer token",
    query: new URLSearchParams({from_utc: fromUtc, until_utc: untilUtc}),
    hasBody: false,
  };
}

function queryObject(): Record<string, string> {
  return {from_utc: period.fromUtc, until_utc: period.untilUtc};
}

function dependencies(overrides: {
  readonly read?: PersonalRelationshipStageChangeSummaryStore["read"];
  readonly missingStore?: boolean;
} = {}): PersonalRelationshipStageChangeSummaryDependencies {
  return {
    identityVerifier: {verify: async () => identity},
    ...(overrides.missingStore
      ? {}
      : {summaryStore: {read: overrides.read ?? (async () => summary)}}),
  };
}

function databaseSummary(): Record<string, unknown> {
  return {
    contract_id: personalRelationshipStageChangeSummaryContract,
    project_id: projectId,
    time_basis: relationshipStageChangeTimeBasis,
    period: {
      from_utc: "2030-01-01T00:00:00.000000Z",
      until_utc: "2030-02-01T00:00:00.000000Z",
    },
    data_cutoff_utc: "2020-02-02T00:00:00.000000Z",
    authorized_at_utc: "2020-02-02T00:00:00.000000Z",
    value: {
      event_count: 5,
      distinct_relationship_count: 4,
      upward_count: 3,
      downward_count: 2,
    },
  };
}
