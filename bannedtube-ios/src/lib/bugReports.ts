import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";
import { CrashReporter } from "./crashReporter";

const BUG_REPORTS_KEY = "bt_bug_reports";
const MAX_REPORTS = 50;

/** Kept in step with `expo.version` in app.json. */
export const APP_VERSION = "1.0.0";

/**
 * Where a finished report is sent. There is no backend, so a report is composed
 * on-device and handed to the OS share sheet — the person choosing where it
 * goes. Set this to a real inbox to offer a one-tap email option.
 */
export const SUPPORT_EMAIL = "";

export const BUG_CATEGORIES = [
  "Playback",
  "Crash or freeze",
  "Layout or visuals",
  "Search",
  "Comments",
  "Saving or history",
  "Something else",
] as const;

export type BugCategory = (typeof BUG_CATEGORIES)[number];

export interface BugReportDiagnostics {
  appVersion: string;
  platform: string;
  osVersion: string;
  /** Message + timestamp of the most recent crashes, newest first. */
  recentErrors: { message: string; timestamp: string }[];
}

export interface BugReport {
  id: string;
  category: BugCategory;
  summary: string;
  details: string;
  /** What the person did before the problem appeared. Optional. */
  steps: string;
  /** Set when the report was filed from a specific video. */
  videoId?: string;
  createdAt: string;
  /** Present only when the person opted in to attaching diagnostics. */
  diagnostics?: BugReportDiagnostics;
}

export interface NewBugReport {
  category: BugCategory;
  summary: string;
  details: string;
  steps?: string;
  videoId?: string;
  includeDiagnostics: boolean;
}

function osVersion(): string {
  return String(Platform.Version ?? "unknown");
}

/**
 * Collects the technical context that makes a report actionable. Only ever
 * called when the person has opted in — nothing here is gathered otherwise.
 */
export async function collectDiagnostics(): Promise<BugReportDiagnostics> {
  let recentErrors: { message: string; timestamp: string }[] = [];
  try {
    const logs = await CrashReporter.getCrashLogs();
    recentErrors = logs.slice(0, 5).map((l) => ({
      message: l.message,
      timestamp: l.timestamp,
    }));
  } catch {
    // A failure to read the crash log must not block filing a report.
  }
  return {
    appVersion: APP_VERSION,
    platform: Platform.OS,
    osVersion: osVersion(),
    recentErrors,
  };
}

/** Renders a report as the plain text that gets shared, mailed or copied. */
export function formatReport(report: BugReport): string {
  const lines: string[] = [
    `BannedTube bug report`,
    ``,
    `Category: ${report.category}`,
    `Summary:  ${report.summary}`,
    `Filed:    ${new Date(report.createdAt).toLocaleString()}`,
  ];

  if (report.videoId) lines.push(`Video:    ${report.videoId}`);

  lines.push(``, `What happened`, report.details);

  if (report.steps.trim()) {
    lines.push(``, `Steps to reproduce`, report.steps);
  }

  if (report.diagnostics) {
    const d = report.diagnostics;
    lines.push(
      ``,
      `Diagnostics`,
      `App version: ${d.appVersion}`,
      `Platform:    ${d.platform} ${d.osVersion}`
    );
    if (d.recentErrors.length > 0) {
      lines.push(`Recent errors:`);
      for (const e of d.recentErrors) {
        lines.push(`  - [${e.timestamp}] ${e.message}`);
      }
    } else {
      lines.push(`Recent errors: none recorded`);
    }
  } else {
    lines.push(``, `Diagnostics were not attached to this report.`);
  }

  return lines.join("\n");
}

/**
 * Date.now() alone collides when two records are created in the same
 * millisecond, which makes ids unusable as list keys or delete targets.
 */
function newId(): string {
  return `bug_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

export const BugReports = {
  async list(): Promise<BugReport[]> {
    try {
      const raw = await AsyncStorage.getItem(BUG_REPORTS_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  },

  async create(input: NewBugReport): Promise<BugReport> {
    const report: BugReport = {
      id: newId(),
      category: input.category,
      summary: input.summary.trim(),
      details: input.details.trim(),
      steps: (input.steps ?? "").trim(),
      videoId: input.videoId,
      createdAt: new Date().toISOString(),
      diagnostics: input.includeDiagnostics
        ? await collectDiagnostics()
        : undefined,
    };

    const existing = await this.list();
    existing.unshift(report);
    if (existing.length > MAX_REPORTS) existing.length = MAX_REPORTS;
    await AsyncStorage.setItem(BUG_REPORTS_KEY, JSON.stringify(existing));
    return report;
  },

  async remove(id: string): Promise<void> {
    const existing = await this.list();
    const next = existing.filter((r) => r.id !== id);
    await AsyncStorage.setItem(BUG_REPORTS_KEY, JSON.stringify(next));
  },

  async clear(): Promise<void> {
    await AsyncStorage.removeItem(BUG_REPORTS_KEY);
  },
};
