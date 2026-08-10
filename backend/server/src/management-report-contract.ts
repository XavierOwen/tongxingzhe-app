export interface CanonicalManagementReportRequest {
  readonly reportId: "contact_sessions_by_channel_two_periods";
  readonly reportVersion: 1;
  readonly metricId: "contact_sessions";
  readonly metricVersion: 1;
  readonly dimension: "channel";
  readonly periodGrain: "week";
  readonly comparisonPeriodCount: 2;
  readonly periodBoundaryId: "iso_week_monday_v1";
  readonly privacyPolicy: "management_contact_session_privacy_v1";
  readonly requiredCapability: "view_anonymous_analytics";
  readonly queryFingerprint:
    "management-report:contact_sessions_by_channel_two_periods:v1";
}

export type CanonicalManagementReportRequestResult = {
  readonly ok: true;
  readonly request: CanonicalManagementReportRequest;
} | {
  readonly ok: false;
  readonly error: "invalid_management_report_request";
};

export type ManagementReportAuditResultStatus =
  | "completed"
  | "forbidden"
  | "failed";

export interface ManagementReportAuditEnvelope {
  readonly appUserId: string;
  readonly projectId: string;
  readonly reportId: CanonicalManagementReportRequest["reportId"];
  readonly reportVersion: CanonicalManagementReportRequest["reportVersion"];
  readonly queryFingerprint:
    CanonicalManagementReportRequest["queryFingerprint"];
  readonly requestedAtUtc: string;
  readonly resultStatus: ManagementReportAuditResultStatus;
}

export interface ManagementReportAuditEnvelopeInput {
  readonly appUserId: string;
  readonly projectId: string;
  readonly request: CanonicalManagementReportRequest;
  readonly requestedAtUtc: Date;
  readonly resultStatus: ManagementReportAuditResultStatus;
}

const contactSessionsByChannelTwoPeriods = Object.freeze({
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
} satisfies CanonicalManagementReportRequest);

/**
 * Accepts only the registered client request shape. Trusted project, time zone,
 * cutoff, and caller identity must come from the later authorization flow.
 */
export function canonicalizeManagementReportRequest(
  value: unknown,
): CanonicalManagementReportRequestResult {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return invalidRequest;
  }
  const keys = Object.keys(value).sort();
  if (
    keys.length !== 2 ||
    keys[0] !== "report_id" ||
    keys[1] !== "report_version"
  ) {
    return invalidRequest;
  }
  const request = value as {
    readonly report_id?: unknown;
    readonly report_version?: unknown;
  };
  if (
    request.report_id !== contactSessionsByChannelTwoPeriods.reportId ||
    request.report_version !== contactSessionsByChannelTwoPeriods.reportVersion
  ) {
    return invalidRequest;
  }
  return {ok: true, request: contactSessionsByChannelTwoPeriods};
}

const invalidRequest = Object.freeze({
  ok: false,
  error: "invalid_management_report_request",
} satisfies CanonicalManagementReportRequestResult);

/** Builds audit metadata without report cells or suppressed source values. */
export function createManagementReportAuditEnvelope(
  input: ManagementReportAuditEnvelopeInput,
): ManagementReportAuditEnvelope {
  if (
    !uuidPattern.test(input.appUserId) ||
    !uuidPattern.test(input.projectId) ||
    input.request !== contactSessionsByChannelTwoPeriods ||
    !(input.requestedAtUtc instanceof Date) ||
    !Number.isFinite(input.requestedAtUtc.getTime()) ||
    !auditResultStatuses.has(input.resultStatus)
  ) {
    throw new TypeError("invalid_management_report_audit_envelope");
  }
  return Object.freeze({
    appUserId: input.appUserId,
    projectId: input.projectId,
    reportId: input.request.reportId,
    reportVersion: input.request.reportVersion,
    queryFingerprint: input.request.queryFingerprint,
    requestedAtUtc: input.requestedAtUtc.toISOString(),
    resultStatus: input.resultStatus,
  });
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const auditResultStatuses = new Set<ManagementReportAuditResultStatus>([
  "completed",
  "forbidden",
  "failed",
]);
