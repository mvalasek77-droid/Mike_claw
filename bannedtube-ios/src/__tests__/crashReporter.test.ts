import AsyncStorage from "@react-native-async-storage/async-storage";
import { CrashReporter } from "../lib/crashReporter";

beforeEach(() => {
  jest.clearAllMocks();
  (AsyncStorage as any).__resetStore();
});

describe("CrashReporter", () => {
  it("captures an exception with message and stack", async () => {
    const error = new Error("Test crash");
    await CrashReporter.captureException(error, { screen: "HomeScreen" });

    const logs = await CrashReporter.getCrashLogs();
    expect(logs).toHaveLength(1);
    expect(logs[0].message).toBe("Test crash");
    expect(logs[0].metadata?.screen).toBe("HomeScreen");
    expect(logs[0].timestamp).toBeTruthy();
  });

  it("captures a message as an error", async () => {
    await CrashReporter.captureMessage("Something went wrong");

    const logs = await CrashReporter.getCrashLogs();
    expect(logs).toHaveLength(1);
    expect(logs[0].message).toBe("Something went wrong");
  });

  it("stores multiple crash logs in reverse chronological order", async () => {
    await CrashReporter.captureException(new Error("First"));
    await CrashReporter.captureException(new Error("Second"));

    const logs = await CrashReporter.getCrashLogs();
    expect(logs).toHaveLength(2);
    expect(logs[0].message).toBe("Second");
    expect(logs[1].message).toBe("First");
  });

  it("caps at 50 crash logs", async () => {
    for (let i = 0; i < 60; i++) {
      await CrashReporter.captureException(new Error(`Crash ${i}`));
    }

    const logs = await CrashReporter.getCrashLogs();
    expect(logs.length).toBeLessThanOrEqual(50);
  });

  it("clears all logs", async () => {
    await CrashReporter.captureException(new Error("Test"));
    await CrashReporter.clearLogs();

    const logs = await CrashReporter.getCrashLogs();
    expect(logs).toEqual([]);
  });
});
