import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import { bearerToken } from "./authorization.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export interface SessionContextHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export interface SessionContextHttpDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
}

export async function getSessionContext(
  authorization: string | undefined,
  dependencies: SessionContextHttpDependencies,
): Promise<SessionContextHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.loadOrCreate(identity);
    return { status: 200, body: serializeContext(context) };
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "context_unavailable");
  }
}

export async function selectSessionProject(
  authorization: string | undefined,
  body: unknown,
  dependencies: SessionContextHttpDependencies,
): Promise<SessionContextHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }
  const projectId = projectIdFromBody(body);
  if (projectId === null) {
    return failure(400, "invalid_project_id");
  }
  if (dependencies.contextStore.selectProject === undefined) {
    return failure(503, "context_unavailable");
  }

  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.selectProject(
      identity,
      projectId,
    );
    return {status: 200, body: serializeContext(context)};
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(403, "project_forbidden");
  }
}

export async function createPersonalProject(
  authorization: string | undefined,
  body: unknown,
  dependencies: SessionContextHttpDependencies,
): Promise<SessionContextHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }
  const displayName = projectDisplayNameFromBody(body);
  if (displayName === null) {
    return failure(400, "invalid_project_name");
  }
  if (dependencies.contextStore.createPersonalProject === undefined) {
    return failure(503, "context_unavailable");
  }

  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.createPersonalProject(
      identity,
      displayName,
    );
    return {status: 201, body: serializeContext(context)};
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "context_unavailable");
  }
}

function projectIdFromBody(body: unknown): string | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const projectId = (body as {project_id?: unknown}).project_id;
  if (typeof projectId !== "string") {
    return null;
  }
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuid.test(projectId) ? projectId : null;
}

function projectDisplayNameFromBody(body: unknown): string | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const value = (body as {display_name?: unknown}).display_name;
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.trim();
  return normalized.length >= 1 && normalized.length <= 120
    ? normalized
    : null;
}

function serializeContext(
  context: SessionContext,
): Readonly<Record<string, unknown>> {
  const serialized = serializeSingleContext(context);
  if (context.availableContexts === undefined) {
    return serialized;
  }
  return {
    ...serialized,
    available_contexts: context.availableContexts.map(serializeSingleContext),
  };
}

function serializeSingleContext(
  context: SessionContext,
): Readonly<Record<string, unknown>> {
  return {
    app_user_id: context.appUserId,
    current_context: {
      workspace: {
        workspace_id: context.current.workspace.id,
        kind: context.current.workspace.kind,
        name: context.current.workspace.name,
      },
      project: {
        project_id: context.current.project.id,
        name: context.current.project.name,
      },
      questionnaire_version: {
        questionnaire_version_id: context.current.questionnaireVersion.id,
        version_number: context.current.questionnaireVersion.versionNumber,
      },
    },
    capabilities: context.capabilities,
  };
}

function failure(status: number, code: string): SessionContextHttpResult {
  return { status, body: { error: { code } } };
}
