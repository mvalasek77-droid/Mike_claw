import AsyncStorage from "@react-native-async-storage/async-storage";

const KEYS = {
  USER_PROFILE: "bt_user_profile",
  LIKED_VIDEOS: "bt_liked_videos",
  DISLIKED_VIDEOS: "bt_disliked_videos",
  SUBSCRIPTIONS: "bt_subscriptions",
  WATCH_HISTORY: "bt_watch_history",
  SAVED_VIDEOS: "bt_saved_videos",
  USER_COMMENTS: "bt_user_comments",
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
}

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

  async getUserComments(): Promise<UserComment[]> {
    return getJSON(KEYS.USER_COMMENTS, []);
  },

  async addComment(videoId: string, text: string, parentId?: string): Promise<UserComment> {
    const comments = await this.getUserComments();
    const comment: UserComment = {
      id: `uc_${Date.now()}`,
      videoId,
      text,
      createdAt: new Date().toISOString(),
      parentId,
    };
    comments.unshift(comment);
    await setJSON(KEYS.USER_COMMENTS, comments);
    return comment;
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
