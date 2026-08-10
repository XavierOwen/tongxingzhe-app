export interface ManagementReportPeriod {
  readonly startUtc: string;
  readonly untilUtc: string;
}

export interface ManagementReportPeriods {
  readonly periodBoundaryId: "iso_week_monday_v1";
  readonly reportingTimeZone: string;
  readonly dataCutoffUtc: string;
  readonly previousPeriod: ManagementReportPeriod;
  readonly currentPeriod: ManagementReportPeriod;
}

export interface ManagementReportPeriodContext {
  readonly reportingTimeZone: string;
  readonly dataCutoffUtc: Date;
}

interface LocalDate {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

interface LocalDateTime extends LocalDate {
  readonly hour: number;
  readonly minute: number;
  readonly second: number;
}

/**
 * Resolves the latest two complete ISO weeks before a trusted data cutoff.
 * The caller must obtain the time zone and cutoff from server-side context.
 */
export function resolveManagementReportPeriods(
  value: unknown,
): ManagementReportPeriods {
  if (!isExactPeriodContext(value)) throw invalidPeriodContext();

  const timeZone = value.reportingTimeZone;
  const cutoff = value.dataCutoffUtc;
  const formatter = timeZoneFormatter(timeZone);
  const cutoffLocalDate = localDateTime(cutoff, formatter);
  const isoDay = isoDayOfWeek(cutoffLocalDate);
  const currentUntilLocal = shiftLocalDate(cutoffLocalDate, -(isoDay - 1));
  const currentStartLocal = shiftLocalDate(currentUntilLocal, -7);
  const previousStartLocal = shiftLocalDate(currentUntilLocal, -14);

  const previousStart = zonedMidnightToUtc(previousStartLocal, formatter);
  const currentStart = zonedMidnightToUtc(currentStartLocal, formatter);
  const currentUntil = zonedMidnightToUtc(currentUntilLocal, formatter);
  if (
    previousStart.getTime() >= currentStart.getTime() ||
    currentStart.getTime() >= currentUntil.getTime() ||
    currentUntil.getTime() > cutoff.getTime()
  ) {
    throw invalidPeriodContext();
  }

  return Object.freeze({
    periodBoundaryId: "iso_week_monday_v1",
    reportingTimeZone: timeZone,
    dataCutoffUtc: cutoff.toISOString(),
    previousPeriod: Object.freeze({
      startUtc: previousStart.toISOString(),
      untilUtc: currentStart.toISOString(),
    }),
    currentPeriod: Object.freeze({
      startUtc: currentStart.toISOString(),
      untilUtc: currentUntil.toISOString(),
    }),
  });
}

function isExactPeriodContext(value: unknown): value is ManagementReportPeriodContext {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const keys = Object.keys(value).sort();
  if (
    keys.length !== 2 ||
    keys[0] !== "dataCutoffUtc" ||
    keys[1] !== "reportingTimeZone"
  ) {
    return false;
  }
  const context = value as Partial<ManagementReportPeriodContext>;
  return typeof context.reportingTimeZone === "string" &&
    validTimeZoneName(context.reportingTimeZone) &&
    context.dataCutoffUtc instanceof Date &&
    Number.isFinite(context.dataCutoffUtc.getTime());
}

function validTimeZoneName(value: string): boolean {
  if (
    value.length === 0 ||
    value.length > 100 ||
    value !== value.trim() ||
    (
      value !== "UTC" &&
      (
        !value.includes("/") ||
        value.startsWith("posix/") ||
        value.startsWith("right/")
      )
    )
  ) {
    return false;
  }
  try {
    new Intl.DateTimeFormat("en", {timeZone: value}).format(new Date(0));
    return true;
  } catch {
    return false;
  }
}

function timeZoneFormatter(timeZone: string): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    calendar: "iso8601",
    numberingSystem: "latn",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
}

function localDateTime(
  instant: Date,
  formatter: Intl.DateTimeFormat,
): LocalDateTime {
  const values = new Map(
    formatter.formatToParts(instant).map((part) => [part.type, part.value]),
  );
  const result = {
    year: Number(values.get("year")),
    month: Number(values.get("month")),
    day: Number(values.get("day")),
    hour: Number(values.get("hour")),
    minute: Number(values.get("minute")),
    second: Number(values.get("second")),
  };
  if (Object.values(result).some((part) => !Number.isInteger(part))) {
    throw invalidPeriodContext();
  }
  return result;
}

function isoDayOfWeek(date: LocalDate): number {
  const sundayBasedDay = new Date(
    Date.UTC(date.year, date.month - 1, date.day),
  ).getUTCDay();
  return sundayBasedDay === 0 ? 7 : sundayBasedDay;
}

function shiftLocalDate(date: LocalDate, dayCount: number): LocalDate {
  const shifted = new Date(
    Date.UTC(date.year, date.month - 1, date.day + dayCount),
  );
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

function zonedMidnightToUtc(
  date: LocalDate,
  formatter: Intl.DateTimeFormat,
): Date {
  const desiredLocalEpoch = Date.UTC(date.year, date.month - 1, date.day);
  let candidateEpoch = desiredLocalEpoch;
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const candidateParts = localDateTime(new Date(candidateEpoch), formatter);
    const representedLocalEpoch = Date.UTC(
      candidateParts.year,
      candidateParts.month - 1,
      candidateParts.day,
      candidateParts.hour,
      candidateParts.minute,
      candidateParts.second,
    );
    const correction = desiredLocalEpoch - representedLocalEpoch;
    if (correction === 0) return new Date(candidateEpoch);
    candidateEpoch += correction;
  }
  throw invalidPeriodContext();
}

function invalidPeriodContext(): TypeError {
  return new TypeError("invalid_management_report_period_context");
}
