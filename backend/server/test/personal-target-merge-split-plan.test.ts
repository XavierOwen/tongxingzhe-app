import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  PersonalTargetMergeSplitPlanStoreError,
  PostgresPersonalTargetMergeSplitPlanStore,
  readPersonalTargetMergeSplitPlan,
} from "../src/personal-target-merge-projection.js";

const identity = {issuer: " https://split-plan.synthetic.example.test/auth/v1 ", subject: " owner "};
const projectId = "7ec10000-0000-4000-8000-000000000001";
const workspaceId = "7ec10000-0000-4000-8000-000000000002";
const generationId = "7ec10000-0000-4000-8000-000000000003";
const actorId = "7ec10000-0000-4000-8000-000000000004";
const otherProject = "7ec10000-0000-4000-8000-000000000005";
const oldBinding = "7ec10000-0000-4000-8000-000000000006";
const firstId = "7ec10000-0000-4000-8000-000000000011";
const secondId = "7ec10000-0000-4000-8000-000000000012";
const partnerId = "7ec10000-0000-4000-8000-000000000013";
const relationshipId = "7ec10000-0000-4000-8000-000000000014";
const time = "2020-10-15T12:34:56.123456Z";
const request = {authorization: "Bearer synthetic", projectId, generationId, hasQuery: false, hasBody: false};
type Document = Record<string, unknown>;

function context(): Document {
  return {app_user_id: actorId, workspace_id: workspaceId, workspace_kind: "personal", project_id: projectId,
    capabilities: ["view_assigned_target_pii", "manage_assigned_target_merges"]};
}

function plan(type = "person"): Document {
  const personId = type === "person" ? firstId : partnerId;
  const institutionId = type === "institution" ? firstId : partnerId;
  const facts = [
    {source_target_id: firstId, metadata: ["project_revision", firstId, otherProject, 1]},
    {source_target_id: firstId, metadata: ["contact_link", "TEXT | : , [\"quoted\"]\u001f/3", 1, firstId]},
    {source_target_id: firstId, metadata: [`institution_relationship_${type}`, relationshipId, personId, institutionId, 2, time, oldBinding]},
    {source_target_id: firstId, metadata: ["project_relationship", firstId, otherProject, 2, time]},
    {source_target_id: firstId, metadata: [`institution_revision_${type}`, relationshipId, 1, personId, institutionId, null]},
    {source_target_id: firstId, metadata: [`institution_revision_${type}`, relationshipId, 2, personId, institutionId, oldBinding]},
    {source_target_id: firstId, metadata: ["contact_link", "", 3, firstId]},
  ];
  return {generation_id: generationId, workspace_id: workspaceId, project_id: projectId,
    target_type: type, member_target_ids: [firstId, secondId], review_due_at_utc: time,
    fact_count: facts.length, fact_fingerprint: "e".repeat(64), facts};
}

function fact(document: Document, index = 0): Document {
  return (document.facts as Document[])[index]!;
}

function metadata(document: Document, index = 0): unknown[] {
  return fact(document, index).metadata as unknown[];
}

function storeFor(value: unknown, eligibility: unknown = context()) {
  let calls = 0;
  return {
    store: new PostgresPersonalTargetMergeSplitPlanStore(async () => ({rows: [
      ++calls === 1 ? {context_result: eligibility} : {split_plan: value},
    ]})),
    calls: () => calls,
  };
}

function failure(status: number, suffix: string) {
  return {status, body: {error: {code: `personal_target_merge_split_plan_${suffix}`}}};
}

test("split plan authenticates before malformed input or dependency checks", async () => {
  let verifies = 0;
  let reads = 0;
  const dependencies = {identityVerifier: {verify: async () => {verifies++; return identity;}},
    splitPlanStore: {read: async () => {reads++; return plan();}}};
  const malformed = {...request, projectId: "bad", hasBody: true, hasQuery: true};
  for (const authorization of [undefined, "Basic private", "Bearer first,second"]) {
    assert.deepEqual(await readPersonalTargetMergeSplitPlan({...malformed, authorization}, dependencies), failure(401, "unauthenticated"));
  }
  assert.equal(verifies, 0);
  for (const [error, expected] of [
    [new IdentityVerificationError(), failure(401, "unauthenticated")],
    [new IdentityVerificationError("unavailable"), failure(503, "unavailable")],
    [new Error("synthetic private dependency detail"), failure(503, "unavailable")],
  ] as const) {
    assert.deepEqual(await readPersonalTargetMergeSplitPlan(malformed, {
      ...dependencies, identityVerifier: {verify: async () => {throw error;}},
    }), expected);
  }
  for (const invalid of [{...request, projectId: "bad"}, {...request, generationId: "bad"},
    {...request, hasQuery: true}, {...request, hasBody: true}]) {
    assert.deepEqual(await readPersonalTargetMergeSplitPlan(invalid, dependencies), failure(400, "invalid_request"));
  }
  assert.equal(verifies, 4);
  assert.equal(reads, 0);
  assert.deepEqual(await readPersonalTargetMergeSplitPlan(request, {identityVerifier: dependencies.identityVerifier}), failure(503, "unavailable"));
});

test("split plan handler retains the exact identity and native result reference", async () => {
  const document = plan();
  const result = await readPersonalTargetMergeSplitPlan(request, {
    identityVerifier: {verify: async () => identity},
    splitPlanStore: {read: async (received, project, generation) => {
      assert.strictEqual(received, identity);
      assert.equal(project, projectId);
      assert.equal(generation, generationId);
      return document;
    }},
  });
  assert.equal(result.status, 200);
  assert.deepEqual(Object.keys(result.body), ["split_plan"]);
  assert.strictEqual(result.body.split_plan, document);
});

test("split plan store uses two fixed queries and captures raw identity once", async () => {
  const document = plan();
  const verified = {...identity};
  let calls = 0;
  const store = new PostgresPersonalTargetMergeSplitPlanStore(async (text, values) => {
    calls++;
    assert.deepEqual(values, calls === 1 ? [identity.issuer, identity.subject, projectId] : [identity.issuer, identity.subject, projectId, generationId]);
    assert.equal(text.replace(/\s+/g, " ").trim(), calls === 1
      ? "SELECT app_data.read_personal_merge_projection_context_v1( $1::text, $2::text, $3::uuid ) AS context_result"
      : "SELECT app_data.read_personal_known_source_merge_split_plan_v1( $1::text, $2::text, $3::uuid, $4::uuid ) AS split_plan");
    if (calls === 1) {
      verified.issuer = "changed-after-context";
      verified.subject = "changed-after-context";
      return {rows: [{context_result: context()}]};
    }
    return {rows: [{split_plan: document}]};
  });
  assert.strictEqual(await store.read(verified, projectId, generationId), document);
  assert.equal(calls, 2);
});

test("split plan preserves seven variants, cross-project history, TEXT IDs, opaque hash and database order", async () => {
  const variants = new Set<string>();
  for (const type of ["person", "institution"]) {
    const document = plan(type);
    const facts = document.facts;
    const result = await storeFor(document).store.read(identity, projectId.toUpperCase(), generationId.toUpperCase());
    assert.strictEqual(result, document);
    assert.strictEqual(result.facts, facts);
    assert.equal(result.review_due_at_utc, time);
    assert.equal(result.fact_fingerprint, "e".repeat(64));
    for (const value of document.facts as Document[]) variants.add(String((value.metadata as unknown[])[0]));
  }
  assert.equal(variants.size, 7);
  const empty = {...plan(), facts: [], fact_count: 0};
  assert.strictEqual(await storeFor(empty).store.read(identity, projectId, generationId), empty);
});

test("split plan refuses missing capabilities or malformed context before the audit query", async () => {
  for (const capabilities of [[], ["view_assigned_target_pii"], ["manage_assigned_target_merges"]]) {
    const fixture = storeFor(plan(), {...context(), capabilities});
    await assert.rejects(fixture.store.read(identity, projectId, generationId), {name: "PersonalTargetMergeSplitPlanStoreError", message: "forbidden"});
    assert.equal(fixture.calls(), 1);
  }
  const missing = context();
  delete missing.app_user_id;
  for (const eligibility of [null, missing, {...context(), unknown: true}, {...context(), project_id: otherProject},
    {...context(), workspace_id: "bad"}, {...context(), workspace_kind: "organization"}, {...context(), capabilities: [1]}]) {
    const fixture = storeFor(plan(), eligibility);
    await assert.rejects(fixture.store.read(identity, projectId, generationId), {name: "PersonalTargetMergeSplitPlanStoreError", message: "unavailable"});
    assert.equal(fixture.calls(), 1);
  }
});

test("split plan maps database 42501 only to forbidden and keeps dependency details private", async () => {
  for (const phase of [1, 2]) {
    for (const code of ["42501", "55000", "22023", "08006"]) {
      let calls = 0;
      const store = new PostgresPersonalTargetMergeSplitPlanStore(async () => {
        if (++calls === phase) throw {code, message: "synthetic SQL metadata/private detail"};
        return {rows: [{context_result: context()}]};
      });
      assert.deepEqual(await readPersonalTargetMergeSplitPlan(request, {
        identityVerifier: {verify: async () => identity}, splitPlanStore: store,
      }), failure(code === "42501" ? 403 : 503, code === "42501" ? "forbidden" : "unavailable"));
      assert.equal(calls, phase);
    }
  }
  for (const error of [new PersonalTargetMergeSplitPlanStoreError("unavailable"), new Error("synthetic private detail")]) {
    assert.deepEqual(await readPersonalTargetMergeSplitPlan(request, {
      identityVerifier: {verify: async () => identity}, splitPlanStore: {read: async () => {throw error;}},
    }), failure(503, "unavailable"));
  }
});

test("split plan waits for the audit query commit and withholds parser failures after commit", async () => {
  let finish: ((value: {rows: readonly unknown[]}) => void) | undefined;
  let failCommit: ((reason: Error) => void) | undefined;
  const commit = new Promise<{rows: readonly unknown[]}>((resolve, reject) => {finish = resolve; failCommit = reject;});
  let calls = 0;
  const pending = readPersonalTargetMergeSplitPlan(request, {
    identityVerifier: {verify: async () => identity},
    splitPlanStore: new PostgresPersonalTargetMergeSplitPlanStore(async () => ++calls === 1
      ? {rows: [{context_result: context()}]} : commit),
  });
  let settled = false;
  void pending.then(() => {settled = true;});
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(calls, 2);
  assert.equal(settled, false);
  assert.ok(finish && failCommit);
  failCommit(new Error("synthetic deferred SQL failure"));
  assert.deepEqual(await pending, failure(503, "unavailable"));

  let committedAudits = 0;
  const malformed = {...plan(), unexpected: "synthetic private detail"};
  const store = new PostgresPersonalTargetMergeSplitPlanStore(async (sql) => {
    if (sql.includes("read_personal_merge_projection_context_v1")) return {rows: [{context_result: context()}]};
    committedAudits += 2;
    return {rows: [{split_plan: malformed}]};
  });
  assert.deepEqual(await readPersonalTargetMergeSplitPlan(request, {
    identityVerifier: {verify: async () => identity}, splitPlanStore: store,
  }), failure(503, "unavailable"));
  assert.equal(committedAudits, 2);
});

test("split plan rejects wrong native result cardinality and JSON types", async () => {
  for (const rows of [[], [{context_result: context()}, {context_result: context()}], [{context_result: context(), unknown: 1}]]) {
    await assert.rejects(new PostgresPersonalTargetMergeSplitPlanStore(async () => ({rows})).read(identity, projectId, generationId), {message: "unavailable"});
  }
  for (const value of [null, [], "{}", 1]) {
    await assert.rejects(storeFor(value).store.read(identity, projectId, generationId), {message: "unavailable"});
  }
});

test("split plan rejects malformed headers, fact wrappers and array variants", async (t) => {
  const mutations: [string, (document: Document) => void][] = [
    ["unknown header", (d) => {d.profile = "synthetic";}],
    ["missing header", (d) => {delete d.fact_count;}],
    ["workspace", (d) => {d.workspace_id = otherProject;}],
    ["project", (d) => {d.project_id = otherProject;}],
    ["generation", (d) => {d.generation_id = oldBinding;}],
    ["type", (d) => {d.target_type = "organization";}],
    ["member count", (d) => {d.member_target_ids = [firstId];}],
    ["member order", (d) => {d.member_target_ids = [secondId, firstId];}],
    ["member duplicate", (d) => {d.member_target_ids = [firstId, firstId];}],
    ["member UUID", (d) => {d.member_target_ids = ["bad", secondId];}],
    ["fractional count", (d) => {d.fact_count = 0.5;}],
    ["negative count", (d) => {d.fact_count = -1;}],
    ["count mismatch", (d) => {d.fact_count = 0;}],
    ["fingerprint format", (d) => {d.fact_fingerprint = "g".repeat(64);}],
    ["fingerprint length", (d) => {d.fact_fingerprint = "e".repeat(63);}],
    ["due precision", (d) => {d.review_due_at_utc = "2020-10-15T12:34:56.123Z";}],
    ["due calendar", (d) => {d.review_due_at_utc = "2020-02-30T12:34:56.123456Z";}],
    ["due offset", (d) => {d.review_due_at_utc = "2020-10-15T12:34:56.123456+00:00";}],
    ["facts array", (d) => {d.facts = {};}],
    ["unknown fact key", (d) => {fact(d).profile = {};}],
    ["missing fact key", (d) => {delete fact(d).source_target_id;}],
    ["source outside pair", (d) => {fact(d).source_target_id = partnerId;}],
    ["metadata array", (d) => {fact(d).metadata = {};}],
    ["unknown variant", (d) => {metadata(d)[0] = "contact_contents";}],
    ["project source", (d) => {metadata(d)[1] = secondId;}],
    ["project UUID", (d) => {metadata(d)[2] = "bad";}],
    ["project revision", (d) => {metadata(d)[3] = 0;}],
    ["contact TEXT", (d) => {metadata(d, 1)[1] = 1;}],
    ["contact revision", (d) => {metadata(d, 1)[2] = 1.5;}],
    ["contact source", (d) => {metadata(d, 1)[3] = secondId;}],
    ["relationship source endpoint", (d) => {metadata(d, 2)[2] = secondId;}],
    ["relationship opposite endpoint in pair", (d) => {metadata(d, 2)[3] = secondId;}],
    ["relationship equal endpoints", (d) => {metadata(d, 2)[3] = firstId;}],
    ["relationship UUID", (d) => {metadata(d, 2)[1] = "bad";}],
    ["relationship revision", (d) => {metadata(d, 2)[4] = 0;}],
    ["relationship timestamp", (d) => {metadata(d, 2)[5] = "2020-10-15T12:34:56.123Z";}],
    ["relationship other binding", (d) => {metadata(d, 2)[6] = "unknown";}],
    ["project head timestamp", (d) => {metadata(d, 3)[4] = "2020-02-30T12:34:56.123456Z";}],
    ["institution revision source", (d) => {metadata(d, 4)[3] = secondId;}],
    ["institution revision endpoint", (d) => {metadata(d, 4)[4] = secondId;}],
    ["institution revision number", (d) => {metadata(d, 4)[2] = 0;}],
    ["institution revision binding", (d) => {metadata(d, 4)[5] = false;}],
    ["institution variant on person generation", (d) => {metadata(d, 2)[0] = "institution_relationship_institution";}],
  ];
  for (const [name, mutate] of mutations) {
    await t.test(name, async () => {
      const document = plan();
      mutate(document);
      await assert.rejects(storeFor(document).store.read(identity, projectId, generationId), {name: "PersonalTargetMergeSplitPlanStoreError", message: "unavailable"});
    });
  }
  for (const type of ["person", "institution"]) {
    for (const index of [0, 1, 2, 3, 4]) {
      for (const change of ["short", "long"]) {
        await t.test(`${type} variant ${index} ${change}`, async () => {
          const document = plan(type);
          if (change === "short") metadata(document, index).pop();
          else metadata(document, index).push("synthetic extra business value");
          await assert.rejects(storeFor(document).store.read(identity, projectId, generationId), {message: "unavailable"});
        });
      }
    }
  }
});

test("split plan rejects duplicate compound facts even when non-key metadata changes", async (t) => {
  for (const [index, mutate] of [
    [0, (_m: unknown[]) => {}],
    [1, (_m: unknown[]) => {}],
    [2, (m: unknown[]) => {m[4] = 8; m[5] = "2020-10-15T12:34:56.123457Z"; m[6] = null;}],
    [3, (m: unknown[]) => {m[3] = 8; m[4] = "2020-10-15T12:34:56.123457Z";}],
    [4, (m: unknown[]) => {m[5] = oldBinding;}],
  ] as const) {
    await t.test(`variant ${index}`, async () => {
      const document = plan();
      const duplicate = structuredClone(fact(document, index));
      mutate(duplicate.metadata as unknown[]);
      (document.facts as Document[]).push(duplicate);
      document.fact_count = (document.facts as Document[]).length;
      await assert.rejects(storeFor(document).store.read(identity, projectId, generationId), {message: "unavailable"});
    });
  }
});
