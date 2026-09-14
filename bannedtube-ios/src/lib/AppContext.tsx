import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";
import * as Haptics from "expo-haptics";
import { Storage, type UserProfile, type WatchHistoryEntry, type UserComment, type Playlist } from "./storage";
import { type Comment } from "./data";
import { Analytics } from "./analytics";

interface AppState {
  ready: boolean;
  profile: UserProfile | null;
  likedVideos: Set<string>;
  dislikedVideos: Set<string>;
  subscriptions: Set<string>;
  savedVideos: Set<string>;
  likedComments: Set<string>;
  playlists: Playlist[];
  watchHistory: WatchHistoryEntry[];
  userComments: UserComment[];
  notifications: {
    push: boolean;
    darkMode: boolean;
    autoplayMuted: boolean;
    autoplayNext: boolean;
  };
  recentSearches: string[];
}

interface AppActions {
  setProfile: (profile: UserProfile) => Promise<void>;
  toggleLike: (videoId: string) => Promise<boolean>;
  toggleDislike: (videoId: string) => Promise<boolean>;
  toggleSubscription: (channelId: string) => Promise<boolean>;
  toggleSaved: (videoId: string) => Promise<boolean>;
  toggleCommentLike: (commentId: string) => Promise<boolean>;
  addWatchHistory: (videoId: string, progress: number) => Promise<void>;
  addComment: (videoId: string, text: string, parentId?: string) => Promise<UserComment>;
  editComment: (id: string, text: string) => Promise<void>;
  deleteComment: (id: string) => Promise<void>;
  removeFromHistory: (videoId: string) => Promise<void>;
  clearHistory: () => Promise<void>;
  clearSaved: () => Promise<void>;
  clearLiked: () => Promise<void>;
  createPlaylist: (name: string) => Promise<Playlist | null>;
  renamePlaylist: (id: string, name: string) => Promise<boolean>;
  deletePlaylist: (id: string) => Promise<void>;
  togglePlaylistVideo: (id: string, videoId: string) => Promise<boolean>;
  clearPlaylist: (id: string) => Promise<void>;
  getVideoComments: (videoId: string) => Comment[];
  isLiked: (videoId: string) => boolean;
  isDisliked: (videoId: string) => boolean;
  isSubscribed: (channelId: string) => boolean;
  isSaved: (videoId: string) => boolean;
  isCommentLiked: (commentId: string) => boolean;
  getWatchProgress: (videoId: string) => number;
  setNotifications: (prefs: { push: boolean; darkMode: boolean; autoplayMuted: boolean; autoplayNext: boolean }) => void;
  addRecentSearch: (query: string) => void;
  clearRecentSearches: () => void;
}

type AppContextType = AppState & AppActions;

const AppContext = createContext<AppContextType | null>(null);

export function useApp(): AppContextType {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp must be used within AppProvider");
  return ctx;
}

export function AppProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AppState>({
    ready: false,
    profile: null,
    likedVideos: new Set(),
    dislikedVideos: new Set(),
    subscriptions: new Set(),
    savedVideos: new Set(),
    likedComments: new Set(),
    playlists: [],
    watchHistory: [],
    userComments: [],
    notifications: { push: true, darkMode: true, autoplayMuted: true, autoplayNext: false },
    recentSearches: [],
  });

  useEffect(() => {
    (async () => {
      const [profile, liked, disliked, subs, saved, history, comments, notifPrefs, recentSearches, likedComments, playlists] =
        await Promise.all([
          Storage.getUserProfile(),
          Storage.getLikedVideos(),
          Storage.getDislikedVideos(),
          Storage.getSubscriptions(),
          Storage.getSavedVideos(),
          Storage.getWatchHistory(),
          Storage.getUserComments(),
          Storage.getNotificationPrefs(),
          Storage.getRecentSearches(),
          Storage.getLikedComments(),
          Storage.getPlaylists(),
        ]);

      setState({
        ready: true,
        profile,
        likedVideos: new Set(liked),
        dislikedVideos: new Set(disliked),
        subscriptions: new Set(subs),
        savedVideos: new Set(saved),
        likedComments: new Set(likedComments),
        playlists,
        watchHistory: history,
        userComments: comments,
      notifications: notifPrefs,
      recentSearches,
    });
    })();
  }, []);

  const setProfile = useCallback(async (profile: UserProfile) => {
    await Storage.setUserProfile(profile);
    setState((s) => ({ ...s, profile }));
  }, []);

  const toggleLike = useCallback(async (videoId: string) => {
    const nowLiked = await Storage.toggleLike(videoId);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    if (nowLiked) Analytics.videoLike(videoId);
    setState((s) => {
      const liked = new Set(s.likedVideos);
      const disliked = new Set(s.dislikedVideos);
      if (nowLiked) {
        liked.add(videoId);
        disliked.delete(videoId);
      } else {
        liked.delete(videoId);
      }
      return { ...s, likedVideos: liked, dislikedVideos: disliked };
    });
    return nowLiked;
  }, []);

  const toggleDislike = useCallback(async (videoId: string) => {
    const nowDisliked = await Storage.toggleDislike(videoId);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setState((s) => {
      const disliked = new Set(s.dislikedVideos);
      const liked = new Set(s.likedVideos);
      if (nowDisliked) {
        disliked.add(videoId);
        liked.delete(videoId);
      } else {
        disliked.delete(videoId);
      }
      return { ...s, likedVideos: liked, dislikedVideos: disliked };
    });
    return nowDisliked;
  }, []);

  const toggleSubscription = useCallback(async (channelId: string) => {
    const nowSubscribed = await Storage.toggleSubscription(channelId);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    if (nowSubscribed) Analytics.subscribe(channelId);
    setState((s) => {
      const subs = new Set(s.subscriptions);
      if (nowSubscribed) subs.add(channelId);
      else subs.delete(channelId);
      return { ...s, subscriptions: subs };
    });
    return nowSubscribed;
  }, []);

  const toggleSaved = useCallback(async (videoId: string) => {
    const nowSaved = await Storage.toggleSaved(videoId);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    if (nowSaved) Analytics.videoSave(videoId);
    setState((s) => {
      const saved = new Set(s.savedVideos);
      if (nowSaved) saved.add(videoId);
      else saved.delete(videoId);
      return { ...s, savedVideos: saved };
    });
    return nowSaved;
  }, []);

  const toggleCommentLike = useCallback(async (commentId: string) => {
    const nowLiked = await Storage.toggleCommentLike(commentId);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setState((s) => {
      const next = new Set(s.likedComments);
      if (nowLiked) next.add(commentId);
      else next.delete(commentId);
      return { ...s, likedComments: next };
    });
    return nowLiked;
  }, []);

  const addWatchHistory = useCallback(
    async (videoId: string, progress: number) => {
      await Storage.addWatchHistory(videoId, progress);
      if (progress === 0) Analytics.videoPlay(videoId, "");
      setState((s) => {
        const history = [...s.watchHistory];
        const idx = history.findIndex((h) => h.videoId === videoId);
        const entry: WatchHistoryEntry = {
          videoId,
          watchedAt: new Date().toISOString(),
          progressPercent: progress,
        };
        if (idx >= 0) history[idx] = entry;
        else history.unshift(entry);
        return { ...s, watchHistory: history };
      });
    },
    []
  );

  const addComment = useCallback(
    async (videoId: string, text: string, parentId?: string) => {
      const comment = await Storage.addComment(videoId, text, parentId);
      setState((s) => ({
        ...s,
        userComments: [comment, ...s.userComments],
      }));
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      Analytics.commentPost(videoId);
      return comment;
    },
    []
  );

  const editComment = useCallback(async (id: string, text: string) => {
    await Storage.editComment(id, text);
    setState((s) => ({
      ...s,
      userComments: s.userComments.map((c) =>
        c.id === id ? { ...c, text, editedAt: new Date().toISOString() } : c
      ),
    }));
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const deleteComment = useCallback(async (id: string) => {
    await Storage.deleteComment(id);
    setState((s) => ({
      ...s,
      userComments: s.userComments.filter(
        (c) => c.id !== id && c.parentId !== id
      ),
    }));
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  }, []);

  const removeFromHistory = useCallback(async (videoId: string) => {
    await Storage.removeWatchHistory(videoId);
    setState((s) => ({
      ...s,
      watchHistory: s.watchHistory.filter((h) => h.videoId !== videoId),
    }));
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const clearHistory = useCallback(async () => {
    await Storage.clearWatchHistory();
    setState((s) => ({ ...s, watchHistory: [] }));
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  }, []);

  const clearSaved = useCallback(async () => {
    await Storage.clearSavedVideos();
    setState((s) => ({ ...s, savedVideos: new Set() }));
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  }, []);

  const clearLiked = useCallback(async () => {
    await Storage.clearLikedVideos();
    setState((s) => ({ ...s, likedVideos: new Set() }));
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  }, []);

  const refreshPlaylists = useCallback(async () => {
    const playlists = await Storage.getPlaylists();
    setState((s) => ({ ...s, playlists }));
  }, []);

  const createPlaylist = useCallback(async (name: string) => {
    const created = await Storage.createPlaylist(name);
    if (created) {
      await refreshPlaylists();
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    }
    return created;
  }, [refreshPlaylists]);

  const renamePlaylist = useCallback(async (id: string, name: string) => {
    const ok = await Storage.renamePlaylist(id, name);
    if (ok) await refreshPlaylists();
    return ok;
  }, [refreshPlaylists]);

  const deletePlaylist = useCallback(async (id: string) => {
    await Storage.deletePlaylist(id);
    await refreshPlaylists();
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  }, [refreshPlaylists]);

  const togglePlaylistVideo = useCallback(async (id: string, videoId: string) => {
    const nowIn = await Storage.togglePlaylistVideo(id, videoId);
    await refreshPlaylists();
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    return nowIn;
  }, [refreshPlaylists]);

  const clearPlaylist = useCallback(async (id: string) => {
    await Storage.clearPlaylist(id);
    await refreshPlaylists();
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  }, [refreshPlaylists]);

  const getVideoComments = useCallback(
    (videoId: string): Comment[] => {
      const topLevel = state.userComments
        .filter((c) => c.videoId === videoId && !c.parentId)
        .map((c) => {
          const replies = state.userComments
            .filter((r) => r.parentId === c.id)
            .map((r) => ({
              id: r.id,
              author: state.profile?.displayName || "You",
              avatarColor: state.profile?.avatarColor || "#805ad5",
              initial: state.profile?.initial || "Y",
              text: r.text,
              likes: 0,
              timeAgo: formatTimeAgo(r.createdAt),
              isOwn: true,
              edited: Boolean(r.editedAt),
            }));
          return {
            id: c.id,
            author: state.profile?.displayName || "You",
            avatarColor: state.profile?.avatarColor || "#805ad5",
            initial: state.profile?.initial || "Y",
            text: c.text,
            likes: 0,
            timeAgo: formatTimeAgo(c.createdAt),
            replies: replies.length > 0 ? replies : undefined,
            isOwn: true,
            edited: Boolean(c.editedAt),
          };
        });
      return topLevel;
    },
    [state.userComments, state.profile]
  );

  const isLiked = useCallback(
    (videoId: string) => state.likedVideos.has(videoId),
    [state.likedVideos]
  );

  const isDisliked = useCallback(
    (videoId: string) => state.dislikedVideos.has(videoId),
    [state.dislikedVideos]
  );

  const isSubscribed = useCallback(
    (channelId: string) => state.subscriptions.has(channelId),
    [state.subscriptions]
  );

  const isSaved = useCallback(
    (videoId: string) => state.savedVideos.has(videoId),
    [state.savedVideos]
  );

  const isCommentLiked = useCallback(
    (commentId: string) => state.likedComments.has(commentId),
    [state.likedComments]
  );

  const getWatchProgress = useCallback(
    (videoId: string) => {
      const entry = state.watchHistory.find((h) => h.videoId === videoId);
      return entry?.progressPercent || 0;
    },
    [state.watchHistory]
  );

  const setNotifications = useCallback(
    (prefs: { push: boolean; darkMode: boolean; autoplayMuted: boolean; autoplayNext: boolean }) => {
      setState((prev) => ({ ...prev, notifications: prefs }));
      Storage.setNotificationPrefs(prefs);
    },
    []
  );

  const addRecentSearch = useCallback(
    (query: string) => {
      setState((prev) => {
        const filtered = prev.recentSearches.filter((q) => q !== query);
        return { ...prev, recentSearches: [query, ...filtered].slice(0, 10) };
      });
      Storage.addRecentSearch(query);
    },
    []
  );

  const clearRecentSearches = useCallback(() => {
    setState((prev) => ({ ...prev, recentSearches: [] }));
    Storage.clearRecentSearches();
  }, []);

  const value: AppContextType = {
    ...state,
    setProfile,
    toggleLike,
    toggleDislike,
    toggleSubscription,
    toggleSaved,
    toggleCommentLike,
    addWatchHistory,
    addComment,
    editComment,
    deleteComment,
    removeFromHistory,
    clearHistory,
    clearSaved,
    clearLiked,
    createPlaylist,
    renamePlaylist,
    deletePlaylist,
    togglePlaylistVideo,
    clearPlaylist,
    getVideoComments,
    isLiked,
    isDisliked,
    isSubscribed,
    isSaved,
    isCommentLiked,
    getWatchProgress,
    setNotifications,
    addRecentSearch,
    clearRecentSearches,
  };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

function formatTimeAgo(isoDate: string): string {
  const seconds = Math.floor(
    (Date.now() - new Date(isoDate).getTime()) / 1000
  );
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return `${Math.floor(days / 7)}w ago`;
}
