import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export interface ContextAuthorizationDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
}

export type ContextAuthorizationResult =
  | {readonly status: "authorized"; readonly context: SessionContext}
  | {
      readonly status: "rejected";
      readonly responseStatus: number;
      readonly errorCode: string;
    };

export async function authorizeContext(
  authorization: string | undefined,
  dependencies: ContextAuthorizationDependencies,
  requiredCapabilities: readonly string[],
  unavailableCode: string,
): Promise<ContextAuthorizationResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return {status: "rejected", responseStatus: 401, errorCode: "unauthenticated"};
  }
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.loadOrCreate(identity);
    return requiredCapabilities.every((capability) =>
        context.capabilities.includes(capability)
      )
      ? {status: "authorized", context}
      : {
          status: "rejected",
          responseStatus: 403,
          errorCode: "capability_forbidden",
        };
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? {status: "rejected", responseStatus: 401, errorCode: "unauthenticated"}
      : {status: "rejected", responseStatus: 503, errorCode: unavailableCode};
  }
}
