import React, { useState } from "react";
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
import Avatar from "../components/Avatar";
import VideoCard from "../components/VideoCard";
import {
  channels,
  videos,
  formatSubscribers,
  THEME,
  type Video,
  type Channel,
} from "../lib/data";

interface SubscriptionsScreenProps {
  onVideoPress: (video: Video) => void;
  onChannelPress: (channelId: string) => void;
}

export default function SubscriptionsScreen({
  onVideoPress,
  onChannelPress,
}: SubscriptionsScreenProps) {
  const [selectedChannel, setSelectedChannel] = useState<string | null>(null);

  const subscribedChannels = channels.slice(0, 6);

  const filteredVideos = selectedChannel
    ? videos.filter((v) => v.channel.id === selectedChannel)
    : videos;

  const sortedVideos = [...filteredVideos].sort(() => Math.random() - 0.5);

  return (
    <SafeAreaView style={styles.container} edges={["top"]}>
      <View style={styles.header}>
        <Ionicons name="people" size={24} color={THEME.accent} />
        <Text style={styles.headerTitle}>Subscriptions</Text>
      </View>

      {/* Channel avatar strip */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.channelStrip}
      >
        <TouchableOpacity
          style={[
            styles.channelChip,
            !selectedChannel && styles.channelChipActive,
          ]}
          onPress={() => setSelectedChannel(null)}
          activeOpacity={0.7}
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
            style={[
              styles.channelChip,
              selectedChannel === ch.id && styles.channelChipActive,
            ]}
            onPress={() =>
              setSelectedChannel(selectedChannel === ch.id ? null : ch.id)
            }
            activeOpacity={0.7}
          >
            <View
              style={[
                styles.channelAvatarWrapper,
                selectedChannel === ch.id && {
                  borderColor: THEME.accent,
                },
              ]}
            >
              <Avatar color={ch.avatarColor} initial={ch.initial} size={40} />
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
            <Ionicons name="videocam-off" size={48} color={THEME.bgTertiary} />
            <Text style={styles.emptyText}>No videos from this channel</Text>
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
  channelChipActive: {},
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
