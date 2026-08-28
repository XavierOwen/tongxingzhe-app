import assert from "node:assert/strict";
import test from "node:test";

import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  SignJWT,
} from "jose";

import {
  createSupabaseIdentityVerifier,
  IdentityVerificationError,
} from "../src/identity.js";
import {
  AuthUserLookupError,
  createOrganizationCreationIdentityVerifier,
  createSupabaseAuthUserLookup,
  OrganizationCreationIdentityError,
  type AuthUserEligibility,
} from "../src/organization-creation-identity.js";

const issuer = "https://synthetic.supabase.co/auth/v1";
const subject = "synthetic-subject";
const providerUser = {
  id: subject,
  is_anonymous: false,
  email_confirmed_at: "2030-01-02T03:04:05.678Z",
};

test("verified JWT and Auth user return only request-scoped eligibility", async () => {
  const fixture = await createTokenFixture();
  const calls: {accessToken: string; expectedSubject: string}[] = [];
  const verifier = createOrganizationCreationIdentityVerifier({
    identityVerifier: fixture.identityVerifier,
    authUserLookup: {
      async lookup(accessToken, expectedSubject) {
        calls.push({accessToken, expectedSubject});
        return "eligible";
      },
    },
  });

  const result = await verifier.verify(fixture.accessToken);

  assert.deepEqual(result, {issuer, subject, purpose: "organization_creation"});
  assert.deepEqual(calls, [{
    accessToken: fixture.accessToken,
    expectedSubject: subject,
  }]);
  assert.equal("email" in result, false);
  assert.equal("email_confirmed_at" in result, false);
});

test("JWT failures precede lookup and preserve authentication availability", async () => {
  const fixture = await createTokenFixture();
  let lookupCount = 0;
  const authUserLookup = {
    async lookup(): Promise<AuthUserEligibility> {
      lookupCount += 1;
      return "eligible";
    },
  };
  const verifier = createOrganizationCreationIdentityVerifier({
    identityVerifier: fixture.identityVerifier,
    authUserLookup,
  });
  await rejectsIdentity(verifier.verify("forged-token"), "unauthenticated");

  const unavailable = createOrganizationCreationIdentityVerifier({
    identityVerifier: {
      async verify() {
        throw new IdentityVerificationError("unavailable");
      },
    },
    authUserLookup,
  });
  await rejectsIdentity(unavailable.verify("token"), "unavailable");
  assert.equal(lookupCount, 0);
});

test("provider-neutral decisions map to stable categories", async () => {
  const fixture = await createTokenFixture();
  for (const [decision, category] of [
    ["identity_mismatch", "unauthenticated"],
    ["anonymous", "forbidden"],
    ["email_unconfirmed", "forbidden"],
    ["unknown", "unavailable"],
  ] as const) {
    const verifier = createOrganizationCreationIdentityVerifier({
      identityVerifier: fixture.identityVerifier,
      authUserLookup: {async lookup() { return decision as never; }},
    });
    await rejectsIdentity(verifier.verify(fixture.accessToken), category);
  }
});

test("JWT claims and metadata cannot replace trusted Auth evidence", async () => {
  const fixture = await createTokenFixture();
  const verifier = createOrganizationCreationIdentityVerifier({
    identityVerifier: fixture.identityVerifier,
    authUserLookup: {async lookup() { return "email_unconfirmed"; }},
  });

  await rejectsIdentity(verifier.verify(fixture.accessToken), "forbidden");
});

test("Supabase adapter validates subject, anonymous state, and confirmation", async () => {
  const cases: readonly [unknown, AuthUserEligibility | "unavailable"][] = [
    [providerUser, "eligible"],
    [{...providerUser, email_confirmed_at: "2030-01-02T03:04:05+05:30"}, "eligible"],
    [{...providerUser, id: undefined}, "identity_mismatch"],
    [{...providerUser, id: 7}, "identity_mismatch"],
    [{...providerUser, id: ""}, "identity_mismatch"],
    [{...providerUser, id: "another-subject"}, "identity_mismatch"],
    [{...providerUser, is_anonymous: true}, "anonymous"],
    [{...providerUser, is_anonymous: undefined}, "unavailable"],
    [{...providerUser, is_anonymous: null}, "unavailable"],
    [{...providerUser, is_anonymous: "false"}, "unavailable"],
    [{...providerUser, is_anonymous: 0}, "unavailable"],
    [{...providerUser, email_confirmed_at: undefined}, "unavailable"],
    [{...providerUser, email_confirmed_at: null}, "email_unconfirmed"],
    [{...providerUser, email_confirmed_at: ""}, "email_unconfirmed"],
    [{...providerUser, email_confirmed_at: 1}, "unavailable"],
    [{...providerUser, email_confirmed_at: "January 1, 2030"}, "unavailable"],
    [{...providerUser, email_confirmed_at: "2030-01-02T03:04:05"}, "unavailable"],
    [{...providerUser, email_confirmed_at: "2030-02-30T03:04:05Z"}, "unavailable"],
    [{id: subject, is_anonymous: false}, "unavailable"],
    [null, "unavailable"],
    [[], "unavailable"],
  ];

  for (const [user, expected] of cases) {
    const lookup = lookupReturning(jsonResponse(user));
    if (expected === "unavailable") {
      await rejectsLookup(lookup.lookup("access-token", subject), expected);
    } else {
      assert.equal(await lookup.lookup("access-token", subject), expected);
    }
  }
});

test("lookup failures expose only stable categories", async () => {
  const fixture = await createTokenFixture();
  for (const [failure, expected] of [
    [new AuthUserLookupError("unauthenticated"), "unauthenticated"],
    [new AuthUserLookupError("unavailable"), "unavailable"],
    [new Error("provider body with private@example.test"), "unavailable"],
  ] as const) {
    const verifier = createOrganizationCreationIdentityVerifier({
      identityVerifier: fixture.identityVerifier,
      authUserLookup: {async lookup() { throw failure; }},
    });
    await assert.rejects(
      verifier.verify(fixture.accessToken),
      (error: unknown) =>
        error instanceof OrganizationCreationIdentityError &&
        error.category === expected &&
        !error.message.includes("private@example.test") &&
        !("cause" in error),
    );
  }
});

test("Supabase adapter sends one fixed GET and returns no provider fields", async () => {
  const requests: {input: string | URL | Request; init?: RequestInit}[] = [];
  const lookup = createSupabaseAuthUserLookup({
    userEndpoint: "https://synthetic.supabase.co/auth/v1/user",
    publishableKey: "sb_publishable_synthetic",
    request: async (input, init) => {
      requests.push({input, ...(init === undefined ? {} : {init})});
      return jsonResponse({
        ...providerUser,
        email: "must-not-return@example.test",
        user_metadata: {email_verified: true},
      });
    },
  });

  assert.equal(await lookup.lookup("access-token", subject), "eligible");
  assert.equal(requests.length, 1);
  assert.equal(
    String(requests[0]?.input),
    "https://synthetic.supabase.co/auth/v1/user",
  );
  assert.deepEqual(requests[0]?.init, {
    method: "GET",
    headers: {
      authorization: "Bearer access-token",
      apikey: "sb_publishable_synthetic",
    },
    redirect: "error",
    signal: requests[0]?.init?.signal,
  });
  assert.equal(requests[0]?.init?.body, undefined);
});

test("Supabase adapter maps HTTP, parsing, size, network, and timeout failures", async () => {
  for (const response of [
    new Response("", {status: 302}),
    new Response("", {status: 500}),
    new Response("not json", {status: 200, headers: {"content-type": "application/json"}}),
    new Response("{}", {status: 200, headers: {"content-type": "text/plain"}}),
    new Response("{}", {status: 200, headers: {"content-type": "application/jsonp"}}),
    new Response("x".repeat(16 * 1024 + 1), {status: 200, headers: {"content-type": "application/json"}}),
    new Response("{}", {status: 200, headers: {"content-type": "application/json", "content-length": "99999"}}),
    new Response(Uint8Array.from([0xff]), {status: 200, headers: {"content-type": "application/json"}}),
  ]) {
    await rejectsLookup(
      lookupReturning(response).lookup("access-token", subject),
      "unavailable",
    );
  }
  for (const status of [401, 403]) {
    await rejectsLookup(
      lookupReturning(new Response("", {status})).lookup("access-token", subject),
      "unauthenticated",
    );
  }

  const network = createSupabaseAuthUserLookup({
    userEndpoint: "https://synthetic.supabase.co/auth/v1/user",
    publishableKey: "sb_publishable_synthetic",
    request: async () => { throw new Error("network body"); },
  });
  await rejectsLookup(network.lookup("access-token", subject), "unavailable");

  const timeout = createSupabaseAuthUserLookup({
    userEndpoint: "https://synthetic.supabase.co/auth/v1/user",
    publishableKey: "sb_publishable_synthetic",
    timeoutMilliseconds: 5,
    request: async (_input, init) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new Error("timeout")));
    }),
  });
  await rejectsLookup(timeout.lookup("access-token", subject), "unavailable");
});

test("Supabase adapter allowlists fixed endpoint and publishable keys", () => {
  const legacyAnon = jwtLikeKey({role: "anon"});
  const invalidOptions = [
    {userEndpoint: "http://example.test/auth/v1/user", publishableKey: "sb_publishable_x"},
    {userEndpoint: "https://user:pass@example.test/auth/v1/user", publishableKey: "sb_publishable_x"},
    {userEndpoint: "https://example.test/auth/v1/user?", publishableKey: "sb_publishable_x"},
    {userEndpoint: "https://example.test/auth/v1/user#", publishableKey: "sb_publishable_x"},
    {userEndpoint: "https://example.test/auth/v1/user?next=other", publishableKey: "sb_publishable_x"},
    {userEndpoint: "https://example.test/auth/v1/user#fragment", publishableKey: "sb_publishable_x"},
    {userEndpoint: "https://example.test/auth/v1/user", publishableKey: "sb_secret_x"},
    {userEndpoint: "https://example.test/auth/v1/user", publishableKey: ""},
    {userEndpoint: "https://example.test/auth/v1/user", publishableKey: "synthetic-anon-key"},
    {userEndpoint: "https://example.test/auth/v1/user", publishableKey: "service_role"},
    {userEndpoint: "https://example.test/auth/v1/user", publishableKey: jwtLikeKey({role: "service_role"})},
  ];
  for (const options of invalidOptions) {
    assert.throws(
      () => createSupabaseAuthUserLookup(options),
      AuthUserLookupError,
    );
  }
  assert.doesNotThrow(() => createSupabaseAuthUserLookup({
    userEndpoint: "https://example.test/auth/v1/user",
    publishableKey: legacyAnon,
  }));
});

async function createTokenFixture(): Promise<{
  readonly accessToken: string;
  readonly identityVerifier: ReturnType<typeof createSupabaseIdentityVerifier>;
}> {
  const {privateKey, publicKey} = await generateKeyPair("ES256");
  const publicJwk = await exportJWK(publicKey);
  const keyResolver = createLocalJWKSet({
    keys: [{...publicJwk, alg: "ES256", kid: "synthetic-key", use: "sig"}],
  });
  const accessToken = await new SignJWT({
    role: "authenticated",
    email: "claim-is-not-evidence@example.test",
    email_verified: true,
    user_metadata: {email_verified: true},
  })
    .setProtectedHeader({alg: "ES256", kid: "synthetic-key", typ: "JWT"})
    .setIssuer(issuer)
    .setAudience("authenticated")
    .setSubject(subject)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(privateKey);
  return {
    accessToken,
    identityVerifier: createSupabaseIdentityVerifier({
      issuer,
      audience: "authenticated",
      keyResolver,
    }),
  };
}

function lookupReturning(response: Response) {
  return createSupabaseAuthUserLookup({
    userEndpoint: "https://synthetic.supabase.co/auth/v1/user",
    publishableKey: "sb_publishable_synthetic",
    request: async () => response,
  });
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: {"content-type": "application/json; charset=utf-8"},
  });
}

function jwtLikeKey(payload: Record<string, unknown>): string {
  return `header.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.signature`;
}

async function rejectsIdentity(
  promise: Promise<unknown>,
  category: "unauthenticated" | "forbidden" | "unavailable",
): Promise<void> {
  await assert.rejects(
    promise,
    (error: unknown) =>
      error instanceof OrganizationCreationIdentityError &&
      error.category === category,
  );
}

async function rejectsLookup(
  promise: Promise<unknown>,
  category: "unauthenticated" | "unavailable",
): Promise<void> {
  await assert.rejects(
    promise,
    (error: unknown) =>
      error instanceof AuthUserLookupError && error.category === category,
  );
}
