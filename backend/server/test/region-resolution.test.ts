import assert from "node:assert/strict";
import test from "node:test";

import { IdentityVerificationError } from "../src/identity.js";
import {
  PostgresRegionResolutionStore,
  resolveContactRegion,
} from "../src/region-resolution.js";

test("region resolver returns the matched node and installable parent path", async () => {
  const result = await resolveContactRegion(
    "Bearer synthetic-token",
    { latitude: 41.7897, longitude: -87.5997 },
    {
      identityVerifier: {
        verify: async () => ({ issuer: "issuer", subject: "subject" }),
      },
      regionResolutionStore: {
        resolve: async () => ({
          regionId: "uchicago",
          treeVersion: "synthetic-v1",
          canonicalName: "University of Chicago",
          regionPath: [
            {
              regionId: "chicago",
              parentRegionId: null,
              canonicalName: "Chicago",
              kind: "city",
              attributes: [],
            },
            {
              regionId: "uchicago",
              parentRegionId: "chicago",
              canonicalName: "University of Chicago",
              kind: "institution",
              attributes: ["campus"],
            },
          ],
        }),
      },
    },
  );

  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {
    result: "resolved",
    location: {
      kind: "resolved",
      place_name: "University of Chicago",
      smallest_region_id: "uchicago",
      region_tree_version: "synthetic-v1",
    },
    region_tree: {
      version: "synthetic-v1",
      nodes: [
        {
          region_id: "chicago",
          parent_region_id: null,
          canonical_name: "Chicago",
          kind: "city",
          attributes: [],
        },
        {
          region_id: "uchicago",
          parent_region_id: "chicago",
          canonical_name: "University of Chicago",
          kind: "institution",
          attributes: ["campus"],
        },
      ],
    },
  });
});

test("region resolver preserves pending state when no boundary matches", async () => {
  const result = await resolveContactRegion(
    "Bearer synthetic-token",
    { latitude: 0, longitude: 0 },
    {
      identityVerifier: {
        verify: async () => ({ issuer: "issuer", subject: "subject" }),
      },
      regionResolutionStore: { resolve: async () => null },
    },
  );

  assert.equal(result.status, 202);
  assert.deepEqual(result.body, { result: "pending" });
});

test("region resolver rejects invalid coordinates before store access", async () => {
  let storeCalled = false;
  const result = await resolveContactRegion(
    "Bearer synthetic-token",
    { latitude: 91, longitude: 0 },
    {
      identityVerifier: {
        verify: async () => ({ issuer: "issuer", subject: "subject" }),
      },
      regionResolutionStore: {
        resolve: async () => {
          storeCalled = true;
          return null;
        },
      },
    },
  );

  assert.equal(result.status, 400);
  assert.equal(storeCalled, false);
});

test("region resolver maps identity rejection without reading boundaries", async () => {
  let storeCalled = false;
  const result = await resolveContactRegion(
    "Bearer expired-token",
    { latitude: 41.7897, longitude: -87.5997 },
    {
      identityVerifier: {
        verify: async () => {
          throw new IdentityVerificationError({ cause: "expired" });
        },
      },
      regionResolutionStore: {
        resolve: async () => {
          storeCalled = true;
          return null;
        },
      },
    },
  );

  assert.equal(result.status, 401);
  assert.equal(storeCalled, false);
});

test("PostgreSQL adapter uses the bounded resolver function", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const store = new PostgresRegionResolutionStore(async (text, values) => {
    calls.push({ text, values });
    return {
      rows: [
        {
          region_id: "chicago",
          tree_version: "synthetic-v1",
          canonical_name: "Chicago",
          region_path: [
            {
              regionId: "chicago",
              parentRegionId: null,
              canonicalName: "Chicago",
              kind: "city",
              attributes: [],
            },
          ],
        },
      ],
    };
  });

  const resolved = await store.resolve(41.88, -87.63);

  assert.equal(resolved?.regionId, "chicago");
  assert.deepEqual(calls[0]?.values, [41.88, -87.63]);
  assert.match(calls[0]?.text ?? "", /resolve_canonical_region/);
});
