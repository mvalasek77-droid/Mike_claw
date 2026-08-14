import AsyncStorage from "@react-native-async-storage/async-storage";
import { Storage } from "../lib/storage";

beforeEach(() => {
  jest.clearAllMocks();
  (AsyncStorage as any).__resetStore();
});

describe("Storage edge cases", () => {
  describe("like/dislike rapid toggling", () => {
    it("rapid like toggles settle to correct final state", async () => {
      await Storage.toggleLike("v1");
      await Storage.toggleLike("v1");
      await Storage.toggleLike("v1");
      const likes = await Storage.getLikedVideos();
      expect(likes).toContain("v1");
    });

    it("rapid dislike toggles settle to correct final state", async () => {
      await Storage.toggleDislike("v1");
      await Storage.toggleDislike("v1");
      await Storage.toggleDislike("v1");
      const dislikes = await Storage.getDislikedVideos();
      expect(dislikes).toContain("v1");
    });

    it("alternating like/dislike leaves only the last action", async () => {
      await Storage.toggleLike("v1");
      await Storage.toggleDislike("v1");
      await Storage.toggleLike("v1");
      await Storage.toggleDislike("v1");

      const likes = await Storage.getLikedVideos();
      const dislikes = await Storage.getDislikedVideos();
      expect(likes).not.toContain("v1");
      expect(dislikes).toContain("v1");
    });

    it("sequential likes on different videos are all stored", async () => {
      await Storage.toggleLike("v1");
      await Storage.toggleLike("v2");
      await Storage.toggleLike("v3");
      const likes = await Storage.getLikedVideos();
      expect(likes).toContain("v1");
      expect(likes).toContain("v2");
      expect(likes).toContain("v3");
    });
  });

  describe("subscription idempotence", () => {
    it("subscribe-unsubscribe-subscribe cycle is correct", async () => {
      expect(await Storage.toggleSubscription("ch1")).toBe(true);
      expect(await Storage.toggleSubscription("ch1")).toBe(false);
      expect(await Storage.toggleSubscription("ch1")).toBe(true);
      const subs = await Storage.getSubscriptions();
      expect(subs).toEqual(["ch1"]);
    });

    it("subscribing to many channels tracks all", async () => {
      for (let i = 0; i < 20; i++) {
        await Storage.toggleSubscription(`ch${i}`);
      }
      const subs = await Storage.getSubscriptions();
      expect(subs).toHaveLength(20);
    });
  });

  describe("watch history deduplication", () => {
    it("re-watching updates timestamp and progress", async () => {
      await Storage.addWatchHistory("v1", 25);
      const before = await Storage.getWatchHistory();
      const firstTimestamp = before[0].watchedAt;

      await new Promise((r) => setTimeout(r, 10));
      await Storage.addWatchHistory("v1", 80);
      const after = await Storage.getWatchHistory();

      expect(after).toHaveLength(1);
      expect(after[0].progressPercent).toBe(80);
      expect(after[0].watchedAt).not.toBe(firstTimestamp);
    });

    it("new videos prepend to history", async () => {
      await Storage.addWatchHistory("v1", 50);
      await Storage.addWatchHistory("v2", 30);
      const history = await Storage.getWatchHistory();
      expect(history[0].videoId).toBe("v2");
      expect(history[1].videoId).toBe("v1");
    });

    it("history cap preserves most recent 200", async () => {
      for (let i = 0; i < 205; i++) {
        await Storage.addWatchHistory(`v${i}`, 10);
      }
      const history = await Storage.getWatchHistory();
      expect(history).toHaveLength(200);
      expect(history[0].videoId).toBe("v204");
    });
  });

  describe("recent searches", () => {
    it("deduplicates by moving repeated query to front", async () => {
      await Storage.addRecentSearch("react");
      await Storage.addRecentSearch("native");
      await Storage.addRecentSearch("expo");
      await Storage.addRecentSearch("react");
      const searches = await Storage.getRecentSearches();
      expect(searches[0]).toBe("react");
      expect(searches).toHaveLength(3);
    });

    it("caps at exactly 10 entries", async () => {
      for (let i = 0; i < 12; i++) {
        await Storage.addRecentSearch(`query${i}`);
      }
      const searches = await Storage.getRecentSearches();
      expect(searches).toHaveLength(10);
      expect(searches[0]).toBe("query11");
    });

    it("clear then add works correctly", async () => {
      await Storage.addRecentSearch("old");
      await Storage.clearRecentSearches();
      await Storage.addRecentSearch("new");
      const searches = await Storage.getRecentSearches();
      expect(searches).toEqual(["new"]);
    });
  });

  describe("saved videos", () => {
    it("multiple saves are independent", async () => {
      await Storage.toggleSaved("v1");
      await Storage.toggleSaved("v2");
      await Storage.toggleSaved("v3");
      const saved = await Storage.getSavedVideos();
      expect(saved).toHaveLength(3);

      await Storage.toggleSaved("v2");
      const after = await Storage.getSavedVideos();
      expect(after).toHaveLength(2);
      expect(after).not.toContain("v2");
    });
  });

  describe("comments", () => {
    it("comments for different videos are stored together", async () => {
      await Storage.addComment("v1", "Hello");
      await Storage.addComment("v2", "World");
      const all = await Storage.getUserComments();
      expect(all).toHaveLength(2);
    });

    it("comment IDs are unique with spaced creation", async () => {
      const ids = new Set<string>();
      for (let i = 0; i < 5; i++) {
        const c = await Storage.addComment("v1", `Comment ${i}`);
        ids.add(c.id);
        await new Promise((r) => setTimeout(r, 2));
      }
      expect(ids.size).toBe(5);
    });

    it("reply parentId links back to parent comment", async () => {
      const parent = await Storage.addComment("v1", "Parent");
      const reply = await Storage.addComment("v1", "Reply", parent.id);
      expect(reply.parentId).toBe(parent.id);
      expect(reply.videoId).toBe("v1");
    });
  });

  describe("onboarding flag", () => {
    it("defaults to false", async () => {
      expect(await Storage.isOnboarded()).toBe(false);
    });

    it("can be set to true", async () => {
      await Storage.setOnboarded();
      expect(await Storage.isOnboarded()).toBe(true);
    });

    it("survives clearAll (not in KEYS?)", async () => {
      await Storage.setOnboarded();
      await Storage.clearAll();
      const isOnboarded = await Storage.isOnboarded();
      expect(isOnboarded).toBe(false);
    });
  });

  describe("error resilience", () => {
    it("handles corrupted JSON gracefully", async () => {
      await AsyncStorage.setItem("bt_liked_videos", "not valid json {{{");
      const likes = await Storage.getLikedVideos();
      expect(likes).toEqual([]);
    });

    it("handles missing keys gracefully", async () => {
      const profile = await Storage.getUserProfile();
      expect(profile).toBeNull();
      const likes = await Storage.getLikedVideos();
      expect(likes).toEqual([]);
      const history = await Storage.getWatchHistory();
      expect(history).toEqual([]);
    });
  });

  describe("clearAll completeness", () => {
    it("removes every known key", async () => {
      await Storage.setUserProfile({
        displayName: "Test",
        avatarColor: "#000",
        initial: "T",
        createdAt: new Date().toISOString(),
      });
      await Storage.toggleLike("v1");
      await Storage.toggleDislike("v2");
      await Storage.toggleSubscription("ch1");
      await Storage.toggleSaved("v3");
      await Storage.addWatchHistory("v4", 50);
      await Storage.addComment("v5", "test");
      await Storage.setNotificationPrefs({ push: false, darkMode: false, autoplayMuted: false, autoplayNext: true });
      await Storage.addRecentSearch("test");
      await Storage.setOnboarded();

      await Storage.clearAll();

      expect(await Storage.getUserProfile()).toBeNull();
      expect(await Storage.getLikedVideos()).toEqual([]);
      expect(await Storage.getDislikedVideos()).toEqual([]);
      expect(await Storage.getSubscriptions()).toEqual([]);
      expect(await Storage.getSavedVideos()).toEqual([]);
      expect(await Storage.getWatchHistory()).toEqual([]);
      expect(await Storage.getUserComments()).toEqual([]);
      expect(await Storage.getRecentSearches()).toEqual([]);
      expect(await Storage.isOnboarded()).toBe(false);
    });
  });
});
