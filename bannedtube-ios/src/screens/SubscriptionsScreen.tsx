import React, { useState, useMemo } from "react";
import {
  View,
  Text,
  FlatList,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LinearGradient } from "expo-linear-gradient";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import Avatar from "../components/Avatar";
import VideoCard from "../components/VideoCard";
import { useApp } from "../lib/AppContext";
import {
  channels,
  videos,
  THEME,
  type Video,
} from "../lib/data";
import { avatars } from "../lib/assets";

interface SubscriptionsScreenProps {
  onVideoPress: (video: Video) => void;
  onChannelPress: (channelId: string) => void;
}

export default function SubscriptionsScreen({
  onVideoPress,
  onChannelPress,
}: SubscriptionsScreenProps) {
  const { subscriptions } = useApp();
  const [selectedChannel, setSelectedChannel] = useState<string | null>(null);

  const subscribedChannels = useMemo(
    () => channels.filter((ch) => subscriptions.has(ch.id)),
    [subscriptions]
  );

  const subscribedIds = subscriptions;
  const subVideos = useMemo(
    () =>
      subscribedIds.size > 0
        ? videos.filter((v) => subscribedIds.has(v.channel.id))
        : videos,
    [subscribedIds]
  );

  const filteredVideos = selectedChannel
    ? subVideos.filter((v) => v.channel.id === selectedChannel)
    : subVideos;

  const sortedVideos = useMemo(
    () => [...filteredVideos].sort((a, b) => a.id.localeCompare(b.id)),
    [filteredVideos]
  );

  function selectChannel(id: string | null) {
    Haptics.selectionAsync();
    setSelectedChannel(id);
  }

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <View style={styles.header}>
        <LinearGradient
          colors={["rgba(255,68,68,0.06)", "transparent"]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={StyleSheet.absoluteFill}
        />
        <Ionicons name="people" size={24} color={THEME.accent} />
        <Text style={styles.headerTitle} accessibilityRole="header">
          Subscriptions
        </Text>
      </View>

      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.channelStrip}
      >
        <TouchableOpacity
          style={styles.channelChip}
          onPress={() => selectChannel(null)}
          activeOpacity={0.7}
          accessibilityRole="button"
          accessibilityLabel="Show all subscriptions"
          accessibilityState={{ selected: !selectedChannel }}
        >
          <View
            style={[
              styles.allCircle,
              !selectedChannel && { borderColor: THEME.accent },
            ]}
          >
            <Ionicons
              name="grid"
              size={18}
              color={!selectedChannel ? THEME.accent : THEME.textSecondary}
            />
          </View>
          <Text
            style={[
              styles.channelChipText,
              !selectedChannel && styles.channelChipTextActive,
            ]}
          >
            All
          </Text>
        </TouchableOpacity>

        {subscribedChannels.map((ch) => (
          <TouchableOpacity
            key={ch.id}
            style={styles.channelChip}
            onPress={() =>
              selectChannel(selectedChannel === ch.id ? null : ch.id)
            }
            activeOpacity={0.7}
            accessibilityRole="button"
            accessibilityLabel={`Filter by ${ch.name}`}
            accessibilityState={{ selected: selectedChannel === ch.id }}
          >
            <View
              style={[
                styles.channelAvatarWrapper,
                selectedChannel === ch.id && {
                  borderColor: THEME.accent,
                },
              ]}
            >
              <Avatar color={ch.avatarColor} initial={ch.initial} size={40} imageSource={avatars[ch.id]} />
            </View>
            <Text
              style={[
                styles.channelChipText,
                selectedChannel === ch.id && styles.channelChipTextActive,
              ]}
              numberOfLines={1}
            >
              {ch.name.split(" ")[0]}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      <View style={styles.divider} />

      <FlatList
        data={sortedVideos}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <View style={styles.cardWrapper}>
            <VideoCard
              video={item}
              onPress={onVideoPress}
              onChannelPress={onChannelPress}
            />
          </View>
        )}
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Ionicons
              name={subscribedIds.size === 0 ? "people-outline" : "videocam-off"}
              size={48}
              color={THEME.bgTertiary}
            />
            <Text style={styles.emptyText}>
              {subscribedIds.size === 0
                ? "Subscribe to channels to see their videos here"
                : "No videos from this channel"}
            </Text>
          </View>
        }
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
    gap: 10,
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 10,
    overflow: "hidden",
  },
  headerTitle: {
    color: THEME.textPrimary,
    fontSize: 20,
    fontWeight: "700",
  },
  channelStrip: {
    paddingHorizontal: 12,
    gap: 14,
    paddingVertical: 8,
  },
  channelChip: {
    alignItems: "center",
    gap: 6,
    width: 64,
  },
  channelAvatarWrapper: {
    borderRadius: 24,
    borderWidth: 2,
    borderColor: "transparent",
    padding: 2,
  },
  allCircle: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: THEME.bgTertiary,
    justifyContent: "center",
    alignItems: "center",
    borderWidth: 2,
    borderColor: "transparent",
  },
  channelChipText: {
    color: THEME.textSecondary,
    fontSize: 11,
    textAlign: "center",
  },
  channelChipTextActive: {
    color: THEME.textPrimary,
    fontWeight: "600",
  },
  divider: {
    height: 1,
    backgroundColor: THEME.border,
  },
  list: {
    paddingBottom: 100,
  },
  cardWrapper: {
    paddingHorizontal: 12,
  },
  empty: {
    alignItems: "center",
    paddingTop: 60,
    gap: 12,
  },
  emptyText: {
    color: THEME.textSecondary,
    fontSize: 15,
  },
});
