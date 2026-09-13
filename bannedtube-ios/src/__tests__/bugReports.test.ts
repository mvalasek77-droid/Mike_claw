import AsyncStorage from "@react-native-async-storage/async-storage";
import {
  BugReports,
  formatReport,
  collectDiagnostics,
  BUG_CATEGORIES,
  APP_VERSION,
  type BugReport,
} from "../lib/bugReports";

describe("bug reports", () => {
  beforeEach(async () => {
    await AsyncStorage.clear();
  });

  describe("create", () => {
    it("stores a report and returns it", async () => {
      const report = await BugReports.create({
        category: "Playback",
        summary: "Video stalls at 10s",
        details: "Playback freezes but audio keeps going.",
        includeDiagnostics: false,
      });

      expect(report.id).toBeTruthy();
      expect(report.category).toBe("Playback");
      expect(report.summary).toBe("Video stalls at 10s");
      expect(new Date(report.createdAt).toString()).not.toBe("Invalid Date");

      const all = await BugReports.list();
      expect(all).toHaveLength(1);
      expect(all[0].id).toBe(report.id);
    });

    it("trims whitespace from free-text fields", async () => {
      const report = await BugReports.create({
        category: "Search",
        summary: "   padded summary   ",
        details: "\n  padded details \n",
        steps: "  1. do a thing  ",
        includeDiagnostics: false,
      });
      expect(report.summary).toBe("padded summary");
      expect(report.details).toBe("padded details");
      expect(report.steps).toBe("1. do a thing");
    });

    it("defaults steps to an empty string when omitted", async () => {
      const report = await BugReports.create({
        category: "Comments",
        summary: "s",
        details: "d",
        includeDiagnostics: false,
      });
      expect(report.steps).toBe("");
    });

    it("omits diagnostics unless the reporter opts in", async () => {
      const without = await BugReports.create({
        category: "Layout or visuals",
        summary: "s",
        details: "d",
        includeDiagnostics: false,
      });
      expect(without.diagnostics).toBeUndefined();

      const withDiag = await BugReports.create({
        category: "Layout or visuals",
        summary: "s",
        details: "d",
        includeDiagnostics: true,
      });
      expect(withDiag.diagnostics).toBeDefined();
      expect(withDiag.diagnostics!.appVersion).toBe(APP_VERSION);
      expect(withDiag.diagnostics!.platform).toBeTruthy();
    });

    it("keeps the newest report first", async () => {
      await BugReports.create({
        category: "Playback",
        summary: "first",
        details: "d",
        includeDiagnostics: false,
      });
      await BugReports.create({
        category: "Playback",
        summary: "second",
        details: "d",
        includeDiagnostics: false,
      });
      const all = await BugReports.list();
      expect(all.map((r) => r.summary)).toEqual(["second", "first"]);
    });

    it("records the video a report was filed against", async () => {
      const report = await BugReports.create({
        category: "Playback",
        summary: "s",
        details: "d",
        videoId: "sintel",
        includeDiagnostics: false,
      });
      expect(report.videoId).toBe("sintel");
    });
  });

  describe("remove and clear", () => {
    it("removes only the named report", async () => {
      const a = await BugReports.create({
        category: "Playback",
        summary: "a",
        details: "d",
        includeDiagnostics: false,
      });
      await BugReports.create({
        category: "Playback",
        summary: "b",
        details: "d",
        includeDiagnostics: false,
      });

      await BugReports.remove(a.id);
      const all = await BugReports.list();
      expect(all).toHaveLength(1);
      expect(all[0].summary).toBe("b");
    });

    it("removing a missing id leaves the list untouched", async () => {
      await BugReports.create({
        category: "Playback",
        summary: "a",
        details: "d",
        includeDiagnostics: false,
      });
      await BugReports.remove("does-not-exist");
      expect(await BugReports.list()).toHaveLength(1);
    });

    it("clear empties the list", async () => {
      await BugReports.create({
        category: "Playback",
        summary: "a",
        details: "d",
        includeDiagnostics: false,
      });
      await BugReports.clear();
      expect(await BugReports.list()).toEqual([]);
    });
  });

  describe("list", () => {
    it("returns an empty array when nothing is stored", async () => {
      expect(await BugReports.list()).toEqual([]);
    });

    it("returns an empty array when stored data is corrupt", async () => {
      await AsyncStorage.setItem("bt_bug_reports", "not json{{");
      expect(await BugReports.list()).toEqual([]);
    });
  });

  describe("formatReport", () => {
    const base: BugReport = {
      id: "bug_1",
      category: "Playback",
      summary: "Video stalls",
      details: "It freezes.",
      steps: "1. Open a video",
      createdAt: new Date("2026-01-15T10:00:00Z").toISOString(),
    };

    it("includes the core fields", () => {
      const text = formatReport(base);
      expect(text).toContain("BannedTube bug report");
      expect(text).toContain("Playback");
      expect(text).toContain("Video stalls");
      expect(text).toContain("It freezes.");
      expect(text).toContain("1. Open a video");
    });

    it("omits the steps section when there are none", () => {
      const text = formatReport({ ...base, steps: "   " });
      expect(text).not.toContain("Steps to reproduce");
    });

    it("says so plainly when diagnostics were withheld", () => {
      expect(formatReport(base)).toContain(
        "Diagnostics were not attached"
      );
    });

    it("renders attached diagnostics including recorded errors", () => {
      const text = formatReport({
        ...base,
        diagnostics: {
          appVersion: "1.0.0",
          platform: "ios",
          osVersion: "18.2",
          recentErrors: [
            { message: "Boom", timestamp: "2026-01-15T09:59:00Z" },
          ],
        },
      });
      expect(text).toContain("App version: 1.0.0");
      expect(text).toContain("ios 18.2");
      expect(text).toContain("Boom");
    });

    it("notes when no errors were recorded", () => {
      const text = formatReport({
        ...base,
        diagnostics: {
          appVersion: "1.0.0",
          platform: "ios",
          osVersion: "18.2",
          recentErrors: [],
        },
      });
      expect(text).toContain("Recent errors: none recorded");
    });

    it("includes the video id when the report came from a video", () => {
      expect(formatReport({ ...base, videoId: "sintel" })).toContain("sintel");
    });
  });

  describe("collectDiagnostics", () => {
    it("reports app version and platform", async () => {
      const d = await collectDiagnostics();
      expect(d.appVersion).toBe(APP_VERSION);
      expect(d.platform).toBeTruthy();
      expect(Array.isArray(d.recentErrors)).toBe(true);
    });

    it("caps recorded errors at five", async () => {
      const logs = Array.from({ length: 12 }, (_, i) => ({
        message: `err ${i}`,
        timestamp: new Date().toISOString(),
      }));
      await AsyncStorage.setItem("bt_crash_log", JSON.stringify(logs));
      const d = await collectDiagnostics();
      expect(d.recentErrors.length).toBeLessThanOrEqual(5);
    });
  });

  describe("categories", () => {
    it("exposes a non-empty, unique category list", () => {
      expect(BUG_CATEGORIES.length).toBeGreaterThan(0);
      expect(new Set(BUG_CATEGORIES).size).toBe(BUG_CATEGORIES.length);
    });
  });
});
