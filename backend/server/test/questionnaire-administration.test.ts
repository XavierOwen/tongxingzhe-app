import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  createQuestionnaireDraft,
  listQuestionnaireAdministration,
  publishQuestionnaireDraft,
  readQuestionnaireDraft,
  updateQuestionnaireDraft,
  type QuestionnaireAdministrationStore,
  type QuestionnaireDesignDraft,
} from "../src/questionnaire-administration.js";
import {
  parseQuestionnaireVersion,
  serializeQuestionnaireVersion,
} from "../src/questionnaire-validator.js";
import type { SessionContext } from "../src/session-context.js";

const fixturePath = new URL(
  "../../../../fixtures/questionnaire/questionnaire-design-contract-v1.json",
  import.meta.url,
);

test("each management operation rechecks the trusted capability", async () => {
  const deps = dependencies(new MemoryStore(), ["record_contact"]);
  const draftId = "44444444-4444-4444-8444-444444444444";
  const results = await Promise.all([
    listQuestionnaireAdministration("Bearer valid-token", deps),
    createQuestionnaireDraft("Bearer valid-token", {}, deps),
    readQuestionnaireDraft("Bearer valid-token", draftId, deps),
    updateQuestionnaireDraft(
      "Bearer valid-token",
      draftId,
      {expected_revision: 1, definition: {questions: []}},
      deps,
    ),
    publishQuestionnaireDraft(
      "Bearer valid-token",
      draftId,
      {
        expected_revision: 1,
        request_id: "revoked-capability-check",
        publication_note: "不可执行",
      },
      deps,
    ),
  ]);

  for (const result of results) {
    assert.deepEqual(result, {
      status: 403,
      body: {error: {code: "capability_forbidden"}},
    });
  }
});

test("manager can clone, edit, and publish a validated draft", async () => {
  const fixture = JSON.parse(await readFile(fixturePath, "utf8")) as {
    current: unknown;
    candidate: unknown;
  };
  const store = new MemoryStore(
    parseQuestionnaireVersion(fixture.current),
  );
  const deps = dependencies(store, [
    "record_contact",
    "manage_analysis_definitions",
  ]);

  const created = await createQuestionnaireDraft(
    "Bearer valid-token",
    { source_version_id: store.current.id },
    deps,
  );
  assert.equal(created.status, 201);
  const draft = (created.body.draft as {draft_id: string; revision: number});

  const candidate = serializeQuestionnaireVersion(
    parseQuestionnaireVersion(fixture.candidate),
  );
  const updated = await updateQuestionnaireDraft(
    "Bearer valid-token",
    draft.draft_id,
    { expected_revision: draft.revision, definition: {
      questions: candidate.questions,
    } },
    deps,
  );
  assert.equal(updated.status, 200);
  assert.equal(
    (updated.body.draft as {revision: number}).revision,
    draft.revision + 1,
  );

  const published = await publishQuestionnaireDraft(
    "Bearer valid-token",
    draft.draft_id,
    {
      expected_revision: draft.revision + 1,
      request_id: "55555555-5555-4555-8555-555555555555",
      publication_note: "调整主题与范围",
    },
    deps,
  );
  assert.equal(published.status, 200);
  assert.equal(
    ((published.body.publication as {summary: {version_number: number}})
      .summary.version_number),
    4,
  );
});

test("publish revalidates revision and rejects an empty questionnaire", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, ["manage_analysis_definitions"]);
  const created = await createQuestionnaireDraft(
    "Bearer valid-token",
    {},
    deps,
  );
  const draft = created.body.draft as {draft_id: string; revision: number};

  const stale = await publishQuestionnaireDraft(
    "Bearer valid-token",
    draft.draft_id,
    {
      expected_revision: 9,
      request_id: "66666666-6666-4666-8666-666666666666",
      publication_note: "空白",
    },
    deps,
  );
  assert.equal(stale.status, 409);

  const empty = await publishQuestionnaireDraft(
    "Bearer valid-token",
    draft.draft_id,
    {
      expected_revision: draft.revision,
      request_id: "77777777-7777-4777-8777-777777777777",
      publication_note: "空白",
    },
    deps,
  );
  assert.deepEqual(empty, {
    status: 400,
    body: { error: { code: "questionnaire_questions_required" } },
  });
});

function dependencies(
  administrationStore: QuestionnaireAdministrationStore,
  capabilities: readonly string[],
) {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => context(capabilities),
    },
    administrationStore,
  };
}

function context(capabilities: readonly string[]): SessionContext {
  return {
    appUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    current: {
      workspace: {
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        kind: "personal",
        name: "个人空间",
      },
      project: {
        id: "22222222-2222-4222-8222-222222222222",
        name: "校园推广",
      },
      questionnaireVersion: {
        id: "11111111-1111-4111-8111-111111111111",
        versionNumber: 3,
      },
    },
    capabilities,
  };
}

class MemoryStore implements QuestionnaireAdministrationStore {
  constructor(
    readonly current: ReturnType<typeof parseQuestionnaireVersion> =
      parseQuestionnaireVersion({
        questionnaire_version_id: "11111111-1111-4111-8111-111111111111",
        project_id: "22222222-2222-4222-8222-222222222222",
        version_number: 1,
        status: "published",
        questions: [],
      }),
  ) {}

  private draft: QuestionnaireDesignDraft | null = null;

  async list() {
    return { currentVersionId: this.current.id, versions: [], drafts: [] };
  }

  async createDraft(
    session: SessionContext,
    sourceVersionId: string | null,
  ) {
    const id = "44444444-4444-4444-8444-444444444444";
    const source = sourceVersionId === null ? [] : this.current.questions;
    this.draft = {
      id,
      projectId: session.current.project.id,
      sourceVersionId,
      revision: 1,
      updatedAt: "2026-08-06T00:00:00.000Z",
      definition: {
        id,
        projectId: session.current.project.id,
        versionNumber: 1,
        questions: source,
      },
    };
    return this.draft;
  }

  async readDraft(_session: SessionContext, draftId: string) {
    return this.draft?.id === draftId ? this.draft : null;
  }

  async updateDraft(
    _session: SessionContext,
    draftId: string,
    expectedRevision: number,
    definition: ReturnType<typeof parseQuestionnaireVersion>,
  ) {
    assert.equal(this.draft?.id, draftId);
    assert.equal(this.draft?.revision, expectedRevision);
    this.draft = {
      ...this.draft!,
      revision: expectedRevision + 1,
      definition: {...definition, versionNumber: expectedRevision + 1},
    };
    return this.draft;
  }

  async publishDraft(
    _session: SessionContext,
    draftId: string,
    expectedRevision: number,
    _requestId: string,
    publicationNote: string,
  ) {
    assert.equal(this.draft?.id, draftId);
    assert.equal(this.draft?.revision, expectedRevision);
    const version = {
      ...this.draft!.definition,
      id: "88888888-8888-4888-8888-888888888888",
      versionNumber: this.current.versionNumber + 1,
    };
    return {
      summary: {
        id: version.id,
        versionNumber: version.versionNumber,
        isCurrent: true,
        publishedAt: "2026-08-06T01:00:00.000Z",
        publishedByAppUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        publicationNote,
      },
      version,
    };
  }
}
