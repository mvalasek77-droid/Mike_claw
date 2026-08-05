import React, { memo } from "react";
import { View, Text, TouchableOpacity, StyleSheet } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import Avatar from "./Avatar";
import VideoThumbnail from "./VideoThumbnail";
import { type Video, formatViews, THEME } from "../lib/data";
import { useApp } from "../lib/AppContext";

interface VideoCardProps {
  video: Video;
  onPress: (video: Video) => void;
  onChannelPress?: (channelId: string) => void;
  layout?: "grid" | "list";
}

export default memo(function VideoCard({
  video,
  onPress,
  onChannelPress,
  layout = "grid",
}: VideoCardProps) {
  const { getWatchProgress, isSaved } = useApp();
  const progress = getWatchProgress(video.id);
  const saved = isSaved(video.id);

  if (layout === "list") {
    return (
      <TouchableOpacity
        style={styles.listContainer}
        onPress={() => onPress(video)}
        activeOpacity={0.7}
        accessibilityRole="button"
        accessibilityLabel={`${video.title} by ${video.channel.name}, ${formatViews(video.views)}${saved ? ", saved" : ""}${progress > 0 ? `, ${Math.round(progress)}% watched` : ""}`}
      >
        <View style={styles.listThumbnail}>
          <VideoThumbnail
            colors={video.thumbnailColors}
            duration={video.duration}
            title={video.title}
            height={90}
            progressPercent={progress}
            saved={saved}
          />
        </View>
        <View style={styles.listInfo}>
          <Text style={styles.listTitle} numberOfLines={2}>
            {video.title}
          </Text>
          <View style={styles.listMetaRow}>
            <Text style={styles.listChannel}>{video.channel.name}</Text>
            {video.channel.verified && (
              <Ionicons
                name="checkmark-circle"
                size={12}
                color={THEME.textSecondary}
                style={{ marginLeft: 4 }}
              />
            )}
          </View>
          <Text style={styles.listMeta}>
            {formatViews(video.views)} · {video.uploadedAt}
          </Text>
        </View>
      </TouchableOpacity>
    );
  }

  return (
    <TouchableOpacity
      style={styles.gridContainer}
      onPress={() => onPress(video)}
      activeOpacity={0.7}
      accessibilityRole="button"
      accessibilityLabel={`${video.title} by ${video.channel.name}, ${formatViews(video.views)}${saved ? ", saved" : ""}${progress > 0 ? `, ${Math.round(progress)}% watched` : ""}`}
    >
      <VideoThumbnail
        colors={video.thumbnailColors}
        duration={video.duration}
        title={video.title}
        progressPercent={progress}
        saved={saved}
      />
      <View style={styles.gridInfo}>
        <TouchableOpacity
          onPress={() => onChannelPress?.(video.channel.id)}
          accessibilityLabel={`${video.channel.name} channel`}
        >
          <Avatar
            color={video.channel.avatarColor}
            initial={video.channel.initial}
            size={36}
            borderColor="rgba(255,68,68,0.2)"
          />
        </TouchableOpacity>
        <View style={styles.gridTextContainer}>
          <Text style={styles.gridTitle} numberOfLines={2}>
            {video.title}
          </Text>
          <View style={styles.gridMetaRow}>
            <Text style={styles.gridChannel}>{video.channel.name}</Text>
            {video.channel.verified && (
              <Ionicons
                name="checkmark-circle"
                size={12}
                color={THEME.textSecondary}
                style={{ marginLeft: 4 }}
              />
            )}
          </View>
          <Text style={styles.gridMeta}>
            {formatViews(video.views)} · {video.uploadedAt}
          </Text>
        </View>
      </View>
    </TouchableOpacity>
  );
});

const styles = StyleSheet.create({
  gridContainer: {
    marginBottom: 20,
  },
  gridInfo: {
    flexDirection: "row",
    marginTop: 10,
    paddingHorizontal: 4,
    gap: 10,
  },
  gridTextContainer: {
    flex: 1,
  },
  gridTitle: {
    color: THEME.textPrimary,
    fontSize: 14,
    fontWeight: "500",
    lineHeight: 19,
  },
  gridMetaRow: {
    flexDirection: "row",
    alignItems: "center",
    marginTop: 3,
  },
  gridChannel: {
    color: THEME.textSecondary,
    fontSize: 12,
  },
  gridMeta: {
    color: THEME.textSecondary,
    fontSize: 12,
    marginTop: 1,
  },
  listContainer: {
    flexDirection: "row",
    gap: 12,
    paddingVertical: 6,
  },
  listThumbnail: {
    width: 168,
    borderRadius: 10,
    overflow: "hidden",
  },
  listInfo: {
    flex: 1,
    justifyContent: "center",
  },
  listTitle: {
    color: THEME.textPrimary,
    fontSize: 14,
    fontWeight: "500",
    lineHeight: 19,
    marginBottom: 4,
  },
  listMetaRow: {
    flexDirection: "row",
    alignItems: "center",
  },
  listChannel: {
    color: THEME.textSecondary,
    fontSize: 12,
  },
  listMeta: {
    color: THEME.textSecondary,
    fontSize: 12,
    marginTop: 1,
  },
});
