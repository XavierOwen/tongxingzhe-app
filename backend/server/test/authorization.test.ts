import assert from "node:assert/strict";
import test from "node:test";

import { bearerToken } from "../src/authorization.js";

test("bearer token parser accepts one trimmed case-insensitive bearer value", () => {
  assert.equal(bearerToken("  bEaReR signed-token  "), "signed-token");
});

test("bearer token parser rejects absent, empty, spaced, and extra values", () => {
  assert.equal(bearerToken(undefined), null);
  assert.equal(bearerToken("Bearer"), null);
  assert.equal(bearerToken("Bearer token with-space"), null);
  assert.equal(bearerToken("Basic token"), null);
  assert.equal(bearerToken("Bearer token, Bearer other"), null);
});
