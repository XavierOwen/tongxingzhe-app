import { createServer, type Server } from "node:http";

import {
  getSessionContext,
  type SessionContextHttpDependencies,
} from "./http-app.js";
import { handleSyncChanges } from "./sync-changes.js";
import { handleSyncCommand } from "./sync-command.js";
import type { SyncCommandStore } from "./sync-store.js";

export interface BackendServerDependencies
  extends SessionContextHttpDependencies {
  readonly commandStore?: SyncCommandStore;
}

export function createBackendServer(
  dependencies: BackendServerDependencies,
): Server {
  return createServer(async (request, response) => {
    response.setHeader("content-type", "application/json; charset=utf-8");
    response.setHeader("cache-control", "no-store");

    if (request.method === "GET" && request.url === "/healthz") {
      response.statusCode = 200;
      response.end(JSON.stringify({ status: "ok" }));
      return;
    }

    if (request.method === "POST" && request.url === "/v1/sync/commands") {
      if (dependencies.commandStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({ error: { code: "sync_unavailable" } }));
        return;
      }
      try {
        const body = await readJsonBody(request);
        const result = await handleSyncCommand(
          request.headers.authorization,
          body,
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            commandStore: dependencies.commandStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        response.statusCode = error instanceof PayloadTooLargeError ? 413 : 400;
        response.end(
          JSON.stringify({
            error: {
              code:
                error instanceof PayloadTooLargeError
                  ? "payload_too_large"
                  : "invalid_json",
            },
          }),
        );
      }
      return;
    }

    const requestUrl = new URL(request.url ?? "/", "http://localhost");
    if (
      request.method === "GET" &&
      requestUrl.pathname === "/v1/sync/changes"
    ) {
      if (dependencies.commandStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({ error: { code: "sync_unavailable" } }));
        return;
      }
      const result = await handleSyncChanges(
        request.headers.authorization,
        requestUrl.searchParams,
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          commandStore: dependencies.commandStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    if (
      request.method === "GET" &&
      request.url === "/v1/session/context"
    ) {
      const result = await getSessionContext(
        request.headers.authorization,
        dependencies,
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    response.statusCode = 404;
    response.end(JSON.stringify({ error: { code: "not_found" } }));
  });
}

class PayloadTooLargeError extends Error {}

async function readJsonBody(request: AsyncIterable<unknown>): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
    size += buffer.length;
    if (size > 1024 * 1024) {
      throw new PayloadTooLargeError();
    }
    chunks.push(buffer);
  }
  if (chunks.length === 0) {
    throw new SyntaxError("Request body is empty");
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
}
