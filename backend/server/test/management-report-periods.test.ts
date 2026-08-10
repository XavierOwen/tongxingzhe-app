import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  resolveManagementReportPeriods,
} from "../src/management-report-periods.js";

test("Backend resolves the shared complete-week period fixture", () => {
  const fixturePath = fileURLToPath(
    new URL(
      "../../../database/fixtures/shared/management_report_periods_v1.csv",
      import.meta.url,
    ),
  );
  const [header, ...rows] = readFileSync(fixturePath, "utf8")
    .trim()
    .split("\n");
  assert.equal(
    header,
    "case_name,reporting_time_zone,data_cutoff_utc,expected_status,expected_previous_start_utc,expected_previous_until_utc,expected_current_start_utc,expected_current_until_utc,expected_previous_hours,expected_current_hours",
  );

  for (const row of rows) {
    const columns = row.split(",");
    assert.equal(columns.length, 10);
    const [
      caseName,
      reportingTimeZone,
      dataCutoffUtc,
      expectedStatus,
      expectedPreviousStartUtc,
      expectedPreviousUntilUtc,
      expectedCurrentStartUtc,
      expectedCurrentUntilUtc,
      expectedPreviousHours,
      expectedCurrentHours,
    ] = columns as [
      string,
      string,
      string,
      string,
      string,
      string,
      string,
      string,
      string,
      string,
    ];

    if (expectedStatus === "rejected") {
      assert.throws(
        () => resolveManagementReportPeriods({
          reportingTimeZone,
          dataCutoffUtc: new Date(dataCutoffUtc),
        }),
        /invalid_management_report_period_context/,
        caseName,
      );
      continue;
    }

    const cutoff = new Date(dataCutoffUtc);
    const result = resolveManagementReportPeriods({
      reportingTimeZone,
      dataCutoffUtc: cutoff,
    });
    assert.deepEqual(result, {
      periodBoundaryId: "iso_week_monday_v1",
      reportingTimeZone,
      dataCutoffUtc,
      previousPeriod: {
        startUtc: expectedPreviousStartUtc,
        untilUtc: expectedPreviousUntilUtc,
      },
      currentPeriod: {
        startUtc: expectedCurrentStartUtc,
        untilUtc: expectedCurrentUntilUtc,
      },
    }, caseName);
    assert.equal(
      durationHours(result.previousPeriod),
      Number(expectedPreviousHours),
      caseName,
    );
    assert.equal(
      durationHours(result.currentPeriod),
      Number(expectedCurrentHours),
      caseName,
    );
    assert.equal(
      result.previousPeriod.untilUtc,
      result.currentPeriod.startUtc,
      caseName,
    );
    assert.ok(
      Date.parse(result.currentPeriod.untilUtc) <= cutoff.getTime(),
      caseName,
    );
    assert.equal(cutoff.toISOString(), dataCutoffUtc, caseName);
    assert.ok(Object.isFrozen(result), caseName);
    assert.ok(Object.isFrozen(result.previousPeriod), caseName);
    assert.ok(Object.isFrozen(result.currentPeriod), caseName);
  }
});

test("period resolver rejects invalid trusted values without mutating input", () => {
  const cutoff = new Date("2026-06-17T12:34:56.000Z");
  const input = Object.freeze({
    reportingTimeZone: "UTC",
    dataCutoffUtc: cutoff,
  });
  resolveManagementReportPeriods(input);
  assert.equal(cutoff.toISOString(), "2026-06-17T12:34:56.000Z");

  for (const value of [null, {}, [], "UTC"]) {
    assert.throws(
      () => resolveManagementReportPeriods(value as never),
      /invalid_management_report_period_context/,
    );
  }
  assert.throws(
    () => resolveManagementReportPeriods({
      reportingTimeZone: "UTC",
      dataCutoffUtc: new Date(Number.NaN),
    }),
    /invalid_management_report_period_context/,
  );
  assert.throws(
    () => resolveManagementReportPeriods({
      reportingTimeZone: "UTC",
      dataCutoffUtc: cutoff,
      projectId: "client-controlled",
    }),
    /invalid_management_report_period_context/,
  );
});

function durationHours(period: {readonly startUtc: string; readonly untilUtc: string}) {
  return (Date.parse(period.untilUtc) - Date.parse(period.startUtc)) / 3_600_000;
}
