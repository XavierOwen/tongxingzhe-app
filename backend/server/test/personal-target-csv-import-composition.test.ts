import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = source("../../src/main.ts");
const productionServer = source("../../src/server.ts");
const importModule = source("../../src/personal-target-csv-import.ts");

test("production composes CSV import from the shared verifier, context, and pool", () => {
  assert.match(
    productionMain,
    /new PostgresPersonalTargetCsvImportStore\(query\)/,
  );
  assert.match(productionMain, /personalTargetCsvImportStore,/);
  assert.match(productionServer, /personalTargetCsvImportStore\?:/);
  assert.match(productionServer, /handlePersonalTargetCsvImportPreview/);
  assert.match(productionServer, /handlePersonalTargetCsvImportConfirm/);
  assert.match(productionServer, /readBody: async \(\) => readRawBody\(request\)/);
});

test("CSV import exposes only two fixed app_data bridges and no logging sink", () => {
  assert.equal(
    (importModule.match(/app_data\.preview_personal_target_csv_import_v1/g) ?? [])
      .length,
    1,
  );
  assert.equal(
    (importModule.match(/app_data\.confirm_personal_target_csv_import_v1/g) ?? [])
      .length,
    1,
  );
  assert.doesNotMatch(importModule, /app_private|console\.|\blogger\b/);
  assert.match(
    productionServer,
    /"\/v1\/promotion-targets\/imports\/csv\/preview"/,
  );
  assert.match(
    productionServer,
    /"\/v1\/promotion-targets\/imports\/csv\/confirm"/,
  );
});

function source(path: string): string {
  return readFileSync(fileURLToPath(new URL(path, import.meta.url)), "utf8");
}
