import AsyncStorage from "@react-native-async-storage/async-storage";

const CRASH_LOG_KEY = "bt_crash_log";
const MAX_CRASH_LOGS = 50;

export interface CrashEntry {
  message: string;
  stack?: string;
  timestamp: string;
  screen?: string;
  metadata?: Record<string, string>;
}

export const CrashReporter = {
  async init() {
    const defaultHandler = ErrorUtils.getGlobalHandler();
    ErrorUtils.setGlobalHandler((error: Error, isFatal?: boolean) => {
      this.captureException(error, { fatal: String(isFatal ?? false) });
      if (defaultHandler) {
        defaultHandler(error, isFatal);
      }
    });
  },

  async captureException(
    error: Error,
    metadata?: Record<string, string>
  ) {
    const entry: CrashEntry = {
      message: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString(),
      metadata,
    };

    try {
      const raw = await AsyncStorage.getItem(CRASH_LOG_KEY);
      const logs: CrashEntry[] = raw ? JSON.parse(raw) : [];
      logs.unshift(entry);
      if (logs.length > MAX_CRASH_LOGS) logs.length = MAX_CRASH_LOGS;
      await AsyncStorage.setItem(CRASH_LOG_KEY, JSON.stringify(logs));
    } catch {
      // Last-resort: don't crash while reporting a crash
    }

    if (__DEV__) {
      console.error("[CrashReporter]", error.message, metadata);
    }
  },

  async captureMessage(message: string, metadata?: Record<string, string>) {
    this.captureException(new Error(message), metadata);
  },

  async getCrashLogs(): Promise<CrashEntry[]> {
    try {
      const raw = await AsyncStorage.getItem(CRASH_LOG_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  },

  async clearLogs() {
    await AsyncStorage.removeItem(CRASH_LOG_KEY);
  },
};
