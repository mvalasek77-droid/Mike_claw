import AsyncStorage from "@react-native-async-storage/async-storage";

const ANALYTICS_KEY = "bt_analytics_events";
const MAX_BUFFERED = 500;

export interface AnalyticsEvent {
  name: string;
  properties?: Record<string, string | number | boolean>;
  timestamp: string;
}

let buffer: AnalyticsEvent[] = [];

export const Analytics = {
  track(name: string, properties?: Record<string, string | number | boolean>) {
    const event: AnalyticsEvent = {
      name,
      properties,
      timestamp: new Date().toISOString(),
    };
    buffer.push(event);
    if (buffer.length >= MAX_BUFFERED) {
      buffer = buffer.slice(-MAX_BUFFERED);
    }
    this.flush();
  },

  async flush() {
    if (buffer.length === 0) return;
    try {
      const existing = await AsyncStorage.getItem(ANALYTICS_KEY);
      const events: AnalyticsEvent[] = existing ? JSON.parse(existing) : [];
      events.push(...buffer);
      if (events.length > MAX_BUFFERED) {
        events.splice(0, events.length - MAX_BUFFERED);
      }
      await AsyncStorage.setItem(ANALYTICS_KEY, JSON.stringify(events));
      buffer = [];
    } catch {
      // Silently fail — analytics should never crash the app
    }
  },

  async getEvents(): Promise<AnalyticsEvent[]> {
    try {
      const raw = await AsyncStorage.getItem(ANALYTICS_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  },

  async clear() {
    buffer = [];
    await AsyncStorage.removeItem(ANALYTICS_KEY);
  },

  // Pre-defined events for type safety
  screenView(screen: string) {
    this.track("screen_view", { screen });
  },

  videoPlay(videoId: string, channelId: string) {
    this.track("video_play", { videoId, channelId });
  },

  videoLike(videoId: string) {
    this.track("video_like", { videoId });
  },

  videoSave(videoId: string) {
    this.track("video_save", { videoId });
  },

  subscribe(channelId: string) {
    this.track("subscribe", { channelId });
  },

  search(query: string, resultCount: number) {
    this.track("search", { query, resultCount });
  },

  share(videoId: string, method: string) {
    this.track("share", { videoId, method });
  },

  commentPost(videoId: string) {
    this.track("comment_post", { videoId });
  },

  tabSwitch(tab: string) {
    this.track("tab_switch", { tab });
  },

  onboardingStep(step: number) {
    this.track("onboarding_step", { step });
  },

  onboardingComplete(subscriptionCount: number) {
    this.track("onboarding_complete", { subscriptionCount });
  },

  aiGenerate(topic: string) {
    this.track("ai_generate", { topic });
  },

  appLaunch() {
    this.track("app_launch");
  },

  error(message: string, screen: string) {
    this.track("error", { message, screen });
  },
};
