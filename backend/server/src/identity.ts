import {
  createRemoteJWKSet,
  errors,
  jwtVerify,
  type JWTVerifyGetKey,
} from "jose";

export interface VerifiedIdentity {
  readonly issuer: string;
  readonly subject: string;
}

export interface IdentityVerifier {
  verify(accessToken: string): Promise<VerifiedIdentity>;
}

export class IdentityVerificationError extends Error {
  readonly category: "unauthenticated" | "unavailable";

  constructor(
    categoryOrOptions:
      | "unauthenticated"
      | "unavailable"
      | ErrorOptions = "unauthenticated",
    options?: ErrorOptions,
  ) {
    const category = typeof categoryOrOptions === "string"
      ? categoryOrOptions
      : "unauthenticated";
    super(
      "Access token verification failed",
      typeof categoryOrOptions === "string" ? options : categoryOrOptions,
    );
    this.name = "IdentityVerificationError";
    this.category = category;
  }
}

export interface SupabaseIdentityVerifierOptions {
  readonly issuer: string;
  readonly audience: string;
  readonly keyResolver: JWTVerifyGetKey;
}

export function createSupabaseIdentityVerifier(
  options: SupabaseIdentityVerifierOptions,
): IdentityVerifier {
  const issuer = requireAbsoluteHttpsUrl(options.issuer, "AUTH_ISSUER");
  const audience = requireNonEmpty(options.audience, "AUTH_AUDIENCE");

  return {
    async verify(accessToken: string): Promise<VerifiedIdentity> {
      try {
        const token = accessToken.trim();
        if (token.length === 0) throw new InvalidIdentityTokenError();
        const { payload } = await jwtVerify(
          token,
          options.keyResolver,
          {
            issuer,
            audience,
            algorithms: ["ES256", "RS256"],
          },
        );

        if (
          payload.iss !== issuer ||
          typeof payload.sub !== "string" ||
          payload.sub.trim().length === 0 ||
          payload.role !== "authenticated"
        ) {
          throw new InvalidIdentityTokenError();
        }

        return { issuer: payload.iss, subject: payload.sub };
      } catch (cause) {
        throw new IdentityVerificationError(identityFailureCategory(cause), {
          cause,
        });
      }
    },
  };
}

function identityFailureCategory(
  cause: unknown,
): "unauthenticated" | "unavailable" {
  if (
    cause instanceof InvalidIdentityTokenError ||
    cause instanceof errors.JOSEAlgNotAllowed ||
    cause instanceof errors.JWSInvalid ||
    cause instanceof errors.JWSSignatureVerificationFailed ||
    cause instanceof errors.JWTClaimValidationFailed ||
    cause instanceof errors.JWTExpired ||
    cause instanceof errors.JWTInvalid ||
    cause instanceof errors.JWKSNoMatchingKey ||
    cause instanceof errors.JWKSMultipleMatchingKeys
  ) {
    return "unauthenticated";
  }
  return "unavailable";
}

class InvalidIdentityTokenError extends Error {}

export function createProductionIdentityVerifier(options: {
  readonly issuer: string;
  readonly audience: string;
  readonly jwksUrl?: string;
}): IdentityVerifier {
  const issuer = requireAbsoluteHttpsUrl(options.issuer, "AUTH_ISSUER");
  const jwksUrl = new URL(
    options.jwksUrl ?? `${issuer}/.well-known/jwks.json`,
  );

  if (jwksUrl.protocol !== "https:") {
    throw new Error("AUTH_JWKS_URL must use HTTPS");
  }

  return createSupabaseIdentityVerifier({
    issuer,
    audience: options.audience,
    keyResolver: createRemoteJWKSet(jwksUrl),
  });
}

function requireNonEmpty(value: string, name: string): string {
  const normalized = value.trim();
  if (normalized.length === 0) {
    throw new Error(`${name} must not be empty`);
  }
  return normalized;
}

function requireAbsoluteHttpsUrl(value: string, name: string): string {
  const normalized = requireNonEmpty(value, name).replace(/\/$/, "");
  const parsed = new URL(normalized);
  if (parsed.protocol !== "https:") {
    throw new Error(`${name} must use HTTPS`);
  }
  return parsed.toString().replace(/\/$/, "");
}
