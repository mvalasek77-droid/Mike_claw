import AsyncStorage from "@react-native-async-storage/async-storage";
import { Analytics } from "../lib/analytics";

beforeEach(async () => {
  jest.clearAllMocks();
  (AsyncStorage as any).__resetStore();
  await Analytics.clear();
});

describe("Analytics event coverage", () => {
  const flush = () => new Promise((r) => setTimeout(r, 50));

  describe("pre-defined events", () => {
    it("screenView tracks screen_view with screen name", async () => {
      Analytics.screenView("WatchScreen");
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "screen_view");
      expect(ev).toBeDefined();
      expect(ev!.properties?.screen).toBe("WatchScreen");
    });

    it("videoPlay tracks video_play with videoId and channelId", async () => {
      Analytics.videoPlay("v1", "ch1");
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "video_play");
      expect(ev!.properties?.videoId).toBe("v1");
      expect(ev!.properties?.channelId).toBe("ch1");
    });

    it("videoLike tracks video_like", async () => {
      Analytics.videoLike("v1");
      await flush();
      const events = await Analytics.getEvents();
      expect(events.find((e) => e.name === "video_like")).toBeDefined();
    });

    it("videoSave tracks video_save", async () => {
      Analytics.videoSave("v1");
      await flush();
      const events = await Analytics.getEvents();
      expect(events.find((e) => e.name === "video_save")).toBeDefined();
    });

    it("subscribe tracks subscribe event", async () => {
      Analytics.subscribe("ch1");
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "subscribe");
      expect(ev!.properties?.channelId).toBe("ch1");
    });

    it("search tracks query and resultCount", async () => {
      Analytics.search("test query", 5);
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "search");
      expect(ev!.properties?.query).toBe("test query");
      expect(ev!.properties?.resultCount).toBe(5);
    });

    it("share tracks videoId and method", async () => {
      Analytics.share("v1", "clipboard");
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "share");
      expect(ev!.properties?.method).toBe("clipboard");
    });

    it("commentPost tracks comment_post", async () => {
      Analytics.commentPost("v1");
      await flush();
      const events = await Analytics.getEvents();
      expect(events.find((e) => e.name === "comment_post")).toBeDefined();
    });

    it("tabSwitch tracks tab_switch", async () => {
      Analytics.tabSwitch("trending");
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "tab_switch");
      expect(ev!.properties?.tab).toBe("trending");
    });

    it("onboardingStep tracks step number", async () => {
      Analytics.onboardingStep(2);
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "onboarding_step");
      expect(ev!.properties?.step).toBe(2);
    });

    it("onboardingComplete tracks subscription count", async () => {
      Analytics.onboardingComplete(3);
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "onboarding_complete");
      expect(ev!.properties?.subscriptionCount).toBe(3);
    });

    it("aiGenerate tracks topic", async () => {
      Analytics.aiGenerate("technology");
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "ai_generate");
      expect(ev!.properties?.topic).toBe("technology");
    });

    it("appLaunch tracks app_launch", async () => {
      Analytics.appLaunch();
      await flush();
      const events = await Analytics.getEvents();
      expect(events.find((e) => e.name === "app_launch")).toBeDefined();
    });

    it("error tracks message and screen", async () => {
      Analytics.error("Something broke", "HomeScreen");
      await flush();
      const events = await Analytics.getEvents();
      const ev = events.find((e) => e.name === "error");
      expect(ev!.properties?.message).toBe("Something broke");
      expect(ev!.properties?.screen).toBe("HomeScreen");
    });
  });

  describe("buffer management", () => {
    it("caps buffer at 500 events", async () => {
      for (let i = 0; i < 510; i++) {
        Analytics.track(`event_${i}`);
      }
      await flush();
      const events = await Analytics.getEvents();
      expect(events.length).toBeLessThanOrEqual(500);
    });

    it("events include ISO timestamps", async () => {
      Analytics.track("timed_event");
      await flush();
      const events = await Analytics.getEvents();
      const last = events[events.length - 1];
      expect(last.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it("clear removes all events and buffer", async () => {
      Analytics.track("before_clear");
      await flush();
      await Analytics.clear();
      const events = await Analytics.getEvents();
      expect(events).toEqual([]);
    });
  });
});
