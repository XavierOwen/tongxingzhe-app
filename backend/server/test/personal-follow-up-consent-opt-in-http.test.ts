import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import type {
  PersonalFollowUpConsentOptInConfiguration,
} from "../src/personal-follow-up-consent-opt-in.js";
import {createBackendServer} from "../src/server.js";
import type {SessionContext} from "../src/session-context.js";

const identity = {
  issuer: "https://synthetic-consent-opt-in-http.example.test/auth/v1",
  subject: "consent-opt-in-http-owner",
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
const configuration: PersonalFollowUpConsentOptInConfiguration = {
  configurationContractId:
    "project_follow_up_consent_opt_in_configuration_v1",
  metricId: "follow_up_consent_ratio@1",
  projectId: context.current.project.id,
  versionNumber: 1,
  expectedVersion: 0,
  enabled: true,
  actorAppUserId: context.appUserId,
  requestId: "55555555-5555-4555-8555-555555555555",
  recordedAtUtc: "2030-01-01T00:00:00.000000Z",
};

test("consent opt-in GET returns current state without internal actor id", async () => {
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {loadOrCreate: async () => context},
    personalFollowUpConsentOptInStore: {
      read: async () => ({
        stateContractId: "project_follow_up_consent_opt_in_state_v1",
        metricId: "follow_up_consent_ratio@1",
        projectId: context.current.project.id,
        status: "enabled",
        configuration,
      }),
      configure: async () => configuration,
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(url(address.port), {
    headers: {authorization: "Bearer token"},
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const body = await response.json();
  assert.deepEqual(body, {
    state: {
      state_contract_id: "project_follow_up_consent_opt_in_state_v1",
      metric_id: "follow_up_consent_ratio@1",
      project_id: context.current.project.id,
      status: "enabled",
      configuration: {
        configuration_contract_id:
          "project_follow_up_consent_opt_in_configuration_v1",
        metric_id: "follow_up_consent_ratio@1",
        project_id: context.current.project.id,
        version_number: 1,
        expected_version: 0,
        enabled: true,
        request_id: configuration.requestId,
        recorded_at_utc: configuration.recordedAtUtc,
      },
    },
  });
  assert.doesNotMatch(JSON.stringify(body), /actor|app_user|subject|sql/i);
});

test("consent opt-in PUT binds current project and returns configuration", async () => {
  let received: readonly unknown[] | undefined;
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {loadOrCreate: async () => context},
    personalFollowUpConsentOptInStore: {
      read: async () => { throw new Error("must not read"); },
      configure: async (...values) => {
        received = values;
        return configuration;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(url(address.port), {
    method: "PUT",
    headers: {
      authorization: "Bearer token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      expected_version: 0,
      enabled: true,
      request_id: configuration.requestId,
    }),
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(received, [
    identity,
    context.current.project.id,
    {
      expectedVersion: 0,
      enabled: true,
      requestId: configuration.requestId,
    },
  ]);
  const body = await response.json();
  assert.deepEqual(body, {
    configuration: {
      configuration_contract_id:
        "project_follow_up_consent_opt_in_configuration_v1",
      metric_id: "follow_up_consent_ratio@1",
      project_id: context.current.project.id,
      version_number: 1,
      expected_version: 0,
      enabled: true,
      request_id: configuration.requestId,
      recorded_at_utc: configuration.recordedAtUtc,
    },
  });
});

test("consent opt-in authenticates before reading an invalid PUT body", async () => {
  let contextLoads = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => {
        throw new IdentityVerificationError();
      },
    },
    contextStore: {
      loadOrCreate: async () => {
        contextLoads++;
        return context;
      },
    },
    personalFollowUpConsentOptInStore: {
      read: async () => {
        storeCalls++;
        throw new Error("must not read");
      },
      configure: async () => {
        storeCalls++;
        throw new Error("must not configure");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await rawRequest(address.port, "PUT", "not json", {
    authorization: "Bearer rejected",
    "content-type": "application/json",
  });

  assert.equal(response.status, 401);
  assert.deepEqual(response.body, {error: {code: "unauthenticated"}});
  assert.equal(contextLoads, 0);
  assert.equal(storeCalls, 0);
});

test("consent opt-in rejects malformed JSON after authentication", async () => {
  let contextLoads = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: async () => {
        contextLoads++;
        return context;
      },
    },
    personalFollowUpConsentOptInStore: {
      read: async () => {
        storeCalls++;
        throw new Error("must not read");
      },
      configure: async () => {
        storeCalls++;
        throw new Error("must not configure");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await rawRequest(address.port, "PUT", "not json", {
    authorization: "Bearer token",
    "content-type": "application/json",
  });

  assert.equal(response.status, 400);
  assert.deepEqual(response.body, {error: {code: "invalid_json"}});
  assert.equal(contextLoads, 0);
  assert.equal(storeCalls, 0);
});

test("consent opt-in rejects GET shape and reports a missing store after auth", async () => {
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

  const shaped = await fetch(`${url(address.port)}?project_id=forged`, {
    headers: {authorization: "Bearer token"},
  });
  assert.equal(shaped.status, 400);
  assert.deepEqual(await shaped.json(), {
    error: {code: "invalid_personal_follow_up_consent_opt_in_request"},
  });

  const unavailable = await fetch(url(address.port), {
    headers: {authorization: "Bearer token"},
  });
  assert.equal(unavailable.status, 503);
  assert.deepEqual(await unavailable.json(), {
    error: {code: "personal_follow_up_consent_opt_in_unavailable"},
  });
  assert.equal(contextLoads, 0);
});

function url(port: number): string {
  return `http://127.0.0.1:${port}/v1/personal/follow-up-consent-ratio/opt-in`;
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

function rawRequest(
  port: number,
  method: string,
  body: string,
  headers: Record<string, string>,
): Promise<{status: number; body: unknown}> {
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      {
        host: "127.0.0.1",
        port,
        path: "/v1/personal/follow-up-consent-ratio/opt-in",
        method,
        headers: {...headers, "content-length": Buffer.byteLength(body)},
      },
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
