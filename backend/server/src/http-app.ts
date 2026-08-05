import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
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

function bearerToken(authorization: string | undefined): string | null {
  if (authorization === undefined) {
    return null;
  }
  const match = /^Bearer ([^\s]+)$/i.exec(authorization.trim());
  return match?.[1] ?? null;
}

function serializeContext(
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
