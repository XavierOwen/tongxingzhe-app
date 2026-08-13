import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import type {VerifiedIdentity} from "../src/identity.js";
import type {
  PersonalFollowUpConsentRatioPeriod,
} from "../src/personal-follow-up-consent-ratio.js";
import {createBackendServer} from "../src/server.js";
import type {SessionContext} from "../src/session-context.js";

const identity = {
  issuer: "https://synthetic-consent-http.example.test/auth/v1",
  subject: "consent-http-owner",
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
const fromUtc = "2030-01-01T00:00:00.000Z";
const untilUtc = "2030-02-01T00:00:00.000Z";

test("consent ratio route returns a no-store fixed personal result", async () => {
  let received:
    | [VerifiedIdentity, string, PersonalFollowUpConsentRatioPeriod]
    | undefined;
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {loadOrCreate: async () => context},
    personalFollowUpConsentRatioStore: {
      read: async (...values) => {
        received = values;
        return {
          contractId: "personal_follow_up_consent_ratio_result_v1",
          metricId: "follow_up_consent_ratio@1",
          projectId: context.current.project.id,
          status: "ready",
          period: {fromUtc, untilUtc},
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
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(url(address.port), {
    headers: {authorization: "Bearer token"},
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(received, [
    identity,
    context.current.project.id,
    {fromUtc, untilUtc},
  ]);
  const body = await response.json();
  assert.deepEqual(body, {
    result: {
      contract_id: "personal_follow_up_consent_ratio_result_v1",
      metric_id: "follow_up_consent_ratio@1",
      project_id: context.current.project.id,
      status: "ready",
      period: {from_utc: fromUtc, until_utc: untilUtc},
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
  });
  assert.doesNotMatch(
    JSON.stringify(body),
    /subject|workspace|display_name|phone|email|note|sql/i,
  );
});

test("consent ratio route authenticates before rejecting query shape", async () => {
  let verifies = 0;
  let contextLoads = 0;
  let storeReads = 0;
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => {
        verifies++;
        return identity;
      },
    },
    contextStore: {
      loadOrCreate: async () => {
        contextLoads++;
        return context;
      },
    },
    personalFollowUpConsentRatioStore: {
      read: async () => {
        storeReads++;
        throw new Error("must not run");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  const base = `http://127.0.0.1:${address.port}` +
    "/v1/personal/follow-up-consent-ratio";

  const unauthenticated = await fetch(`${base}?project_id=forged`);
  assert.equal(unauthenticated.status, 401);

  const duplicate = await fetch(
    `${base}?from_utc=${encodeURIComponent(fromUtc)}` +
    `&from_utc=${encodeURIComponent(fromUtc)}` +
    `&until_utc=${encodeURIComponent(untilUtc)}`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(duplicate.status, 400);
  assert.deepEqual(await duplicate.json(), {
    error: {code: "invalid_personal_follow_up_consent_ratio_request"},
  });

  const body = await rawGet(
    address.port,
    "/v1/personal/follow-up-consent-ratio" +
      `?from_utc=${encodeURIComponent(fromUtc)}` +
      `&until_utc=${encodeURIComponent(untilUtc)}`,
    {authorization: "Bearer token", "content-length": "2"},
    "{}",
  );
  assert.equal(body.status, 400);
  assert.equal(verifies, 2);
  assert.equal(contextLoads, 0);
  assert.equal(storeReads, 0);
});

test("consent ratio route reports a missing adapter after authentication", async () => {
  let contextLoads = 0;
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: async () => {
        contextLoads++;
        return context;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(url(address.port), {
    headers: {authorization: "Bearer token"},
  });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    error: {code: "personal_follow_up_consent_ratio_unavailable"},
  });
  assert.equal(contextLoads, 0);
});

function url(port: number): string {
  return `http://127.0.0.1:${port}/v1/personal/follow-up-consent-ratio` +
    `?from_utc=${encodeURIComponent(fromUtc)}` +
    `&until_utc=${encodeURIComponent(untilUtc)}`;
}

async function listen(
  server: ReturnType<typeof createBackendServer>,
): Promise<AddressInfo> {
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return server.address() as AddressInfo;
}

function close(server: ReturnType<typeof createBackendServer>): Promise<void> {
  return new Promise((resolve) => server.close(() => resolve()));
}

function rawGet(
  port: number,
  path: string,
  headers: Record<string, string>,
  body: string,
): Promise<{status: number; body: unknown}> {
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      {host: "127.0.0.1", port, path, method: "GET", headers},
      (response) => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        response.on("end", () => resolve({
          status: response.statusCode ?? 0,
          body: JSON.parse(Buffer.concat(chunks).toString("utf8")),
        }));
      },
    );
    request.on("error", reject);
    request.end(body);
  });
}
