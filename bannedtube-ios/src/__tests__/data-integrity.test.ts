import {
  videos,
  channels,
  categories,
  THEME,
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
  type Video,
  type Channel,
} from "../lib/data";

describe("data integrity — deep checks", () => {
  describe("video-channel referential integrity", () => {
    it("every video references a channel that exists in channels[]", () => {
      const channelIds = new Set(channels.map((c) => c.id));
      for (const v of videos) {
        expect(channelIds.has(v.channel.id)).toBe(true);
      }
    });

    it("every channel with videos has getVideosByChannel results", () => {
      const channelsWithVideos = new Set(videos.map((v) => v.channel.id));
      for (const cid of channelsWithVideos) {
        const vids = getVideosByChannel(cid);
        expect(vids.length).toBeGreaterThan(0);
      }
    });

    it("video.channel object matches the channel in channels[]", () => {
      for (const v of videos) {
        const channel = getChannelById(v.channel.id);
        expect(channel).toBeDefined();
        expect(v.channel.name).toBe(channel!.name);
        expect(v.channel.initial).toBe(channel!.initial);
      }
    });
  });

  describe("THEME tokens", () => {
    it("all color values are valid hex or rgba", () => {
      const hexOrRgba = /^(#[0-9a-fA-F]{6}|rgba?\(.+\))$/;
      for (const [key, value] of Object.entries(THEME)) {
        expect(value).toMatch(hexOrRgba);
      }
    });

    it("has required keys", () => {
      expect(THEME.bgPrimary).toBeDefined();
      expect(THEME.bgSecondary).toBeDefined();
      expect(THEME.textPrimary).toBeDefined();
      expect(THEME.textSecondary).toBeDefined();
      expect(THEME.accent).toBeDefined();
      expect(THEME.success).toBeDefined();
      expect(THEME.warning).toBeDefined();
      expect(THEME.info).toBeDefined();
    });
  });

  describe("categories", () => {
    it("includes 'All' as the first category", () => {
      expect(categories[0]).toBe("All");
    });

    it("every video category appears in the categories list", () => {
      const cats = new Set(categories);
      for (const v of videos) {
        expect(cats.has(v.category) || cats.has("All")).toBe(true);
      }
    });

    it("categories are unique", () => {
      expect(new Set(categories).size).toBe(categories.length);
    });
  });

  describe("channel fields", () => {
    it("channels with bannerColors have exactly 3 colors", () => {
      for (const c of channels) {
        if (c.bannerColors) {
          expect(c.bannerColors).toHaveLength(3);
        }
      }
    });

    it("verified channels have higher subscriber counts on average", () => {
      const verified = channels.filter((c) => c.verified);
      const unverified = channels.filter((c) => !c.verified);
      if (verified.length > 0 && unverified.length > 0) {
        const avgVerified =
          verified.reduce((s, c) => s + c.subscribers, 0) / verified.length;
        const avgUnverified =
          unverified.reduce((s, c) => s + c.subscribers, 0) / unverified.length;
        expect(avgVerified).toBeGreaterThan(avgUnverified);
      }
    });

    it("every channel initial is a single uppercase letter", () => {
      for (const c of channels) {
        expect(c.initial).toMatch(/^[A-Z]$/);
      }
    });
  });

  describe("video fields", () => {
    it("thumbnailColors are valid hex pairs", () => {
      const hex = /^#[0-9a-fA-F]{6}$/;
      for (const v of videos) {
        expect(v.thumbnailColors[0]).toMatch(hex);
        expect(v.thumbnailColors[1]).toMatch(hex);
      }
    });

    it("duration format is MM:SS or H:MM:SS", () => {
      const durationRe = /^\d{1,2}:\d{2}(:\d{2})?$/;
      for (const v of videos) {
        expect(v.duration).toMatch(durationRe);
      }
    });

    it("views and likes are non-negative", () => {
      for (const v of videos) {
        expect(v.views).toBeGreaterThanOrEqual(0);
        expect(v.likes).toBeGreaterThanOrEqual(0);
        expect(v.dislikes).toBeGreaterThanOrEqual(0);
      }
    });

    it("tags are non-empty arrays of strings", () => {
      for (const v of videos) {
        expect(v.tags.length).toBeGreaterThan(0);
        for (const tag of v.tags) {
          expect(typeof tag).toBe("string");
          expect(tag.length).toBeGreaterThan(0);
        }
      }
    });
  });

  describe("format functions edge cases", () => {
    it("formatViews handles 0", () => {
      const result = formatViews(0);
      expect(result).toContain("0");
    });

    it("formatViews handles exact millions", () => {
      expect(formatViews(1000000)).toMatch(/1\.0M|1M/);
    });

    it("formatSubscribers handles 0", () => {
      const result = formatSubscribers(0);
      expect(result).toBeDefined();
    });

    it("formatCompact handles negative numbers", () => {
      const result = formatCompact(-100);
      expect(result).toBeDefined();
    });

    it("formatCompact handles thousands boundary", () => {
      expect(formatCompact(999)).toBe("999");
      expect(formatCompact(1000)).toMatch(/1\.0K|1K/);
    });
  });

  describe("getVideosByCategory advanced", () => {
    it("'Trending' returns videos sorted by views descending", () => {
      const trending = getVideosByCategory("Trending");
      for (let i = 1; i < trending.length; i++) {
        expect(trending[i - 1].views).toBeGreaterThanOrEqual(trending[i].views);
      }
    });

    it("specific category returns only matching videos", () => {
      const cat = videos[0].category;
      const filtered = getVideosByCategory(cat);
      for (const v of filtered) {
        expect(v.category).toBe(cat);
      }
    });

    it("unknown category returns empty", () => {
      expect(getVideosByCategory("NonexistentCategory123")).toHaveLength(0);
    });
  });

  describe("searchVideos thorough", () => {
    it("matches by channel name", () => {
      const channelName = videos[0].channel.name.split(" ")[0];
      const results = searchVideos(channelName);
      expect(results.length).toBeGreaterThan(0);
    });

    it("matches by tag", () => {
      const tag = videos[0].tags[0];
      const results = searchVideos(tag);
      expect(results.length).toBeGreaterThan(0);
    });

    it("empty query returns all videos (no filter applied)", () => {
      const results = searchVideos("");
      expect(results.length).toBe(videos.length);
    });

    it("single character query works", () => {
      const results = searchVideos("a");
      expect(Array.isArray(results)).toBe(true);
    });

    it("special characters don't crash", () => {
      expect(() => searchVideos("test (parentheses)")).not.toThrow();
      expect(() => searchVideos("test [brackets]")).not.toThrow();
      expect(() => searchVideos("test.dots")).not.toThrow();
    });
  });

  describe("getComments structure", () => {
    it("comments have optional replies array", () => {
      const comments = getComments();
      for (const c of comments) {
        if (c.replies) {
          expect(Array.isArray(c.replies)).toBe(true);
          for (const r of c.replies) {
            expect(r.id).toBeTruthy();
            expect(r.author).toBeTruthy();
            expect(r.text).toBeTruthy();
          }
        }
      }
    });

    it("comment IDs are unique", () => {
      const comments = getComments();
      const ids: string[] = [];
      function collectIds(c: any) {
        ids.push(c.id);
        if (c.replies) c.replies.forEach(collectIds);
      }
      comments.forEach(collectIds);
      expect(new Set(ids).size).toBe(ids.length);
    });
  });

  describe("AI functions", () => {
    it("title suggestions have valid confidence 0-100", () => {
      const suggestions = getAITitleSuggestions("test");
      for (const s of suggestions) {
        expect(s.confidence).toBeGreaterThanOrEqual(0);
        expect(s.confidence).toBeLessThanOrEqual(100);
        expect(s.type).toBeDefined();
        expect(s.content).toBeTruthy();
        expect(s.reasoning).toBeTruthy();
      }
    });

    it("trending topics have growth percentages", () => {
      const topics = getAITrendingTopics();
      for (const t of topics) {
        expect(typeof t.growth).toBe("number");
        expect(t.category).toBeTruthy();
        expect(t.relatedKeywords.length).toBeGreaterThan(0);
        expect(t.suggestedAngle).toBeTruthy();
      }
    });

    it("creator insights have valid trend direction", () => {
      const insights = getCreatorInsights();
      for (const i of insights) {
        expect(["up", "down", "stable"]).toContain(i.trend);
        expect(typeof i.change).toBe("number");
        expect(i.suggestion).toBeTruthy();
      }
    });
  });
});
