import {
  videos,
  channels,
  formatViews,
  formatSubscribers,
  formatCompact,
  getVideoById,
  getChannelById,
  getVideosByChannel,
  getVideosByCategory,
  searchVideos,
  getComments,
  getAITitleSuggestions,
  getAITrendingTopics,
  getCreatorInsights,
} from "../lib/data";

describe("data module", () => {
  describe("static data integrity", () => {
    it("has at least 10 videos", () => {
      expect(videos.length).toBeGreaterThanOrEqual(10);
    });

    it("has at least 5 channels", () => {
      expect(channels.length).toBeGreaterThanOrEqual(5);
    });

    it("every video has required fields", () => {
      for (const v of videos) {
        expect(v.id).toBeTruthy();
        expect(v.title).toBeTruthy();
        expect(v.thumbnailColors).toHaveLength(2);
        expect(v.channel).toBeDefined();
        expect(v.channel.id).toBeTruthy();
        expect(v.views).toBeGreaterThanOrEqual(0);
        expect(v.duration).toBeTruthy();
        expect(v.category).toBeTruthy();
        expect(Array.isArray(v.tags)).toBe(true);
      }
    });

    it("every channel has required fields", () => {
      for (const c of channels) {
        expect(c.id).toBeTruthy();
        expect(c.name).toBeTruthy();
        expect(c.initial).toHaveLength(1);
        expect(c.subscribers).toBeGreaterThanOrEqual(0);
        expect(typeof c.verified).toBe("boolean");
      }
    });

    it("video IDs are unique", () => {
      const ids = videos.map((v) => v.id);
      expect(new Set(ids).size).toBe(ids.length);
    });

    it("channel IDs are unique", () => {
      const ids = channels.map((c) => c.id);
      expect(new Set(ids).size).toBe(ids.length);
    });
  });

  describe("formatViews", () => {
    it("formats millions", () => {
      expect(formatViews(2500000)).toMatch(/2\.5M/);
    });

    it("formats thousands", () => {
      expect(formatViews(15000)).toMatch(/15\.0K|15K/);
    });

    it("formats small numbers", () => {
      const result = formatViews(500);
      expect(result).toContain("500");
    });
  });

  describe("formatSubscribers", () => {
    it("formats millions", () => {
      expect(formatSubscribers(1200000)).toMatch(/1\.2M/);
    });

    it("formats thousands", () => {
      expect(formatSubscribers(50000)).toMatch(/50\.0K|50K/);
    });
  });

  describe("formatCompact", () => {
    it("formats large numbers", () => {
      expect(formatCompact(1500000)).toMatch(/1\.5M/);
    });

    it("returns small numbers as-is", () => {
      expect(formatCompact(42)).toBe("42");
    });
  });

  describe("lookup functions", () => {
    it("getVideoById returns correct video", () => {
      const first = videos[0];
      expect(getVideoById(first.id)).toBe(first);
    });

    it("getVideoById returns undefined for missing id", () => {
      expect(getVideoById("nonexistent")).toBeUndefined();
    });

    it("getChannelById returns correct channel", () => {
      const first = channels[0];
      expect(getChannelById(first.id)).toBe(first);
    });

    it("getVideosByChannel returns only matching videos", () => {
      const channelId = videos[0].channel.id;
      const result = getVideosByChannel(channelId);
      expect(result.length).toBeGreaterThan(0);
      for (const v of result) {
        expect(v.channel.id).toBe(channelId);
      }
    });
  });

  describe("getVideosByCategory", () => {
    it("'All' returns all videos", () => {
      expect(getVideosByCategory("All")).toHaveLength(videos.length);
    });

    it("'Trending' returns top 10 by views", () => {
      const trending = getVideosByCategory("Trending");
      expect(trending.length).toBeLessThanOrEqual(10);
      for (let i = 1; i < trending.length; i++) {
        expect(trending[i - 1].views).toBeGreaterThanOrEqual(trending[i].views);
      }
    });

    it("category filter returns only matching videos", () => {
      const category = videos[0].category;
      const result = getVideosByCategory(category);
      for (const v of result) {
        expect(v.category).toBe(category);
      }
    });
  });

  describe("searchVideos", () => {
    it("finds videos by title", () => {
      const titleWord = videos[0].title.split(" ")[0];
      const results = searchVideos(titleWord);
      expect(results.length).toBeGreaterThan(0);
    });

    it("is case-insensitive", () => {
      const titleWord = videos[0].title.split(" ")[0];
      const upper = searchVideos(titleWord.toUpperCase());
      const lower = searchVideos(titleWord.toLowerCase());
      expect(upper).toEqual(lower);
    });

    it("returns empty for nonsense query", () => {
      expect(searchVideos("xyzzyplugh12345")).toHaveLength(0);
    });
  });

  describe("getComments", () => {
    it("returns an array of comments", () => {
      const comments = getComments();
      expect(Array.isArray(comments)).toBe(true);
      expect(comments.length).toBeGreaterThan(0);
    });

    it("each comment has required fields", () => {
      const comments = getComments();
      for (const c of comments) {
        expect(c.id).toBeTruthy();
        expect(c.author).toBeTruthy();
        expect(c.text).toBeTruthy();
        expect(typeof c.likes).toBe("number");
      }
    });
  });

  describe("AI functions", () => {
    it("getAITitleSuggestions returns suggestions", () => {
      const suggestions = getAITitleSuggestions("technology");
      expect(suggestions.length).toBeGreaterThan(0);
      for (const s of suggestions) {
        expect(s.confidence).toBeGreaterThan(0);
        expect(s.confidence).toBeLessThanOrEqual(100);
      }
    });

    it("getAITrendingTopics returns topics", () => {
      const topics = getAITrendingTopics();
      expect(topics.length).toBeGreaterThan(0);
    });

    it("getCreatorInsights returns insights", () => {
      const insights = getCreatorInsights();
      expect(insights.length).toBeGreaterThan(0);
    });
  });
});
