import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export type OrganizationCreationIdentityFailure =
  | "unauthenticated"
  | "forbidden"
  | "unavailable";

export interface OrganizationCreationEligibility extends VerifiedIdentity {
  readonly purpose: "organization_creation";
}

export interface OrganizationCreationIdentityVerifier {
  verify(accessToken: string): Promise<OrganizationCreationEligibility>;
}

export interface AuthUserLookup {
  lookup(
    accessToken: string,
    expectedSubject: string,
  ): Promise<AuthUserEligibility>;
}

export type AuthUserEligibility =
  | "eligible"
  | "identity_mismatch"
  | "anonymous"
  | "email_unconfirmed";

export class OrganizationCreationIdentityError extends Error {
  constructor(readonly category: OrganizationCreationIdentityFailure) {
    super("Organization creation identity verification failed");
    this.name = "OrganizationCreationIdentityError";
  }
}

export class AuthUserLookupError extends Error {
  constructor(readonly category: "unauthenticated" | "unavailable") {
    super("Auth user lookup failed");
    this.name = "AuthUserLookupError";
  }
}

/**
 * 用 access token 建立一次请求内的组织创建资格；不保存 user object 或 PII。
 * JWT 身份必须先通过，Auth lookup 才能作为邮箱确认的可信证据。
 */
export function createOrganizationCreationIdentityVerifier(options: {
  readonly identityVerifier: IdentityVerifier;
  readonly authUserLookup: AuthUserLookup;
}): OrganizationCreationIdentityVerifier {
  return {
    async verify(
      accessToken: string,
    ): Promise<OrganizationCreationEligibility> {
      let identity: VerifiedIdentity;
      try {
        identity = await options.identityVerifier.verify(accessToken);
      } catch (error) {
        const category = error instanceof IdentityVerificationError
          ? error.category
          : "unavailable";
        throw new OrganizationCreationIdentityError(category);
      }

      let eligibility: AuthUserEligibility;
      try {
        eligibility = await options.authUserLookup.lookup(
          accessToken,
          identity.subject,
        );
      } catch (error) {
        const category = error instanceof AuthUserLookupError
          ? error.category
          : "unavailable";
        throw new OrganizationCreationIdentityError(category);
      }

      if (eligibility === "identity_mismatch") {
        throw new OrganizationCreationIdentityError("unauthenticated");
      }
      if (eligibility === "anonymous" || eligibility === "email_unconfirmed") {
        throw new OrganizationCreationIdentityError("forbidden");
      }
      if (eligibility !== "eligible") {
        throw new OrganizationCreationIdentityError("unavailable");
      }

      return {
        issuer: identity.issuer,
        subject: identity.subject,
        purpose: "organization_creation",
      };
    },
  };
}

export interface SupabaseAuthUserLookupOptions {
  readonly userEndpoint: string;
  readonly publishableKey: string;
  readonly request?: typeof fetch;
  readonly timeoutMilliseconds?: number;
}

/** 只读调用 Supabase Auth user endpoint；不会跟随重定向或保留响应。 */
export function createSupabaseAuthUserLookup(
  options: SupabaseAuthUserLookupOptions,
): AuthUserLookup {
  const userEndpoint = requireUserEndpoint(options.userEndpoint);
  const publishableKey = requirePublishableKey(options.publishableKey);
  const request = options.request ?? fetch;
  const timeoutMilliseconds = options.timeoutMilliseconds ?? 5_000;
  if (
    !Number.isInteger(timeoutMilliseconds) ||
    timeoutMilliseconds <= 0 ||
    timeoutMilliseconds > 60_000
  ) {
    throw new AuthUserLookupError("unavailable");
  }

  return {
    async lookup(
      accessToken: string,
      expectedSubject: string,
    ): Promise<AuthUserEligibility> {
      const token = accessToken.trim();
      if (token.length === 0 || /\s/.test(token)) {
        throw new AuthUserLookupError("unauthenticated");
      }

      try {
        const response = await request(userEndpoint, {
          method: "GET",
          headers: {
            authorization: `Bearer ${token}`,
            apikey: publishableKey,
          },
          redirect: "error",
          signal: AbortSignal.timeout(timeoutMilliseconds),
        });
        if (response.status === 401 || response.status === 403) {
          throw new AuthUserLookupError("unauthenticated");
        }
        const mediaType = response.headers.get("content-type")
          ?.split(";", 1)[0]
          ?.trim()
          .toLowerCase();
        if (response.status !== 200 || mediaType !== "application/json") {
          throw new AuthUserLookupError("unavailable");
        }

        const body = await readBoundedBody(response, 16 * 1024);
        try {
          return providerEligibility(
            JSON.parse(body) as unknown,
            expectedSubject,
          );
        } catch {
          throw new AuthUserLookupError("unavailable");
        }
      } catch (error) {
        if (error instanceof AuthUserLookupError) throw error;
        throw new AuthUserLookupError("unavailable");
      }
    },
  };
}

function providerEligibility(
  value: unknown,
  expectedSubject: string,
): AuthUserEligibility {
  const user = object(value);
  if (
    user === null ||
    !Object.hasOwn(user, "is_anonymous") ||
    !Object.hasOwn(user, "email_confirmed_at")
  ) {
    throw new AuthUserLookupError("unavailable");
  }
  const id = user.id;
  if (
    typeof id !== "string" ||
    id.trim().length === 0 ||
    id !== expectedSubject
  ) {
    return "identity_mismatch";
  }
  if (user.is_anonymous === true) return "anonymous";
  if (user.is_anonymous !== false) {
    throw new AuthUserLookupError("unavailable");
  }
  const confirmedAt = user.email_confirmed_at;
  if (confirmedAt === undefined || confirmedAt === null || confirmedAt === "") {
    return "email_unconfirmed";
  }
  if (typeof confirmedAt !== "string" || !isRfc3339Timestamp(confirmedAt)) {
    throw new AuthUserLookupError("unavailable");
  }
  return "eligible";
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function requireUserEndpoint(value: string): URL {
  const normalized = value.trim();
  let url: URL;
  try {
    url = new URL(normalized);
  } catch {
    throw new AuthUserLookupError("unavailable");
  }
  if (
    url.protocol !== "https:" ||
    url.hostname.length === 0 ||
    url.username.length > 0 ||
    url.password.length > 0 ||
    normalized.includes("?") ||
    normalized.includes("#") ||
    url.search.length > 0 ||
    url.hash.length > 0
  ) {
    throw new AuthUserLookupError("unavailable");
  }
  return url;
}

function requirePublishableKey(value: string): string {
  const key = value.trim();
  if (!key.startsWith("sb_publishable_") && legacyJwtRole(key) !== "anon") {
    throw new AuthUserLookupError("unavailable");
  }
  return key;
}

function legacyJwtRole(key: string): string | null {
  const parts = key.split(".");
  if (parts.length !== 3 || parts[1] === undefined) return null;
  try {
    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8"),
    ) as unknown;
    const role = object(payload)?.role;
    return typeof role === "string" ? role : null;
  } catch {
    return null;
  }
}

async function readBoundedBody(
  response: Response,
  maximumBytes: number,
): Promise<string> {
  const contentLength = response.headers.get("content-length");
  if (
    contentLength !== null &&
    (!/^\d+$/.test(contentLength) || Number(contentLength) > maximumBytes)
  ) {
    throw new AuthUserLookupError("unavailable");
  }
  if (response.body === null) return "";

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const {done, value} = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maximumBytes) {
      await reader.cancel().catch(() => undefined);
      throw new AuthUserLookupError("unavailable");
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder("utf-8", {fatal: true}).decode(bytes);
  } catch {
    throw new AuthUserLookupError("unavailable");
  }
}

function isRfc3339Timestamp(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$/.exec(
    value,
  );
  if (match === null) return false;
  const [year, month, day, hour, minute, second, offsetHour, offsetMinute] =
    match.slice(1).map(Number);
  if (
    year === undefined ||
    month === undefined ||
    day === undefined ||
    hour === undefined ||
    minute === undefined ||
    second === undefined ||
    year === 0 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth(year, month) ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    (offsetHour !== undefined && offsetHour > 23) ||
    (offsetMinute !== undefined && offsetMinute > 59)
  ) {
    return false;
  }
  return Number.isFinite(Date.parse(value));
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28;
  }
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}
