import React, { useRef, useState, useCallback } from "react";
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
  Pressable,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import { LinearGradient } from "expo-linear-gradient";
import * as Haptics from "expo-haptics";
import { useApp } from "../lib/AppContext";
import { THEME, type Video } from "../lib/data";

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
    addComment,
    getVideoComments,
    profile,
  } = useApp();

  const viewabilityConfig = useRef({
    itemVisiblePercentThreshold: 60,
  }).current;

  const onViewRef = useRef(({ viewableItems }: any) => {
    if (viewableItems.length > 0) {
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

        {/* Center play icon */}
        <View style={styles.playContainer}>
          <View style={styles.playGlow} />
          <View style={styles.playButton}>
            <Ionicons name="play" size={40} color="#fff" style={{ marginLeft: 4 }} />
          </View>
        </View>

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
              {formatCompact(video.likes + (liked ? 1 : 0))}
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
            <TouchableOpacity style={styles.subscribeBtn}>
              <Text style={styles.subscribeText}>Subscribe</Text>
            </TouchableOpacity>
          </View>
          <Text style={styles.shortTitle} numberOfLines={2}>
            {video.title}
          </Text>
          <Text style={styles.shortMeta} numberOfLines={1}>
            {formatCompact(video.views)} views · {video.uploadedAt}
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

function formatCompact(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${n}`;
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
