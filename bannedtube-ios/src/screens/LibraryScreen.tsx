import React, { useState } from "react";
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  SectionList,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import VideoCard from "../components/VideoCard";
import { useApp } from "../lib/AppContext";
import { THEME, type Video, getVideoById } from "../lib/data";

interface LibraryScreenProps {
  onVideoPress: (video: Video) => void;
  onChannelPress: (channelId: string) => void;
}

type Filter = "history" | "saved" | "liked";

export default function LibraryScreen({
  onVideoPress,
  onChannelPress,
}: LibraryScreenProps) {
  const { watchHistory, savedVideos, likedVideos } = useApp();
  const [filter, setFilter] = useState<Filter>("history");

  const historyVideos = watchHistory
    .map((h) => getVideoById(h.videoId))
    .filter((v): v is Video => v !== undefined);

  const savedVideoList = Array.from(savedVideos)
    .map((id) => getVideoById(id))
    .filter((v): v is Video => v !== undefined);

  const likedVideoList = Array.from(likedVideos)
    .map((id) => getVideoById(id))
    .filter((v): v is Video => v !== undefined);

  const currentList =
    filter === "history"
      ? historyVideos
      : filter === "saved"
      ? savedVideoList
      : likedVideoList;

  const filters: { key: Filter; label: string; icon: string; count: number }[] = [
    { key: "history", label: "History", icon: "time-outline", count: historyVideos.length },
    { key: "saved", label: "Saved", icon: "bookmark-outline", count: savedVideoList.length },
    { key: "liked", label: "Liked", icon: "thumbs-up-outline", count: likedVideoList.length },
  ];

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Vault</Text>
      </View>

      <View style={styles.filterRow}>
        {filters.map((f) => (
          <TouchableOpacity
            key={f.key}
            style={[
              styles.filterChip,
              filter === f.key && styles.filterChipActive,
            ]}
            onPress={() => setFilter(f.key)}
            accessibilityRole="button"
            accessibilityLabel={`${f.label} tab, ${f.count} videos`}
          >
            <Ionicons
              name={f.icon as any}
              size={16}
              color={filter === f.key ? THEME.accent : THEME.textSecondary}
            />
            <Text
              style={[
                styles.filterText,
                filter === f.key && styles.filterTextActive,
              ]}
            >
              {f.label}
            </Text>
            {f.count > 0 && (
              <View style={styles.countBadge}>
                <Text style={styles.countText}>{f.count}</Text>
              </View>
            )}
          </TouchableOpacity>
        ))}
      </View>

      <FlatList
        data={currentList}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <View style={styles.cardWrapper}>
            <VideoCard
              video={item}
              onPress={onVideoPress}
              onChannelPress={onChannelPress}
              layout="list"
            />
          </View>
        )}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Ionicons
              name={
                filter === "history"
                  ? "time-outline"
                  : filter === "saved"
                  ? "bookmark-outline"
                  : "thumbs-up-outline"
              }
              size={56}
              color={THEME.bgTertiary}
            />
            <Text style={styles.emptyTitle}>
              {filter === "history"
                ? "No watch history yet"
                : filter === "saved"
                ? "No saved videos yet"
                : "No liked videos yet"}
            </Text>
            <Text style={styles.emptySubtitle}>
              {filter === "history"
                ? "Videos you watch will appear here"
                : filter === "saved"
                ? "Tap the bookmark icon on a video to save it"
                : "Tap the like button on a video to see it here"}
            </Text>
          </View>
        }
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: THEME.bgPrimary,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 10,
  },
  headerTitle: {
    color: THEME.textPrimary,
    fontSize: 22,
    fontWeight: "700",
  },
  filterRow: {
    flexDirection: "row",
    paddingHorizontal: 12,
    paddingBottom: 12,
    gap: 8,
  },
  filterChip: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: THEME.bgSecondary,
    borderWidth: 1,
    borderColor: THEME.border,
  },
  filterChipActive: {
    backgroundColor: "rgba(255,68,68,0.15)",
    borderColor: THEME.accent,
  },
  filterText: {
    color: THEME.textSecondary,
    fontSize: 13,
    fontWeight: "500",
  },
  filterTextActive: {
    color: THEME.accent,
    fontWeight: "600",
  },
  countBadge: {
    backgroundColor: THEME.bgTertiary,
    borderRadius: 10,
    paddingHorizontal: 6,
    paddingVertical: 1,
    minWidth: 20,
    alignItems: "center",
  },
  countText: {
    color: THEME.textSecondary,
    fontSize: 10,
    fontWeight: "700",
  },
  list: {
    paddingBottom: 100,
  },
  cardWrapper: {
    paddingHorizontal: 12,
  },
  empty: {
    alignItems: "center",
    paddingTop: 80,
    gap: 8,
  },
  emptyTitle: {
    color: THEME.textPrimary,
    fontSize: 17,
    fontWeight: "600",
    marginTop: 12,
  },
  emptySubtitle: {
    color: THEME.textSecondary,
    fontSize: 14,
    textAlign: "center",
    paddingHorizontal: 40,
  },
});
