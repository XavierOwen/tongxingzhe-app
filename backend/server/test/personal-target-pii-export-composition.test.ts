import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = source("../../src/main.ts");
const productionServer = source("../../src/server.ts");
const exportModule = source("../../src/personal-target-pii-export.ts");

test("production composes personal PII export from shared identity and pool", () => {
  assert.match(
    productionMain,
    /new PostgresPersonalTargetPiiExportStore\(query\)/,
  );
  assert.match(productionMain, /personalTargetPiiExportStore,/);
  assert.match(productionServer, /personalTargetPiiExportStore\?:/);
  assert.match(productionServer, /exportPersonalTargetPii/);
  assert.match(
    productionServer,
    /requestUrl\.pathname === "\/v1\/promotion-targets\/export"/,
  );
});

test("personal PII export uses only the public 0112 bridge and no logging sink", () => {
  assert.equal(
    (exportModule.match(/app_data\.prepare_personal_target_pii_export_v1/g) ?? [])
      .length,
    1,
  );
  assert.doesNotMatch(exportModule, /app_private|console\.|\blogger\b/);
});

function source(path: string): string {
  return readFileSync(fileURLToPath(new URL(path, import.meta.url)), "utf8");
}
