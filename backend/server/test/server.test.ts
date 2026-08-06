import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import test from "node:test";

import { createBackendServer } from "../src/server.js";

test("HTTP context route requires bearer token and disables caching", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({
        issuer: "https://synthetic.supabase.co/auth/v1",
        subject: "synthetic-subject",
      }),
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("context lookup must not run without a token");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/session/context`,
  );

  assert.equal(response.status, 401);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {
    error: { code: "unauthenticated" },
  });
});

test("HTTP context selection returns the selected trusted project", async () => {
  const selectedProjectId = "55555555-5555-4555-8555-555555555555";
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({
        issuer: "https://synthetic.supabase.co/auth/v1",
        subject: "synthetic-subject",
      }),
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("bootstrap must not run while selecting a project");
      },
      selectProject: async (_identity, projectId) => ({
        appUserId: "11111111-1111-4111-8111-111111111111",
        current: {
          workspace: {
            id: "22222222-2222-4222-8222-222222222222",
            kind: "personal",
            name: "个人空间",
          },
          project: {id: projectId, name: "校园推广"},
          questionnaireVersion: {
            id: "66666666-6666-4666-8666-666666666666",
            versionNumber: 1,
          },
        },
        capabilities: ["record_contact"],
      }),
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/session/context/select`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer synthetic-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({project_id: selectedProjectId}),
    },
  );

  assert.equal(response.status, 200);
  const body = await response.json() as {
    current_context: {project: {project_id: string}};
  };
  assert.equal(body.current_context.project.project_id, selectedProjectId);
});

test("HTTP personal project creation returns the new trusted context", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({
        issuer: "https://synthetic.supabase.co/auth/v1",
        subject: "synthetic-subject",
      }),
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("bootstrap must not run while creating a project");
      },
      createPersonalProject: async (_identity, displayName) => ({
        appUserId: "11111111-1111-4111-8111-111111111111",
        current: {
          workspace: {
            id: "22222222-2222-4222-8222-222222222222",
            kind: "personal",
            name: "个人空间",
          },
          project: {
            id: "55555555-5555-4555-8555-555555555555",
            name: displayName,
          },
          questionnaireVersion: {
            id: "66666666-6666-4666-8666-666666666666",
            versionNumber: 1,
          },
        },
        capabilities: ["record_contact"],
      }),
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/session/projects`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer synthetic-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({display_name: "校园推广"}),
    },
  );

  assert.equal(response.status, 201);
  const body = await response.json() as {
    current_context: {project: {name: string}};
  };
  assert.equal(body.current_context.project.name, "校园推广");
});

test("HTTP region resolution returns a trusted canonical match", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({
        issuer: "https://synthetic.supabase.co/auth/v1",
        subject: "synthetic-subject",
      }),
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("context lookup must not run while resolving a region");
      },
    },
    regionResolutionStore: {
      resolve: async () => ({
        regionId: "chicago",
        treeVersion: "synthetic-v1",
        canonicalName: "Chicago",
        regionPath: [
          {
            regionId: "chicago",
            parentRegionId: null,
            canonicalName: "Chicago",
            kind: "city",
            attributes: [],
          },
        ],
      }),
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/regions/resolve`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer synthetic-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({ latitude: 41.88, longitude: -87.63 }),
    },
  );

  assert.equal(response.status, 200);
  const body = await response.json() as {
    location: { smallest_region_id: string };
  };
  assert.equal(body.location.smallest_region_id, "chicago");
});

test("unknown route returns a stable 404", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => {
        throw new Error("identity verification must not run on unknown routes");
      },
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("context lookup must not run on unknown routes");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(`http://127.0.0.1:${address.port}/unknown`);

  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: { code: "not_found" } });
});

test("HTTP sync route parses JSON and returns a stable accepted result", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({
        issuer: "https://synthetic.supabase.co/auth/v1",
        subject: "synthetic-subject",
      }),
    },
    contextStore: {
      loadOrCreate: async () => ({
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
      }),
    },
    commandStore: {
      apply: async () => ({
        result: "accepted",
        serverCursor: "opaque-http-1",
      }),
      pull: async () => ({ changes: [], nextCursor: null }),
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/sync/commands`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer synthetic-token",
        "content-type": "application/json",
      },
      body: JSON.stringify(validCommandBody()),
    },
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    result: "accepted",
    server_cursor: "opaque-http-1",
  });
});

test("HTTP sync changes route forwards its query and returns a batch", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({
        issuer: "https://synthetic.supabase.co/auth/v1",
        subject: "synthetic-subject",
      }),
    },
    contextStore: {
      loadOrCreate: async () => ({
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
      }),
    },
    commandStore: {
      apply: async () => {
        throw new Error("push must not run while pulling");
      },
      pull: async (_context, cursor, limit) => ({
        changes: [],
        nextCursor: cursor === "opaque-before" && limit === 25
          ? "opaque-before"
          : "unexpected",
      }),
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const url = new URL(
    `http://127.0.0.1:${address.port}/v1/sync/changes`,
  );
  url.searchParams.set("workspace_id", "22222222-2222-4222-8222-222222222222");
  url.searchParams.set("project_id", "33333333-3333-4333-8333-333333333333");
  url.searchParams.set("cursor", "opaque-before");
  url.searchParams.set("limit", "25");
  const response = await fetch(url, {
    headers: { authorization: "Bearer synthetic-token" },
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    changes: [],
    next_cursor: "opaque-before",
  });
});

function validCommandBody(): Record<string, unknown> {
  return {
    protocol_version: 1,
    command_id: "command-1",
    device_id: "device-1",
    aggregate_id: "contact-1",
    base_revision: 0,
    type: "contact.submit.v1",
    typed_payload: {
      contact_id: "contact-1",
      workspace_id: "22222222-2222-4222-8222-222222222222",
      project_id: "33333333-3333-4333-8333-333333333333",
      questionnaire_version_id: "44444444-4444-4444-8444-444444444444",
      occurred_at_utc: "2030-01-08T18:00:00.000Z",
      occurred_time_zone: "America/Chicago",
      channel: "video_call",
      channel_detail: null,
      location: {
        kind: "not_applicable",
        place_name: null,
        smallest_region_id: null,
        latitude: null,
        longitude: null,
        accuracy_meters: null,
      },
      reach_count: 2,
      interest_level: 3,
      answers: [],
    },
  };
}
