import AsyncStorage from "@react-native-async-storage/async-storage";
import { Storage } from "../lib/storage";

beforeEach(() => {
  jest.clearAllMocks();
  (AsyncStorage as any).__resetStore();
});

describe("Storage", () => {
  describe("UserProfile", () => {
    it("returns null when no profile exists", async () => {
      const profile = await Storage.getUserProfile();
      expect(profile).toBeNull();
    });

    it("saves and retrieves a profile", async () => {
      const profile = {
        displayName: "Mike",
        avatarColor: "#ff4444",
        initial: "M",
        createdAt: "2026-01-01T00:00:00.000Z",
      };
      await Storage.setUserProfile(profile);
      const result = await Storage.getUserProfile();
      expect(result).toEqual(profile);
    });
  });

  describe("Like/Dislike mutual exclusion", () => {
    it("liking a video returns true", async () => {
      const result = await Storage.toggleLike("v1");
      expect(result).toBe(true);
    });

    it("liking then unliking returns false", async () => {
      await Storage.toggleLike("v1");
      const result = await Storage.toggleLike("v1");
      expect(result).toBe(false);
    });

    it("liking removes an existing dislike", async () => {
      await Storage.toggleDislike("v1");
      let dislikes = await Storage.getDislikedVideos();
      expect(dislikes).toContain("v1");

      await Storage.toggleLike("v1");
      dislikes = await Storage.getDislikedVideos();
      expect(dislikes).not.toContain("v1");

      const likes = await Storage.getLikedVideos();
      expect(likes).toContain("v1");
    });

    it("disliking removes an existing like", async () => {
      await Storage.toggleLike("v1");
      let likes = await Storage.getLikedVideos();
      expect(likes).toContain("v1");

      await Storage.toggleDislike("v1");
      likes = await Storage.getLikedVideos();
      expect(likes).not.toContain("v1");

      const dislikes = await Storage.getDislikedVideos();
      expect(dislikes).toContain("v1");
    });
  });

  describe("Subscriptions", () => {
    it("subscribing returns true, unsubscribing returns false", async () => {
      const sub = await Storage.toggleSubscription("ch1");
      expect(sub).toBe(true);

      const unsub = await Storage.toggleSubscription("ch1");
      expect(unsub).toBe(false);
    });

    it("multiple channels are independent", async () => {
      await Storage.toggleSubscription("ch1");
      await Storage.toggleSubscription("ch2");
      const subs = await Storage.getSubscriptions();
      expect(subs).toContain("ch1");
      expect(subs).toContain("ch2");

      await Storage.toggleSubscription("ch1");
      const subs2 = await Storage.getSubscriptions();
      expect(subs2).not.toContain("ch1");
      expect(subs2).toContain("ch2");
    });
  });

  describe("Watch History", () => {
    it("adds a watch history entry", async () => {
      await Storage.addWatchHistory("v1", 50);
      const history = await Storage.getWatchHistory();
      expect(history).toHaveLength(1);
      expect(history[0].videoId).toBe("v1");
      expect(history[0].progressPercent).toBe(50);
    });

    it("updates progress on re-watch", async () => {
      await Storage.addWatchHistory("v1", 25);
      await Storage.addWatchHistory("v1", 75);
      const history = await Storage.getWatchHistory();
      expect(history).toHaveLength(1);
      expect(history[0].progressPercent).toBe(75);
    });

    it("caps at 200 entries", async () => {
      for (let i = 0; i < 210; i++) {
        await Storage.addWatchHistory(`v${i}`, 10);
      }
      const history = await Storage.getWatchHistory();
      expect(history.length).toBeLessThanOrEqual(200);
    });
  });

  describe("Saved Videos", () => {
    it("saving returns true, unsaving returns false", async () => {
      const saved = await Storage.toggleSaved("v1");
      expect(saved).toBe(true);

      const unsaved = await Storage.toggleSaved("v1");
      expect(unsaved).toBe(false);
    });
  });

  describe("Comments", () => {
    it("adds a comment with generated id", async () => {
      const comment = await Storage.addComment("v1", "Great video!");
      expect(comment.id).toMatch(/^uc_/);
      expect(comment.videoId).toBe("v1");
      expect(comment.text).toBe("Great video!");
    });

    it("adds a reply with parentId", async () => {
      const parent = await Storage.addComment("v1", "Nice");
      const reply = await Storage.addComment("v1", "Thanks!", parent.id);
      expect(reply.parentId).toBe(parent.id);
    });

    it("newest comment appears first", async () => {
      await Storage.addComment("v1", "First");
      await Storage.addComment("v1", "Second");
      const comments = await Storage.getUserComments();
      expect(comments[0].text).toBe("Second");
      expect(comments[1].text).toBe("First");
    });
  });

  describe("Notification Preferences", () => {
    it("returns defaults when none saved", async () => {
      const prefs = await Storage.getNotificationPrefs();
      expect(prefs.push).toBe(true);
      expect(prefs.darkMode).toBe(true);
      expect(prefs.autoplayMuted).toBe(true);
      expect(prefs.autoplayNext).toBe(false);
    });

    it("saves and retrieves custom prefs", async () => {
      const custom = { push: false, darkMode: false, autoplayMuted: false, autoplayNext: true };
      await Storage.setNotificationPrefs(custom);
      const result = await Storage.getNotificationPrefs();
      expect(result).toEqual(custom);
    });
  });

  describe("Recent Searches", () => {
    it("adds and retrieves recent searches", async () => {
      await Storage.addRecentSearch("react native");
      const searches = await Storage.getRecentSearches();
      expect(searches).toEqual(["react native"]);
    });

    it("deduplicates and moves to front", async () => {
      await Storage.addRecentSearch("a");
      await Storage.addRecentSearch("b");
      await Storage.addRecentSearch("a");
      const searches = await Storage.getRecentSearches();
      expect(searches).toEqual(["a", "b"]);
    });

    it("caps at 10 searches", async () => {
      for (let i = 0; i < 15; i++) {
        await Storage.addRecentSearch(`search${i}`);
      }
      const searches = await Storage.getRecentSearches();
      expect(searches).toHaveLength(10);
    });

    it("clears all searches", async () => {
      await Storage.addRecentSearch("test");
      await Storage.clearRecentSearches();
      const searches = await Storage.getRecentSearches();
      expect(searches).toEqual([]);
    });
  });

  describe("clearAll", () => {
    it("removes all stored data", async () => {
      await Storage.setUserProfile({
        displayName: "Test",
        avatarColor: "#000",
        initial: "T",
        createdAt: new Date().toISOString(),
      });
      await Storage.toggleLike("v1");
      await Storage.toggleSubscription("ch1");

      await Storage.clearAll();

      const profile = await Storage.getUserProfile();
      const likes = await Storage.getLikedVideos();
      const subs = await Storage.getSubscriptions();
      expect(profile).toBeNull();
      expect(likes).toEqual([]);
      expect(subs).toEqual([]);
    });
  });
});
