import assert from "node:assert/strict";
import test from "node:test";

import {
  createLocalJWKSet,
  errors,
  exportJWK,
  generateKeyPair,
  SignJWT,
} from "jose";

import {
  createSupabaseIdentityVerifier,
  IdentityVerificationError,
} from "../src/identity.js";

const issuer = "https://synthetic.supabase.co/auth/v1";

test("verified token returns only issuer and subject", async () => {
  const fixture = await createTokenFixture();
  const verifier = createSupabaseIdentityVerifier({
    issuer,
    audience: "authenticated",
    keyResolver: fixture.keyResolver,
  });

  const identity = await verifier.verify(fixture.accessToken);

  assert.deepEqual(identity, {
    issuer,
    subject: "synthetic-subject",
  });
  assert.equal("email" in identity, false);
});

test("verified identity reports the latest valid password AMR timestamp", async () => {
  const cases = [
    { amr: [{ method: "password", timestamp: 42 }], expected: 42 },
    {
      amr: [
        { method: "password", timestamp: 12 },
        { method: "mfa", timestamp: 900 },
        { method: "password", timestamp: 31 },
      ],
      expected: 31,
    },
  ] as const;

  for (const { amr, expected } of cases) {
    const fixture = await createTokenFixture({ amr });
    const verifier = createSupabaseIdentityVerifier({
      issuer,
      audience: "authenticated",
      keyResolver: fixture.keyResolver,
    });

    assert.deepEqual(await verifier.verify(fixture.accessToken), {
      issuer,
      subject: "synthetic-subject",
      passwordAuthenticatedAtUnixSeconds: expected,
    });
  }
});

test("missing or invalid password AMR timestamps are omitted", async () => {
  const invalidAmrClaims: readonly unknown[][] = [
    [],
    ["password", null, {}, { method: "password" }],
    [
      { method: "unknown", timestamp: 100 },
      { method: "password", timestamp: null },
      { method: "password", timestamp: -1 },
      { method: "password", timestamp: 1.5 },
      { method: "password", timestamp: Number.NaN },
      { method: "password", timestamp: Number.POSITIVE_INFINITY },
      { method: "password", timestamp: Number.MAX_SAFE_INTEGER + 1 },
    ],
  ];

  for (const amr of invalidAmrClaims) {
    const fixture = await createTokenFixture({ amr });
    const verifier = createSupabaseIdentityVerifier({
      issuer,
      audience: "authenticated",
      keyResolver: fixture.keyResolver,
    });

    assert.deepEqual(await verifier.verify(fixture.accessToken), {
      issuer,
      subject: "synthetic-subject",
    });
  }

  for (const amr of ["password", { method: "password", timestamp: 5 }]) {
    const fixture = await createTokenFixture({ amr });
    const verifier = createSupabaseIdentityVerifier({
      issuer,
      audience: "authenticated",
      keyResolver: fixture.keyResolver,
    });

    assert.deepEqual(await verifier.verify(fixture.accessToken), {
      issuer,
      subject: "synthetic-subject",
    });
  }

  const fixture = await createTokenFixture();
  const verifier = createSupabaseIdentityVerifier({
    issuer,
    audience: "authenticated",
    keyResolver: fixture.keyResolver,
  });
  assert.deepEqual(await verifier.verify(fixture.accessToken), {
    issuer,
    subject: "synthetic-subject",
  });
});

test("token from another issuer is rejected before context lookup", async () => {
  const fixture = await createTokenFixture({
    tokenIssuer: "https://forged.example.test/auth/v1",
  });
  const verifier = createSupabaseIdentityVerifier({
    issuer,
    audience: "authenticated",
    keyResolver: fixture.keyResolver,
  });

  await assert.rejects(
    verifier.verify(fixture.accessToken),
    IdentityVerificationError,
  );
});

test("token without authenticated role is rejected", async () => {
  const fixture = await createTokenFixture({ role: "anon" });
  const verifier = createSupabaseIdentityVerifier({
    issuer,
    audience: "authenticated",
    keyResolver: fixture.keyResolver,
  });

  await assert.rejects(
    verifier.verify(fixture.accessToken),
    (error: unknown) =>
      error instanceof IdentityVerificationError &&
      error.category === "unauthenticated",
  );
});

test("key resolver failures stay distinct from invalid credentials", async () => {
  const fixture = await createTokenFixture();
  for (const failure of [
    new Error("synthetic JWKS outage"),
    new errors.JOSEError("synthetic JWKS response failure"),
  ]) {
    const verifier = createSupabaseIdentityVerifier({
      issuer,
      audience: "authenticated",
      keyResolver: async () => { throw failure; },
    });

    await assert.rejects(
      verifier.verify(fixture.accessToken),
      (error: unknown) =>
        error instanceof IdentityVerificationError &&
        error.category === "unavailable",
    );
  }
});

test("expired and incorrectly signed tokens stay unauthenticated", async () => {
  const trusted = await createTokenFixture();
  const expired = await createTokenFixture({expirationTime: 1});
  const incorrectlySigned = await createTokenFixture();
  for (const [accessToken, keyResolver] of [
    [expired.accessToken, expired.keyResolver],
    [incorrectlySigned.accessToken, trusted.keyResolver],
  ] as const) {
    const verifier = createSupabaseIdentityVerifier({
      issuer,
      audience: "authenticated",
      keyResolver,
    });
    await assert.rejects(
      verifier.verify(accessToken),
      (error: unknown) =>
        error instanceof IdentityVerificationError &&
        error.category === "unauthenticated",
    );
  }
});

async function createTokenFixture(options?: {
  readonly tokenIssuer?: string;
  readonly role?: string;
  readonly expirationTime?: string | number;
  readonly amr?: unknown;
}): Promise<{
  readonly accessToken: string;
  readonly keyResolver: ReturnType<typeof createLocalJWKSet>;
}> {
  const { privateKey, publicKey } = await generateKeyPair("ES256");
  const publicJwk = await exportJWK(publicKey);
  const keyResolver = createLocalJWKSet({
    keys: [{ ...publicJwk, alg: "ES256", kid: "synthetic-key", use: "sig" }],
  });
  const accessToken = await new SignJWT({
    role: options?.role ?? "authenticated",
    email: "not-returned@example.test",
    ...(options?.amr === undefined ? {} : { amr: options.amr }),
  })
    .setProtectedHeader({ alg: "ES256", kid: "synthetic-key", typ: "JWT" })
    .setIssuer(options?.tokenIssuer ?? issuer)
    .setAudience("authenticated")
    .setSubject("synthetic-subject")
    .setIssuedAt()
    .setExpirationTime(options?.expirationTime ?? "5m")
    .sign(privateKey);

  return { accessToken, keyResolver };
}
