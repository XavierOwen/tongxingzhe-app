import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
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

test("HTTP management snapshot route waits for the committed store result", async () => {
  const projectId = "33333333-3333-4333-8333-333333333333";
  const snapshotId = "88888888-8888-4888-8888-888888888888";
  const accessEventId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  let finishRead: (() => void) | undefined;
  const readGate = new Promise<void>((resolve) => {finishRead = resolve;});
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("personal context must not authorize management read");
      },
    },
    managementReportSnapshotStore: {
      read: async (identity, receivedProjectId, receivedSnapshotId) => {
        assert.deepEqual(identity, {issuer: "issuer", subject: "subject"});
        assert.equal(receivedProjectId, projectId);
        assert.equal(receivedSnapshotId, snapshotId);
        await readGate;
        return {
          status: "completed",
          accessEventId,
          requestedSnapshotId: snapshotId,
          resolvedSnapshotId: snapshotId,
          protectedReport: {cells: []},
        };
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  let responseSettled = false;
  const responsePromise = fetch(
    `http://127.0.0.1:${address.port}/v1/projects/${projectId}/management-report-snapshots/${snapshotId}`,
    {headers: {authorization: "Bearer token"}},
  ).then((response) => {
    responseSettled = true;
    return response;
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(responseSettled, false);

  finishRead?.();
  const response = await responsePromise;
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {
    access_event_id: accessEventId,
    snapshot_id: snapshotId,
    report: {cells: []},
  });
});

test("HTTP management snapshot route rejects query fields and missing store", async () => {
  const projectId = "33333333-3333-4333-8333-333333333333";
  const snapshotId = "88888888-8888-4888-8888-888888888888";
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("context is not expected");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));
  const endpoint =
    `http://127.0.0.1:${address.port}/v1/projects/${projectId}/management-report-snapshots/${snapshotId}`;

  const queryResponse = await fetch(`${endpoint}?from_utc=2030-01-01`);
  assert.equal(queryResponse.status, 400);
  assert.deepEqual(await queryResponse.json(), {
    error: {code: "invalid_management_report_snapshot_request"},
  });

  const unavailableResponse = await fetch(endpoint, {
    headers: {authorization: "Bearer token"},
  });
  assert.equal(unavailableResponse.status, 503);
  assert.deepEqual(await unavailableResponse.json(), {
    error: {code: "management_report_snapshot_unavailable"},
  });
});

test("HTTP management analysis context is separate from personal context", async () => {
  const projectId = "33333333-3333-4333-8333-333333333333";
  let personalContextCalls = 0;
  let loadCalls = 0;
  let selectedProjectId: string | undefined;
  const navigationContext = {
    organization: {
      id: "22222222-2222-4222-8222-222222222222",
      name: "Synthetic organization",
    },
    project: {id: projectId, name: "Synthetic project"},
  };
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => {
        personalContextCalls += 1;
        throw new Error("personal context must not authorize management navigation");
      },
    },
    managementAnalysisContextStore: {
      load: async () => {
        loadCalls += 1;
        return {current: null, available: [navigationContext]};
      },
      select: async (_identity, receivedProjectId) => {
        selectedProjectId = receivedProjectId;
        return {
          current: navigationContext,
          available: [navigationContext],
        };
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));
  const endpoint =
    `http://127.0.0.1:${address.port}/v1/management-analysis/context`;

  const getResponse = await fetch(endpoint, {
    headers: {authorization: "Bearer token"},
  });
  assert.equal(getResponse.status, 200);
  assert.equal(getResponse.headers.get("cache-control"), "no-store");
  assert.deepEqual(await getResponse.json(), {
    current_context: null,
    available_contexts: [{
      organization: {
        workspace_id: navigationContext.organization.id,
        name: navigationContext.organization.name,
      },
      project: {project_id: projectId, name: navigationContext.project.name},
    }],
    authorization: "must_reauthorize",
  });

  const putResponse = await fetch(endpoint, {
    method: "PUT",
    headers: {
      authorization: "Bearer token",
      "content-type": "application/json",
    },
    body: JSON.stringify({project_id: projectId}),
  });
  assert.equal(putResponse.status, 200);
  assert.equal(putResponse.headers.get("cache-control"), "no-store");
  assert.equal(selectedProjectId, projectId);
  assert.equal(loadCalls, 1);
  assert.equal(personalContextCalls, 0);
});

test("HTTP management context rejects query and GET body before the store", async () => {
  let storeCalls = 0;
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => {throw new Error("context is not expected");},
    },
    managementAnalysisContextStore: {
      load: async () => {
        storeCalls += 1;
        return {current: null, available: []};
      },
      select: async () => {
        storeCalls += 1;
        return {current: null, available: []};
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));
  const endpoint = `/v1/management-analysis/context`;

  const queryResponse = await fetch(
    `http://127.0.0.1:${address.port}${endpoint}?project_id=forged`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(queryResponse.status, 400);

  const bodyResponse = await rawHttpRequest(
    address.port,
    "GET",
    endpoint,
    {
      authorization: "Bearer token",
      "content-type": "application/json",
    },
    "{}",
  );
  assert.equal(bodyResponse.status, 400);
  assert.deepEqual(bodyResponse.body, {
    error: {code: "invalid_management_analysis_context"},
  });
  assert.equal(storeCalls, 0);
});

test("HTTP management context authenticates before request validation", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => {throw new IdentityVerificationError();},
    },
    contextStore: {
      loadOrCreate: async () => {throw new Error("context is not expected");},
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));
  const endpoint =
    `http://127.0.0.1:${address.port}/v1/management-analysis/context`;

  const queryResponse = await fetch(`${endpoint}?project_id=forged`, {
    headers: {authorization: "Bearer invalid"},
  });
  assert.equal(queryResponse.status, 401);
  assert.deepEqual(await queryResponse.json(), {
    error: {code: "unauthenticated"},
  });

  const bodyResponse = await rawHttpRequest(
    address.port,
    "PUT",
    "/v1/management-analysis/context",
    {
      authorization: "Bearer invalid",
      "content-type": "application/json",
    },
    "{",
  );
  assert.equal(bodyResponse.status, 401);
  assert.deepEqual(bodyResponse.body, {
    error: {code: "unauthenticated"},
  });
});

test("HTTP management context reports a missing store", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => {throw new Error("context is not expected");},
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/management-analysis/context`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    error: {code: "management_analysis_context_unavailable"},
  });
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

test("HTTP promotion target route uses the trusted current context", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
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
            name: "校园推广",
          },
          questionnaireVersion: {
            id: "44444444-4444-4444-8444-444444444444",
            versionNumber: 1,
          },
        },
        capabilities: ["create_target", "view_assigned_target_pii"],
      }),
    },
    promotionTargetStore: {
      listAssigned: async () => [],
      create: async (context, input) => {
        assert.equal(
          context.current.workspace.id,
          "22222222-2222-4222-8222-222222222222",
        );
        assert.equal(input.displayName, "王小明");
        return {
          id: "55555555-5555-4555-8555-555555555555",
          type: input.type,
          displayName: input.displayName,
          phone: input.phone,
          email: input.email,
          createdAt: "2026-08-06T12:00:00.000Z",
        };
      },
      updateRelationship: async () => {
        throw new Error("relationship update is not expected in this test");
      },
      configureStageAliases: async () => {
        throw new Error("stage alias update is not expected in this test");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/promotion-targets`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        target_type: "person",
        display_name: "王小明",
        phone: null,
        email: null,
        request_id: "create-target-1",
      }),
    },
  );

  assert.equal(response.status, 201);
  assert.equal(
    (await response.json() as {target: {target_id: string}}).target.target_id,
    "55555555-5555-4555-8555-555555555555",
  );
});

test("HTTP relationship routes use trusted target and project context", async () => {
  const aliases = Array.from({length: 5}, (_, stage) => ({
    stage,
    displayStage: stage * 2,
    displayName: null,
  }));
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
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
            name: "校园推广",
          },
          questionnaireVersion: {
            id: "44444444-4444-4444-8444-444444444444",
            versionNumber: 1,
          },
        },
        capabilities: [
          "view_assigned_target_pii",
          "manage_assigned_target_follow_up",
          "manage_analysis_definitions",
        ],
      }),
    },
    promotionTargetStore: {
      listAssigned: async () => [],
      create: async () => {
        throw new Error("target create is not expected in this test");
      },
      updateRelationship: async (context, targetId, input) => {
        assert.equal(
          context.current.project.id,
          "33333333-3333-4333-8333-333333333333",
        );
        assert.equal(
          targetId,
          "55555555-5555-4555-8555-555555555555",
        );
        assert.equal(input.expectedRevision, 2);
        return {
          status: "accepted",
          duplicate: false,
          acceptedRevision: 3,
          relationship: {
            targetId,
            projectId: context.current.project.id,
            stage: input.stage,
            displayStage: input.stage * 2,
            lifecycleStatus: input.lifecycleStatus,
            followUpNote: input.followUpNote,
            revisionNumber: 3,
            updatedAt: "2026-08-06T13:00:00.000Z",
            stageAliases: aliases,
            history: [],
          },
        };
      },
      configureStageAliases: async (_context, input) => input.map((alias) => ({
        stage: alias.stage,
        displayStage: alias.stage * 2,
        displayName: alias.displayName,
      })),
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/promotion-targets/55555555-5555-4555-8555-555555555555/relationship`,
    {
      method: "PATCH",
      headers: {
        authorization: "Bearer token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        expected_revision: 2,
        stage: 3,
        lifecycle_status: "active",
        follow_up_note: "下周联系",
        reason_code: "progress_update",
        reason_detail: null,
        mutation_id: "relationship-change-1",
        resolved_conflict_id: null,
      }),
    },
  );

  assert.equal(response.status, 200);
  assert.equal(
    (await response.json() as {relationship: {display_stage: number}})
      .relationship.display_stage,
    6,
  );
});

test("HTTP person-to-institution route uses trusted workspace assignments", async () => {
  const relationshipId = "77777777-7777-4777-8777-777777777777";
  const personTargetId = "55555555-5555-4555-8555-555555555555";
  const institutionTargetId = "66666666-6666-4666-8666-666666666666";
  const relationship = {
    id: relationshipId,
    personTargetId,
    institutionTargetId,
    kind: "employment_representative" as const,
    roleDescription: "项目协调员",
    startedAt: "2026-08-06T12:00:00.000Z",
    endedAt: null,
    status: "active" as const,
    revisionNumber: 1,
    history: [],
  };
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
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
            name: "校园推广",
          },
          questionnaireVersion: {
            id: "44444444-4444-4444-8444-444444444444",
            versionNumber: 1,
          },
        },
        capabilities: [
          "view_assigned_target_pii",
          "manage_assigned_target_relations",
        ],
      }),
    },
    targetInstitutionRelationshipStore: {
      list: async () => [],
      create: async (context, input) => {
        assert.equal(
          context.current.workspace.id,
          "22222222-2222-4222-8222-222222222222",
        );
        assert.equal(input.personTargetId, personTargetId);
        assert.equal(input.institutionTargetId, institutionTargetId);
        return {duplicate: false, relationship};
      },
      end: async () => {
        throw new Error("end is not expected in this test");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/promotion-target-institution-relationships`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        person_target_id: personTargetId,
        institution_target_id: institutionTargetId,
        relationship_kind: "employment_representative",
        role_description: "项目协调员",
        mutation_id: "institution-relation-create-1",
      }),
    },
  );

  assert.equal(response.status, 201);
  assert.equal(
    (await response.json() as {relationship: {relationship_id: string}})
      .relationship.relationship_id,
    relationshipId,
  );
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

test("malformed questionnaire path returns a stable validation error", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => {
        throw new Error("invalid version must fail before identity lookup");
      },
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("invalid version must fail before context lookup");
      },
    },
    questionnaireStore: {
      readPublishedVersion: async () => {
        throw new Error("invalid version must fail before database lookup");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/questionnaire-versions/%E0%A4%A`,
    { headers: { authorization: "Bearer synthetic-token" } },
  );

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: { code: "invalid_questionnaire_version_id" },
  });
});

test("HTTP questionnaire administration route rechecks manager context", async () => {
  let contextLookups = 0;
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({
        issuer: "https://synthetic.supabase.co/auth/v1",
        subject: "synthetic-subject",
      }),
    },
    contextStore: {
      loadOrCreate: async () => {
        contextLookups += 1;
        return {
          appUserId: "11111111-1111-4111-8111-111111111111",
          current: {
            workspace: {
              id: "22222222-2222-4222-8222-222222222222",
              kind: "personal" as const,
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
          capabilities: ["manage_analysis_definitions"],
        };
      },
    },
    questionnaireAdministrationStore: {
      list: async () => ({
        currentVersionId: "44444444-4444-4444-8444-444444444444",
        versions: [],
        drafts: [],
      }),
      createDraft: async () => {
        throw new Error("create must not run while listing");
      },
      readDraft: async () => {
        throw new Error("read must not run while listing");
      },
      updateDraft: async () => {
        throw new Error("update must not run while listing");
      },
      publishDraft: async () => {
        throw new Error("publish must not run while listing");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/questionnaire-administration`,
    {headers: {authorization: "Bearer synthetic-token"}},
  );

  assert.equal(response.status, 200);
  assert.equal(contextLookups, 1);
  assert.deepEqual(await response.json(), {
    current_version_id: "44444444-4444-4444-8444-444444444444",
    versions: [],
    drafts: [],
  });
});

test("HTTP questionnaire metric route returns the trusted project catalog", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
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
            name: "校园推广",
          },
          questionnaireVersion: {
            id: "44444444-4444-4444-8444-444444444444",
            versionNumber: 2,
          },
        },
        capabilities: ["manage_analysis_definitions"],
      }),
    },
    questionnaireMetricCompatibilityStore: {
      list: async () => ({
        metrics: [],
        availableQuestions: [],
        events: [],
      }),
      record: async () => {
        throw new Error("record must not run for a list request");
      },
      revoke: async () => {
        throw new Error("revoke must not run for a list request");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/questionnaire-metrics`,
    {headers: {authorization: "Bearer token"}},
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    metrics: [],
    available_questions: [],
    events: [],
  });
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

  const batchResponse = await fetch(
    `http://127.0.0.1:${address.port}/v1/sync/commands/batch`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer synthetic-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({ commands: [validCommandBody()] }),
    },
  );
  assert.equal(batchResponse.status, 200);
  assert.deepEqual(await batchResponse.json(), {
    results: [
      {
        command_id: "command-1",
        result: "accepted",
        server_cursor: "opaque-http-1",
      },
    ],
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

test("HTTP personal plan route exposes only the verified user's plan", async () => {
  let appUserId = "";
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
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
            name: "校园推广",
          },
          questionnaireVersion: {
            id: "44444444-4444-4444-8444-444444444444",
            versionNumber: 1,
          },
        },
        capabilities: [],
      }),
    },
    personalActionPlanStore: {
      read: async (context) => {
        appUserId = context.appUserId;
        return null;
      },
      save: async () => {
        throw new Error("save must not run for GET");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/personal-action-plan`,
    {headers: {authorization: "Bearer synthetic-token"}},
  );

  assert.equal(response.status, 200);
  assert.equal(appUserId, "11111111-1111-4111-8111-111111111111");
  assert.deepEqual(await response.json(), {plan: null});
});

test("HTTP personal reminder route exposes only the verified user's schedule", async () => {
  let appUserId = "";
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
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
            name: "校园推广",
          },
          questionnaireVersion: {
            id: "44444444-4444-4444-8444-444444444444",
            versionNumber: 1,
          },
        },
        capabilities: [],
      }),
    },
    personalActionReminderStore: {
      read: async (context) => {
        appUserId = context.appUserId;
        return null;
      },
      save: async () => {
        throw new Error("save must not run for GET");
      },
    },
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  test.after(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/personal-action-reminder`,
    {headers: {authorization: "Bearer synthetic-token"}},
  );

  assert.equal(response.status, 200);
  assert.equal(appUserId, "11111111-1111-4111-8111-111111111111");
  assert.deepEqual(await response.json(), {reminder: null});
});

function rawHttpRequest(
  port: number,
  method: string,
  path: string,
  headers: Readonly<Record<string, string>>,
  body: string,
): Promise<{status: number; body: unknown}> {
  return new Promise((resolve, reject) => {
    const request = httpRequest({
      host: "127.0.0.1",
      port,
      method,
      path,
      headers: {...headers, "content-length": Buffer.byteLength(body)},
    }, (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk: Buffer) => chunks.push(chunk));
      response.on("end", () => resolve({
        status: response.statusCode ?? 0,
        body: JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown,
      }));
    });
    request.on("error", reject);
    request.end(body);
  });
}

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
