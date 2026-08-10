import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  canonicalizeManagementReportRequest,
  createManagementReportAuditEnvelope,
} from "../src/management-report-contract.js";

test("registered report request becomes one stable canonical query", () => {
  const result = canonicalizeManagementReportRequest({
    report_id: "contact_sessions_by_channel_two_periods",
    report_version: 1,
  });

  assert.deepEqual(result, {
    ok: true,
    request: {
      reportId: "contact_sessions_by_channel_two_periods",
      reportVersion: 1,
      metricId: "contact_sessions",
      metricVersion: 1,
      dimension: "channel",
      periodGrain: "week",
      comparisonPeriodCount: 2,
      periodBoundaryId: "iso_week_monday_v1",
      privacyPolicy: "management_contact_session_privacy_v1",
      requiredCapability: "view_anonymous_analytics",
      queryFingerprint:
        "management-report:contact_sessions_by_channel_two_periods:v1",
    },
  });
});

test("unknown reports and caller-controlled query fields fail closed", () => {
  const invalidRequests = [
    null,
    [],
    {},
    {report_id: "unknown", report_version: 1},
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 2,
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: "1",
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      project_id: "33333333-3333-4333-8333-333333333333",
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      time_zone: "UTC",
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      from_utc: "2030-01-01T00:00:00Z",
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      dimensions: ["region"],
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      filters: {},
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      export_fields: ["value_count"],
    },
    {
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      exclude_app_user_id: "11111111-1111-4111-8111-111111111111",
    },
  ];

  for (const value of invalidRequests) {
    assert.deepEqual(canonicalizeManagementReportRequest(value), {
      ok: false,
      error: "invalid_management_report_request",
    });
  }
});

test("audit envelope records trusted scope without report values", () => {
  const canonical = canonicalizeManagementReportRequest({
    report_id: "contact_sessions_by_channel_two_periods",
    report_version: 1,
  });
  assert.equal(canonical.ok, true);
  if (!canonical.ok) return;

  const envelope = createManagementReportAuditEnvelope({
    appUserId: "11111111-1111-4111-8111-111111111111",
    projectId: "33333333-3333-4333-8333-333333333333",
    request: canonical.request,
    requestedAtUtc: new Date("2030-01-15T12:00:00.000Z"),
    resultStatus: "completed",
  });

  assert.deepEqual(envelope, {
    appUserId: "11111111-1111-4111-8111-111111111111",
    projectId: "33333333-3333-4333-8333-333333333333",
    reportId: "contact_sessions_by_channel_two_periods",
    reportVersion: 1,
    queryFingerprint:
      "management-report:contact_sessions_by_channel_two_periods:v1",
    requestedAtUtc: "2030-01-15T12:00:00.000Z",
    resultStatus: "completed",
  });
  assert.deepEqual(Object.keys(envelope), [
    "appUserId",
    "projectId",
    "reportId",
    "reportVersion",
    "queryFingerprint",
    "requestedAtUtc",
    "resultStatus",
  ]);
});

test("audit envelope rejects invalid trusted metadata and forged requests", () => {
  const canonical = canonicalizeManagementReportRequest({
    report_id: "contact_sessions_by_channel_two_periods",
    report_version: 1,
  });
  assert.equal(canonical.ok, true);
  if (!canonical.ok) return;
  const validInput = {
    appUserId: "11111111-1111-4111-8111-111111111111",
    projectId: "33333333-3333-4333-8333-333333333333",
    request: canonical.request,
    requestedAtUtc: new Date("2030-01-15T12:00:00.000Z"),
    resultStatus: "completed" as const,
  };

  assert.throws(
    () => createManagementReportAuditEnvelope({...validInput, appUserId: "x"}),
    /invalid_management_report_audit_envelope/,
  );
  assert.throws(
    () => createManagementReportAuditEnvelope({...validInput, projectId: "x"}),
    /invalid_management_report_audit_envelope/,
  );
  assert.throws(
    () => createManagementReportAuditEnvelope({
      ...validInput,
      requestedAtUtc: new Date(Number.NaN),
    }),
    /invalid_management_report_audit_envelope/,
  );
  assert.throws(
    () => createManagementReportAuditEnvelope({
      ...validInput,
      request: {...canonical.request},
    }),
    /invalid_management_report_audit_envelope/,
  );
  assert.throws(
    () => createManagementReportAuditEnvelope({
      ...validInput,
      resultStatus: "displayed" as unknown as "completed",
    }),
    /invalid_management_report_audit_envelope/,
  );
});

test("Backend agrees with the shared report request fixture", () => {
  const fixturePath = fileURLToPath(
    new URL(
      "../../../database/fixtures/shared/management_report_requests_v1.csv",
      import.meta.url,
    ),
  );
  const [header, ...rows] = readFileSync(fixturePath, "utf8")
    .trim()
    .split("\n");
  assert.equal(
    header,
    "case_name,report_id,report_version,extra_key,extra_value,expected_status,expected_fingerprint",
  );

  for (const row of rows) {
    const columns = row.split(",");
    assert.equal(columns.length, 7);
    const [
      caseName,
      reportId,
      reportVersion,
      extraKey,
      extraValue,
      expectedStatus,
      expectedFingerprint,
    ] = columns as [string, string, string, string, string, string, string];
    assert.ok(caseName);
    const request: Record<string, unknown> = {
      report_id: reportId,
      report_version: Number(reportVersion),
    };
    if (extraKey !== "") request[extraKey] = extraValue;

    const result = canonicalizeManagementReportRequest(request);
    assert.equal(result.ok ? "accepted" : "rejected", expectedStatus, caseName);
    assert.equal(
      result.ok ? result.request.queryFingerprint : "",
      expectedFingerprint,
      caseName,
    );
  }
});
