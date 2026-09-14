import AsyncStorage from "@react-native-async-storage/async-storage";

const KEYS = {
  USER_PROFILE: "bt_user_profile",
  LIKED_VIDEOS: "bt_liked_videos",
  DISLIKED_VIDEOS: "bt_disliked_videos",
  SUBSCRIPTIONS: "bt_subscriptions",
  WATCH_HISTORY: "bt_watch_history",
  SAVED_VIDEOS: "bt_saved_videos",
  USER_COMMENTS: "bt_user_comments",
  LIKED_COMMENTS: "bt_liked_comments",
  PLAYLISTS: "bt_playlists",
  NOTIFICATION_PREFS: "bt_notif_prefs",
  ONBOARDED: "bt_onboarded",
  RECENT_SEARCHES: "bt_recent_searches",
} as const;

export interface UserProfile {
  displayName: string;
  avatarColor: string;
  initial: string;
  createdAt: string;
}

export interface WatchHistoryEntry {
  videoId: string;
  watchedAt: string;
  progressPercent: number;
}

export interface UserComment {
  id: string;
  videoId: string;
  text: string;
  createdAt: string;
  parentId?: string;
  /** Set the first time the comment is edited, so the UI can mark it. */
  editedAt?: string;
}

export interface Playlist {
  id: string;
  name: string;
  /** Ordered newest-first, matching how videos are added. */
  videoIds: string[];
  createdAt: string;
  updatedAt: string;
}

export const PLAYLIST_NAME_MAX = 60;

export interface NotificationPrefs {
  push: boolean;
  darkMode: boolean;
  autoplayMuted: boolean;
  autoplayNext: boolean;
}

async function getJSON<T>(key: string, fallback: T): Promise<T> {
  try {
    const raw = await AsyncStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

async function setJSON(key: string, value: unknown): Promise<void> {
  await AsyncStorage.setItem(key, JSON.stringify(value));
}

export const Storage = {
  async getUserProfile(): Promise<UserProfile | null> {
    return getJSON(KEYS.USER_PROFILE, null);
  },

  async setUserProfile(profile: UserProfile): Promise<void> {
    await setJSON(KEYS.USER_PROFILE, profile);
  },

  async getLikedVideos(): Promise<string[]> {
    return getJSON(KEYS.LIKED_VIDEOS, []);
  },

  async toggleLike(videoId: string): Promise<boolean> {
    const likes = await this.getLikedVideos();
    const idx = likes.indexOf(videoId);
    if (idx >= 0) {
      likes.splice(idx, 1);
      await setJSON(KEYS.LIKED_VIDEOS, likes);
      return false;
    }
    likes.push(videoId);
    await setJSON(KEYS.LIKED_VIDEOS, likes);
    const dislikes = await this.getDislikedVideos();
    const dIdx = dislikes.indexOf(videoId);
    if (dIdx >= 0) {
      dislikes.splice(dIdx, 1);
      await setJSON(KEYS.DISLIKED_VIDEOS, dislikes);
    }
    return true;
  },

  async getDislikedVideos(): Promise<string[]> {
    return getJSON(KEYS.DISLIKED_VIDEOS, []);
  },

  async toggleDislike(videoId: string): Promise<boolean> {
    const dislikes = await this.getDislikedVideos();
    const idx = dislikes.indexOf(videoId);
    if (idx >= 0) {
      dislikes.splice(idx, 1);
      await setJSON(KEYS.DISLIKED_VIDEOS, dislikes);
      return false;
    }
    dislikes.push(videoId);
    await setJSON(KEYS.DISLIKED_VIDEOS, dislikes);
    const likes = await this.getLikedVideos();
    const lIdx = likes.indexOf(videoId);
    if (lIdx >= 0) {
      likes.splice(lIdx, 1);
      await setJSON(KEYS.LIKED_VIDEOS, likes);
    }
    return true;
  },

  async getSubscriptions(): Promise<string[]> {
    return getJSON(KEYS.SUBSCRIPTIONS, []);
  },

  async toggleSubscription(channelId: string): Promise<boolean> {
    const subs = await this.getSubscriptions();
    const idx = subs.indexOf(channelId);
    if (idx >= 0) {
      subs.splice(idx, 1);
      await setJSON(KEYS.SUBSCRIPTIONS, subs);
      return false;
    }
    subs.push(channelId);
    await setJSON(KEYS.SUBSCRIPTIONS, subs);
    return true;
  },

  async getWatchHistory(): Promise<WatchHistoryEntry[]> {
    return getJSON(KEYS.WATCH_HISTORY, []);
  },

  async addWatchHistory(
    videoId: string,
    progressPercent: number
  ): Promise<void> {
    const history = await this.getWatchHistory();
    const existing = history.findIndex((h) => h.videoId === videoId);
    const entry: WatchHistoryEntry = {
      videoId,
      watchedAt: new Date().toISOString(),
      progressPercent,
    };
    if (existing >= 0) {
      history[existing] = entry;
    } else {
      history.unshift(entry);
    }
    if (history.length > 200) history.length = 200;
    await setJSON(KEYS.WATCH_HISTORY, history);
  },

  async removeWatchHistory(videoId: string): Promise<void> {
    const history = await this.getWatchHistory();
    await setJSON(
      KEYS.WATCH_HISTORY,
      history.filter((h) => h.videoId !== videoId)
    );
  },

  async clearWatchHistory(): Promise<void> {
    await setJSON(KEYS.WATCH_HISTORY, []);
  },

  async getSavedVideos(): Promise<string[]> {
    return getJSON(KEYS.SAVED_VIDEOS, []);
  },

  async toggleSaved(videoId: string): Promise<boolean> {
    const saved = await this.getSavedVideos();
    const idx = saved.indexOf(videoId);
    if (idx >= 0) {
      saved.splice(idx, 1);
      await setJSON(KEYS.SAVED_VIDEOS, saved);
      return false;
    }
    saved.push(videoId);
    await setJSON(KEYS.SAVED_VIDEOS, saved);
    return true;
  },

  /**
   * Bulk clears exist because toggling each id in turn is a read-modify-write
   * per item; fired concurrently they race and all but the last write is lost.
   */
  async clearSavedVideos(): Promise<void> {
    await setJSON(KEYS.SAVED_VIDEOS, []);
  },

  async clearLikedVideos(): Promise<void> {
    await setJSON(KEYS.LIKED_VIDEOS, []);
  },

  async getUserComments(): Promise<UserComment[]> {
    return getJSON(KEYS.USER_COMMENTS, []);
  },

  async addComment(videoId: string, text: string, parentId?: string): Promise<UserComment> {
    const comments = await this.getUserComments();
    const comment: UserComment = {
      // A bare timestamp collides for comments posted in the same millisecond,
      // which would break reply threading and duplicate React keys.
      id: `uc_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      videoId,
      text,
      createdAt: new Date().toISOString(),
      parentId,
    };
    comments.unshift(comment);
    await setJSON(KEYS.USER_COMMENTS, comments);
    return comment;
  },

  async editComment(id: string, text: string): Promise<void> {
    const comments = await this.getUserComments();
    const idx = comments.findIndex((c) => c.id === id);
    if (idx < 0) return;
    comments[idx] = { ...comments[idx], text, editedAt: new Date().toISOString() };
    await setJSON(KEYS.USER_COMMENTS, comments);
  },

  /** Deleting a top-level comment takes its replies with it. */
  async deleteComment(id: string): Promise<void> {
    const comments = await this.getUserComments();
    const remaining = comments.filter((c) => c.id !== id && c.parentId !== id);
    await setJSON(KEYS.USER_COMMENTS, remaining);

    // Drop any likes pointing at comments that no longer exist.
    const liked = await this.getLikedComments();
    const removedIds = new Set(
      comments.filter((c) => c.id === id || c.parentId === id).map((c) => c.id)
    );
    const nextLiked = liked.filter((cid) => !removedIds.has(cid));
    if (nextLiked.length !== liked.length) {
      await setJSON(KEYS.LIKED_COMMENTS, nextLiked);
    }
  },

  async getLikedComments(): Promise<string[]> {
    return getJSON(KEYS.LIKED_COMMENTS, []);
  },

  async toggleCommentLike(commentId: string): Promise<boolean> {
    const liked = await this.getLikedComments();
    const idx = liked.indexOf(commentId);
    if (idx >= 0) {
      liked.splice(idx, 1);
      await setJSON(KEYS.LIKED_COMMENTS, liked);
      return false;
    }
    liked.push(commentId);
    await setJSON(KEYS.LIKED_COMMENTS, liked);
    return true;
  },

  async getPlaylists(): Promise<Playlist[]> {
    return getJSON(KEYS.PLAYLISTS, []);
  },

  /** Returns null when the name is blank or already taken. */
  async createPlaylist(name: string): Promise<Playlist | null> {
    const trimmed = name.trim().slice(0, PLAYLIST_NAME_MAX);
    if (!trimmed) return null;

    const playlists = await this.getPlaylists();
    const taken = playlists.some(
      (p) => p.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (taken) return null;

    const now = new Date().toISOString();
    const playlist: Playlist = {
      id: `pl_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      name: trimmed,
      videoIds: [],
      createdAt: now,
      updatedAt: now,
    };
    playlists.unshift(playlist);
    await setJSON(KEYS.PLAYLISTS, playlists);
    return playlist;
  },

  async renamePlaylist(id: string, name: string): Promise<boolean> {
    const trimmed = name.trim().slice(0, PLAYLIST_NAME_MAX);
    if (!trimmed) return false;

    const playlists = await this.getPlaylists();
    const clash = playlists.some(
      (p) => p.id !== id && p.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (clash) return false;

    const idx = playlists.findIndex((p) => p.id === id);
    if (idx < 0) return false;

    playlists[idx] = {
      ...playlists[idx],
      name: trimmed,
      updatedAt: new Date().toISOString(),
    };
    await setJSON(KEYS.PLAYLISTS, playlists);
    return true;
  },

  async deletePlaylist(id: string): Promise<void> {
    const playlists = await this.getPlaylists();
    await setJSON(
      KEYS.PLAYLISTS,
      playlists.filter((p) => p.id !== id)
    );
  },

  /** Adds or removes the video; returns whether it is in the playlist after. */
  async togglePlaylistVideo(id: string, videoId: string): Promise<boolean> {
    const playlists = await this.getPlaylists();
    const idx = playlists.findIndex((p) => p.id === id);
    if (idx < 0) return false;

    const current = playlists[idx].videoIds;
    const present = current.includes(videoId);
    const videoIds = present
      ? current.filter((v) => v !== videoId)
      : [videoId, ...current];

    playlists[idx] = {
      ...playlists[idx],
      videoIds,
      updatedAt: new Date().toISOString(),
    };
    await setJSON(KEYS.PLAYLISTS, playlists);
    return !present;
  },

  /** Empties a playlist in one write, keeping the playlist itself. */
  async clearPlaylist(id: string): Promise<void> {
    const playlists = await this.getPlaylists();
    const idx = playlists.findIndex((p) => p.id === id);
    if (idx < 0) return;
    playlists[idx] = {
      ...playlists[idx],
      videoIds: [],
      updatedAt: new Date().toISOString(),
    };
    await setJSON(KEYS.PLAYLISTS, playlists);
  },

  async getNotificationPrefs(): Promise<NotificationPrefs> {
    return getJSON(KEYS.NOTIFICATION_PREFS, {
      push: true,
      darkMode: true,
      autoplayMuted: true,
      autoplayNext: false,
    });
  },

  async setNotificationPrefs(prefs: NotificationPrefs): Promise<void> {
    await setJSON(KEYS.NOTIFICATION_PREFS, prefs);
  },

  async getRecentSearches(): Promise<string[]> {
    return getJSON(KEYS.RECENT_SEARCHES, []);
  },

  async addRecentSearch(query: string): Promise<void> {
    const recent = await this.getRecentSearches();
    const filtered = recent.filter((q) => q !== query);
    filtered.unshift(query);
    await setJSON(KEYS.RECENT_SEARCHES, filtered.slice(0, 10));
  },

  async clearRecentSearches(): Promise<void> {
    await setJSON(KEYS.RECENT_SEARCHES, []);
  },

  async isOnboarded(): Promise<boolean> {
    return getJSON(KEYS.ONBOARDED, false);
  },

  async setOnboarded(): Promise<void> {
    await setJSON(KEYS.ONBOARDED, true);
  },

  async clearAll(): Promise<void> {
    const keys = Object.values(KEYS);
    await Promise.all(keys.map((k) => AsyncStorage.removeItem(k)));
  },
};
