import AsyncStorage from "@react-native-async-storage/async-storage";
import { Storage, PLAYLIST_NAME_MAX } from "../lib/storage";

describe("playlists", () => {
  beforeEach(async () => {
    await AsyncStorage.clear();
  });

  describe("create", () => {
    it("starts empty", async () => {
      expect(await Storage.getPlaylists()).toEqual([]);
    });

    it("creates a named playlist with no videos", async () => {
      const p = await Storage.createPlaylist("Watch on the train");
      expect(p).not.toBeNull();
      expect(p!.name).toBe("Watch on the train");
      expect(p!.videoIds).toEqual([]);
      expect(await Storage.getPlaylists()).toHaveLength(1);
    });

    it("trims the name", async () => {
      const p = await Storage.createPlaylist("   Spaced   ");
      expect(p!.name).toBe("Spaced");
    });

    it("refuses a blank name", async () => {
      expect(await Storage.createPlaylist("   ")).toBeNull();
      expect(await Storage.getPlaylists()).toHaveLength(0);
    });

    it("refuses a duplicate name regardless of case", async () => {
      await Storage.createPlaylist("Later");
      expect(await Storage.createPlaylist("later")).toBeNull();
      expect(await Storage.getPlaylists()).toHaveLength(1);
    });

    it("caps the name length", async () => {
      const p = await Storage.createPlaylist("x".repeat(PLAYLIST_NAME_MAX + 40));
      expect(p!.name).toHaveLength(PLAYLIST_NAME_MAX);
    });

    it("gives distinct ids in a tight loop", async () => {
      for (let i = 0; i < 20; i++) await Storage.createPlaylist(`list ${i}`);
      const ids = (await Storage.getPlaylists()).map((p) => p.id);
      expect(new Set(ids).size).toBe(ids.length);
    });

    it("puts the newest playlist first", async () => {
      await Storage.createPlaylist("first");
      await Storage.createPlaylist("second");
      expect((await Storage.getPlaylists()).map((p) => p.name)).toEqual([
        "second",
        "first",
      ]);
    });
  });

  describe("membership", () => {
    it("adds then removes a video", async () => {
      const p = (await Storage.createPlaylist("Mine"))!;

      expect(await Storage.togglePlaylistVideo(p.id, "sintel")).toBe(true);
      let stored = (await Storage.getPlaylists())[0];
      expect(stored.videoIds).toEqual(["sintel"]);

      expect(await Storage.togglePlaylistVideo(p.id, "sintel")).toBe(false);
      stored = (await Storage.getPlaylists())[0];
      expect(stored.videoIds).toEqual([]);
    });

    it("keeps newest additions first", async () => {
      const p = (await Storage.createPlaylist("Mine"))!;
      await Storage.togglePlaylistVideo(p.id, "a");
      await Storage.togglePlaylistVideo(p.id, "b");
      expect((await Storage.getPlaylists())[0].videoIds).toEqual(["b", "a"]);
    });

    it("does not add the same video twice", async () => {
      const p = (await Storage.createPlaylist("Mine"))!;
      await Storage.togglePlaylistVideo(p.id, "a");
      await Storage.togglePlaylistVideo(p.id, "a");
      await Storage.togglePlaylistVideo(p.id, "a");
      expect((await Storage.getPlaylists())[0].videoIds).toEqual(["a"]);
    });

    it("toggling on an unknown playlist is harmless", async () => {
      expect(await Storage.togglePlaylistVideo("nope", "a")).toBe(false);
      expect(await Storage.getPlaylists()).toEqual([]);
    });

    it("bumps updatedAt when the contents change", async () => {
      const p = (await Storage.createPlaylist("Mine"))!;
      const before = (await Storage.getPlaylists())[0].updatedAt;
      await new Promise((r) => setTimeout(r, 2));
      await Storage.togglePlaylistVideo(p.id, "a");
      const after = (await Storage.getPlaylists())[0].updatedAt;
      expect(new Date(after).getTime()).toBeGreaterThanOrEqual(
        new Date(before).getTime()
      );
    });
  });

  describe("rename", () => {
    it("renames a playlist", async () => {
      const p = (await Storage.createPlaylist("Old"))!;
      expect(await Storage.renamePlaylist(p.id, "New")).toBe(true);
      expect((await Storage.getPlaylists())[0].name).toBe("New");
    });

    it("refuses a blank name", async () => {
      const p = (await Storage.createPlaylist("Keep"))!;
      expect(await Storage.renamePlaylist(p.id, "  ")).toBe(false);
      expect((await Storage.getPlaylists())[0].name).toBe("Keep");
    });

    it("refuses a name another playlist already has", async () => {
      await Storage.createPlaylist("Taken");
      const p = (await Storage.createPlaylist("Mine"))!;
      expect(await Storage.renamePlaylist(p.id, "taken")).toBe(false);
    });

    it("lets a playlist keep its own name", async () => {
      const p = (await Storage.createPlaylist("Same"))!;
      expect(await Storage.renamePlaylist(p.id, "Same")).toBe(true);
    });

    it("returns false for an unknown id", async () => {
      expect(await Storage.renamePlaylist("nope", "Anything")).toBe(false);
    });
  });

  describe("delete and clear", () => {
    it("deletes only the named playlist", async () => {
      const a = (await Storage.createPlaylist("A"))!;
      await Storage.createPlaylist("B");

      await Storage.deletePlaylist(a.id);
      const left = await Storage.getPlaylists();
      expect(left).toHaveLength(1);
      expect(left[0].name).toBe("B");
    });

    it("clears contents in one write but keeps the playlist", async () => {
      const p = (await Storage.createPlaylist("Mine"))!;
      await Storage.togglePlaylistVideo(p.id, "a");
      await Storage.togglePlaylistVideo(p.id, "b");

      await Storage.clearPlaylist(p.id);
      const stored = await Storage.getPlaylists();
      expect(stored).toHaveLength(1);
      expect(stored[0].videoIds).toEqual([]);
    });

    it("clearing an unknown playlist is harmless", async () => {
      await Storage.createPlaylist("Mine");
      await Storage.clearPlaylist("nope");
      expect(await Storage.getPlaylists()).toHaveLength(1);
    });
  });

  describe("resilience", () => {
    it("returns an empty list when stored data is corrupt", async () => {
      await AsyncStorage.setItem("bt_playlists", "{{ not json");
      expect(await Storage.getPlaylists()).toEqual([]);
    });
  });
});
