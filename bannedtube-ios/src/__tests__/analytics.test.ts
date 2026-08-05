import AsyncStorage from "@react-native-async-storage/async-storage";
import { Analytics } from "../lib/analytics";

beforeEach(() => {
  jest.clearAllMocks();
  (AsyncStorage as any).__resetStore();
});

describe("Analytics", () => {
  it("tracks an event and flushes to storage", async () => {
    Analytics.track("test_event", { key: "value" });
    await new Promise((r) => setTimeout(r, 50));

    const events = await Analytics.getEvents();
    expect(events.length).toBeGreaterThan(0);
    expect(events[events.length - 1].name).toBe("test_event");
    expect(events[events.length - 1].properties).toEqual({ key: "value" });
  });

  it("tracks screenView events", async () => {
    Analytics.screenView("HomeScreen");
    await new Promise((r) => setTimeout(r, 50));

    const events = await Analytics.getEvents();
    const last = events[events.length - 1];
    expect(last.name).toBe("screen_view");
    expect(last.properties?.screen).toBe("HomeScreen");
  });

  it("tracks videoPlay events", async () => {
    Analytics.videoPlay("v1", "ch1");
    await new Promise((r) => setTimeout(r, 50));

    const events = await Analytics.getEvents();
    const last = events[events.length - 1];
    expect(last.name).toBe("video_play");
    expect(last.properties?.videoId).toBe("v1");
  });

  it("clears all events", async () => {
    Analytics.track("event1");
    await new Promise((r) => setTimeout(r, 50));
    await Analytics.clear();

    const events = await Analytics.getEvents();
    expect(events).toEqual([]);
  });

  it("includes timestamp on every event", async () => {
    Analytics.track("timed");
    await new Promise((r) => setTimeout(r, 50));

    const events = await Analytics.getEvents();
    const last = events[events.length - 1];
    expect(last.timestamp).toBeTruthy();
    expect(new Date(last.timestamp).getTime()).toBeGreaterThan(0);
  });
});
