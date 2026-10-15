import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {request as requestHttp} from "node:http";
import type {AddressInfo} from "node:net";
import {generateKeyPair, SignJWT} from "jose";
import {Pool} from "pg";
import test from "node:test";

import {createSupabaseIdentityVerifier} from "../src/identity.js";
import {
  PostgresPersonalTargetMergeProjectionStore,
  PostgresPersonalTargetMergeSplitPlanStore,
  PostgresPersonalTargetMergeDirectoryStore,
} from "../src/personal-target-merge-projection.js";
import {createBackendServer} from "../src/server.js";

const databaseUrl = process.env.DATABASE_URL?.trim();

test("known-source HTTP reads reauthorize exact identity and commit source audits", {
  skip: !databaseUrl,
}, async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const runtimeClient = await pool.connect();
  const suffix = randomUUID();
  const issuer = `https://synthetic-merge-read-${suffix}.example.test/auth/v1`;
  const subject = ` owner-${suffix} `;
  const triggerName = `fixture_7ei_commit_${suffix.replaceAll("-", "")}`;
  let triggerInstalled = false;
  let server: ReturnType<typeof createBackendServer> | undefined;
  let contextCalls = 0;
  let corruptResult = false;
  let revokeBeforeAudit = false;
  let databaseCalls = 0;

  try {
    const contextResult = await pool.query(
      "SELECT * FROM app_data.bootstrap_personal_context($1::text,$2::text)",
      [issuer, subject],
    );
    const context = contextResult.rows[0] as {
      app_user_id: string;
      workspace_id: string;
      project_id: string;
      questionnaire_version_id: string;
    };
    await pool.query(
      "SELECT * FROM app_data.list_personal_project_contexts($1::text,$2::text)",
      [issuer, subject],
    );
    const targets: string[] = [];
    for (const type of ["person", "person", "institution", "institution"]) {
      const result = await pool.query(
        `SELECT target FROM app_data.create_promotion_target(
          $1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::text,$7::text,$8::text)`,
        [context.app_user_id, context.workspace_id, context.project_id, type,
          `来源 ${targets.length + 1} ${suffix}`, "+1 312 555 0568",
          targets.length === 1 ? `source-${suffix}@example.test` : null, randomUUID()],
      );
      targets.push(String(result.rows[0].target.target_id));
    }
    const [firstTarget, secondTarget, institutionTarget, secondInstitution] = targets as [string, string, string, string];
    const submit = async (label: string, linkedTargets: readonly string[]) => {
      const contactId = `7ei-http-${label}-${suffix}`;
      const result = await pool.query(
        `SELECT result_code FROM app_data.apply_contact_submit_v3(
          $1::uuid,$2::text,1,'contact.submit.v1','7ei-http-device',$3::text,0,$4::jsonb)`,
        [context.app_user_id, `${contactId}-submit`, contactId, {
          contactId,
          workspaceId: context.workspace_id,
          projectId: context.project_id,
          questionnaireVersionId: context.questionnaire_version_id,
          reason: "synthetic source contract",
          occurredAtUtc: new Date(Date.now() - 86400000).toISOString(),
          occurredTimeZone: "UTC",
          channel: "video_call",
          location: {kind: "not_applicable"},
          reachCount: 2,
          interestLevel: 2,
          answers: [],
          targetLinks: linkedTargets.map((targetId) => ({
            targetId,
            targetType: "person",
            responseLevel: 0,
            followUpConsent: "unknown",
            institutionRepresentativeConfirmed: false,
            confirmStageZero: true,
          })),
        }],
      );
      assert.equal(result.rows[0].result_code, "accepted");
      return contactId;
    };
    const activate = async (first = firstTarget, second = secondTarget) => {
      const preview = await pool.query(
        `SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
          $1::text,$2::text,$3::uuid,$4::uuid,$5::uuid)`,
        [issuer, subject, context.project_id, first, second],
      );
      const activation = await pool.query(
        `SELECT app_private.activate_personal_target_merge_generation_v2(
          $1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7::uuid,$8::uuid) AS generation_id`,
        [context.app_user_id, context.project_id, randomUUID(), preview.rows[0].preview_id,
          first, second, first, first],
      );
      return String(activation.rows[0].generation_id);
    };
    await submit("pre", [firstTarget]);
    const oldGeneration = await activate();
    await submit("old", [secondTarget]);
    await pool.query(
      `SELECT app_private.end_known_source_personal_target_merge_generation_v1(
        $1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,manifest.fact_fingerprint)
       FROM app_private.personal_target_merge_known_source_manifest_v1($5::uuid) manifest`,
      [context.app_user_id, context.workspace_id, context.project_id, randomUUID(), oldGeneration],
    );
    const generationId = await activate();
    const institutionGenerationId = await activate(institutionTarget, secondInstitution);
    const currentContact = await submit("current|\"", [firstTarget, secondTarget]);
    for (const revision of [1, 2]) {
      const revisionResult = await pool.query(
        `SELECT result_code FROM app_data.apply_contact_revise_v3(
          $1::uuid,$2::text,1,'contact.revise.v1','7el-http-device',$3::text,$4::integer,
          (SELECT snapshot || jsonb_build_object('reason','synthetic historical revision')
           FROM app_data.contact_revisions WHERE contact_id=$3::text AND revision_number=$4::integer))`,
        [context.app_user_id, `${currentContact}-revise-${revision}`, currentContact, revision],
      );
      assert.equal(revisionResult.rows[0].result_code, "accepted");
    }
    const alternateProject = randomUUID();
    await pool.query(
      "INSERT INTO app_data.projects(project_id,workspace_id,display_name) VALUES ($1::uuid,$2::uuid,'synthetic historical project')",
      [alternateProject, context.workspace_id],
    );
    await pool.query(
      `INSERT INTO app_data.promotion_target_project_relationships(
        promotion_target_id,project_id,current_stage,established_by_app_user_id,established_at,updated_by_app_user_id,updated_at)
       VALUES ($1::uuid,$2::uuid,2,$3::uuid,clock_timestamp(),$3::uuid,clock_timestamp())`,
      [firstTarget, alternateProject, context.app_user_id],
    );
    const relation = await pool.query(
      `SELECT * FROM app_data.create_target_institution_relationship(
        $1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,'partnership_service','synthetic role',$6::text)`,
      [context.app_user_id, context.workspace_id, context.project_id,
        firstTarget, institutionTarget, randomUUID()],
    );
    const relationshipId = relation.rows[0].result.relationship.relationship_id as string;
    await pool.query(
      `SELECT result FROM app_data.end_target_institution_relationship(
        $1::uuid,$2::uuid,$3::uuid,$4::uuid,1,$5::text)`,
      [context.app_user_id, context.workspace_id, context.project_id, relationshipId, randomUUID()],
    );
    await pool.query("UPDATE app_data.promotion_targets SET phone = NULL WHERE promotion_target_id = $1::uuid", [firstTarget]);
    const expectedResult = await pool.query(
      `SELECT app_private.read_known_source_personal_target_merge_projection_v1(
        $1::uuid,$2::uuid,$3::uuid,$4::uuid) AS projection`,
      [context.app_user_id, context.workspace_id, context.project_id, generationId],
    );
    const expected = expectedResult.rows[0].projection as Record<string, unknown>;
    const expectedPlan = async (generation: string) => (await pool.query(
      `SELECT app_private.read_known_source_personal_merge_split_plan_v1(
        $1::uuid,$2::uuid,$3::uuid,$4::uuid) AS split_plan`,
      [context.app_user_id, context.workspace_id, context.project_id, generation],
    )).rows[0].split_plan as Record<string, unknown>;
    const personPlan = await expectedPlan(generationId);
    const institutionPlan = await expectedPlan(institutionGenerationId);
    const auditCount = async () => Number((await pool.query(
      "SELECT count(*)::integer AS n FROM app_data.promotion_target_access_events WHERE workspace_id = $1::uuid",
      [context.workspace_id],
    )).rows[0].n);
    const identityState = async () => (await pool.query(
      `WITH identities AS MATERIALIZED (
         SELECT * FROM app_data.external_identities WHERE issuer = $1::text
       ), owners AS (SELECT app_user_id FROM identities)
       SELECT jsonb_build_object(
         'identities',(SELECT count(*) FROM identities),
         'users',(SELECT count(*) FROM app_data.app_users WHERE app_user_id IN (SELECT app_user_id FROM owners)),
         'workspaces',(SELECT count(*) FROM app_data.workspaces WHERE personal_owner_app_user_id IN (SELECT app_user_id FROM owners)),
         'current_projects',(SELECT count(*) FROM app_data.user_current_projects WHERE app_user_id IN (SELECT app_user_id FROM owners))) AS state`,
      [issuer],
    )).rows[0].state;
    const query = async (text: string, values: readonly unknown[]) => {
      databaseCalls++;
      const auditRead = text.includes("read_personal_known_source_merge_projection_v1")
        || text.includes("read_personal_known_source_merge_split_plan_v1")
        || text.includes("read_personal_merge_directory_v1");
      if (revokeBeforeAudit && auditRead) {
        revokeBeforeAudit = false;
        await pool.query("UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = $1::uuid", [context.app_user_id]);
      }
      await runtimeClient.query("SET ROLE tongxingzhe_runtime");
      try {
        const result = await runtimeClient.query(text, [...values]);
        if (corruptResult && auditRead) {
          const field = text.includes("split_plan_v1") ? "split_plan"
            : text.includes("merge_directory_v1") ? "directory" : "projection";
          return {rows: [{[field]: {...result.rows[0][field], unexpected_profile: "sensitive result"}}]};
        }
        return result;
      } finally {
        await runtimeClient.query("RESET ROLE");
      }
    };
    const {privateKey, publicKey} = await generateKeyPair("ES256");
    const tokenFor = (tokenSubject: string) => new SignJWT({role: "authenticated"})
      .setProtectedHeader({alg: "ES256"}).setIssuer(issuer).setSubject(tokenSubject)
      .setAudience("authenticated").setIssuedAt().setExpirationTime("10m").sign(privateKey);
    const token = await tokenFor(subject);
    const identityVerifier = createSupabaseIdentityVerifier({
      issuer, audience: "authenticated", keyResolver: async () => publicKey,
    });
    assert.deepEqual(await identityVerifier.verify(token), {issuer, subject});
    server = createBackendServer({
      identityVerifier,
      contextStore: {loadOrCreate: async () => {
        contextCalls++;
        throw new Error("merge reads must not bootstrap context");
      }},
      personalTargetMergeProjectionStore: new PostgresPersonalTargetMergeProjectionStore(query),
      personalTargetMergeSplitPlanStore: new PostgresPersonalTargetMergeSplitPlanStore(query),
      personalTargetMergeDirectoryStore: new PostgresPersonalTargetMergeDirectoryStore(query),
    });
    await new Promise<void>((resolve) => server!.listen(0, "127.0.0.1", resolve));
    const address = server.address() as AddressInfo;
    const endpoint = `http://127.0.0.1:${address.port}/v1/projects/${context.project_id}/promotion-target-merges/${generationId}`;
    const read = async (url = endpoint, accessToken = token) => {
      const response = await fetch(url, {headers: {authorization: `Bearer ${accessToken}`}});
      return {response, body: await response.json() as Record<string, unknown>};
    };
    const assertError = (result: Awaited<ReturnType<typeof read>>, status: number, code: string, kind = "projection") => {
      assert.equal(result.response.status, status);
      assert.deepEqual(result.body, {error: {code: `personal_target_merge_${kind}_${code}`}});
      assert.equal(result.response.headers.get("cache-control"), "no-store");
    };

    const beforeAudits = await auditCount();
    const successful = await read();
    assert.equal(successful.response.status, 200);
    assert.equal(successful.response.headers.get("cache-control"), "no-store");
    assert.deepEqual(successful.body, {projection: expected});
    assert.equal(expected.phone, null);
    assert.equal(expected.email, null);
    assert.equal(await auditCount(), beforeAudits + 2);
    assert.equal(databaseCalls, 2);
    assert.equal(contextCalls, 0);

    const beforeDenied = await auditCount();
    const beforeIdentity = await identityState();
    const beforeUnauthenticatedCalls = databaseCalls;
    assertError(await read(endpoint.replace(generationId, "malformed"), "invalid-token"), 401, "unauthenticated");
    assert.equal(databaseCalls, beforeUnauthenticatedCalls);
    assertError(await read(endpoint.replace(generationId, "malformed")), 400, "invalid_request");
    assertError(await read(`${endpoint}?debug=1`), 400, "invalid_request");
    const readWithBody = (url: string) => new Promise<{status: number | undefined; body: unknown}>((resolve, reject) => {
      const request = requestHttp(url, {
        method: "GET", headers: {authorization: `Bearer ${token}`, "content-length": "1"},
      }, (response) => {
        let body = "";
        response.setEncoding("utf8");
        response.on("data", (chunk: string) => { body += chunk; });
        response.on("end", () => resolve({status: response.statusCode, body: JSON.parse(body)}));
      });
      request.on("error", reject);
      request.end("x");
    });
    const bodyRejection = await readWithBody(endpoint);
    assert.equal(bodyRejection.status, 400);
    assert.deepEqual(bodyRejection.body, {error: {code: "personal_target_merge_projection_invalid_request"}});
    assertError(await read(endpoint, await tokenFor("never-known")), 403, "forbidden");
    assertError(await read(endpoint, await tokenFor(subject.trim())), 403, "forbidden");
    assertError(await read(endpoint.replace(generationId, randomUUID())), 403, "forbidden");
    assert.equal(await auditCount(), beforeDenied);
    assert.deepEqual(await identityState(), beforeIdentity);

    await pool.query("DELETE FROM app_data.user_current_projects WHERE app_user_id = $1::uuid", [context.app_user_id]);
    const missingCurrentState = await identityState();
    try {
      assertError(await read(), 403, "forbidden");
      assert.deepEqual(await identityState(), missingCurrentState);
      assert.equal(await auditCount(), beforeDenied);
    } finally {
      await pool.query("INSERT INTO app_data.user_current_projects(app_user_id,project_id) VALUES ($1::uuid,$2::uuid)", [context.app_user_id, context.project_id]);
    }

    revokeBeforeAudit = true;
    try {
      assertError(await read(), 403, "forbidden");
      assert.equal(await auditCount(), beforeDenied);
    } finally {
      await pool.query("UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = $1::uuid", [context.app_user_id]);
    }

    corruptResult = true;
    try {
      assertError(await read(), 503, "unavailable");
      assert.equal(await auditCount(), beforeDenied + 2);
    } finally {
      corruptResult = false;
    }

    const splitEndpoint = `${endpoint}/split-plan`;
    const beforePlanAudits = await auditCount();
    let expectedPlanAudits = beforePlanAudits;
    for (const [url, expectedPlan] of [
      [splitEndpoint, personPlan],
      [splitEndpoint, personPlan],
      [splitEndpoint.replace(generationId, institutionGenerationId), institutionPlan],
    ] as const) {
      const result = await read(url);
      assert.equal(result.response.status, 200);
      assert.equal(result.response.headers.get("cache-control"), "no-store");
      assert.deepEqual(result.body, {split_plan: expectedPlan});
      expectedPlanAudits += 2;
      assert.equal(await auditCount(), expectedPlanAudits);
    }
    assert.equal(await auditCount(), beforePlanAudits + 6);
    const metadata = [personPlan, institutionPlan].flatMap((plan) =>
      (plan.facts as {metadata: unknown[]}[]).map((fact) => fact.metadata));
    assert.deepEqual(new Set(metadata.map((fact) => fact[0])), new Set([
      "contact_link", "project_relationship", "project_revision", "institution_relationship_person",
      "institution_relationship_institution", "institution_revision_person", "institution_revision_institution",
    ]));
    assert.ok(metadata.some((fact) => fact[0] === "project_relationship" && fact[2] === alternateProject));
    assert.deepEqual(new Set(metadata.filter((fact) => fact[0] === "contact_link" && fact[1] === currentContact)
      .map((fact) => fact[2])), new Set([1, 2, 3]));
    assert.ok(metadata.some((fact) => fact[0] === "institution_revision_person" && fact[1] === relationshipId && fact[2] === 2));

    const beforeSplitDenied = await auditCount();
    const splitIdentity = await identityState();
    const beforeSplitUnauthenticatedCalls = databaseCalls;
    assertError(await read(splitEndpoint.replace(generationId, "malformed"), "invalid-token"), 401, "unauthenticated", "split_plan");
    assert.equal(databaseCalls, beforeSplitUnauthenticatedCalls);
    assertError(await read(splitEndpoint.replace(generationId, "malformed")), 400, "invalid_request", "split_plan");
    assertError(await read(`${splitEndpoint}?debug=1`), 400, "invalid_request", "split_plan");
    assert.deepEqual(await readWithBody(splitEndpoint), {
      status: 400, body: {error: {code: "personal_target_merge_split_plan_invalid_request"}},
    });
    assertError(await read(splitEndpoint, await tokenFor("never-known")), 403, "forbidden", "split_plan");
    assertError(await read(splitEndpoint, await tokenFor(subject.trim())), 403, "forbidden", "split_plan");
    assertError(await read(splitEndpoint.replace(generationId, randomUUID())), 403, "forbidden", "split_plan");
    assertError(await read(splitEndpoint.replace(generationId, oldGeneration)), 403, "forbidden", "split_plan");
    assert.equal(await auditCount(), beforeSplitDenied);
    assert.deepEqual(await identityState(), splitIdentity);
    await pool.query("DELETE FROM app_data.user_current_projects WHERE app_user_id = $1::uuid", [context.app_user_id]);
    const splitMissingCurrent = await identityState();
    try {
      assertError(await read(splitEndpoint), 403, "forbidden", "split_plan");
      assert.deepEqual(await identityState(), splitMissingCurrent);
      assert.equal(await auditCount(), beforeSplitDenied);
    } finally {
      await pool.query("INSERT INTO app_data.user_current_projects(app_user_id,project_id) VALUES ($1::uuid,$2::uuid)", [context.app_user_id, context.project_id]);
    }
    revokeBeforeAudit = true;
    try {
      assertError(await read(splitEndpoint), 403, "forbidden", "split_plan");
      assert.equal(await auditCount(), beforeSplitDenied);
    } finally {
      await pool.query("UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = $1::uuid", [context.app_user_id]);
    }
    corruptResult = true;
    try {
      assertError(await read(splitEndpoint), 503, "unavailable", "split_plan");
      assert.equal(await auditCount(), beforeSplitDenied + 2);
    } finally {
      corruptResult = false;
    }

    const directoryEndpoint = endpoint.slice(0, -(generationId.length + 1));
    const directoryItems = [
      {generation_id: generationId, target_type: "person", retained_target_id: firstTarget,
        member_target_ids: personPlan.member_target_ids, review_due_at_utc: personPlan.review_due_at_utc},
      {generation_id: institutionGenerationId, target_type: "institution", retained_target_id: institutionTarget,
        member_target_ids: institutionPlan.member_target_ids, review_due_at_utc: institutionPlan.review_due_at_utc},
    ].sort((left, right) => left.generation_id < right.generation_id ? -1 : 1);
    const expectedDirectory = (items = directoryItems) => ({
      workspace_id: context.workspace_id, project_id: context.project_id, items, next_cursor: null,
    });
    const beforeDirectory = await auditCount();
    const beforeDirectoryCalls = databaseCalls;
    for (const url of [directoryEndpoint, directoryEndpoint]) {
      const baseline = await auditCount();
      const result = await read(url);
      assert.equal(result.response.status, 200);
      assert.equal(result.response.headers.get("cache-control"), "no-store");
      assert.deepEqual(result.body, {directory: expectedDirectory()});
      assert.equal(await auditCount(), baseline + 2 * directoryItems.length);
    }
    assert.equal(databaseCalls, beforeDirectoryCalls + 4);
    const afterFirst = await read(`${directoryEndpoint}?after=${directoryItems[0]!.generation_id.toUpperCase()}`);
    assert.equal(afterFirst.response.status, 200);
    assert.deepEqual(afterFirst.body, {directory: expectedDirectory(directoryItems.slice(1))});
    assert.equal(await auditCount(), beforeDirectory + 10);
    for (const after of [directoryItems[1]!.generation_id, "ffffffff-ffff-ffff-ffff-ffffffffffff"]) {
      const result = await read(`${directoryEndpoint}?after=${after}`);
      assert.equal(result.response.status, 200);
      assert.deepEqual(result.body, {directory: expectedDirectory([])});
      assert.equal(await auditCount(), beforeDirectory + 10);
    }
    const afterNil = await read(`${directoryEndpoint}?after=00000000-0000-0000-0000-000000000000`);
    assert.equal(afterNil.response.status, 200);
    assert.deepEqual(afterNil.body, {directory: expectedDirectory()});
    assert.equal(await auditCount(), beforeDirectory + 14);

    const beforeDirectoryDenied = await auditCount();
    const directoryIdentity = await identityState();
    const beforeDirectoryUnauthenticated = databaseCalls;
    assertError(await read(directoryEndpoint.replace(context.project_id, "malformed"), "invalid-token"), 401, "unauthenticated", "directory");
    assert.equal(databaseCalls, beforeDirectoryUnauthenticated);
    for (const query of ["after=bad", "limit=20", `after=${generationId}&after=${generationId}`, "workspace=private"]) {
      assertError(await read(`${directoryEndpoint}?${query}`), 400, "invalid_request", "directory");
    }
    assert.deepEqual(await readWithBody(directoryEndpoint), {
      status: 400, body: {error: {code: "personal_target_merge_directory_invalid_request"}},
    });
    assertError(await read(directoryEndpoint, await tokenFor("never-known")), 403, "forbidden", "directory");
    assertError(await read(directoryEndpoint, await tokenFor(subject.trim())), 403, "forbidden", "directory");
    assertError(await read(directoryEndpoint.replace(context.project_id, randomUUID())), 403, "forbidden", "directory");
    assert.equal(await auditCount(), beforeDirectoryDenied);
    assert.deepEqual(await identityState(), directoryIdentity);

    await pool.query("DELETE FROM app_data.user_current_projects WHERE app_user_id = $1::uuid", [context.app_user_id]);
    const directoryMissingCurrent = await identityState();
    try {
      assertError(await read(directoryEndpoint), 403, "forbidden", "directory");
      assert.deepEqual(await identityState(), directoryMissingCurrent);
      assert.equal(await auditCount(), beforeDirectoryDenied);
    } finally {
      await pool.query("INSERT INTO app_data.user_current_projects(app_user_id,project_id) VALUES ($1::uuid,$2::uuid)", [context.app_user_id, context.project_id]);
    }
    await pool.query("UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = $1::uuid", [context.app_user_id]);
    try {
      const beforeCalls = databaseCalls;
      assertError(await read(directoryEndpoint), 403, "forbidden", "directory");
      assert.equal(databaseCalls, beforeCalls + 1);
      assert.equal(await auditCount(), beforeDirectoryDenied);
    } finally {
      await pool.query("UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = $1::uuid", [context.app_user_id]);
    }
    revokeBeforeAudit = true;
    try {
      const beforeCalls = databaseCalls;
      assertError(await read(directoryEndpoint), 403, "forbidden", "directory");
      assert.equal(databaseCalls, beforeCalls + 2);
      assert.equal(await auditCount(), beforeDirectoryDenied);
    } finally {
      await pool.query("UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = $1::uuid", [context.app_user_id]);
    }
    corruptResult = true;
    try {
      assertError(await read(directoryEndpoint), 503, "unavailable", "directory");
      assert.equal(await auditCount(), beforeDirectoryDenied + 4);
    } finally {
      corruptResult = false;
    }

    // A deferred failure occurs at implicit commit, after the function has made its result.
    const beforeCommitFailure = await auditCount();
    await pool.query(`CREATE FUNCTION public.${triggerName}() RETURNS trigger LANGUAGE plpgsql AS $body$
      BEGIN
        IF NEW.workspace_id = '${context.workspace_id}'::uuid AND NEW.action = 'viewed' THEN
          RAISE EXCEPTION USING ERRCODE = 'ZXCOM', MESSAGE = 'synthetic deferred audit failure';
        END IF;
        RETURN NEW;
      END $body$;
      CREATE CONSTRAINT TRIGGER ${triggerName} AFTER INSERT ON app_data.promotion_target_access_events
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.${triggerName}();`);
    triggerInstalled = true;
    assertError(await read(), 503, "unavailable");
    assertError(await read(splitEndpoint), 503, "unavailable", "split_plan");
    assertError(await read(directoryEndpoint), 503, "unavailable", "directory");
    assert.equal(await auditCount(), beforeCommitFailure);
    assert.equal(contextCalls, 0);
    process.stdout.write("Known-source merge projection, split plan and directory runtime JWT/HTTP integration: passed\n");
  } finally {
    try {
      if (server !== undefined) {
        server.closeAllConnections();
        await new Promise<void>((resolve, reject) => server!.close((error) => error ? reject(error) : resolve()));
      }
      if (triggerInstalled) {
        await pool.query(`DROP TRIGGER ${triggerName} ON app_data.promotion_target_access_events;
          DROP FUNCTION public.${triggerName}();`);
      }
    } finally {
      runtimeClient.release();
      await pool.end();
    }
  }
});
