global.__DEV__ = true;
global.ErrorUtils = {
  getGlobalHandler: jest.fn(() => () => {}),
  setGlobalHandler: jest.fn(),
};

jest.mock("@react-native-async-storage/async-storage", () => {
  let store = {};
  return {
    getItem: jest.fn((key) => Promise.resolve(store[key] || null)),
    setItem: jest.fn((key, value) => {
      store[key] = value;
      return Promise.resolve();
    }),
    removeItem: jest.fn((key) => {
      delete store[key];
      return Promise.resolve();
    }),
    clear: jest.fn(() => {
      store = {};
      return Promise.resolve();
    }),
    __getStore: () => store,
    __resetStore: () => {
      store = {};
    },
  };
});

// The suite runs in a plain node environment, so react-native's ESM entry
// point is never transformed. Only the pieces the library code touches are
// stubbed here; component rendering is not exercised by these tests.
jest.mock("react-native", () => ({
  Platform: {
    OS: "ios",
    Version: "18.0",
    select: (spec) => spec.ios ?? spec.default,
  },
}));

jest.mock("expo-haptics", () => ({
  impactAsync: jest.fn(),
  selectionAsync: jest.fn(),
  notificationAsync: jest.fn(),
  ImpactFeedbackStyle: { Light: "light", Medium: "medium", Heavy: "heavy" },
  NotificationFeedbackType: { Success: "success", Error: "error", Warning: "warning" },
}));

jest.mock("expo-sharing", () => ({
  isAvailableAsync: jest.fn(() => Promise.resolve(false)),
  shareAsync: jest.fn(),
}));

jest.mock("expo-clipboard", () => ({
  setStringAsync: jest.fn(() => Promise.resolve()),
  getStringAsync: jest.fn(() => Promise.resolve("")),
}));

jest.mock("expo-blur", () => ({
  BlurView: "BlurView",
}));

jest.mock("expo-linear-gradient", () => ({
  LinearGradient: "LinearGradient",
}));

jest.mock("expo-status-bar", () => ({
  StatusBar: "StatusBar",
}));
