import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  PersonalTargetMergeProjectionStoreError,
  PostgresPersonalTargetMergeProjectionStore,
  readPersonalTargetMergeProjection,
  type PersonalTargetMergeProjectionQuery,
} from "../src/personal-target-merge-projection.js";

const identity = {issuer: " https://merge.synthetic.example.test/auth/v1 ", subject: " owner "};
const projectId = "7e900000-0000-4000-8000-000000000001";
const generationId = "7e900000-0000-4000-8000-000000000002";
const workspaceId = "7e900000-0000-4000-8000-000000000003";
const actorId = "7e900000-0000-4000-8000-000000000004";
const firstId = "7e900000-0000-4000-8000-000000000011";
const secondId = "7e900000-0000-4000-8000-000000000012";
const partnerId = "7e900000-0000-4000-8000-000000000013";
const previousGenerationId = "7e900000-0000-4000-8000-000000000099";
const firstDue = "2027-10-15T12:34:56.123455Z";
const secondDue = "2027-10-15T12:34:56.123456Z";
const request = {authorization: "Bearer synthetic-token", projectId, generationId, hasQuery: false, hasBody: false};
type Document = Record<string, unknown>;

function contextFixture(): Document {
  return {
    app_user_id: actorId, workspace_id: workspaceId, workspace_kind: "personal", project_id: projectId,
    capabilities: ["view_assigned_target_pii", "manage_assigned_target_merges"],
  };
}

function projectionFixture(targetType = "person"): Document {
  return {
    generation_id: generationId, workspace_id: workspaceId, project_id: projectId, target_type: targetType,
    retained_target_id: firstId, display_name: "Synthetic source B", phone: null, email: null,
    display_name_source_target_id: secondId, phone_source_target_id: secondId, email_source_target_id: firstId,
    review_due_at_utc: firstDue,
    sources: [firstId, secondId].map((targetId, index) => ({
      target_id: targetId,
      profile: {
        target_id: targetId, target_type: targetType, display_name: index === 0 ? "Synthetic source A" : "Synthetic source B",
        phone: index === 0 ? "+1 312 555 0123" : null,
        email: index === 0 ? null : "synthetic-source@example.test",
        created_at: "2026-10-15T07:34:56.123456-05:00",
      },
      review_due_at_utc: index === 0 ? firstDue : secondDue,
      project_relationship: {
        target_id: targetId, project_id: projectId, stage: index, display_stage: index * 2,
        lifecycle_status: index === 0 ? "active" : "paused", follow_up_note: null,
        revision_number: 2, updated_at: "2026-10-15T12:34:56+00:00", history: [],
        stage_aliases: Array.from({length: 5}, (_, stage) => ({
          stage, display_stage: stage * 2, display_name: stage === 2 ? "Synthetic alias" : null,
        })),
      },
      contact_links: [{
        contact_id: "synthetic-contact/not-a-uuid", revision_number: 3, promotion_target_id: targetId,
        response_level: index === 0 ? null : 4, follow_up_consent: "unknown",
        institution_representative_confirmed: false, confirmed_project_entry: true,
        merge_generation_id: index === 0 ? previousGenerationId : null,
      }],
      institution_relationships: [{
        relationship_id: index === 0 ? firstId : secondId,
        person_target_id: targetType === "person" ? targetId : partnerId,
        institution_target_id: targetType === "institution" ? targetId : partnerId,
        relationship_kind: "membership_affiliation", role_description: null,
        started_at: "2026-10-14T10:00:00.123456+00:00",
        ended_at: index === 0 ? null : "2026-10-14T10:00:00.123457Z",
        status: index === 0 ? "active" : "ended", revision_number: index + 1,
      }],
    })),
  };
}

function source(document: Document, index = 0): Document {
  return (document.sources as Document[])[index]!;
}

function relation(document: Document): Document {
  return source(document).project_relationship as Document;
}

function link(document: Document): Document {
  return (source(document).contact_links as Document[])[0]!;
}

function institution(document: Document): Document {
  return (source(document).institution_relationships as Document[])[0]!;
}

function storeFor(document: unknown, context: unknown = contextFixture()) {
  let calls = 0;
  const store = new PostgresPersonalTargetMergeProjectionStore(async () => {
    calls += 1;
    return {rows: [calls === 1 ? {context_result: context} : {projection: document}]};
  });
  return {store, calls: () => calls};
}

function failure(status: number, suffix: string) {
  return {status, body: {error: {code: `personal_target_merge_projection_${suffix}`}}};
}

test("merge projection authenticates before request validation and store access", async () => {
  let verifies = 0;
  let reads = 0;
  const dependencies = {
    identityVerifier: {verify: async () => {verifies += 1; return identity;}},
    projectionStore: {read: async () => {reads += 1; return projectionFixture();}},
  };
  const malformed = {...request, projectId: "invalid", hasQuery: true, hasBody: true};
  for (const authorization of [undefined, "Basic secret", "Bearer first,second"]) {
    assert.deepEqual(await readPersonalTargetMergeProjection({...malformed, authorization}, dependencies), failure(401, "unauthenticated"));
  }
  assert.equal(verifies, 0);
  assert.deepEqual(await readPersonalTargetMergeProjection(malformed, dependencies), failure(400, "invalid_request"));
  assert.equal(verifies, 1);
  assert.equal(reads, 0);

  for (const [error, expected] of [
    [new IdentityVerificationError(), failure(401, "unauthenticated")],
    [new IdentityVerificationError("unavailable"), failure(503, "unavailable")],
    [new Error("synthetic dependency detail"), failure(503, "unavailable")],
  ] as const) {
    assert.deepEqual(await readPersonalTargetMergeProjection(malformed, {
      ...dependencies, identityVerifier: {verify: async () => {throw error;}},
    }), expected);
  }
  assert.equal(reads, 0);
});

test("merge projection rejects query, body and either malformed UUID after authentication", async () => {
  let verifies = 0;
  let reads = 0;
  for (const invalid of [
    {...request, hasQuery: true}, {...request, hasBody: true},
    {...request, projectId: "invalid"}, {...request, generationId: "invalid"},
    {...request, generationId: ""},
  ]) {
    assert.deepEqual(await readPersonalTargetMergeProjection(invalid, {
      identityVerifier: {verify: async () => {verifies += 1; return identity;}},
      projectionStore: {read: async () => {reads += 1; return projectionFixture();}},
    }), failure(400, "invalid_request"));
  }
  assert.equal(verifies, 5);
  assert.equal(reads, 0);
});

test("merge projection handler keeps the VerifiedIdentity and native projection unchanged", async () => {
  const document = projectionFixture();
  const result = await readPersonalTargetMergeProjection(request, {
    identityVerifier: {verify: async (token) => {assert.equal(token, "synthetic-token"); return identity;}},
    projectionStore: {read: async (receivedIdentity, receivedProject, receivedGeneration) => {
      assert.strictEqual(receivedIdentity, identity);
      assert.equal(receivedProject, projectId);
      assert.equal(receivedGeneration, generationId);
      return document;
    }},
  });
  assert.equal(result.status, 200);
  assert.deepEqual(Object.keys(result.body), ["projection"]);
  assert.strictEqual(result.body.projection, document);
});

test("merge projection handler returns value-free errors for missing dependencies and store errors", async () => {
  const identityVerifier = {verify: async () => identity};
  assert.deepEqual(await readPersonalTargetMergeProjection(request, {identityVerifier}), failure(503, "unavailable"));
  for (const [error, expected] of [
    [new PersonalTargetMergeProjectionStoreError("forbidden"), failure(403, "forbidden")],
    [new PersonalTargetMergeProjectionStoreError("unavailable"), failure(503, "unavailable")],
    [new Error("synthetic SQL/PII detail must stay private"), failure(503, "unavailable")],
  ] as const) {
    assert.deepEqual(await readPersonalTargetMergeProjection(request, {
      identityVerifier, projectionStore: {read: async () => {throw error;}},
    }), expected);
  }
});

test("merge projection store uses only the two fixed SQL calls in order with raw identity values", async () => {
  const document = projectionFixture();
  const calls: {text: string; values: readonly unknown[]}[] = [];
  const store = new PostgresPersonalTargetMergeProjectionStore(async (text, values) => {
    calls.push({text, values});
    if (calls.length === 1) {
      assert.equal(text.replace(/\s+/g, " ").trim(), "SELECT app_data.read_personal_merge_projection_context_v1( $1::text, $2::text, $3::uuid ) AS context_result");
      assert.deepEqual(values, [identity.issuer, identity.subject, projectId]);
      return {rows: [{context_result: contextFixture()}]};
    }
    assert.equal(text.replace(/\s+/g, " ").trim(), "SELECT app_data.read_personal_known_source_merge_projection_v1( $1::text, $2::text, $3::uuid, $4::uuid ) AS projection");
    assert.deepEqual(values, [identity.issuer, identity.subject, projectId, generationId]);
    return {rows: [{projection: document}]};
  });
  assert.strictEqual(await store.read(identity, projectId, generationId), document);
  assert.equal(calls.length, 2);
});

test("merge projection accepts native person and institution facts, NULL choices and prior generations", async () => {
  for (const targetType of ["person", "institution"]) {
    const document = projectionFixture(targetType);
    const {store} = storeFor(document);
    assert.strictEqual(await store.read(identity, projectId.toUpperCase(), generationId.toUpperCase()), document);
    assert.equal(document.phone, null);
    assert.equal(document.email, null);
    assert.equal(document.review_due_at_utc, firstDue);
  }
  const empty = projectionFixture();
  source(empty).project_relationship = null;
  source(empty).contact_links = [];
  source(empty).institution_relationships = [];
  assert.strictEqual(await storeFor(empty).store.read(identity, projectId, generationId), empty);
});

test("merge projection binds both SQL phases to the original verified identity values", async () => {
  const verified = {...identity};
  let calls = 0;
  const document = projectionFixture();
  const store = new PostgresPersonalTargetMergeProjectionStore(async (_text, values) => {
    calls += 1;
    assert.deepEqual(values.slice(0, 2), [identity.issuer, identity.subject]);
    if (calls === 1) {
      verified.issuer = "changed-after-eligibility";
      verified.subject = "changed-after-eligibility";
      return {rows: [{context_result: contextFixture()}]};
    }
    return {rows: [{projection: document}]};
  });
  assert.strictEqual(await store.read(verified, projectId, generationId), document);
  assert.equal(calls, 2);
});

test("merge projection missing either capability refuses before the audit bridge", async () => {
  for (const capabilities of [[], ["view_assigned_target_pii"], ["manage_assigned_target_merges"]]) {
    const context = {...contextFixture(), capabilities};
    const fixture = storeFor(projectionFixture(), context);
    await assert.rejects(fixture.store.read(identity, projectId, generationId), {
      name: "PersonalTargetMergeProjectionStoreError", message: "forbidden",
    });
    assert.equal(fixture.calls(), 1);
  }
});

test("merge projection validates context keys and scope before the audit bridge", async () => {
  const invalid: Document[] = [
    {...contextFixture(), unexpected: true}, {...contextFixture(), workspace_kind: "organization"},
    {...contextFixture(), project_id: generationId}, {...contextFixture(), workspace_id: "invalid"},
    {...contextFixture(), app_user_id: null}, {...contextFixture(), capabilities: "view_assigned_target_pii"},
    {...contextFixture(), capabilities: ["view_assigned_target_pii", null]},
  ];
  const missing = contextFixture();
  delete missing.workspace_id;
  invalid.push(missing);
  for (const context of invalid) {
    const fixture = storeFor(projectionFixture(), context);
    await assert.rejects(fixture.store.read(identity, projectId, generationId), {message: "unavailable"});
    assert.equal(fixture.calls(), 1);
  }
});

test("merge projection maps 42501 from either SQL phase and sanitizes other database errors", async () => {
  for (const phase of [1, 2]) {
    for (const code of ["42501", "55000", "08006"]) {
      let calls = 0;
      const store = new PostgresPersonalTargetMergeProjectionStore(async () => {
        calls += 1;
        if (calls === phase) throw {code, message: "synthetic SQL/PII detail"};
        return {rows: [{context_result: contextFixture()}]};
      });
      await assert.rejects(store.read(identity, projectId, generationId), {
        name: "PersonalTargetMergeProjectionStoreError", message: code === "42501" ? "forbidden" : "unavailable",
      });
      assert.equal(calls, phase);
    }
  }
});

test("merge projection requires one native JSON result per SQL call", async () => {
  for (const rows of [[], [{context_result: contextFixture()}, {context_result: contextFixture()}],
    [{context_result: JSON.stringify(contextFixture())}], [{context_result: contextFixture(), extra: 1}]]) {
    const store = new PostgresPersonalTargetMergeProjectionStore(async () => ({rows}));
    await assert.rejects(store.read(identity, projectId, generationId), {message: "unavailable"});
  }
  for (const document of [null, "{}", [], 12]) {
    await assert.rejects(storeFor(document).store.read(identity, projectId, generationId), {message: "unavailable"});
  }
});

test("merge projection rejects unknown and missing keys at every projection layer", async (t) => {
  const layers: [string, (document: Document) => Document, string][] = [
    ["projection", (document) => document, "retained_target_id"],
    ["source", (document) => source(document), "target_id"],
    ["profile", (document) => source(document).profile as Document, "email"],
    ["project relationship", relation, "history"],
    ["stage alias", (document) => (relation(document).stage_aliases as Document[])[0]!, "display_name"],
    ["contact link", link, "merge_generation_id"],
    ["institution relationship", institution, "ended_at"],
  ];
  for (const [name, layer, key] of layers) {
    for (const mutation of ["unknown", "missing"]) {
      await t.test(`${name} ${mutation} key`, async () => {
        const document = projectionFixture();
        if (mutation === "unknown") layer(document).unexpected = "synthetic";
        else delete layer(document)[key];
        await assert.rejects(storeFor(document).store.read(identity, projectId, generationId), {message: "unavailable"});
      });
    }
  }
});

test("merge projection rejects inconsistent identities, source selection and current due", async (t) => {
  const mutations: [string, (document: Document) => void][] = [
    ["project scope", (d) => {d.project_id = workspaceId;}],
    ["generation scope", (d) => {d.generation_id = previousGenerationId;}],
    ["workspace scope", (d) => {d.workspace_id = actorId;}],
    ["target type", (d) => {d.target_type = "organization";}],
    ["pair length", (d) => {(d.sources as unknown[]).pop();}],
    ["source order", (d) => {(d.sources as unknown[]).reverse();}],
    ["duplicate source", (d) => {(d.sources as unknown[])[1] = source(d);}],
    ["source profile identity", (d) => {(source(d).profile as Document).target_id = secondId;}],
    ["source profile type", (d) => {(source(d).profile as Document).target_type = "institution";}],
    ["retained outside pair", (d) => {d.retained_target_id = partnerId;}],
    ["name source outside pair", (d) => {d.display_name_source_target_id = partnerId;}],
    ["phone source outside pair", (d) => {d.phone_source_target_id = partnerId;}],
    ["email source outside pair", (d) => {d.email_source_target_id = partnerId;}],
    ["name source mismatch", (d) => {d.display_name_source_target_id = firstId;}],
    ["phone NULL fallback", (d) => {d.phone = "+1 312 555 0123";}],
    ["email NULL fallback", (d) => {d.email = "synthetic-source@example.test";}],
    ["missing selected NULL", (d) => {delete d.phone;}],
    ["minimum due microseconds", (d) => {d.review_due_at_utc = secondDue;}],
    ["due precision", (d) => {d.review_due_at_utc = "2027-10-15T12:34:56.123Z";}],
    ["source due precision", (d) => {source(d).review_due_at_utc = "2027-10-15T12:34:56Z";}],
    ["invalid due calendar", (d) => {source(d).review_due_at_utc = "2027-02-30T12:34:56.123455Z";}],
    ["invalid profile timestamp", (d) => {(source(d).profile as Document).created_at = "2026-02-30T01:00:00+00:00";}],
    ["invalid profile name", (d) => {(source(d).profile as Document).display_name = " ";}],
    ["invalid profile phone", (d) => {(source(d).profile as Document).phone = 123;}],
  ];
  for (const [name, mutate] of mutations) {
    await t.test(name, async () => {
      const document = projectionFixture();
      mutate(document);
      await assert.rejects(storeFor(document).store.read(identity, projectId, generationId), {message: "unavailable"});
    });
  }
});

test("merge projection rejects malformed project, contact and institution facts", async (t) => {
  const mutations: [string, (document: Document) => void][] = [
    ["relationship target", (d) => {relation(d).target_id = secondId;}],
    ["relationship project", (d) => {relation(d).project_id = generationId;}],
    ["relationship history", (d) => {relation(d).history = [{}];}],
    ["relationship stage", (d) => {relation(d).stage = 5;}],
    ["relationship display stage", (d) => {relation(d).display_stage = 4;}],
    ["relationship lifecycle", (d) => {relation(d).lifecycle_status = ["active"];}],
    ["relationship revision", (d) => {relation(d).revision_number = 0;}],
    ["relationship timestamp", (d) => {relation(d).updated_at = "yesterday";}],
    ["alias count", (d) => {relation(d).stage_aliases = [];}],
    ["alias repeated stage", (d) => {(relation(d).stage_aliases as Document[])[1]!.stage = 0;}],
    ["alias display stage", (d) => {(relation(d).stage_aliases as Document[])[1]!.display_stage = 1;}],
    ["alias label", (d) => {(relation(d).stage_aliases as Document[])[1]!.display_name = false;}],
    ["contact links array", (d) => {source(d).contact_links = {};}],
    ["contact id text", (d) => {link(d).contact_id = 1;}],
    ["contact target", (d) => {link(d).promotion_target_id = secondId;}],
    ["contact revision", (d) => {link(d).revision_number = 1.5;}],
    ["contact response", (d) => {link(d).response_level = 5;}],
    ["contact consent", (d) => {link(d).follow_up_consent = ["yes"];}],
    ["contact representative boolean", (d) => {link(d).institution_representative_confirmed = "false";}],
    ["contact project entry boolean", (d) => {link(d).confirmed_project_entry = 1;}],
    ["contact generation UUID", (d) => {link(d).merge_generation_id = "current";}],
    ["institution relations array", (d) => {source(d).institution_relationships = null;}],
    ["institution history", (d) => {institution(d).history = [];}],
    ["institution partner profile", (d) => {institution(d).profile = {display_name: "synthetic"};}],
    ["institution endpoint", (d) => {institution(d).person_target_id = secondId;}],
    ["institution distinct endpoints", (d) => {institution(d).institution_target_id = firstId;}],
    ["institution kind", (d) => {institution(d).relationship_kind = ["other"];}],
    ["institution other role", (d) => {institution(d).relationship_kind = "other";}],
    ["institution status", (d) => {institution(d).status = "ended";}],
    ["institution timestamp", (d) => {institution(d).started_at = "invalid";}],
    ["institution ended before start microseconds", (d) => {
      institution(d).ended_at = "2026-10-14T10:00:00.123455Z"; institution(d).status = "ended";
    }],
    ["institution revision", (d) => {institution(d).revision_number = 0;}],
  ];
  for (const [name, mutate] of mutations) {
    await t.test(name, async () => {
      const document = projectionFixture();
      mutate(document);
      await assert.rejects(storeFor(document).store.read(identity, projectId, generationId), {message: "unavailable"});
    });
  }
});

test("merge projection withholds a malformed audited result without claiming the database audit rolled back", async () => {
  const document = projectionFixture();
  document.unexpected = "synthetic private detail";
  let successfulAuditCalls = 0;
  const query: PersonalTargetMergeProjectionQuery = async (text) => {
    if (text.includes("read_personal_merge_projection_context_v1")) {
      return {rows: [{context_result: contextFixture()}]};
    }
    successfulAuditCalls += 1;
    return {rows: [{projection: document}]};
  };
  assert.deepEqual(await readPersonalTargetMergeProjection(request, {
    identityVerifier: {verify: async () => identity},
    projectionStore: new PostgresPersonalTargetMergeProjectionStore(query),
  }), failure(503, "unavailable"));
  assert.equal(successfulAuditCalls, 1);
});
