import assert from "node:assert/strict";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  PersonalTargetMergeDirectoryStoreError,
  PostgresPersonalTargetMergeDirectoryStore,
  readPersonalTargetMergeDirectory,
} from "../src/personal-target-merge-projection.js";
import {createBackendServer} from "../src/server.js";

const identity = {issuer: " https://directory.synthetic.example.test/auth/v1 ", subject: " owner "};
const projectId = "7ee10000-0000-4000-8000-000000000001";
const workspaceId = "7ee10000-0000-4000-8000-000000000002";
const actorId = "7ee10000-0000-4000-8000-000000000003";
type Document = Record<string, unknown>;
const id = (number: number) => `7ee10000-0000-4000-8000-${String(number).padStart(12, "0")}`;

function context(): Document {
  return {app_user_id: actorId, workspace_id: workspaceId, workspace_kind: "personal", project_id: projectId,
    capabilities: ["view_assigned_target_pii", "manage_assigned_target_merges"]};
}

function directory(count = 2, more = false): Document {
  return {workspace_id: workspaceId, project_id: projectId,
    items: Array.from({length: count}, (_, index) => ({
      generation_id: id(100 + index), target_type: index % 2 === 0 ? "person" : "institution",
      retained_target_id: id(1001 + index * 2), member_target_ids: [id(1000 + index * 2), id(1001 + index * 2)],
      review_due_at_utc: "2020-10-15T12:34:56.123456Z",
    })), next_cursor: more ? id(99 + count) : null};
}

const request = {authorization: "Bearer synthetic", projectId, query: new URLSearchParams(), hasBody: false};
const failure = (status: number, code: string) => ({status, body: {error: {code: `personal_target_merge_directory_${code}`}}});

function storeFor(document: unknown, eligibility: unknown = context()) {
  let calls = 0;
  return {
    store: new PostgresPersonalTargetMergeDirectoryStore(async () => ({rows: [
      ++calls === 1 ? {context_result: eligibility} : {directory: document},
    ]})),
    calls: () => calls,
  };
}

test("merge directory authenticates before validating project, query or dependencies", async () => {
  let verifies = 0;
  let reads = 0;
  const dependencies = {identityVerifier: {verify: async () => {verifies++; return identity;}},
    directoryStore: {read: async () => {reads++; return directory();}}};
  const malformed = {...request, projectId: "bad", query: new URLSearchParams("limit=20"), hasBody: true};
  for (const authorization of [undefined, "Basic private", "Bearer first,second"]) {
    assert.deepEqual(await readPersonalTargetMergeDirectory({...malformed, authorization}, dependencies), failure(401, "unauthenticated"));
  }
  assert.equal(verifies, 0);
  for (const [error, expected] of [
    [new IdentityVerificationError(), failure(401, "unauthenticated")],
    [new IdentityVerificationError("unavailable"), failure(503, "unavailable")],
    [new Error("synthetic private verifier details"), failure(503, "unavailable")],
  ] as const) {
    assert.deepEqual(await readPersonalTargetMergeDirectory(malformed, {
      ...dependencies, identityVerifier: {verify: async () => {throw error;}},
    }), expected);
  }
  assert.equal(reads, 0);
  assert.deepEqual(await readPersonalTargetMergeDirectory(request, {identityVerifier: dependencies.identityVerifier}), failure(503, "unavailable"));
});

test("merge directory accepts only zero or one valid after parameter and retains raw cursor text", async () => {
  const document = directory();
  const received: (string | null)[] = [];
  const dependencies = {identityVerifier: {verify: async () => identity}, directoryStore: {
    read: async (verified: typeof identity, project: string, after: string | null) => {
      assert.strictEqual(verified, identity);
      assert.equal(project, projectId);
      received.push(after);
      return document;
    },
  }};
  for (const after of [null, id(50).toUpperCase()]) {
    const result = await readPersonalTargetMergeDirectory({...request,
      query: new URLSearchParams(after === null ? "" : `after=${after}`)}, dependencies);
    assert.equal(result.status, 200);
    assert.strictEqual(result.body.directory, document);
  }
  assert.deepEqual(received, [null, id(50).toUpperCase()]);
  for (const query of ["after=", "after=bad", `after=${id(50)}&after=${id(50)}`, "limit=20", "workspace=x", "actor=x",
    `after=${id(50)}&debug=1`, `After=${id(50)}`]) {
    assert.deepEqual(await readPersonalTargetMergeDirectory({...request, query: new URLSearchParams(query)}, dependencies), failure(400, "invalid_request"));
  }
  for (const invalid of [{...request, projectId: "bad"}, {...request, hasBody: true}]) {
    assert.deepEqual(await readPersonalTargetMergeDirectory(invalid, dependencies), failure(400, "invalid_request"));
  }
  assert.equal(received.length, 2);
});

test("merge directory store captures raw identity and returns the original page after two fixed queries", async () => {
  for (const after of [null, id(50).toUpperCase()]) {
    const document = directory(20, true);
    const verified = {...identity};
    let calls = 0;
    const store = new PostgresPersonalTargetMergeDirectoryStore(async (sql, values) => {
      calls++;
      if (calls === 1) {
        assert.match(sql, /^SELECT app_data\.read_personal_merge_projection_context_v1\(/);
        assert.deepEqual(values, [identity.issuer, identity.subject, projectId]);
        verified.issuer = "different issuer";
        verified.subject = "different subject";
        return {rows: [{context_result: context()}]};
      }
      assert.match(sql, /^SELECT app_data\.read_personal_merge_directory_v1\(/);
      assert.deepEqual(values, [identity.issuer, identity.subject, projectId, after]);
      return {rows: [{directory: document}]};
    });
    const result = await store.read(verified, projectId, after);
    assert.strictEqual(result, document);
    assert.strictEqual(result.items, document.items);
    assert.equal(calls, 2);
  }
});

test("merge directory allows empty and terminal pages, preserves case and does not apply a client clock", async () => {
  for (const document of [directory(0), directory(1), directory(20), directory(20, true)]) {
    const item = (document.items as Document[])[0];
    if (item !== undefined) {
      item.generation_id = String(item.generation_id).toUpperCase();
      item.retained_target_id = String(item.retained_target_id).toUpperCase();
      item.member_target_ids = (item.member_target_ids as string[]).map((value) => value.toUpperCase());
    }
    document.project_id = projectId.toUpperCase();
    document.workspace_id = workspaceId.toUpperCase();
    if (document.next_cursor !== null) document.next_cursor = String(document.next_cursor).toUpperCase();
    assert.strictEqual(await storeFor(document).store.read(identity, projectId.toUpperCase(), id(50)), document);
  }
});

test("merge directory accepts PostgreSQL canonical UUIDs including nil and maximum cursor boundaries", async () => {
  const nil = "00000000-0000-0000-0000-000000000000";
  const maximum = "ffffffff-ffff-ffff-ffff-ffffffffffff";
  const document = {workspace_id: maximum, project_id: nil, next_cursor: null, items: [{
    generation_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", target_type: "person",
    retained_target_id: maximum, member_target_ids: [nil, maximum], review_due_at_utc: "2020-10-15T12:34:56.123456Z",
  }]};
  const fixture = storeFor(document, {...context(), project_id: nil, workspace_id: maximum, app_user_id: nil});
  assert.strictEqual(await fixture.store.read(identity, nil, nil), document);
  const empty = directory(0);
  assert.strictEqual(await storeFor(empty).store.read(identity, projectId, maximum), empty);
  for (const after of [nil, maximum.toUpperCase()]) {
    assert.equal((await readPersonalTargetMergeDirectory({...request, query: new URLSearchParams(`after=${after}`)}, {
      identityVerifier: {verify: async () => identity}, directoryStore: {read: async (_identity, _project, cursor) => {
        assert.equal(cursor, after);
        return empty;
      }},
    })).status, 200);
  }
});

test("merge directory requires both capabilities before issuing the audited query", async () => {
  for (const capabilities of [[], ["view_assigned_target_pii"], ["manage_assigned_target_merges"]]) {
    const fixture = storeFor(directory(), {...context(), capabilities});
    assert.deepEqual(await readPersonalTargetMergeDirectory(request, {
      identityVerifier: {verify: async () => identity}, directoryStore: fixture.store,
    }), failure(403, "forbidden"));
    assert.equal(fixture.calls(), 1);
  }
  const missing = context();
  delete missing.app_user_id;
  for (const eligibility of [null, missing, {...context(), extra: true}, {...context(), project_id: id(9)},
    {...context(), workspace_kind: "organization"}, {...context(), workspace_id: "bad"}, {...context(), capabilities: [1]}]) {
    const fixture = storeFor(directory(), eligibility);
    await assert.rejects(fixture.store.read(identity, projectId, null), {message: "unavailable"});
    assert.equal(fixture.calls(), 1);
  }
});

test("merge directory fails closed on reauthorization and keeps all dependency errors value-free", async () => {
  for (const phase of [1, 2]) {
    for (const code of ["42501", "55000", "22023", "08006"]) {
      let calls = 0;
      const store = new PostgresPersonalTargetMergeDirectoryStore(async () => {
        if (++calls === phase) throw {code, message: "synthetic SQL/private details"};
        return {rows: [{context_result: context()}]};
      });
      assert.deepEqual(await readPersonalTargetMergeDirectory(request, {
        identityVerifier: {verify: async () => identity}, directoryStore: store,
      }), failure(code === "42501" ? 403 : 503, code === "42501" ? "forbidden" : "unavailable"));
      assert.equal(calls, phase);
    }
  }
  for (const error of [new PersonalTargetMergeDirectoryStoreError("forbidden"),
    new PersonalTargetMergeDirectoryStoreError("unavailable"), new Error("synthetic private details")]) {
    assert.deepEqual(await readPersonalTargetMergeDirectory(request, {
      identityVerifier: {verify: async () => identity}, directoryStore: {read: async () => {throw error;}},
    }), error instanceof PersonalTargetMergeDirectoryStoreError && error.code === "forbidden"
      ? failure(403, "forbidden") : failure(503, "unavailable"));
  }
});

test("merge directory waits for commit and does not claim parser failure rolls back committed audits", async () => {
  let rejectCommit: ((error: Error) => void) | undefined;
  const commit = new Promise<{rows: readonly unknown[]}>((_resolve, reject) => {rejectCommit = reject;});
  let calls = 0;
  const pending = readPersonalTargetMergeDirectory(request, {
    identityVerifier: {verify: async () => identity},
    directoryStore: new PostgresPersonalTargetMergeDirectoryStore(async () => ++calls === 1
      ? {rows: [{context_result: context()}]} : commit),
  });
  let settled = false;
  void pending.then(() => {settled = true;});
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(calls, 2);
  assert.equal(settled, false);
  assert.ok(rejectCommit);
  rejectCommit(new Error("synthetic deferred audit failure"));
  assert.deepEqual(await pending, failure(503, "unavailable"));
  let committedAudits = 0;
  const store = new PostgresPersonalTargetMergeDirectoryStore(async (sql) => {
    if (sql.includes("read_personal_merge_projection_context_v1")) return {rows: [{context_result: context()}]};
    committedAudits += 4;
    return {rows: [{directory: {...directory(), profile: "synthetic sensitive detail"}}]};
  });
  assert.deepEqual(await readPersonalTargetMergeDirectory(request, {
    identityVerifier: {verify: async () => identity}, directoryStore: store,
  }), failure(503, "unavailable"));
  assert.equal(committedAudits, 4);
});

test("merge directory rejects malformed native pages and pagination boundaries", async (t) => {
  const item = (document: Document, index = 0) => (document.items as Document[])[index]!;
  const mutations: [string, (document: Document) => void][] = [
    ["extra header", (d) => {d.profile = "synthetic";}],
    ["missing header", (d) => {delete d.next_cursor;}],
    ["wrong workspace", (d) => {d.workspace_id = id(9);}],
    ["wrong project", (d) => {d.project_id = id(9);}],
    ["items not array", (d) => {d.items = {};}],
    ["more than twenty", (d) => {d.items = directory(21).items;}],
    ["item not object", (d) => {(d.items as unknown[])[0] = [];}],
    ["extra item profile", (d) => {item(d).display_name = "synthetic";}],
    ["missing item key", (d) => {delete item(d).retained_target_id;}],
    ["invalid generation", (d) => {item(d).generation_id = "bad";}],
    ["unsorted generations", (d) => {(d.items as Document[]).reverse();}],
    ["duplicate generation ignoring case", (d) => {item(d, 1).generation_id = String(item(d).generation_id).toUpperCase();}],
    ["equal after", (d) => {item(d).generation_id = id(50).toUpperCase();}],
    ["below after", (d) => {item(d).generation_id = id(49);}],
    ["wrong type", (d) => {item(d).target_type = "organization";}],
    ["member count", (d) => {item(d).member_target_ids = [id(1000)];}],
    ["member UUID", (d) => {item(d).member_target_ids = ["bad", id(1001)];}],
    ["member order", (d) => {(item(d).member_target_ids as string[]).reverse();}],
    ["duplicate member ignoring case", (d) => {item(d).member_target_ids = [id(1000), id(1000).toUpperCase()];}],
    ["retained not member", (d) => {item(d).retained_target_id = id(9);}],
    ["retained UUID", (d) => {item(d).retained_target_id = null;}],
    ["due precision", (d) => {item(d).review_due_at_utc = "2020-10-15T12:34:56.123Z";}],
    ["due calendar", (d) => {item(d).review_due_at_utc = "2020-02-30T12:34:56.123456Z";}],
    ["due offset", (d) => {item(d).review_due_at_utc = "2020-10-15T12:34:56.123456+00:00";}],
    ["next UUID", (d) => {d.next_cursor = "bad";}],
    ["next page too short", (d) => {d.next_cursor = id(101);}],
    ["next not final ID", (d) => {d.items = directory(20).items; d.next_cursor = id(118);}],
    ["next beyond final ID", (d) => {d.items = directory(20).items; d.next_cursor = id(120);}],
    ["empty page with cursor", (d) => {d.items = []; d.next_cursor = id(101);}],
  ];
  for (const [name, mutate] of mutations) {
    await t.test(name, async () => {
      const document = directory();
      mutate(document);
      await assert.rejects(storeFor(document).store.read(identity, projectId, id(50)), {
        name: "PersonalTargetMergeDirectoryStoreError", message: "unavailable",
      });
    });
  }
  for (const document of [null, [], "{}", 1]) {
    await assert.rejects(storeFor(document).store.read(identity, projectId, null), {message: "unavailable"});
  }
  for (const rows of [[], [{context_result: context()}, {context_result: context()}], [{context_result: context(), extra: 1}]]) {
    await assert.rejects(new PostgresPersonalTargetMergeDirectoryStore(async () => ({rows})).read(identity, projectId, null), {message: "unavailable"});
  }
});

test("merge directory route returns only native metadata without bootstrapping", async () => {
  const directory = {workspace_id: workspaceId, project_id: projectId, items: [], next_cursor: null};
  let storeFailure: "forbidden" | "unavailable" | undefined;
  const cursors: (string | null)[] = [];
  const server = createBackendServer({
    identityVerifier: {verify: async (token) => {
      if (token === "invalid") throw new IdentityVerificationError();
      if (token === "unavailable") throw new IdentityVerificationError("unavailable");
      return identity;
    }},
    contextStore: {loadOrCreate: async () => {throw new Error("directory must not bootstrap");}},
    personalTargetMergeDirectoryStore: {read: async (_identity, _project, after) => {
      cursors.push(after);
      if (storeFailure !== undefined) throw new PersonalTargetMergeDirectoryStoreError(storeFailure);
      return directory;
    }},
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address() as AddressInfo;
    const endpoint = `http://127.0.0.1:${address.port}/v1/projects/${projectId}/promotion-target-merges`;
    const response = await fetch(endpoint, {
      headers: {authorization: "Bearer synthetic"},
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.deepEqual(await response.json(), {directory});
    const after = id(50).toUpperCase();
    assert.equal((await fetch(`${endpoint}?after=${after}`, {headers: {authorization: "Bearer synthetic"}})).status, 200);
    assert.deepEqual(cursors, [null, after]);
    for (const [url, token, status, code] of [
      [endpoint.replace(projectId, "malformed"), "invalid", 401, "unauthenticated"],
      [endpoint, "unavailable", 503, "unavailable"],
      [`${endpoint}?after=${after}&after=${after}`, "synthetic", 400, "invalid_request"],
      [`${endpoint}?limit=20`, "synthetic", 400, "invalid_request"],
    ] as const) {
      const result = await fetch(url, {headers: {authorization: `Bearer ${token}`}});
      assert.equal(result.status, status);
      assert.equal(result.headers.get("cache-control"), "no-store");
      assert.deepEqual(await result.json(), failure(status, code).body);
    }
    assert.equal(cursors.length, 2);
    for (const code of ["forbidden", "unavailable"] as const) {
      storeFailure = code;
      const result = await fetch(endpoint, {headers: {authorization: "Bearer synthetic"}});
      assert.equal(result.status, code === "forbidden" ? 403 : 503);
      assert.equal(result.headers.get("cache-control"), "no-store");
      assert.deepEqual(await result.json(), failure(result.status, code).body);
    }
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
});
