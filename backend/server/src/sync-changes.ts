import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";
import {
  InvalidSyncCursorError,
  type SyncCommandStore,
} from "./sync-store.js";

export interface SyncChangesHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export interface SyncChangesHttpDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly commandStore: SyncCommandStore;
}

export async function handleSyncChanges(
  authorization: string | undefined,
  query: URLSearchParams,
  dependencies: SyncChangesHttpDependencies,
): Promise<SyncChangesHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  let context: SessionContext;
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    context = await dependencies.contextStore.loadOrCreate(identity);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "context_unavailable");
  }

  const workspaceId = query.get("workspace_id");
  const projectId = query.get("project_id");
  if (
    workspaceId !== context.current.workspace.id ||
    projectId !== context.current.project.id
  ) {
    return failure(403, "project_forbidden");
  }
  if (!context.capabilities.includes("record_contact")) {
    return failure(403, "capability_forbidden");
  }

  const rawLimit = query.get("limit") ?? "100";
  const limit = Number(rawLimit);
  if (!/^\d+$/.test(rawLimit) || !Number.isInteger(limit) || limit < 1 || limit > 100) {
    return failure(400, "invalid_limit");
  }
  const rawCursor = query.get("cursor");
  const cursor = rawCursor === null || rawCursor.length === 0 ? null : rawCursor;
  if (cursor !== null && cursor.length > 200) {
    return failure(400, "invalid_cursor");
  }

  try {
    const batch = await dependencies.commandStore.pull(context, cursor, limit);
    return {
      status: 200,
      body: {
        changes: batch.changes.map((change) => ({
          change_type: change.changeType,
          revision_number: change.revisionNumber,
          payload: change.payload,
        })),
        next_cursor: batch.nextCursor,
      },
    };
  } catch (error) {
    if (error instanceof InvalidSyncCursorError) {
      return failure(400, "invalid_cursor");
    }
    return failure(503, "sync_unavailable");
  }
}

function bearerToken(authorization: string | undefined): string | null {
  if (authorization === undefined) {
    return null;
  }
  return /^Bearer ([^\s]+)$/i.exec(authorization.trim())?.[1] ?? null;
}

function failure(status: number, code: string): SyncChangesHttpResult {
  return { status, body: { error: { code } } };
}
