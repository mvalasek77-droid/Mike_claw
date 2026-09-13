import React, { useRef, useState, useCallback, useEffect } from "react";
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
  Pressable,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { LinearGradient } from "expo-linear-gradient";
import * as Haptics from "expo-haptics";
import { Share as RNShare } from "react-native";
import { useVideoPlayer, VideoView } from "expo-video";
import { useApp } from "../lib/AppContext";
import { THEME, formatCompact, formatViews, type Video } from "../lib/data";

const { height: SCREEN_HEIGHT } = Dimensions.get("window");

interface ShortsScreenProps {
  videos: Video[];
}

export default function ShortsScreen({ videos }: ShortsScreenProps) {
  const [activeIndex, setActiveIndex] = useState(0);
  const {
    isLiked,
    isDisliked,
    toggleLike,
    toggleDislike,
    toggleSaved,
    isSaved,
    isSubscribed,
    toggleSubscription,
    notifications,
  } = useApp();

  // One player drives the whole feed; its source follows whichever clip is on
  // screen. Creating a player per row would hold several decoders open at once.
  const player = useVideoPlayer(videos[0]?.videoUrl ?? null, (p) => {
    p.loop = true;
    p.muted = notifications.autoplayMuted;
  });
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const current = videos[activeIndex];
    if (!current) return;
    let cancelled = false;
    (async () => {
      try {
        await player.replaceAsync(current.videoUrl);
        if (!cancelled) {
          setPaused(false);
          player.play();
        }
      } catch {
        // A source that fails to load leaves the poster art in place.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [activeIndex, videos, player]);

  const togglePlayback = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    if (player.playing) {
      player.pause();
      setPaused(true);
    } else {
      player.play();
      setPaused(false);
    }
  }, [player]);

  const viewabilityConfig = useRef({
    itemVisiblePercentThreshold: 60,
  }).current;

  const onViewRef = useRef(({ viewableItems }: any) => {
    if (viewableItems.length > 0 && viewableItems[0].index != null) {
      setActiveIndex(viewableItems[0].index);
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    }
  }).current;

  const handleLike = useCallback(
    (videoId: string) => {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      toggleLike(videoId);
    },
    [toggleLike]
  );

  const handleDislike = useCallback(
    (videoId: string) => {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      toggleDislike(videoId);
    },
    [toggleDislike]
  );

  const handleSave = useCallback(
    (videoId: string) => {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      toggleSaved(videoId);
    },
    [toggleSaved]
  );

  const renderItem = ({ item: video, index }: { item: Video; index: number }) => {
    const liked = isLiked(video.id);
    const disliked = isDisliked(video.id);
    const saved = isSaved(video.id);
    const isActive = index === activeIndex;

    return (
      <View style={styles.shortItem}>
        {/* Gradient background */}
        <LinearGradient
          colors={[video.thumbnailColors[0], video.thumbnailColors[1], "#000"]}
          style={StyleSheet.absoluteFill}
        />

        {/* Dark overlay for readability */}
        <LinearGradient
          colors={["transparent", "transparent", "rgba(0,0,0,0.6)"]}
          style={StyleSheet.absoluteFill}
        />

        {/* The active clip plays in place; the rest keep their poster art. */}
        {isActive && (
          <VideoView
            player={player}
            style={StyleSheet.absoluteFill}
            contentFit="cover"
            nativeControls={false}
          />
        )}

        {/* Tap anywhere to pause or resume. */}
        <Pressable
          style={StyleSheet.absoluteFill}
          onPress={togglePlayback}
          accessibilityRole="button"
          accessibilityLabel={paused ? "Resume clip" : "Pause clip"}
        />

        {isActive && paused && (
          <View style={styles.playContainer} pointerEvents="none">
            <View style={styles.playGlow} />
            <View style={styles.playButton}>
              <Ionicons name="play" size={40} color="#fff" style={{ marginLeft: 4 }} />
            </View>
          </View>
        )}

        {/* Right action bar */}
        <View style={styles.actionBar}>
          <TouchableOpacity
            style={styles.actionButton}
            onPress={() => handleLike(video.id)}
            accessibilityLabel={liked ? "Remove like" : "Like"}
          >
            <Ionicons
              name={liked ? "heart" : "heart-outline"}
              size={30}
              color={liked ? THEME.accent : "#fff"}
            />
            <Text style={styles.actionLabel}>
              {video.likes + (liked ? 1 : 0) > 0
                ? formatCompact(video.likes + (liked ? 1 : 0))
                : "Like"}
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.actionButton}
            onPress={() => handleDislike(video.id)}
            accessibilityLabel={disliked ? "Remove dislike" : "Dislike"}
          >
            <Ionicons
              name={disliked ? "thumbs-down" : "thumbs-down-outline"}
              size={30}
              color={disliked ? THEME.accent : "#fff"}
            />
            <Text style={styles.actionLabel}>Dislike</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.actionButton}
            onPress={() => handleSave(video.id)}
            accessibilityLabel={saved ? "Unsave" : "Save"}
          >
            <Ionicons
              name={saved ? "bookmark" : "bookmark-outline"}
              size={30}
              color={saved ? THEME.accent : "#fff"}
            />
            <Text style={styles.actionLabel}>Save</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.actionButton}
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              RNShare.share({
                message: `Check out "${video.title}" on BannedTube`,
                title: "BannedTube",
              });
            }}
            accessibilityLabel="Share"
          >
            <Ionicons name="share-outline" size={30} color="#fff" />
            <Text style={styles.actionLabel}>Share</Text>
          </TouchableOpacity>
        </View>

        {/* Bottom info */}
        <View style={styles.bottomInfo}>
          <View style={styles.channelRow}>
            <View style={[styles.channelAvatar, { backgroundColor: video.channel.avatarColor }]}>
              <Text style={styles.channelInitial}>{video.channel.initial}</Text>
            </View>
            <Text style={styles.channelName}>@{video.channel.name}</Text>
            {video.channel.verified && (
              <Ionicons name="checkmark-circle" size={14} color="#fff" />
            )}
            <TouchableOpacity
              style={styles.subscribeBtn}
              onPress={() => toggleSubscription(video.channel.id)}
              accessibilityRole="button"
              accessibilityLabel={
                isSubscribed(video.channel.id)
                  ? `Unfollow ${video.channel.name}`
                  : `Follow ${video.channel.name}`
              }
            >
              <Text style={styles.subscribeText}>
                {isSubscribed(video.channel.id) ? "Following" : "Follow"}
              </Text>
            </TouchableOpacity>
          </View>
          <Text style={styles.shortTitle} numberOfLines={2}>
            {video.title}
          </Text>
          <Text style={styles.shortMeta} numberOfLines={1}>
            {formatViews(video.views)} · {video.uploadedAt}
          </Text>
        </View>
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <FlatList
        data={videos}
        keyExtractor={(item) => item.id}
        renderItem={renderItem}
        pagingEnabled
        showsVerticalScrollIndicator={false}
        onViewableItemsChanged={onViewRef}
        viewabilityConfig={viewabilityConfig}
        getItemLayout={(_, index) => ({
          length: SCREEN_HEIGHT,
          offset: SCREEN_HEIGHT * index,
          index,
        })}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#000",
  },
  shortItem: {
    height: SCREEN_HEIGHT,
    justifyContent: "center",
    alignItems: "center",
  },
  playContainer: {
    position: "relative",
    marginBottom: 60,
  },
  playGlow: {
    position: "absolute",
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: "rgba(255,68,68,0.3)",
    top: -10,
    left: -10,
  },
  playButton: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: "rgba(255,255,255,0.15)",
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 2,
    borderColor: "rgba(255,255,255,0.25)",
  },
  actionBar: {
    position: "absolute",
    right: 12,
    bottom: 120,
    gap: 20,
  },
  actionButton: {
    alignItems: "center",
    gap: 4,
  },
  actionLabel: {
    color: "#fff",
    fontSize: 11,
    fontWeight: "600",
  },
  bottomInfo: {
    position: "absolute",
    bottom: 100,
    left: 12,
    right: 72,
    gap: 8,
  },
  channelRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  channelAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: "center",
    alignItems: "center",
  },
  channelInitial: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "700",
  },
  channelName: {
    color: "#fff",
    fontSize: 14,
    fontWeight: "600",
  },
  subscribeBtn: {
    backgroundColor: THEME.accent,
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
    marginLeft: 4,
  },
  subscribeText: {
    color: "#fff",
    fontSize: 12,
    fontWeight: "700",
  },
  shortTitle: {
    color: "#fff",
    fontSize: 15,
    fontWeight: "500",
    lineHeight: 20,
  },
  shortMeta: {
    color: "rgba(255,255,255,0.7)",
    fontSize: 13,
  },
});
