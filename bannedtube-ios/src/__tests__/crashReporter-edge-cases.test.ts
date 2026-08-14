import AsyncStorage from "@react-native-async-storage/async-storage";
import { CrashReporter } from "../lib/crashReporter";

beforeEach(() => {
  jest.clearAllMocks();
  (AsyncStorage as any).__resetStore();
});

describe("CrashReporter edge cases", () => {
  it("captures error with stack trace", async () => {
    const error = new Error("Stack test");
    await CrashReporter.captureException(error);
    const logs = await CrashReporter.getCrashLogs();
    expect(logs[0].stack).toBeDefined();
    expect(logs[0].stack).toContain("Stack test");
  });

  it("metadata is optional", async () => {
    await CrashReporter.captureException(new Error("No metadata"));
    const logs = await CrashReporter.getCrashLogs();
    expect(logs[0].message).toBe("No metadata");
    expect(logs[0].metadata).toBeUndefined();
  });

  it("captureMessage creates an Error internally", async () => {
    await CrashReporter.captureMessage("Test message", { source: "test" });
    const logs = await CrashReporter.getCrashLogs();
    expect(logs[0].message).toBe("Test message");
    expect(logs[0].metadata?.source).toBe("test");
  });

  it("logs are in reverse chronological order", async () => {
    await CrashReporter.captureException(new Error("First"));
    await new Promise((r) => setTimeout(r, 10));
    await CrashReporter.captureException(new Error("Second"));
    const logs = await CrashReporter.getCrashLogs();
    expect(logs[0].message).toBe("Second");
    expect(logs[1].message).toBe("First");
    const t0 = new Date(logs[0].timestamp).getTime();
    const t1 = new Date(logs[1].timestamp).getTime();
    expect(t0).toBeGreaterThanOrEqual(t1);
  });

  it("exactly 50 log cap — oldest dropped", async () => {
    for (let i = 0; i < 55; i++) {
      await CrashReporter.captureException(new Error(`Error ${i}`));
    }
    const logs = await CrashReporter.getCrashLogs();
    expect(logs).toHaveLength(50);
    expect(logs[0].message).toBe("Error 54");
  });

  it("clearLogs then getCrashLogs returns empty", async () => {
    await CrashReporter.captureException(new Error("Will be cleared"));
    await CrashReporter.clearLogs();
    const logs = await CrashReporter.getCrashLogs();
    expect(logs).toEqual([]);
  });

  it("handles corrupted storage gracefully", async () => {
    await AsyncStorage.setItem("bt_crash_log", "invalid json {{{");
    const logs = await CrashReporter.getCrashLogs();
    expect(logs).toEqual([]);
  });

  it("init sets global error handler", async () => {
    await CrashReporter.init();
    expect(ErrorUtils.setGlobalHandler).toHaveBeenCalled();
  });

  it("global handler captures and chains to default", async () => {
    const defaultHandler = jest.fn();
    (ErrorUtils.getGlobalHandler as jest.Mock).mockReturnValue(defaultHandler);

    await CrashReporter.init();
    const handler = (ErrorUtils.setGlobalHandler as jest.Mock).mock.calls[0][0];

    const error = new Error("Global crash");
    await handler(error, true);

    const logs = await CrashReporter.getCrashLogs();
    expect(logs.length).toBeGreaterThan(0);
    expect(defaultHandler).toHaveBeenCalledWith(error, true);
  });

  it("timestamp is valid ISO date", async () => {
    await CrashReporter.captureException(new Error("Time check"));
    const logs = await CrashReporter.getCrashLogs();
    const date = new Date(logs[0].timestamp);
    expect(date.getTime()).toBeGreaterThan(0);
    expect(logs[0].timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });
});
